param(
    [Parameter(Mandatory = $true)]
    [string]$EmployeeId,

    [int]$SmokePort = 3106
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$EmployeeId = $EmployeeId.Trim()

if (
    $EmployeeId -notmatch
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
) {
    throw "EmployeeId inválido. Informe o UUID de employee.id, não userId nem employeeCode."
}

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

        [AllowNull()]
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

        [AllowNull()]
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

function Get-ResponseItems {
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return @()
    }

    # Array normal vindo da API
    if ($Value -is [System.Array]) {
        $Result = @()

        foreach ($Entry in $Value) {
            $Result += @(
                Get-ResponseItems `
                    -Value $Entry
            )
        }

        return $Result
    }

    # Caso futuro de resposta:
    # { "items": [...] }
    $ItemsProperty = `
        $Value.PSObject.Properties['items']

    if ($null -ne $ItemsProperty) {
        return @(
            Get-ResponseItems `
                -Value $ItemsProperty.Value
        )
    }

    # Caso futuro de resposta:
    # { "data": [...] }
    $DataProperty = `
        $Value.PSObject.Properties['data']

    if ($null -ne $DataProperty) {
        return @(
            Get-ResponseItems `
                -Value $DataProperty.Value
        )
    }

    # Objeto individual
    return @($Value)
}

function Test-CollectionContainsId {
    param(
        [AllowNull()]
        [object]$Collection,

        [Parameter(Mandatory = $true)]
        [string]$Id
    )

    $Items = @(
        Get-ResponseItems `
            -Value $Collection
    )

    foreach ($Item in $Items) {
        if ($null -eq $Item) {
            continue
        }

        $IdProperty = `
            $Item.PSObject.Properties['id']

        if ($null -eq $IdProperty) {
            continue
        }

        $CurrentId = `
            [string]$IdProperty.Value

        if ($CurrentId -eq $Id) {
            return $true
        }
    }

    return $false
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

$RandomSuffix = `
    Get-Random `
        -Minimum 10000000 `
        -Maximum 99999999

$LocalDigits = `
    "119$RandomSuffix"

$ExpectedE164 = `
    "+55$LocalDigits"

$MaskedInput = `
    "($($LocalDigits.Substring(0, 2))) " +
    "$($LocalDigits.Substring(2, 5))-" +
    "$($LocalDigits.Substring(7, 4))"

$WithoutPlusInput = `
    "55$LocalDigits"

try {
    Write-Host ""
    Write-Host `
        "==== Stage 3B.2 runtime build ====" `
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
                    -Method GET `
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
        "==== Phone normalization ====" `
        -ForegroundColor Cyan

    Write-Host `
        "Input:    $MaskedInput"

    Write-Host `
        "Expected: $ExpectedE164"

    $Number = `
        Invoke-Json `
            -Uri "$BaseUrl/whatsapp-numbers" `
            -Method POST `
            -AccessToken $AdminToken `
            -Body @{
                displayName = "WhatsApp Stage 3B2"
                e164 = $MaskedInput
                notes = "Stage 3B2 runtime validation"
            }

    if (
        $Number.e164 -ne
        $ExpectedE164
    ) {
        throw "Phone normalization failed. Expected $ExpectedE164 but received $($Number.e164)."
    }

    if (
        $null -ne
        $Number.assignedEmployeeId
    ) {
        throw "New number should initially be unassigned."
    }

    $NumberId = `
        [string]$Number.id

    Write-Host `
        "[OK] Human input normalized to E.164." `
        -ForegroundColor Green

    Write-Host `
        "[OK] ADMIN created unassigned WhatsApp number." `
        -ForegroundColor Green

    Write-Host ""
    Write-Host `
        "==== Duplicate normalization protection ====" `
        -ForegroundColor Cyan

    Assert-HttpStatus `
        -Uri "$BaseUrl/whatsapp-numbers" `
        -Method POST `
        -AccessToken $AdminToken `
        -Body @{
            displayName = "Duplicate WhatsApp"
            e164 = $WithoutPlusInput
        } `
        -ExpectedStatus 409 `
        -Description "Same number using 55 without plus"

    Write-Host ""
    Write-Host `
        "==== Invalid phone validation ====" `
        -ForegroundColor Cyan

    Assert-HttpStatus `
        -Uri "$BaseUrl/whatsapp-numbers" `
        -Method POST `
        -AccessToken $AdminToken `
        -Body @{
            displayName = "Invalid WhatsApp"
            e164 = "123"
        } `
        -ExpectedStatus 400 `
        -Description "Invalid phone number"

    Write-Host ""
    Write-Host `
        "==== Unassigned number visibility ====" `
        -ForegroundColor Cyan

    $AdminNumbers = `
        @(Invoke-Json `
            -Uri "$BaseUrl/whatsapp-numbers" `
            -Method GET `
            -AccessToken $AdminToken)

$AdminContainsNumber = `
    Test-CollectionContainsId `
        -Collection $AdminNumbers `
        -Id $NumberId

if (-not $AdminContainsNumber) {
    Write-Host ""
    Write-Host `
        "[DEBUG] Expected NumberId:" `
        -ForegroundColor Yellow

    Write-Host $NumberId

    Write-Host ""
    Write-Host `
        "[DEBUG] GET /whatsapp-numbers returned:" `
        -ForegroundColor Yellow

    $AdminNumbers |
        ConvertTo-Json `
            -Depth 10 |
        Write-Host

    throw "ADMIN cannot see unassigned number."
}
    Write-Host `
        "[OK] ADMIN sees unassigned number." `
        -ForegroundColor Green

    $EmployeeNumbersBeforeAssignment = `
        @(Invoke-Json `
            -Uri "$BaseUrl/whatsapp-numbers" `
            -Method GET `
            -AccessToken $EmployeeToken)

    if (
        Test-CollectionContainsId `
            -Collection $EmployeeNumbersBeforeAssignment `
            -Id $NumberId
    ) {
        throw "EMPLOYEE should not see unassigned number."
    }

    Write-Host `
        "[OK] EMPLOYEE cannot see unassigned number." `
        -ForegroundColor Green

    Assert-HttpStatus `
        -Uri "$BaseUrl/whatsapp-numbers/$NumberId" `
        -Method GET `
        -AccessToken $EmployeeToken `
        -ExpectedStatus 404 `
        -Description "EMPLOYEE reading unassigned number"

    Write-Host ""
    Write-Host `
        "==== ADMIN assigns number ====" `
        -ForegroundColor Cyan

    $AssignedNumber = `
        Invoke-Json `
            -Uri "$BaseUrl/whatsapp-numbers/$NumberId" `
            -Method PATCH `
            -AccessToken $AdminToken `
            -Body @{
                assignedEmployeeId = $EmployeeId
            }

    if (
        $AssignedNumber.assignedEmployeeId -ne
        $EmployeeId
    ) {
        throw "Number assignment failed."
    }

    Write-Host `
        "[OK] ADMIN assigned number to EMPLOYEE." `
        -ForegroundColor Green

    Write-Host ""
    Write-Host `
        "==== EMPLOYEE ownership read ====" `
        -ForegroundColor Cyan

    $EmployeeNumbersAfterAssignment = `
        @(Invoke-Json `
            -Uri "$BaseUrl/whatsapp-numbers" `
            -Method GET `
            -AccessToken $EmployeeToken)

    if (
        -not (
            Test-CollectionContainsId `
                -Collection $EmployeeNumbersAfterAssignment `
                -Id $NumberId
        )
    ) {
        throw "EMPLOYEE cannot see assigned number."
    }

    Write-Host `
        "[OK] EMPLOYEE sees assigned number." `
        -ForegroundColor Green

    $EmployeeDetail = `
        Invoke-Json `
            -Uri "$BaseUrl/whatsapp-numbers/$NumberId" `
            -Method GET `
            -AccessToken $EmployeeToken

    if (
        $EmployeeDetail.id -ne
        $NumberId
    ) {
        throw "EMPLOYEE received unexpected number."
    }

    Write-Host `
        "[OK] EMPLOYEE can read assigned number detail." `
        -ForegroundColor Green

    Write-Host ""
    Write-Host `
        "==== EMPLOYEE write restrictions ====" `
        -ForegroundColor Cyan

    Assert-HttpStatus `
        -Uri "$BaseUrl/whatsapp-numbers" `
        -Method POST `
        -AccessToken $EmployeeToken `
        -Body @{
            displayName = "Forbidden WhatsApp"
            e164 = "+5511987654321"
        } `
        -ExpectedStatus 403 `
        -Description "EMPLOYEE creating WhatsApp number"

    Assert-HttpStatus `
        -Uri "$BaseUrl/whatsapp-numbers/$NumberId" `
        -Method PATCH `
        -AccessToken $EmployeeToken `
        -Body @{
            displayName = "Forbidden Update"
        } `
        -ExpectedStatus 403 `
        -Description "EMPLOYEE updating WhatsApp number"

    Write-Host ""
    Write-Host `
        "==== ADMIN status management ====" `
        -ForegroundColor Cyan

    $PausedNumber = `
        Invoke-Json `
            -Uri "$BaseUrl/whatsapp-numbers/$NumberId" `
            -Method PATCH `
            -AccessToken $AdminToken `
            -Body @{
                status = "PAUSED"
            }

    if (
        $PausedNumber.status -ne
        "PAUSED"
    ) {
        throw "Number status update failed."
    }

    Write-Host `
        "[OK] ADMIN changed number status to PAUSED." `
        -ForegroundColor Green

    $ActiveNumber = `
        Invoke-Json `
            -Uri "$BaseUrl/whatsapp-numbers/$NumberId" `
            -Method PATCH `
            -AccessToken $AdminToken `
            -Body @{
                status = "ACTIVE"
            }

    if (
        $ActiveNumber.status -ne
        "ACTIVE"
    ) {
        throw "Number status restore failed."
    }

    Write-Host `
        "[OK] ADMIN restored number status to ACTIVE." `
        -ForegroundColor Green

    Write-Host ""
    Write-Host `
        "==== ADMIN removes assignment ====" `
        -ForegroundColor Cyan

    $UnassignedNumber = `
        Invoke-Json `
            -Uri "$BaseUrl/whatsapp-numbers/$NumberId" `
            -Method PATCH `
            -AccessToken $AdminToken `
            -Body @{
                assignedEmployeeId = $null
            }

    if (
        $null -ne
        $UnassignedNumber.assignedEmployeeId
    ) {
        throw "Number was not unassigned."
    }

    Write-Host `
        "[OK] ADMIN removed EMPLOYEE assignment." `
        -ForegroundColor Green

    $EmployeeNumbersAfterRemoval = `
        @(Invoke-Json `
            -Uri "$BaseUrl/whatsapp-numbers" `
            -Method GET `
            -AccessToken $EmployeeToken)

    if (
        Test-CollectionContainsId `
            -Collection $EmployeeNumbersAfterRemoval `
            -Id $NumberId
    ) {
        throw "EMPLOYEE still sees number after assignment removal."
    }

    Write-Host `
        "[OK] EMPLOYEE no longer sees unassigned number." `
        -ForegroundColor Green

    Assert-HttpStatus `
        -Uri "$BaseUrl/whatsapp-numbers/$NumberId" `
        -Method GET `
        -AccessToken $EmployeeToken `
        -ExpectedStatus 404 `
        -Description "EMPLOYEE reading number after assignment removal"

    Write-Host ""
    Write-Host `
        "============================================" `
        -ForegroundColor Green

    Write-Host `
        "[OK] STAGE 3B.2 RUNTIME VALIDATION PASSED." `
        -ForegroundColor Green

    Write-Host `
        "[OK] Phone normalization validated." `
        -ForegroundColor Green

    Write-Host `
        "[OK] Duplicate normalization protection validated." `
        -ForegroundColor Green

    Write-Host `
        "[OK] Invalid phone rejection validated." `
        -ForegroundColor Green

    Write-Host `
        "[OK] ADMIN number management validated." `
        -ForegroundColor Green

    Write-Host `
        "[OK] EMPLOYEE ownership visibility validated." `
        -ForegroundColor Green

    Write-Host `
        "[OK] EMPLOYEE write denial validated." `
        -ForegroundColor Green

    Write-Host `
        "[OK] Assignment removal visibility validated." `
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