param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [int]$SmokePort = 3104
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function ConvertTo-PlainText {
    param(
        [Parameter(Mandatory = $true)]
        [Security.SecureString]$SecureValue
    )

    $Pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR(
        $SecureValue
    )

    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
            $Pointer
        )
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR(
            $Pointer
        )
    }
}

function Read-DotEnvValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    $Pattern = "^\s*" + [regex]::Escape($Key) + "\s*="

    $Line = Get-Content -LiteralPath $Path |
        Where-Object {
            $_ -match $Pattern
        } |
        Select-Object -First 1

    if (-not $Line) {
        return $null
    }

    return ($Line -split "=", 2)[1].Trim()
}

function Invoke-JsonPost {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [hashtable]$Body
    )

    return Invoke-RestMethod `
        -Uri $Uri `
        -Method Post `
        -ContentType "application/json" `
        -Body ($Body | ConvertTo-Json -Depth 10) `
        -TimeoutSec 15
}

function Invoke-AuthenticatedGet {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [string]$AccessToken
    )

    return Invoke-RestMethod `
        -Uri $Uri `
        -Method Get `
        -Headers @{
            Authorization = "Bearer $AccessToken"
        } `
        -TimeoutSec 15
}

function Assert-HttpStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [ValidateSet("GET", "POST")]
        [string]$Method = "GET",

        [hashtable]$Headers = @{},

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
            Headers = $Headers
            TimeoutSec = 15
            UseBasicParsing = $true
        }

        if ($null -ne $Body) {
            $Parameters.ContentType = "application/json"
            $Parameters.Body = $Body | ConvertTo-Json -Depth 10
        }

        Invoke-WebRequest @Parameters |
            Out-Null

        if ($ExpectedStatus -ne 200) {
            throw "$Description unexpectedly returned HTTP 200."
        }

        Write-Host `
            "[OK] $Description returned HTTP 200." `
            -ForegroundColor Green
    }
    catch {
        $StatusCode = $null

        if (
            $_.Exception.Response -and
            $_.Exception.Response.StatusCode
        ) {
            try {
                $StatusCode = [int]$_.Exception.Response.StatusCode
            }
            catch {
                $StatusCode = $null
            }
        }

        if ($StatusCode -ne $ExpectedStatus) {
            throw "$Description returned HTTP $StatusCode instead of $ExpectedStatus."
        }

        Write-Host `
            "[OK] $Description returned HTTP $ExpectedStatus." `
            -ForegroundColor Green
    }
}

function Assert-TokenResponse {
    param(
        [Parameter(Mandatory = $true)]
        $Response,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    if (-not $Response.accessToken) {
        throw "$Description did not return accessToken."
    }

    if (-not $Response.refreshToken) {
        throw "$Description did not return refreshToken."
    }

    if (-not $Response.sessionId) {
        throw "$Description did not return sessionId."
    }

    if ($Response.tokenType -ne "Bearer") {
        throw "$Description returned invalid tokenType."
    }

    Write-Host `
        "[OK] $Description returned complete authentication payload." `
        -ForegroundColor Green
}

Set-Location $ProjectRoot

$EnvPath = Join-Path $ProjectRoot ".env"

if (-not (Test-Path -LiteralPath $EnvPath)) {
    throw ".env not found."
}

$OrganizationSlug = Read-DotEnvValue `
    -Path $EnvPath `
    -Key "SEED_ORGANIZATION_SLUG"

$AdminEmail = Read-DotEnvValue `
    -Path $EnvPath `
    -Key "SEED_ADMIN_EMAIL"

$EmployeeEmail = "employee@example.com"

if ([string]::IsNullOrWhiteSpace($OrganizationSlug)) {
    $OrganizationSlug = "crm-ads-whatsapp"
}

if ([string]::IsNullOrWhiteSpace($AdminEmail)) {
    $AdminEmail = "admin@example.com"
}

$AdminPasswordSecure = Read-Host `
    "Digite a senha atual do ADMIN para a validacao integrada da Etapa 2" `
    -AsSecureString

$AdminPassword = ConvertTo-PlainText `
    $AdminPasswordSecure

$EmployeePasswordSecure = Read-Host `
    "Digite a senha do EMPLOYEE para a validacao integrada da Etapa 2" `
    -AsSecureString

