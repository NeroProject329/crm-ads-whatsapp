[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-NativeOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter()]
        [string[]]$Arguments = @()
    )

    $output = & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $Command $($Arguments -join ' ')"
    }

    return ($output | Out-String).Trim()
}

function Write-Check {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    Write-Host ("[OK] {0}: {1}" -f $Name, $Value) -ForegroundColor Green
}

$nodeCommand = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeCommand) {
    throw "Node.js was not found in PATH."
}

$nodeVersionText = Get-NativeOutput -Command "node" -Arguments @("--version")
if ($nodeVersionText -notmatch '^v(?<version>\d+\.\d+\.\d+)$') {
    throw "Could not parse Node.js version: $nodeVersionText"
}

$nodeVersion = [Version]$Matches.version
$minimumNodeVersion = [Version]"24.18.0"
$maximumNodeVersion = [Version]"25.0.0"

if ($nodeVersion -lt $minimumNodeVersion -or $nodeVersion -ge $maximumNodeVersion) {
    throw "Node.js >=24.18.0 and <25 is required. Found: $nodeVersionText"
}
Write-Check -Name "Node.js" -Value $nodeVersionText

$corepackCommand = Get-Command corepack -ErrorAction SilentlyContinue
if (-not $corepackCommand) {
    throw "Corepack was not found in PATH."
}
$corepackVersion = Get-NativeOutput -Command "corepack" -Arguments @("--version")
Write-Check -Name "Corepack" -Value $corepackVersion

# Do not run 'corepack enable' here. On this machine Node is installed at D:\,
# and Corepack tries to create shims in the drive root, which causes EPERM.
$pnpmCommand = Get-Command pnpm -ErrorAction SilentlyContinue
if (-not $pnpmCommand) {
    throw "pnpm was not found in PATH. Install/activate pnpm 11.15.1 before continuing."
}

$pnpmVersion = Get-NativeOutput -Command "pnpm" -Arguments @("--version")
if ($pnpmVersion -ne "11.15.1") {
    throw "pnpm 11.15.1 is required. Found: $pnpmVersion"
}
Write-Check -Name "pnpm" -Value $pnpmVersion

Write-Host "Environment ready for Etapa 1." -ForegroundColor Cyan
