param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [int]$SmokePort = 3102
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

    $Json = $Body | ConvertTo-Json -Depth 10

    return Invoke-RestMethod `
        -Uri $Uri `
        -Method Post `
        -ContentType "application/json" `
        -Body $Json `
        -TimeoutSec 15
}

function Assert-UnauthorizedPost {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [hashtable]$Body,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    $Json = $Body | ConvertTo-Json -Depth 10

    try {
        Invoke-RestMethod `
            -Uri $Uri `
            -Method Post `
            -ContentType "application/json" `
            -Body $Json `
            -TimeoutSec 15 |
            Out-Null

        throw "$Description should have returned HTTP 401."
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

        if ($StatusCode -ne 401) {
            throw "$Description failed with unexpected status code: $StatusCode"
        }

        Write-Host "[OK] $Description returned HTTP 401." `
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
        throw "$Description returned unexpected tokenType."
    }

    Write-Host "[OK] $Description returned valid token payload." `
        -ForegroundColor Green
}

Set-Location $ProjectRoot

$EnvPath = Join-Path $ProjectRoot ".env"

if (-not (Test-Path -LiteralPath $EnvPath)) {
    throw ".env not found at $EnvPath."
}

$OrganizationSlug = Read-DotEnvValue `
    -Path $EnvPath `
    -Key "SEED_ORGANIZATION_SLUG"

$AdminEmail = Read-DotEnvValue `
    -Path $EnvPath `
    -Key "SEED_ADMIN_EMAIL"

if ([string]::IsNullOrWhiteSpace($OrganizationSlug)) {
    $OrganizationSlug = "crm-ads-whatsapp"
}

if ([string]::IsNullOrWhiteSpace($AdminEmail)) {
    $AdminEmail = "admin@example.com"
}

$PasswordSecure = Read-Host `
    "Digite a senha atual do ADMIN para o smoke test da 2C" `
    -AsSecureString

$Password = ConvertTo-PlainText $PasswordSecure

$PreviousPort = $env:PORT
$env:PORT = [string]$SmokePort

