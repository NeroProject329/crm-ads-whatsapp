Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepositoryRoot

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Read-Text {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return [System.IO.File]::ReadAllText(
        [System.IO.Path]::GetFullPath($Path)
    )
}

function Write-Text {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Content
    )

    $FullPath = [System.IO.Path]::GetFullPath($Path)
    $Parent = Split-Path -Parent $FullPath

    if (-not (Test-Path $Parent)) {
        New-Item `
            -ItemType Directory `
            -Path $Parent `
            -Force |
            Out-Null
    }

    [System.IO.File]::WriteAllText(
        $FullPath,
        $Content,
        $Utf8NoBom
    )
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " CORRECAO ETAPA 8 - RUNTIME / ESM" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

# ============================================================
# 1. WEBHOOK INGRESS MUST BE ESM
# ============================================================

$WebhookPackagePath =
    ".\apps\webhook-ingress\package.json"

$WebhookPackage =
    Read-Text -Path $WebhookPackagePath

if (
    -not $WebhookPackage.Contains(
        '"type": "module"'
    )
) {
    $Anchor =
        '"private": true,'

    if (
        -not $WebhookPackage.Contains(
            $Anchor
        )
    ) {
        throw "Anchor private=true nao encontrado no webhook package.json."
    }

    $WebhookPackage =
        $WebhookPackage.Replace(
            $Anchor,
            "$Anchor`r`n  `"type`": `"module`","
        )

    Write-Text `
        -Path $WebhookPackagePath `
        -Content $WebhookPackage
}

Write-Host "[OK] webhook-ingress alinhado para ESM." -ForegroundColor Green

# ============================================================
# 2. RESTORE ESM LOAD ENVIRONMENT
# ============================================================

$LoadEnvironment = @'
import {
  config,
} from 'dotenv';

import {
  dirname,
  resolve,
} from 'node:path';

import {
  fileURLToPath,
} from 'node:url';

const appDirectory =
  resolve(
    dirname(
      fileURLToPath(
        import.meta.url,
      ),
    ),
    '..',
  );

config({
  path:
    resolve(
      appDirectory,
      '../../.env',
    ),

  quiet:
    true,
});
'@

Write-Text `
    -Path ".\apps\webhook-ingress\src\load-environment.ts" `
    -Content $LoadEnvironment

Write-Host "[OK] load-environment restaurado para ESM." -ForegroundColor Green

# ============================================================
# 3. RUNTIME TSC CONFIG
# ============================================================

$RuntimeTsConfig = @'
{
  "extends": "../../tooling/typescript/nest.json",
  "compilerOptions": {
    "rootDir": "../..",
    "outDir": ".stage8-runtime-dist",
    "declaration": false,
    "declarationMap": false,
    "sourceMap": false,
    "noEmit": false,
    "noEmitOnError": true
  },
  "include": [
    "scripts/stage8-runtime-validation.ts"
  ],
  "exclude": [
    "node_modules",
    "dist",
    "coverage",
    ".stage8-runtime-dist"
  ]
}
'@

Write-Text `
    -Path ".\apps\webhook-ingress\tsconfig.runtime.json" `
    -Content $RuntimeTsConfig

Write-Host "[OK] tsconfig.runtime.json criado." -ForegroundColor Green

# ============================================================
# 4. ENSURE RUNTIME HAS async main()
# ============================================================

$RuntimePath =
    ".\apps\webhook-ingress\scripts\stage8-runtime-validation.ts"

if (-not (Test-Path $RuntimePath)) {
    throw "stage8-runtime-validation.ts nao encontrado."
}

$RuntimeContent =
    Read-Text -Path $RuntimePath

if (
    -not $RuntimeContent.Contains(
        "async function main(): Promise<void>"
    )
) {
    $TryIndex =
        $RuntimeContent.IndexOf(
            "try {"
        )

    if ($TryIndex -lt 0) {
        throw "Bloco try principal do Stage 8 runtime nao encontrado."
    }

    $RuntimeContent =
        $RuntimeContent.Insert(
            $TryIndex,
            "async function main(): Promise<void> {`r`n"
        )

    $RuntimeContent =
        $RuntimeContent.TrimEnd() +
        "`r`n}`r`n`r`n" +
        "void main().catch((error) => {`r`n" +
        "  console.error(error);`r`n" +
        "  process.exitCode = 1;`r`n" +
        "});`r`n"

    Write-Text `
        -Path $RuntimePath `
        -Content $RuntimeContent
}

Write-Host "[OK] Runtime possui async main()." -ForegroundColor Green

# ============================================================
# 5. HARDEN STAGE 8.1 GENERATOR
# ============================================================

$Stage81Path =
    ".\scripts\CRIAR_ETAPA_8_MACROBLOCO_1.ps1"

$Stage81 =
    Read-Text -Path $Stage81Path

