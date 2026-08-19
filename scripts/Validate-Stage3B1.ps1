param(
    [Parameter(Mandatory = $true)]
    [string]$EmployeeId,

    [int]$SmokePort = 3105
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function ConvertTo-PlainText {
    param(
        [Parameter(Mandatory = $true)]
        [Security.SecureString]$Value
    )

    $Pointer = `
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR(
            $Value
        )

    try {
        return `
            [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
                $Pointer
            )
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR(
            $Pointer
        )
    }
}

function Invoke-Json {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [string]$Method,

        [string]$AccessToken,

        [hashtable]$Body
    )

    $Parameters = @{
        Uri = $Uri
        Method = $Method
        TimeoutSec = 15
    }

    if ($AccessToken) {
        $Parameters.Headers = @{
            Authorization = "Bearer $AccessToken"
        }
    }

    if ($null -ne $Body) {
        $Parameters.ContentType = "application/json"
        $Parameters.Body = `
            $Body |
            ConvertTo-Json -Depth 10
    }

    return Invoke-RestMethod @Parameters
}

function Assert-HttpStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [string]$Method,

        [string]$AccessToken,

        [hashtable]$Body,

        [Parameter(Mandatory = $true)]
        [int]$ExpectedStatus,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    try {
        $Parameters = @{
            Uri = $Uri
            Method = $Method
            TimeoutSec = 15
            UseBasicParsing = $true
        }

        if ($AccessToken) {
            $Parameters.Headers = @{
                Authorization = "Bearer $AccessToken"
            }
        }

        if ($null -ne $Body) {
            $Parameters.ContentType = "application/json"
            $Parameters.Body = `
                $Body |
                ConvertTo-Json -Depth 10
        }

        $Response = Invoke-WebRequest @Parameters

        $ActualStatus = [int]$Response.StatusCode

        if ($ActualStatus -ne $ExpectedStatus) {
            throw "$Description returned HTTP $ActualStatus instead of $ExpectedStatus."
        }

        Write-Host `
            "[OK] $Description returned HTTP $ExpectedStatus." `
            -ForegroundColor Green
    }
    catch {
        $StatusCode = $null

        if (
            $_.Exception.Response -and
            $_.Exception.Response.StatusCode
        ) {
            $StatusCode = `
                [int]$_.Exception.Response.StatusCode
        }

        if ($StatusCode -ne $ExpectedStatus) {
            throw "$Description returned HTTP $StatusCode instead of $ExpectedStatus."
        }

        Write-Host `
            "[OK] $Description returned HTTP $ExpectedStatus." `
            -ForegroundColor Green
    }
}

Set-Location `
    (Split-Path -Parent $PSScriptRoot)

$AdminPasswordSecure = Read-Host `
    "Digite a senha do ADMIN" `
    -AsSecureString

$EmployeePasswordSecure = Read-Host `
    "Digite a senha do EMPLOYEE" `
    -AsSecureString

$AdminPassword = `
    ConvertTo-PlainText `
        $AdminPasswordSecure

$EmployeePassword = `
    ConvertTo-PlainText `
        $EmployeePasswordSecure

$PreviousPort = $env:PORT
$env:PORT = [string]$SmokePort

$Process = $null

$Timestamp = `
    Get-Date `
        -Format "yyyyMMddHHmmss"

$SiteSlug = `
    "stage3b1-$Timestamp"

$Hostname = `
    "$SiteSlug.example.com"

try {
    Write-Host ""
    Write-Host `
        "==== Stage 3B.1 runtime build ====" `
        -ForegroundColor Cyan

    pnpm exec turbo run build --filter="@crm/api"

    if ($LASTEXITCODE -ne 0) {
        throw "API build failed."
    }

    $Process = Start-Process `
        -FilePath "node" `
        -ArgumentList "apps/api/dist/main.js" `
        -WorkingDirectory (Get-Location) `
        -NoNewWindow `
        -PassThru

    $BaseUrl = `
        "http://127.0.0.1:$SmokePort/api/v1"

    $Deadline = `
        (Get-Date).AddSeconds(25)

    $Ready = $false

    while ((Get-Date) -lt $Deadline) {
        try {
            $Health = `
                Invoke-RestMethod `
                    -Uri "$BaseUrl/health/ready" `
                    -Method Get `
                    -TimeoutSec 2

            if ($Health.status -eq "ok") {
                $Ready = $true
                break
            }
        }
        catch {
            Start-Sleep `
                -Milliseconds 500
        }
    }

    if (-not $Ready) {
        throw "API did not become ready."
    }

    Write-Host `
        "[OK] API ready." `
        -ForegroundColor Green

    Write-Host ""
    Write-Host `
        "==== Login ====" `
        -ForegroundColor Cyan

    $AdminLogin = `
        Invoke-Json `
            -Uri "$BaseUrl/auth/login" `
            -Method POST `
            -Body @{
                email = "admin@example.com"
                organizationSlug = "crm-ads-whatsapp"
                password = $AdminPassword
            }

    $EmployeeLogin = `
        Invoke-Json `
            -Uri "$BaseUrl/auth/login" `
            -Method POST `
            -Body @{
                email = "employee@example.com"
                organizationSlug = "crm-ads-whatsapp"
                password = $EmployeePassword
            }

    $AdminToken = `
        [string]$AdminLogin.accessToken

    $EmployeeToken = `
        [string]$EmployeeLogin.accessToken

    Write-Host `
        "[OK] ADMIN and EMPLOYEE authenticated." `
        -ForegroundColor Green

    Write-Host ""
    Write-Host `
        "==== ADMIN creates employee-owned site ====" `
        -ForegroundColor Cyan

    $Site = `
        Invoke-Json `
            -Uri "$BaseUrl/sites" `
            -Method POST `
            -AccessToken $AdminToken `
            -Body @{
                ownerEmployeeId = $EmployeeId
                name = "Stage 3B1 Runtime Site"
                slug = $SiteSlug
                description = "Temporary runtime validation site"
            }

    if (
        $Site.ownerEmployeeId -ne
        $EmployeeId
    ) {
        throw "Site owner does not match EMPLOYEE."
    }

    $SiteId = `
        [string]$Site.id

    Write-Host `
        "[OK] ADMIN created site assigned to EMPLOYEE." `
        -ForegroundColor Green

    Write-Host ""
    Write-Host `
        "==== Domain management ====" `
        -ForegroundColor Cyan

    $Domain = `
        Invoke-Json `
            -Uri "$BaseUrl/sites/$SiteId/domains" `
            -Method POST `
            -AccessToken $AdminToken `
            -Body @{
                hostname = $Hostname
                isPrimary = $true
            }

    if (-not $Domain.isPrimary) {
        throw "Domain was not created as primary."
    }

    Write-Host `
        "[OK] ADMIN created primary domain." `
        -ForegroundColor Green

    Write-Host ""
    Write-Host `
        "==== EMPLOYEE ownership read ====" `
        -ForegroundColor Cyan

    $EmployeeSites = `
        @(Invoke-Json `
            -Uri "$BaseUrl/sites" `
            -Method GET `
            -AccessToken $EmployeeToken)

    $EmployeeSite = `
        $EmployeeSites |
        Where-Object {
            $_.id -eq $SiteId
        }

    if (-not $EmployeeSite) {
        throw "EMPLOYEE cannot see own site."
    }

    Write-Host `
        "[OK] EMPLOYEE can see assigned site." `
        -ForegroundColor Green

    $EmployeeSiteDetail = `
        Invoke-Json `
            -Uri "$BaseUrl/sites/$SiteId" `
            -Method GET `
            -AccessToken $EmployeeToken

    if (
        $EmployeeSiteDetail.id -ne
        $SiteId
    ) {
        throw "EMPLOYEE site detail returned unexpected resource."
    }

    Write-Host `
        "[OK] EMPLOYEE can read own site detail." `
        -ForegroundColor Green

    $EmployeeDomains = `
        @(Invoke-Json `
            -Uri "$BaseUrl/sites/$SiteId/domains" `
            -Method GET `
            -AccessToken $EmployeeToken)

    if (
        -not (
            $EmployeeDomains |
            Where-Object {
                $_.id -eq $Domain.id
            }
        )
    ) {
        throw "EMPLOYEE cannot see domain from own site."
    }

    Write-Host `
        "[OK] EMPLOYEE can read own site domains." `
        -ForegroundColor Green

    Write-Host ""
    Write-Host `
        "==== EMPLOYEE write restrictions ====" `
        -ForegroundColor Cyan

    Assert-HttpStatus `
        -Uri "$BaseUrl/sites" `
        -Method POST `
        -AccessToken $EmployeeToken `
        -Body @{
            ownerEmployeeId = $EmployeeId
            name = "Forbidden Site"
            slug = "forbidden-$Timestamp"
        } `
        -ExpectedStatus 403 `
        -Description "EMPLOYEE creating site"

    Assert-HttpStatus `
        -Uri "$BaseUrl/sites/$SiteId" `
        -Method PATCH `
        -AccessToken $EmployeeToken `
        -Body @{
            name = "Forbidden Update"
        } `
        -ExpectedStatus 403 `
        -Description "EMPLOYEE updating site"

    Assert-HttpStatus `
        -Uri "$BaseUrl/sites/$SiteId/domains" `
        -Method POST `
        -AccessToken $EmployeeToken `
        -Body @{
            hostname = "forbidden-$Timestamp.example.com"
        } `
        -ExpectedStatus 403 `
        -Description "EMPLOYEE creating domain"

    Write-Host ""
    Write-Host `
        "==== ADMIN visibility ====" `
        -ForegroundColor Cyan

    $AdminSites = `
        @(Invoke-Json `
            -Uri "$BaseUrl/sites" `
            -Method GET `
            -AccessToken $AdminToken)

    if (
        -not (
            $AdminSites |
            Where-Object {
                $_.id -eq $SiteId
            }
        )
    ) {
        throw "ADMIN cannot see organization site."
    }

    Write-Host `
        "[OK] ADMIN can see organization resources." `
        -ForegroundColor Green

    Write-Host ""
    Write-Host `
        "============================================" `
        -ForegroundColor Green

    Write-Host `
        "[OK] STAGE 3B.1 RUNTIME VALIDATION PASSED." `
        -ForegroundColor Green

    Write-Host `
        "[OK] ADMIN site management validated." `
        -ForegroundColor Green

    Write-Host `
        "[OK] ADMIN domain management validated." `
        -ForegroundColor Green

    Write-Host `
        "[OK] EMPLOYEE ownership read validated." `
        -ForegroundColor Green

    Write-Host `
        "[OK] EMPLOYEE write denial validated." `
        -ForegroundColor Green

    Write-Host `
        "============================================" `
        -ForegroundColor Green
}
finally {
    if (
        $Process -and
        -not $Process.HasExited
    ) {
        Stop-Process `
            -Id $Process.Id `
            -Force `
            -ErrorAction SilentlyContinue
    }

    if ($null -eq $PreviousPort) {
        Remove-Item `
            Env:PORT `
            -ErrorAction SilentlyContinue
    }
    else {
        $env:PORT = $PreviousPort
    }

    $AdminPassword = $null
    $EmployeePassword = $null
}