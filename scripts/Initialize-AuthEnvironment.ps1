param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-Base64UrlSecret {
    param([int]$ByteLength = 48)

    $bytes = New-Object byte[] $ByteLength
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()

    try {
        $rng.GetBytes($bytes)
    }
    finally {
        $rng.Dispose()
    }

    return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Set-EnvValueIfMissing {
    param(
        [string[]]$Lines,
        [string]$Key,
        [string]$Value
    )

    $pattern = "^\s*" + [regex]::Escape($Key) + "\s*="
    $foundIndex = -1

    for ($index = 0; $index -lt $Lines.Count; $index++) {
        if ($Lines[$index] -match $pattern) {
            $foundIndex = $index
            break
        }
    }

    if ($foundIndex -lt 0) {
        return ($Lines + "$Key=$Value")
    }

    $currentValue = ($Lines[$foundIndex] -split "=", 2)[1].Trim()
    if ([string]::IsNullOrWhiteSpace($currentValue) -or $currentValue -match "CHANGE_ME|example|placeholder") {
        $Lines[$foundIndex] = "$Key=$Value"
    }

    return $Lines
}

$envPath = Join-Path $ProjectRoot ".env"
if (-not (Test-Path -LiteralPath $envPath)) {
    throw ".env not found at $envPath. Etapa 2A must be configured first."
}

$lines = @(Get-Content -LiteralPath $envPath)

$lines = Set-EnvValueIfMissing -Lines $lines -Key "AUTH_ACCESS_TOKEN_SECRET" -Value (New-Base64UrlSecret)
$lines = Set-EnvValueIfMissing -Lines $lines -Key "AUTH_REFRESH_TOKEN_PEPPER" -Value (New-Base64UrlSecret)
$lines = Set-EnvValueIfMissing -Lines $lines -Key "AUTH_ACCESS_TOKEN_ISSUER" -Value "crm-ads-whatsapp-api"
$lines = Set-EnvValueIfMissing -Lines $lines -Key "AUTH_ACCESS_TOKEN_AUDIENCE" -Value "crm-ads-whatsapp"
$lines = Set-EnvValueIfMissing -Lines $lines -Key "AUTH_ACCESS_TOKEN_TTL_SECONDS" -Value "900"
$lines = Set-EnvValueIfMissing -Lines $lines -Key "AUTH_REFRESH_TOKEN_TTL_SECONDS" -Value "2592000"
$lines = Set-EnvValueIfMissing -Lines $lines -Key "AUTH_MAX_FAILED_LOGIN_ATTEMPTS" -Value "5"
$lines = Set-EnvValueIfMissing -Lines $lines -Key "AUTH_LOGIN_LOCK_SECONDS" -Value "900"

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines($envPath, $lines, $utf8NoBom)

Write-Host "[OK] Auth environment initialized in local .env." -ForegroundColor Green
Write-Host "Secrets were not printed and .env remains ignored by Git."