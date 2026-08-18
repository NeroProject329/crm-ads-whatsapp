param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [int]$SmokePort = 3103
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

        [hashtable]$Headers = @{},

        [Parameter(Mandatory = $true)]
        [int]$ExpectedStatus,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    try {
        Invoke-WebRequest `
            -Uri $Uri `
            -Method Get `
            -Headers $Headers `
            -TimeoutSec 15 `
            -UseBasicParsing |
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

$PasswordSecure = Read-Host `
    "Digite a senha atual do ADMIN para o smoke test da 2D" `
    -AsSecureString

$Password = ConvertTo-PlainText `
    $PasswordSecure

$EmployeePasswordSecure = Read-Host `
    "Digite a senha do EMPLOYEE para o teste de RBAC" `
    -AsSecureString

$EmployeePassword = ConvertTo-PlainText `
    $EmployeePasswordSecure

$PreviousPort = $env:PORT
$env:PORT = [string]$SmokePort

$LogDirectory = Join-Path `
    $ProjectRoot `
    ".stage-backups\stage2d-smoke"

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
    Write-Host ""
    Write-Host `
        "==== Build API + dependencies ====" `
        -ForegroundColor Cyan

    & pnpm exec turbo run build --filter="@crm/api"

    if ($LASTEXITCODE -ne 0) {
        throw "API dependency build failed with exit code ${LASTEXITCODE}."
    }

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
        "[OK] API ready." `
        -ForegroundColor Green

    # --------------------------------------------------------
    # 1. Sem token
    # --------------------------------------------------------

    Write-Host ""
    Write-Host `
        "==== Authentication Guard ====" `
        -ForegroundColor Cyan

    Assert-HttpStatus `
        -Uri "$BaseUrl/auth/me" `
        -ExpectedStatus 401 `
        -Description "Protected endpoint without Authorization"

    # --------------------------------------------------------
    # 2. Token invalido
    # --------------------------------------------------------

    Assert-HttpStatus `
        -Uri "$BaseUrl/auth/me" `
        -Headers @{
            Authorization = "Bearer invalid-token"
        } `
        -ExpectedStatus 401 `
        -Description "Protected endpoint with invalid token"

    # --------------------------------------------------------
    # 3. Login ADMIN
    # --------------------------------------------------------

    Write-Host ""
    Write-Host `
        "==== ADMIN authorization ====" `
        -ForegroundColor Cyan

    $Login = Invoke-JsonPost `
        -Uri "$BaseUrl/auth/login" `
        -Body @{
            email = $AdminEmail
            organizationSlug = $OrganizationSlug
            password = $Password
        }

    if (-not $Login.accessToken) {
        throw "Login did not return accessToken."
    }

    if (-not $Login.refreshToken) {
        throw "Login did not return refreshToken."
    }

    $AccessToken = [string]$Login.accessToken
    $RefreshToken = [string]$Login.refreshToken

    Write-Host `
        "[OK] ADMIN login succeeded." `
        -ForegroundColor Green

    # --------------------------------------------------------
    # 4. /auth/me ADMIN
    # --------------------------------------------------------

    $Me = Invoke-AuthenticatedGet `
        -Uri "$BaseUrl/auth/me" `
        -AccessToken $AccessToken

    if ($Me.userId -ne $Login.user.userId) {
        throw "/auth/me returned unexpected userId."
    }

    if (
        $Me.organizationId -ne
        $Login.user.organizationId
    ) {
        throw "/auth/me returned unexpected organizationId."
    }

    Write-Host `
        "[OK] Authenticated principal loaded." `
        -ForegroundColor Green

    Write-Host `
        "[OK] Organization identity preserved." `
        -ForegroundColor Green

    # --------------------------------------------------------
    # 5. ADMIN role + permission
    # --------------------------------------------------------

    $AdminCheck = Invoke-AuthenticatedGet `
        -Uri "$BaseUrl/auth/admin-check" `
        -AccessToken $AccessToken

    if (
        $AdminCheck.userId -ne
        $Login.user.userId
    ) {
        throw "ADMIN authorization returned unexpected principal."
    }

    Write-Host `
        "[OK] ADMIN role authorization passed." `
        -ForegroundColor Green

    Write-Host `
        "[OK] organization.manage permission passed." `
        -ForegroundColor Green

    # --------------------------------------------------------
    # 6. Revoga sessao ADMIN via logout
    # --------------------------------------------------------

    $Logout = Invoke-JsonPost `
        -Uri "$BaseUrl/auth/logout" `
        -Body @{
            refreshToken = $RefreshToken
        }

    if ($Logout.success -ne $true) {
        throw "Logout failed."
    }

    Write-Host `
        "[OK] Session revoked through logout." `
        -ForegroundColor Green

    # O access token continua criptograficamente valido,
    # mas a Session foi marcada como REVOKED no PostgreSQL.
    Assert-HttpStatus `
        -Uri "$BaseUrl/auth/me" `
        -Headers @{
            Authorization = "Bearer $AccessToken"
        } `
        -ExpectedStatus 401 `
        -Description "Access token after session revocation"

    Write-Host `
        "[OK] Revoked session invalidates existing access token immediately." `
        -ForegroundColor Green

    # --------------------------------------------------------
    # 7. EMPLOYEE RBAC
    # --------------------------------------------------------

    Write-Host ""
    Write-Host `
        "==== EMPLOYEE RBAC ====" `
        -ForegroundColor Cyan

    $EmployeeLogin = Invoke-JsonPost `
        -Uri "$BaseUrl/auth/login" `
        -Body @{
            email = $EmployeeEmail
            organizationSlug = $OrganizationSlug
            password = $EmployeePassword
        }

    if (-not $EmployeeLogin.accessToken) {
        throw "EMPLOYEE login did not return accessToken."
    }

    if (-not $EmployeeLogin.refreshToken) {
        throw "EMPLOYEE login did not return refreshToken."
    }

    $EmployeeAccessToken = `
        [string]$EmployeeLogin.accessToken

    $EmployeeRefreshToken = `
        [string]$EmployeeLogin.refreshToken

    Write-Host `
        "[OK] EMPLOYEE login succeeded." `
        -ForegroundColor Green

    # EMPLOYEE possui profile.read
    $EmployeeMe = Invoke-AuthenticatedGet `
        -Uri "$BaseUrl/auth/me" `
        -AccessToken $EmployeeAccessToken

    if (
        $EmployeeMe.userId -ne
        $EmployeeLogin.user.userId
    ) {
        throw "/auth/me returned unexpected EMPLOYEE userId."
    }

    if (
        $EmployeeMe.organizationId -ne
        $EmployeeLogin.user.organizationId
    ) {
        throw "/auth/me returned unexpected EMPLOYEE organizationId."
    }

    Write-Host `
        "[OK] EMPLOYEE profile.read permission passed." `
        -ForegroundColor Green

    # EMPLOYEE nao possui ADMIN nem organization.manage
    Assert-HttpStatus `
        -Uri "$BaseUrl/auth/admin-check" `
        -Headers @{
            Authorization = "Bearer $EmployeeAccessToken"
        } `
        -ExpectedStatus 403 `
        -Description "EMPLOYEE accessing ADMIN endpoint"

    Write-Host `
        "[OK] EMPLOYEE denied ADMIN role/permission." `
        -ForegroundColor Green

    # --------------------------------------------------------
    # 8. Limpeza da sessao EMPLOYEE
    # --------------------------------------------------------

    $EmployeeLogout = Invoke-JsonPost `
        -Uri "$BaseUrl/auth/logout" `
        -Body @{
            refreshToken = $EmployeeRefreshToken
        }

    if ($EmployeeLogout.success -ne $true) {
        throw "EMPLOYEE logout failed."
    }

    Write-Host `
        "[OK] EMPLOYEE session cleaned up." `
        -ForegroundColor Green

    Assert-HttpStatus `
        -Uri "$BaseUrl/auth/me" `
        -Headers @{
            Authorization = "Bearer $EmployeeAccessToken"
        } `
        -ExpectedStatus 401 `
        -Description "EMPLOYEE access token after logout"

    # --------------------------------------------------------
    # Resultado
    # --------------------------------------------------------

    Write-Host ""
    Write-Host `
        "========================================" `
        -ForegroundColor Green

    Write-Host `
        "[OK] Etapa 2D authorization smoke passed." `
        -ForegroundColor Green

    Write-Host `
        "[OK] Bearer authentication validated." `
        -ForegroundColor Green

    Write-Host `
        "[OK] Session status validation validated." `
        -ForegroundColor Green

    Write-Host `
        "[OK] ADMIN role authorization validated." `
        -ForegroundColor Green

    Write-Host `
        "[OK] Permission authorization validated." `
        -ForegroundColor Green

    Write-Host `
        "[OK] EMPLOYEE profile permission validated." `
        -ForegroundColor Green

    Write-Host `
        "[OK] EMPLOYEE forbidden access validated with HTTP 403." `
        -ForegroundColor Green

    Write-Host `
        "[OK] Organization binding validated." `
        -ForegroundColor Green

    Write-Host `
        "========================================" `
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

    $Password = $null
    $EmployeePassword = $null
}