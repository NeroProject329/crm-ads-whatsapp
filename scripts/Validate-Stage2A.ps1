[CmdletBinding()]
param(
    [switch]$SkipInstall,
    [switch]$WithDatabase
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    Write-Host "`n> $Command $($Arguments -join ' ')" -ForegroundColor Cyan
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $Command $($Arguments -join ' ')"
    }
}

if (-not $SkipInstall) {
    Invoke-NativeCommand -Command "pnpm" -Arguments @("install")
}

Invoke-NativeCommand -Command "pnpm" -Arguments @("db:format")
Invoke-NativeCommand -Command "pnpm" -Arguments @("db:generate")
Invoke-NativeCommand -Command "pnpm" -Arguments @("db:validate")
Invoke-NativeCommand -Command "pnpm" -Arguments @("format")
Invoke-NativeCommand -Command "pnpm" -Arguments @("ci:check")

if ($WithDatabase) {
    Invoke-NativeCommand -Command "pnpm" -Arguments @("db:migrate:status")
    Invoke-NativeCommand -Command "pnpm" -Arguments @("db:health")
    Invoke-NativeCommand -Command "pnpm" -Arguments @("db:verify-seed")
    Invoke-NativeCommand -Command "pnpm" -Arguments @("api:health:verify")
}

Write-Host "`nEtapa 2A code validation completed successfully." -ForegroundColor Green
Write-Host "No migration or seed mutation was executed by this script." -ForegroundColor Yellow