$WebhookPackagePattern =
    '(?s)(\$WebhookPackage\s*=\s*@''\r?\n)(.*?)(\r?\n''@)'

$WebhookPackageMatch =
    [regex]::Match(
        $Stage81,
        $WebhookPackagePattern
    )

if (-not $WebhookPackageMatch.Success) {
    throw "Template WebhookPackage do Stage 8.1 nao encontrado."
}

$WebhookPackageTemplate =
    $WebhookPackageMatch.Groups[2].Value

if (
    -not $WebhookPackageTemplate.Contains(
        '"type": "module"'
    )
) {
    $WebhookPackageTemplate =
        $WebhookPackageTemplate.Replace(
            '"private": true,',
            '"private": true,' +
            "`r`n" +
            '  "type": "module",'
        )

    $Stage81 =
        $Stage81.Substring(
            0,
            $WebhookPackageMatch.Groups[2].Index
        ) +
        $WebhookPackageTemplate +
        $Stage81.Substring(
            $WebhookPackageMatch.Groups[2].Index +
            $WebhookPackageMatch.Groups[2].Length
        )
}

$LoadPattern =
    '(?s)(\$WebhookLoadEnvironment\s*=\s*@''\r?\n)(.*?)(\r?\n''@)'

$LoadMatch =
    [regex]::Match(
        $Stage81,
        $LoadPattern
    )

if (-not $LoadMatch.Success) {
    throw "Template WebhookLoadEnvironment do Stage 8.1 nao encontrado."
}

$Stage81 =
    $Stage81.Substring(
        0,
        $LoadMatch.Groups[2].Index
    ) +
    $LoadEnvironment.TrimEnd() +
    $Stage81.Substring(
        $LoadMatch.Groups[2].Index +
        $LoadMatch.Groups[2].Length
    )

Write-Text `
    -Path $Stage81Path `
    -Content $Stage81

Write-Host "[OK] Stage 8.1 endurecido para ESM." -ForegroundColor Green

# ============================================================
# 6. PATCH FINALIZER RUNTIME EXECUTION
# ============================================================

$FinalizerPath =
    ".\scripts\FINALIZAR_ETAPA_8.ps1"

$Finalizer =
    Read-Text -Path $FinalizerPath

$SectionMarker =
    '==== Stage 8 database runtime validation ===='

$SectionIndex =
    $Finalizer.IndexOf(
        $SectionMarker
    )

if ($SectionIndex -lt 0) {
    throw "Secao Stage 8 database runtime validation nao encontrada."
}

$CommandIndex =
    $Finalizer.IndexOf(
        '& pnpm',
        $SectionIndex
    )

if ($CommandIndex -lt 0) {
    throw "Inicio do comando runtime nao encontrado."
}

$IfIndex =
    $Finalizer.IndexOf(
        'if ($LASTEXITCODE -ne 0)',
        $CommandIndex
    )

if ($IfIndex -lt 0) {
    throw "Validacao LASTEXITCODE runtime nao encontrada."
}

$NewRuntimeCommand = @'
Invoke-Native `
    -Description "Compile Stage 8 runtime validator" `
    -Command "pnpm" `
    -Arguments @(
        "exec",
        "tsc",
        "-p",
        "apps/webhook-ingress/tsconfig.runtime.json"
    )

& node "apps/webhook-ingress/.stage8-runtime-dist/apps/webhook-ingress/scripts/stage8-runtime-validation.js"

'@

$Finalizer =
    $Finalizer.Substring(
        0,
        $CommandIndex
    ) +
    $NewRuntimeCommand +
    "`r`n" +
    $Finalizer.Substring(
        $IfIndex
    )

$SuccessMarker =
    'Write-Host "[OK] Stage 8 database runtime validation." -ForegroundColor Green'

if (
    -not $Finalizer.Contains(
        $SuccessMarker
    )
) {
    throw "Success marker Stage 8 runtime nao encontrado."
}

$CleanupBlock = @'

Remove-Item `
    ".\apps\webhook-ingress\.stage8-runtime-dist" `
    -Recurse `
    -Force `
    -ErrorAction SilentlyContinue
'@

if (
    -not $Finalizer.Contains(
        '".\apps\webhook-ingress\.stage8-runtime-dist"'
    )
) {
    $Finalizer =
        $Finalizer.Replace(
            $SuccessMarker,
            $SuccessMarker +
            $CleanupBlock
        )
}

Write-Text `
    -Path $FinalizerPath `
    -Content $Finalizer

Write-Host "[OK] Finalizador Stage 8 usa tsc + Node puro." -ForegroundColor Green

# ============================================================
# 7. CLEAN OLD RUNTIME OUTPUT
# ============================================================

Remove-Item `
    ".\apps\webhook-ingress\.stage8-runtime-dist" `
    -Recurse `
    -Force `
    -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host "[OK] CORRECAO RUNTIME ETAPA 8 APLICADA." -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green