$EmployeePassword = ConvertTo-PlainText `
    $EmployeePasswordSecure

$PreviousPort = $env:PORT
$env:PORT = [string]$SmokePort

$LogDirectory = Join-Path `
    $ProjectRoot `
    ".stage-backups\stage2e-smoke"

New-Item `
    -ItemType Directory `
    -Path $LogDirectory `
    -Force |
    Out-Null

$StdoutPath = Join-Path `
    $LogDirectory `
    "api.stdout.log"

$StderrPath = Join-Path `
    $LogDirectory `
    "api.stderr.log"

$Process = $null

try {
    # --------------------------------------------------------
    # 1. Banco
    # --------------------------------------------------------

    Write-Host ""
    Write-Host `
        "==== Etapa 2 - Database foundation ====" `
        -ForegroundColor Cyan

    & pnpm db:migrate:status

    if ($LASTEXITCODE -ne 0) {
        throw "Database migration status failed with exit code ${LASTEXITCODE}."
    }

    & pnpm db:verify-seed

    if ($LASTEXITCODE -ne 0) {
        throw "Database seed verification failed with exit code ${LASTEXITCODE}."
    }

    Write-Host `
        "[OK] Database migration state validated." `
        -ForegroundColor Green

    Write-Host `
        "[OK] Organization, roles and permissions seed validated." `
        -ForegroundColor Green

    # --------------------------------------------------------
    # 2. Build runtime completo
    # --------------------------------------------------------

    Write-Host ""
    Write-Host `
        "==== Runtime build ====" `
        -ForegroundColor Cyan

    & pnpm exec turbo run build --filter="@crm/api"

    if ($LASTEXITCODE -ne 0) {
        throw "API dependency build failed with exit code ${LASTEXITCODE}."
    }

    # --------------------------------------------------------
    # 3. Iniciar API
    # --------------------------------------------------------

    $Process = Start-Process `
        -FilePath "node" `
        -ArgumentList "apps/api/dist/main.js" `
        -WorkingDirectory $ProjectRoot `
        -RedirectStandardOutput $StdoutPath `
        -RedirectStandardError $StderrPath `
        -NoNewWindow `
        -PassThru

    $BaseUrl = "http://127.0.0.1:$SmokePort/api/v1"
    $ReadyUrl = "$BaseUrl/health/ready"

    $Deadline = (Get-Date).AddSeconds(25)
    $Ready = $false

    while ((Get-Date) -lt $Deadline) {
        if ($Process.HasExited) {
            break
        }

        try {
            $Health = Invoke-RestMethod `
                -Uri $ReadyUrl `
                -Method Get `
                -TimeoutSec 2

            if ($Health.status -eq "ok") {
                $Ready = $true
                break
            }
        }
        catch {
            Start-Sleep -Milliseconds 500
        }
    }

    if (-not $Ready) {
        Write-Host ""
        Write-Host "---- API STDOUT ----"

        if (Test-Path -LiteralPath $StdoutPath) {
            Get-Content -LiteralPath $StdoutPath
        }

        Write-Host ""
        Write-Host "---- API STDERR ----"

        if (Test-Path -LiteralPath $StderrPath) {
            Get-Content -LiteralPath $StderrPath
        }

        throw "API did not become ready on port $SmokePort."
    }

    Write-Host `
        "[OK] API ready with PostgreSQL connected." `
        -ForegroundColor Green

    # --------------------------------------------------------
    # 4. Protecao sem autenticacao
    # --------------------------------------------------------

    Write-Host ""
    Write-Host `
        "==== Authentication boundary ====" `
        -ForegroundColor Cyan

    Assert-HttpStatus `
        -Uri "$BaseUrl/auth/me" `
        -ExpectedStatus 401 `
        -Description "Protected route without token"

    Assert-HttpStatus `
        -Uri "$BaseUrl/auth/me" `
        -Headers @{
            Authorization = "Bearer invalid-token"
        } `
        -ExpectedStatus 401 `
        -Description "Protected route with invalid token"

    # --------------------------------------------------------
    # 5. ADMIN login + RBAC
    # --------------------------------------------------------

    Write-Host ""
    Write-Host `
        "==== ADMIN identity and authorization ====" `
        -ForegroundColor Cyan

    $AdminLogin = Invoke-JsonPost `
        -Uri "$BaseUrl/auth/login" `
        -Body @{
            email = $AdminEmail
            organizationSlug = $OrganizationSlug
            password = $AdminPassword
        }

    Assert-TokenResponse `
        -Response $AdminLogin `
        -Description "ADMIN login"

    $AdminAccessToken = [string]$AdminLogin.accessToken
    $AdminRefreshTokenA = [string]$AdminLogin.refreshToken

    $AdminMe = Invoke-AuthenticatedGet `
        -Uri "$BaseUrl/auth/me" `
        -AccessToken $AdminAccessToken

    if ($AdminMe.userId -ne $AdminLogin.user.userId) {
        throw "ADMIN principal returned unexpected userId."
    }

    if (
        $AdminMe.organizationId -ne
        $AdminLogin.user.organizationId
    ) {
        throw "ADMIN principal returned unexpected organizationId."
    }

    Write-Host `
        "[OK] ADMIN principal and organization binding validated." `
        -ForegroundColor Green

    $AdminCheck = Invoke-AuthenticatedGet `
        -Uri "$BaseUrl/auth/admin-check" `
        -AccessToken $AdminAccessToken

    if ($AdminCheck.userId -ne $AdminLogin.user.userId) {
        throw "ADMIN authorization returned unexpected principal."
    }

    Write-Host `
        "[OK] ADMIN role and organization.manage permission validated." `
        -ForegroundColor Green

    # --------------------------------------------------------
    # 6. Refresh rotation
    # --------------------------------------------------------

    Write-Host ""
    Write-Host `
        "==== Refresh token rotation ====" `
        -ForegroundColor Cyan

    $AdminRefresh = Invoke-JsonPost `
        -Uri "$BaseUrl/auth/refresh" `
        -Body @{
            refreshToken = $AdminRefreshTokenA
        }

    Assert-TokenResponse `
        -Response $AdminRefresh `
        -Description "ADMIN refresh rotation"

    $AdminRefreshTokenB = [string]$AdminRefresh.refreshToken

    if ($AdminRefreshTokenA -eq $AdminRefreshTokenB) {
        throw "Refresh token was not rotated."
    }

    if ($AdminRefresh.sessionId -ne $AdminLogin.sessionId) {
        throw "Refresh rotation changed sessionId."
    }

    Write-Host `
        "[OK] Refresh token rotated inside the same session." `
        -ForegroundColor Green

    # --------------------------------------------------------
    # 7. Reuse detection
    # --------------------------------------------------------

    Write-Host ""
    Write-Host `
        "==== Refresh reuse detection ====" `
        -ForegroundColor Cyan

    Assert-HttpStatus `
        -Uri "$BaseUrl/auth/refresh" `
        -Method POST `
        -Body @{
            refreshToken = $AdminRefreshTokenA
        } `
        -ExpectedStatus 401 `
        -Description "Consumed refresh token reuse"

    Assert-HttpStatus `
        -Uri "$BaseUrl/auth/refresh" `
        -Method POST `
        -Body @{
            refreshToken = $AdminRefreshTokenB
        } `
        -ExpectedStatus 401 `
        -Description "Rotated token after reuse revocation"

    Write-Host `
        "[OK] Refresh-token family reuse protection validated." `
        -ForegroundColor Green

    # --------------------------------------------------------
    # 8. EMPLOYEE RBAC
    # --------------------------------------------------------

    Write-Host ""
    Write-Host `
        "==== EMPLOYEE authorization ====" `
        -ForegroundColor Cyan

    $EmployeeLogin = Invoke-JsonPost `
        -Uri "$BaseUrl/auth/login" `
        -Body @{
            email = $EmployeeEmail
            organizationSlug = $OrganizationSlug
            password = $EmployeePassword
        }

    Assert-TokenResponse `
        -Response $EmployeeLogin `
        -Description "EMPLOYEE login"

    $EmployeeAccessToken = [string]$EmployeeLogin.accessToken
    $EmployeeRefreshToken = [string]$EmployeeLogin.refreshToken

    $EmployeeMe = Invoke-AuthenticatedGet `
        -Uri "$BaseUrl/auth/me" `
        -AccessToken $EmployeeAccessToken

    if (
        $EmployeeMe.userId -ne
        $EmployeeLogin.user.userId
    ) {
        throw "EMPLOYEE principal returned unexpected userId."
    }

    Write-Host `
        "[OK] EMPLOYEE profile.read permission validated." `
        -ForegroundColor Green

    Assert-HttpStatus `
        -Uri "$BaseUrl/auth/admin-check" `
        -Headers @{
            Authorization = "Bearer $EmployeeAccessToken"
        } `
        -ExpectedStatus 403 `
        -Description "EMPLOYEE accessing ADMIN resource"

    Write-Host `
        "[OK] EMPLOYEE forbidden boundary validated." `
        -ForegroundColor Green

    # --------------------------------------------------------
    # 9. Logout EMPLOYEE
    # --------------------------------------------------------

    $EmployeeLogout = Invoke-JsonPost `
        -Uri "$BaseUrl/auth/logout" `
        -Body @{
            refreshToken = $EmployeeRefreshToken
        }

    if ($EmployeeLogout.success -ne $true) {
        throw "EMPLOYEE logout failed."
    }

    Assert-HttpStatus `
        -Uri "$BaseUrl/auth/me" `
        -Headers @{
            Authorization = "Bearer $EmployeeAccessToken"
        } `
        -ExpectedStatus 401 `
        -Description "EMPLOYEE access after session revocation"

    Write-Host `
        "[OK] Session revocation invalidates existing access token." `
        -ForegroundColor Green

    # --------------------------------------------------------
    # 10. Logout all
    # --------------------------------------------------------

    Write-Host ""
    Write-Host `
        "==== Multi-session revocation ====" `
        -ForegroundColor Cyan

    $AdminSessionA = Invoke-JsonPost `
        -Uri "$BaseUrl/auth/login" `
        -Body @{
            email = $AdminEmail
            organizationSlug = $OrganizationSlug
            password = $AdminPassword
        }

    $AdminSessionB = Invoke-JsonPost `
        -Uri "$BaseUrl/auth/login" `
        -Body @{
            email = $AdminEmail
            organizationSlug = $OrganizationSlug
            password = $AdminPassword
        }

    Assert-TokenResponse `
        -Response $AdminSessionA `
        -Description "ADMIN multi-session A"

    Assert-TokenResponse `
        -Response $AdminSessionB `
        -Description "ADMIN multi-session B"

    if ($AdminSessionA.sessionId -eq $AdminSessionB.sessionId) {
        throw "Independent logins created the same sessionId."
    }

    $LogoutAll = Invoke-JsonPost `
        -Uri "$BaseUrl/auth/logout-all" `
        -Body @{
            refreshToken = [string]$AdminSessionA.refreshToken
        }

    if ($LogoutAll.success -ne $true) {
        throw "Logout-all failed."
    }

    Assert-HttpStatus `
        -Uri "$BaseUrl/auth/refresh" `
        -Method POST `
        -Body @{
            refreshToken = [string]$AdminSessionB.refreshToken
        } `
        -ExpectedStatus 401 `
        -Description "Second ADMIN session after logout-all"

    Assert-HttpStatus `
        -Uri "$BaseUrl/auth/me" `
        -Headers @{
            Authorization = "Bearer $($AdminSessionB.accessToken)"
        } `
        -ExpectedStatus 401 `
        -Description "Second ADMIN access token after logout-all"

    Write-Host `
        "[OK] Logout-all revoked all active user sessions." `
        -ForegroundColor Green

    # --------------------------------------------------------
    # Resultado final
    # --------------------------------------------------------

    Write-Host ""
    Write-Host `
        "====================================================" `
        -ForegroundColor Green

    Write-Host `
        "[OK] ETAPA 2 INTEGRATED RUNTIME VALIDATION PASSED." `
        -ForegroundColor Green

    Write-Host `
        "[OK] PostgreSQL and seed validated." `
        -ForegroundColor Green

    Write-Host `
        "[OK] Password authentication validated." `
        -ForegroundColor Green

    Write-Host `
        "[OK] Access JWT validation validated." `
        -ForegroundColor Green

    Write-Host `
        "[OK] Refresh rotation validated." `
        -ForegroundColor Green

    Write-Host `
        "[OK] Refresh reuse detection validated." `
        -ForegroundColor Green

    Write-Host `
        "[OK] Session revocation validated." `
        -ForegroundColor Green

    Write-Host `
        "[OK] Logout-all validated." `
        -ForegroundColor Green

    Write-Host `
        "[OK] ADMIN RBAC validated." `
        -ForegroundColor Green

    Write-Host `
        "[OK] EMPLOYEE RBAC validated." `
        -ForegroundColor Green

    Write-Host `
        "[OK] Organization binding validated." `
        -ForegroundColor Green

    Write-Host `
        "====================================================" `
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