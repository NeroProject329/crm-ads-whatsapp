param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
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

Set-Location $ProjectRoot

$passwordSecure = Read-Host "Digite a senha inicial do ADMIN" -AsSecureString
$confirmationSecure = Read-Host "Confirme a senha inicial do ADMIN" -AsSecureString

$password = ConvertTo-PlainText $passwordSecure
$confirmation = ConvertTo-PlainText $confirmationSecure

try {
    if ($password -ne $confirmation) {
        throw "Passwords do not match."
    }

    if ($password.Length -lt 12 -or $password.Length -gt 256) {
        throw "ADMIN password must contain between 12 and 256 characters."
    }

    $env:BOOTSTRAP_ADMIN_PASSWORD = $password

    & pnpm --filter "@crm/api" auth:bootstrap-admin
    if ($LASTEXITCODE -ne 0) {
        throw "ADMIN bootstrap failed with exit code ${LASTEXITCODE}."
    }

    Write-Host "[OK] ADMIN activated successfully." -ForegroundColor Green
}
finally {
    Remove-Item Env:BOOTSTRAP_ADMIN_PASSWORD -ErrorAction SilentlyContinue
    $password = $null
    $confirmation = $null
}