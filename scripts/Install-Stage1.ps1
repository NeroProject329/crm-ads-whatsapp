[CmdletBinding()]
param(
    [switch]$SkipChecks,
    [switch]$CleanInstall
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter()]
        [string[]]$Arguments = @()
    )

    Write-Host ("> {0} {1}" -f $Command, ($Arguments -join " ")) -ForegroundColor DarkGray
    & $Command @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $Command $($Arguments -join ' ')"
    }
}

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

& "$PSScriptRoot\Check-Environment.ps1"

if ($CleanInstall) {
    Write-Host "Removing previous node_modules directories..." -ForegroundColor Yellow

    $candidatePaths = @(
        (Join-Path $projectRoot "node_modules"),
        (Join-Path $projectRoot ".turbo")
    )

    foreach ($group in @("apps", "packages", "tooling")) {
        $groupPath = Join-Path $projectRoot $group
        if (Test-Path -LiteralPath $groupPath) {
            Get-ChildItem -LiteralPath $groupPath -Directory | ForEach-Object {
                $candidatePaths += Join-Path $_.FullName "node_modules"
                $candidatePaths += Join-Path $_.FullName ".turbo"
            }
        }
    }

    foreach ($path in ($candidatePaths | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }
}

Write-Host "Installing dependencies and generating pnpm-lock.yaml..." -ForegroundColor Cyan
Invoke-Native -Command "pnpm" -Arguments @("install")

Write-Host "Rebuilding explicitly approved native dependencies..." -ForegroundColor Cyan
Invoke-Native -Command "pnpm" -Arguments @("rebuild", "esbuild", "sharp")

Write-Host "Validating workspace structure..." -ForegroundColor Cyan
Invoke-Native -Command "pnpm" -Arguments @("structure:check")

if (-not $SkipChecks) {
    Write-Host "Running the complete Etapa 1 validation..." -ForegroundColor Cyan
    Invoke-Native -Command "pnpm" -Arguments @("ci:check")
}

Write-Host "Etapa 1 installed and validated successfully." -ForegroundColor Green
