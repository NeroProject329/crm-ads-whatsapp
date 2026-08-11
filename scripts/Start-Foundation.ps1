[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

Write-Host "Iniciando os cinco processos da fundação..." -ForegroundColor Cyan
Write-Host "Web: http://localhost:3000" -ForegroundColor DarkGray
Write-Host "API: http://localhost:3001/api/v1/health" -ForegroundColor DarkGray
Write-Host "Webhook: http://localhost:3002/health" -ForegroundColor DarkGray

pnpm dev