$LogDirectory = Join-Path `
    $ProjectRoot `
    ".stage-backups\stage2c-smoke"

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
    Write-Host "==== Build da API ====" `
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

    Write-Host "[OK] API ready." `
        -ForegroundColor Green

    $LoginUrl = "$BaseUrl/auth/login"
    $RefreshUrl = "$BaseUrl/auth/refresh"
    $LogoutUrl = "$BaseUrl/auth/logout"
    $LogoutAllUrl = "$BaseUrl/auth/logout-all"

    $LoginBody = @{
        email = $AdminEmail
        organizationSlug = $OrganizationSlug
        password = $Password
    }

    # --------------------------------------------------------
    # TESTE 1
    # Refresh rotation
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "==== Refresh rotation ====" `
        -ForegroundColor Cyan

    $Login1 = Invoke-JsonPost `
        -Uri $LoginUrl `
        -Body $LoginBody

    Assert-TokenResponse `
        -Response $Login1 `
        -Description "Initial login"

    $OriginalRefreshToken = [string]$Login1.refreshToken

    $Refresh1 = Invoke-JsonPost `
        -Uri $RefreshUrl `
        -Body @{
            refreshToken = $OriginalRefreshToken
        }

    Assert-TokenResponse `
        -Response $Refresh1 `
        -Description "Refresh rotation"

    $RotatedRefreshToken = [string]$Refresh1.refreshToken

    if ($RotatedRefreshToken -eq $OriginalRefreshToken) {
        throw "Refresh token was not rotated."
    }

    if ($Refresh1.sessionId -ne $Login1.sessionId) {
        throw "Refresh rotation unexpectedly changed sessionId."
    }

    Write-Host "[OK] Refresh token rotated." `
        -ForegroundColor Green

    Write-Host "[OK] Session ID preserved during rotation." `
        -ForegroundColor Green

    # --------------------------------------------------------
    # TESTE 2
    # Reuse detection
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "==== Refresh reuse detection ====" `
        -ForegroundColor Cyan

    Assert-UnauthorizedPost `
        -Uri $RefreshUrl `
        -Body @{
            refreshToken = $OriginalRefreshToken
        } `
        -Description "Consumed refresh-token reuse"

    Assert-UnauthorizedPost `
        -Uri $RefreshUrl `
        -Body @{
            refreshToken = $RotatedRefreshToken
        } `
        -Description "Rotated token after family revocation"

    Write-Host "[OK] Reuse detection revoked the session/family." `
        -ForegroundColor Green

    # --------------------------------------------------------
    # TESTE 3
    # Logout da sessão atual
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "==== Logout ====" `
        -ForegroundColor Cyan

    $Login2 = Invoke-JsonPost `
        -Uri $LoginUrl `
        -Body $LoginBody

    Assert-TokenResponse `
        -Response $Login2 `
        -Description "Login before logout"

    $LogoutResponse = Invoke-JsonPost `
        -Uri $LogoutUrl `
        -Body @{
            refreshToken = [string]$Login2.refreshToken
        }

    if ($LogoutResponse.success -ne $true) {
        throw "Logout did not return success=true."
    }

    Write-Host "[OK] Logout returned success=true." `
        -ForegroundColor Green

    Assert-UnauthorizedPost `
        -Uri $RefreshUrl `
        -Body @{
            refreshToken = [string]$Login2.refreshToken
        } `
        -Description "Refresh after logout"

    Write-Host "[OK] Logout revoked the current session." `
        -ForegroundColor Green

    # --------------------------------------------------------
    # TESTE 4
    # Logout all
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "==== Logout all ====" `
        -ForegroundColor Cyan

    $Login3 = Invoke-JsonPost `
        -Uri $LoginUrl `
        -Body $LoginBody

    $Login4 = Invoke-JsonPost `
        -Uri $LoginUrl `
        -Body $LoginBody

    Assert-TokenResponse `
        -Response $Login3 `
        -Description "Logout-all session A"

    Assert-TokenResponse `
        -Response $Login4 `
        -Description "Logout-all session B"

    if ($Login3.sessionId -eq $Login4.sessionId) {
        throw "Two logins unexpectedly created the same session."
    }

    $LogoutAllResponse = Invoke-JsonPost `
        -Uri $LogoutAllUrl `
        -Body @{
            refreshToken = [string]$Login3.refreshToken
        }

    if ($LogoutAllResponse.success -ne $true) {
        throw "Logout-all did not return success=true."
    }

    Write-Host "[OK] Logout-all returned success=true." `
        -ForegroundColor Green

    Assert-UnauthorizedPost `
        -Uri $RefreshUrl `
        -Body @{
            refreshToken = [string]$Login3.refreshToken
        } `
        -Description "Session A after logout-all"

    Assert-UnauthorizedPost `
        -Uri $RefreshUrl `
        -Body @{
            refreshToken = [string]$Login4.refreshToken
        } `
        -Description "Session B after logout-all"

    Write-Host "[OK] Logout-all revoked all active user sessions." `
        -ForegroundColor Green

    # --------------------------------------------------------
    # Resultado
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "========================================" `
        -ForegroundColor Green

    Write-Host "[OK] Etapa 2C runtime smoke passed." `
        -ForegroundColor Green

    Write-Host "[OK] Refresh rotation validated." `
        -ForegroundColor Green

    Write-Host "[OK] Refresh reuse detection validated." `
        -ForegroundColor Green

    Write-Host "[OK] Session revocation validated." `
        -ForegroundColor Green

    Write-Host "[OK] Logout validated." `
        -ForegroundColor Green

    Write-Host "[OK] Logout-all validated." `
        -ForegroundColor Green

    Write-Host "========================================" `
        -ForegroundColor Green
}
finally {
    if ($Process -and -not $Process.HasExited) {
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
}