param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [int]$SmokePort = 3101
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function ConvertTo-PlainText {
    param([Security.SecureString]$SecureValue)

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)

    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Read-DotEnvValue {
    param(
        [string]$Path,
        [string]$Key
    )

    $line = Get-Content -LiteralPath $Path |
        Where-Object { $_ -match ("^\s*" + [regex]::Escape($Key) + "\s*=") } |
        Select-Object -First 1

    if (-not $line) {
        return $null
    }

    return ($line -split "=", 2)[1].Trim()
}

Set-Location $ProjectRoot

$envPath = Join-Path $ProjectRoot ".env"
if (-not (Test-Path -LiteralPath $envPath)) {
    throw ".env not found."
}

$organizationSlug = Read-DotEnvValue -Path $envPath -Key "SEED_ORGANIZATION_SLUG"
$adminEmail = Read-DotEnvValue -Path $envPath -Key "SEED_ADMIN_EMAIL"

if ([string]::IsNullOrWhiteSpace($organizationSlug)) {
    $organizationSlug = "crm-ads-whatsapp"
}

if ([string]::IsNullOrWhiteSpace($adminEmail)) {
    $adminEmail = "admin@example.com"
}

$passwordSecure = Read-Host "Digite a senha atual do ADMIN para o smoke test" -AsSecureString
$password = ConvertTo-PlainText $passwordSecure

$previousPort = $env:PORT
$env:PORT = [string]$SmokePort

$logDirectory = Join-Path $ProjectRoot ".stage-backups\stage2b-smoke"
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null

$stdoutPath = Join-Path $logDirectory "api.stdout.log"
$stderrPath = Join-Path $logDirectory "api.stderr.log"

$process = $null

try {
    & pnpm --filter "@crm/api" build
    if ($LASTEXITCODE -ne 0) {
        throw "API build failed with exit code ${LASTEXITCODE}."
    }

    $process = Start-Process `
        -FilePath "node" `
        -ArgumentList "apps/api/dist/main.js" `
        -WorkingDirectory $ProjectRoot `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -NoNewWindow `
        -PassThru

    $readyUrl = "http://127.0.0.1:$SmokePort/api/v1/health/ready"
    $deadline = (Get-Date).AddSeconds(25)
    $ready = $false

    while ((Get-Date) -lt $deadline) {
        if ($process.HasExited) {
            break
        }

        try {
            $health = Invoke-RestMethod -Uri $readyUrl -Method Get -TimeoutSec 2
            if ($health.status -eq "ok") {
                $ready = $true
                break
            }
        }
        catch {
            Start-Sleep -Milliseconds 500
        }
    }

    if (-not $ready) {
        Write-Host "---- API STDOUT ----"
        if (Test-Path -LiteralPath $stdoutPath) {
            Get-Content -LiteralPath $stdoutPath
        }

        Write-Host "---- API STDERR ----"
        if (Test-Path -LiteralPath $stderrPath) {
            Get-Content -LiteralPath $stderrPath
        }

        throw "API did not become ready on port $SmokePort."
    }

    $body = @{
        email = $adminEmail
        organizationSlug = $organizationSlug
        password = $password
    } | ConvertTo-Json

    $response = Invoke-RestMethod `
        -Uri "http://127.0.0.1:$SmokePort/api/v1/auth/login" `
        -Method Post `
        -ContentType "application/json" `
        -Body $body `
        -TimeoutSec 10

    if (-not $response.accessToken) {
        throw "Login response did not include accessToken."
    }

    if (-not $response.refreshToken) {
        throw "Login response did not include refreshToken."
    }

    if (-not $response.sessionId) {
        throw "Login response did not include sessionId."
    }

    if ($response.user.roles -notcontains "ADMIN") {
        throw "Login response did not include ADMIN role."
    }

    Write-Host "[OK] API ready." -ForegroundColor Green
    Write-Host "[OK] ADMIN login succeeded." -ForegroundColor Green
    Write-Host "[OK] Access token issued." -ForegroundColor Green
    Write-Host "[OK] Refresh token issued and session persisted." -ForegroundColor Green
    Write-Host "[OK] Etapa 2B runtime smoke passed." -ForegroundColor Green
}
finally {
    if ($process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }

    if ($null -eq $previousPort) {
        Remove-Item Env:PORT -ErrorAction SilentlyContinue
    }
    else {
        $env:PORT = $previousPort
    }

    $password = $null
}