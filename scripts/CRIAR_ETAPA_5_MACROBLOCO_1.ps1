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
        New-Item -ItemType Directory -Path $Parent -Force | Out-Null
    }

    [System.IO.File]::WriteAllText(
        $FullPath,
        $Content,
        $Utf8NoBom
    )
}

function Get-PrismaBlock {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [ValidateSet("model", "enum")]
        [string]$Kind,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $EscapedName = [regex]::Escape($Name)
    $Pattern = "(?ms)^$Kind\s+$EscapedName\s+\{.*?^\}"

    $Match = [regex]::Match(
        $Content,
        $Pattern
    )

    if (-not $Match.Success) {
        throw "Bloco Prisma nao encontrado: $Kind $Name"
    }

    return $Match
}

function Add-ToPrismaModel {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$ModelName,

        [Parameter(Mandatory = $true)]
        [string]$Marker,

        [Parameter(Mandatory = $true)]
        [string]$Insertion
    )

    $Content = Read-Text -Path $Path

    $Match = Get-PrismaBlock `
        -Content $Content `
        -Kind "model" `
        -Name $ModelName

    $Block = $Match.Value

    if ($Block.Contains($Marker)) {
        return
    }

    $AttributeMatch = [regex]::Match(
        $Block,
        '(?m)^  @@'
    )

    if ($AttributeMatch.Success) {
        $InsertAt = $AttributeMatch.Index
    }
    else {
        $ClosingIndex = $Block.LastIndexOf("}")

        if ($ClosingIndex -lt 0) {
            throw "Fechamento do model $ModelName nao encontrado."
        }

        $InsertAt = $ClosingIndex
    }

    $NewBlock = (
        $Block.Substring(0, $InsertAt) +
        $Insertion.TrimEnd() +
        "`r`n`r`n" +
        $Block.Substring($InsertAt)
    )

    $NewContent = (
        $Content.Substring(0, $Match.Index) +
        $NewBlock +
        $Content.Substring($Match.Index + $Match.Length)
    )

    Write-Text `
        -Path $Path `
        -Content $NewContent
}

function Insert-AfterPrismaBlock {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateSet("model", "enum")]
        [string]$Kind,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Marker,

        [Parameter(Mandatory = $true)]
        [string]$Insertion
    )

    $Content = Read-Text -Path $Path

    if ($Content.Contains($Marker)) {
        return
    }

    $Match = Get-PrismaBlock `
        -Content $Content `
        -Kind $Kind `
        -Name $Name

    $InsertAt = $Match.Index + $Match.Length

    $NewContent = (
        $Content.Substring(0, $InsertAt) +
        "`r`n`r`n" +
        $Insertion.Trim() +
        "`r`n" +
        $Content.Substring($InsertAt)
    )

    Write-Text `
        -Path $Path `
        -Content $NewContent
}

function Insert-BeforePrismaBlock {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateSet("model", "enum")]
        [string]$Kind,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Marker,

        [Parameter(Mandatory = $true)]
        [string]$Insertion
    )

    $Content = Read-Text -Path $Path

    if ($Content.Contains($Marker)) {
        return
    }

    $Match = Get-PrismaBlock `
        -Content $Content `
        -Kind $Kind `
        -Name $Name

    $NewContent = (
        $Content.Substring(0, $Match.Index) +
        $Insertion.Trim() +
        "`r`n`r`n" +
        $Content.Substring($Match.Index)
    )

    Write-Text `
        -Path $Path `
        -Content $NewContent
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " ETAPA 5 - MACROBLOCO 5.1" -ForegroundColor Cyan
Write-Host " SCHEDULER + MICROBATCH + ROUND ROBIN" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

$SchemaPath = ".\packages\database\prisma\schema.prisma"
$WorkerPackagePath = ".\apps\worker\package.json"
$ContractsPath = ".\packages\contracts\src\ads.ts"
$AdsServicePath = ".\apps\api\src\ads\ads.service.ts"
$EnvExamplePath = ".\.env.example"

$BackupDirectory = ".\tmp\stage5-macroblock1-backup"

if (-not (Test-Path $BackupDirectory)) {
    New-Item `
        -ItemType Directory `
        -Path $BackupDirectory `
        -Force |
        Out-Null

    $BackupFiles = @(
        $SchemaPath,
        $WorkerPackagePath,
        $ContractsPath,
        $AdsServicePath,
        $EnvExamplePath
    )

    foreach ($File in $BackupFiles) {
        if (-not (Test-Path $File)) {
            throw "Arquivo obrigatorio nao encontrado: $File"
        }

        $BackupName = $File -replace '^[.][\\/]', ''
        $BackupName = $BackupName -replace '[\\/]', '__'

        Copy-Item `
            -Path $File `
            -Destination (Join-Path $BackupDirectory $BackupName) `
            -Force
    }
}

Write-Host "[OK] Backup Stage 5 preparado." -ForegroundColor Green

# ============================================================
# PRISMA ENUM
# ============================================================

$MicrobatchEnum = @'
enum AdsMicrobatchStatus {
  PLANNED
  DELIVERING
  COMPLETED
  CANCELLED
  FAILED
}
'@

Insert-AfterPrismaBlock `
    -Path $SchemaPath `
    -Kind "enum" `
    -Name "AdsQueueItemStatus" `
    -Marker "enum AdsMicrobatchStatus" `
    -Insertion $MicrobatchEnum

Write-Host "[OK] AdsMicrobatchStatus criado." -ForegroundColor Green

# ============================================================
# PRISMA RELATIONS
# ============================================================

Add-ToPrismaModel `
    -Path $SchemaPath `
    -ModelName "Organization" `
    -Marker "trafficPoolSchedulerStates" `
    -Insertion @'
  trafficPoolSchedulerStates TrafficPoolSchedulerState[]
  adsMicrobatches             AdsMicrobatch[]
'@

Add-ToPrismaModel `
    -Path $SchemaPath `
    -ModelName "Employee" `
    -Marker "adsMicrobatches" `
    -Insertion @'
  adsMicrobatches AdsMicrobatch[]
'@

Add-ToPrismaModel `
    -Path $SchemaPath `
    -ModelName "WhatsAppNumber" `
    -Marker "adsMicrobatches" `
    -Insertion @'
  adsMicrobatches AdsMicrobatch[]
'@

Add-ToPrismaModel `
    -Path $SchemaPath `
    -ModelName "TrafficPool" `
    -Marker "schedulerState" `
    -Insertion @'
  schedulerState  TrafficPoolSchedulerState?
  adsMicrobatches AdsMicrobatch[]
'@

Add-ToPrismaModel `
    -Path $SchemaPath `
    -ModelName "TrafficPoolMember" `
    -Marker "adsMicrobatches" `
    -Insertion @'
  adsMicrobatches AdsMicrobatch[]
'@

Add-ToPrismaModel `
    -Path $SchemaPath `
    -ModelName "AdsRequest" `
    -Marker "scheduledLeadCount" `
    -Insertion @'
  scheduledLeadCount Int             @default(0)
  microbatches       AdsMicrobatch[]

  @@index([organizationId, employeeId, status, scheduledLeadCount])
'@

Add-ToPrismaModel `
    -Path $SchemaPath `
    -ModelName "AdsQueueItem" `
    -Marker "claimedByWorkerId" `
    -Insertion @'
  claimedByWorkerId String?         @db.VarChar(120)
  leaseExpiresAt    DateTime?       @db.Timestamptz(3)
  lastAttemptAt     DateTime?       @db.Timestamptz(3)
  microbatches      AdsMicrobatch[]

  @@index([organizationId, status, leaseExpiresAt])
'@

Write-Host "[OK] Relacoes e campos Stage 5 adicionados." -ForegroundColor Green

# ============================================================
# NEW PRISMA MODELS
# ============================================================

$SchedulerModels = @'
model TrafficPoolSchedulerState {
  id             String   @id @default(uuid()) @db.Uuid
  organizationId String   @db.Uuid
  trafficPoolId  String   @db.Uuid
  nextPosition   Int      @default(1)
  createdAt      DateTime @default(now()) @db.Timestamptz(3)
  updatedAt      DateTime @updatedAt @db.Timestamptz(3)

  organization Organization @relation(fields: [organizationId], references: [id], onDelete: Restrict)
  trafficPool  TrafficPool  @relation(fields: [organizationId, trafficPoolId], references: [organizationId, id], onDelete: Cascade)

  @@unique([organizationId, id])
  @@unique([organizationId, trafficPoolId])
  @@index([organizationId, updatedAt])
  @@map("traffic_pool_scheduler_states")
}

model AdsMicrobatch {
  id                  String              @id @default(uuid()) @db.Uuid
  organizationId      String              @db.Uuid
  adsRequestId        String              @db.Uuid
  adsQueueItemId      String              @db.Uuid
  employeeId          String              @db.Uuid
  trafficPoolId       String              @db.Uuid
  trafficPoolMemberId String              @db.Uuid
  whatsAppNumberId    String              @db.Uuid
  sequence            Int
  reservedLeadCount   Int
  deliveredLeadCount  Int                 @default(0)
  status              AdsMicrobatchStatus @default(PLANNED)
  plannedAt           DateTime            @default(now()) @db.Timestamptz(3)
  startedAt           DateTime?           @db.Timestamptz(3)
  completedAt         DateTime?           @db.Timestamptz(3)
  cancelledAt         DateTime?           @db.Timestamptz(3)
  failureReason       String?             @db.VarChar(500)
  createdAt           DateTime            @default(now()) @db.Timestamptz(3)
  updatedAt           DateTime            @updatedAt @db.Timestamptz(3)

  organization      Organization      @relation(fields: [organizationId], references: [id], onDelete: Restrict)
  adsRequest        AdsRequest        @relation(fields: [organizationId, adsRequestId], references: [organizationId, id], onDelete: Cascade)
  adsQueueItem      AdsQueueItem      @relation(fields: [organizationId, adsQueueItemId], references: [organizationId, id], onDelete: Cascade)
  employee          Employee          @relation(fields: [organizationId, employeeId], references: [organizationId, id], onDelete: Restrict)
  trafficPool       TrafficPool       @relation(fields: [organizationId, trafficPoolId], references: [organizationId, id], onDelete: Restrict)
  trafficPoolMember TrafficPoolMember @relation(fields: [trafficPoolMemberId], references: [id], onDelete: Restrict)
  whatsAppNumber    WhatsAppNumber    @relation(fields: [organizationId, whatsAppNumberId], references: [organizationId, id], onDelete: Restrict)

  @@unique([organizationId, id])
  @@unique([adsRequestId, sequence])
  @@index([organizationId, employeeId, status])
  @@index([organizationId, trafficPoolId, status])
  @@index([organizationId, whatsAppNumberId, status])
  @@index([organizationId, adsRequestId, status])
  @@map("ads_microbatches")
}
'@

Insert-BeforePrismaBlock `
    -Path $SchemaPath `
    -Kind "model" `
    -Name "AuditLog" `
    -Marker "model TrafficPoolSchedulerState {" `
    -Insertion $SchedulerModels

$SchemaContent = Read-Text -Path $SchemaPath
$SchemaContent = $SchemaContent.TrimStart([char]0xFEFF)

Write-Text `
    -Path $SchemaPath `
    -Content $SchemaContent

Write-Host "[OK] SchedulerState + AdsMicrobatch criados." -ForegroundColor Green

# ============================================================
# CONTRACTS
# ============================================================

$AdsContracts = @'
export type AdsRequestStatus =
  | 'QUEUED'
  | 'PROCESSING'
  | 'PARTIALLY_FULFILLED'
  | 'FULFILLED'
  | 'CANCELLED'
  | 'FAILED';

export type AdsQueueItemStatus =
  | 'WAITING'
  | 'CLAIMED'
  | 'COMPLETED'
  | 'CANCELLED'
  | 'FAILED';

export type AdsRequestSiteResponse = Readonly<{
  id: string;
  name: string;
  slug: string;
}>;

export type AdsRequestTrafficPoolResponse = Readonly<{
  id: string;
  name: string;
  slug: string;
}>;

export type AdsRequestEmployeeResponse = Readonly<{
  id: string;
  employeeCode: string;
}>;

export type AdsQueueItemSummaryResponse = Readonly<{
  id: string;
  status: AdsQueueItemStatus;
  priority: number;
  attempts: number;
  enqueuedAt: string;
  availableAt: string;
  claimedAt: string | null;
  claimedByWorkerId: string | null;
  leaseExpiresAt: string | null;
  lastAttemptAt: string | null;
  completedAt: string | null;
  cancelledAt: string | null;
}>;

export type AdsRequestResponse = Readonly<{
  id: string;
  organizationId: string;
  employeeId: string;
  siteId: string;
  trafficPoolId: string;
  requestedByUserId: string;
  requestedLeadCount: number;
  scheduledLeadCount: number;
  fulfilledLeadCount: number;
  status: AdsRequestStatus;
  notes: string | null;
  queuedAt: string;
  startedAt: string | null;
  completedAt: string | null;
  cancelledAt: string | null;
  failureReason: string | null;
  site: AdsRequestSiteResponse;
  trafficPool: AdsRequestTrafficPoolResponse;
  employee: AdsRequestEmployeeResponse;
  queueItem: AdsQueueItemSummaryResponse | null;
  createdAt: string;
  updatedAt: string;
}>;

export type AdsRequestListResponse = readonly AdsRequestResponse[];

export type CreateAdsRequestRequest = Readonly<{
  siteId: string;
  trafficPoolId: string;
  requestedLeadCount: number;
  notes?: string | null;
}>;

export type AdsQueueRequestSummaryResponse = Readonly<{
  id: string;
  status: AdsRequestStatus;
  requestedLeadCount: number;
  scheduledLeadCount: number;
  fulfilledLeadCount: number;
}>;

export type AdsQueueItemResponse = Readonly<{
  id: string;
  organizationId: string;
  adsRequestId: string;
  employeeId: string;
  trafficPoolId: string;
  status: AdsQueueItemStatus;
  priority: number;
  attempts: number;
  enqueuedAt: string;
  availableAt: string;
  claimedAt: string | null;
  claimedByWorkerId: string | null;
  leaseExpiresAt: string | null;
  lastAttemptAt: string | null;
  completedAt: string | null;
  cancelledAt: string | null;
  adsRequest: AdsQueueRequestSummaryResponse;
  createdAt: string;
  updatedAt: string;
}>;

export type AdsQueueListResponse = readonly AdsQueueItemResponse[];
'@

Write-Text `
    -Path $ContractsPath `
    -Content $AdsContracts

Write-Host "[OK] Contracts Stage 5 atualizados." -ForegroundColor Green

# ============================================================
# ADS SERVICE - RESPONSE FIELDS
# ============================================================

$AdsService = Read-Text -Path $AdsServicePath

if (-not $AdsService.Contains("scheduledLeadCount: request.scheduledLeadCount")) {
    $Anchor = "      requestedLeadCount: request.requestedLeadCount,"

    if (-not $AdsService.Contains($Anchor)) {
        throw "Anchor requestedLeadCount mapRequest nao encontrado."
    }

    $AdsService = $AdsService.Replace(
        $Anchor,
        $Anchor + "`r`n      scheduledLeadCount: request.scheduledLeadCount,"
    )
}

if (-not $AdsService.Contains("claimedByWorkerId: request.queueItem.claimedByWorkerId")) {
    $Anchor = "            attempts: request.queueItem.attempts,"

    if (-not $AdsService.Contains($Anchor)) {
        throw "Anchor queue summary nao encontrado."
    }

    $Replacement = @'
            attempts: request.queueItem.attempts,
            claimedByWorkerId: request.queueItem.claimedByWorkerId,
            leaseExpiresAt: request.queueItem.leaseExpiresAt?.toISOString() ?? null,
            lastAttemptAt: request.queueItem.lastAttemptAt?.toISOString() ?? null,
'@

    $AdsService = $AdsService.Replace(
        $Anchor,
        $Replacement.TrimEnd()
    )
}

if (-not $AdsService.Contains("claimedByWorkerId: item.claimedByWorkerId")) {
    $Anchor = "      attempts: item.attempts,"

    if (-not $AdsService.Contains($Anchor)) {
        throw "Anchor queue item map nao encontrado."
    }

    $Replacement = @'
      attempts: item.attempts,
      claimedByWorkerId: item.claimedByWorkerId,
      leaseExpiresAt: item.leaseExpiresAt?.toISOString() ?? null,
      lastAttemptAt: item.lastAttemptAt?.toISOString() ?? null,
'@

    $AdsService = $AdsService.Replace(
        $Anchor,
        $Replacement.TrimEnd()
    )
}

if (-not $AdsService.Contains("scheduledLeadCount: item.adsRequest.scheduledLeadCount")) {
    $Anchor = "        requestedLeadCount: item.adsRequest.requestedLeadCount,"

    if (-not $AdsService.Contains($Anchor)) {
        throw "Anchor queue request summary nao encontrado."
    }

    $AdsService = $AdsService.Replace(
        $Anchor,
        $Anchor + "`r`n        scheduledLeadCount: item.adsRequest.scheduledLeadCount,"
    )
}

# ============================================================
# ADS SERVICE - STAGE 5 CANCELLATION
# ============================================================

$NewCancelMethod = @'
  async cancelRequest(
    principal: AuthenticatedPrincipal,
    requestId: string,
  ): Promise<AdsRequestResponse> {
    const request = await this.getAccessibleRequest(principal, requestId);

    if (request.status === 'CANCELLED') {
      return this.mapRequest(request);
    }

    if (
      request.status !== 'QUEUED' &&
      request.status !== 'PROCESSING' &&
      request.status !== 'PARTIALLY_FULFILLED'
    ) {
      throw new ConflictException({
        code: 'ADS_REQUEST_NOT_CANCELLABLE',
        message: 'This ADS request can no longer be cancelled.',
      });
    }

    if (!request.queueItem) {
      throw new ConflictException({
        code: 'ADS_QUEUE_ITEM_NOT_FOUND',
        message: 'ADS queue item was not found for this request.',
      });
    }

    const queueItemId = request.queueItem.id;
    const now = new Date();

    const updated = await this.database.client.$transaction(async (transaction) => {
      const requestUpdate = await transaction.adsRequest.updateMany({
        where: {
          id: request.id,
          organizationId: principal.organizationId,
          status: {
            in: ['QUEUED', 'PROCESSING', 'PARTIALLY_FULFILLED'],
          },
        },

        data: {
          status: 'CANCELLED',
          cancelledAt: now,
        },
      });

      if (requestUpdate.count !== 1) {
        throw new ConflictException({
          code: 'ADS_REQUEST_CANCEL_CONFLICT',
          message: 'ADS request changed before cancellation could complete.',
        });
      }

      const queueUpdate = await transaction.adsQueueItem.updateMany({
        where: {
          organizationId: principal.organizationId,
          adsRequestId: request.id,
          status: {
            in: ['WAITING', 'CLAIMED'],
          },
        },

        data: {
          status: 'CANCELLED',
          cancelledAt: now,
          claimedAt: null,
          claimedByWorkerId: null,
          leaseExpiresAt: null,
        },
      });

      const microbatchUpdate = await transaction.adsMicrobatch.updateMany({
        where: {
          organizationId: principal.organizationId,
          adsRequestId: request.id,
          status: {
            in: ['PLANNED', 'DELIVERING'],
          },
        },

        data: {
          status: 'CANCELLED',
          cancelledAt: now,
        },
      });

      await transaction.auditLog.create({
        data: {
          organizationId: principal.organizationId,
          actorType: 'USER',
          actorUserId: principal.userId,
          action: 'ads_request.cancelled',
          resourceType: 'ads_request',
          resourceId: request.id,
          outcome: 'SUCCESS',

          metadata: {
            queueItemsCancelled: queueUpdate.count,
            microbatchesCancelled: microbatchUpdate.count,
          },
        },
      });

      if (queueUpdate.count > 0) {
        await transaction.auditLog.create({
          data: {
            organizationId: principal.organizationId,
            actorType: 'USER',
            actorUserId: principal.userId,
            action: 'ads_queue.cancelled',
            resourceType: 'ads_queue_item',
            resourceId: queueItemId,
            outcome: 'SUCCESS',

            metadata: {
              adsRequestId: request.id,
            },
          },
        });
      }

      if (microbatchUpdate.count > 0) {
        await transaction.auditLog.create({
          data: {
            organizationId: principal.organizationId,
            actorType: 'USER',
            actorUserId: principal.userId,
            action: 'ads_microbatch.cancelled',
            resourceType: 'ads_request',
            resourceId: request.id,
            outcome: 'SUCCESS',

            metadata: {
              count: microbatchUpdate.count,
            },
          },
        });
      }

      return transaction.adsRequest.findUniqueOrThrow({
        where: {
          id: request.id,
        },

        include: {
          employee: true,
          site: true,
          trafficPool: true,
          queueItem: true,
        },
      });
    });

    return this.mapRequest(updated);
  }

'@

$CancelRegex = New-Object System.Text.RegularExpressions.Regex(
    '  async cancelRequest\([\s\S]*?(?=  async listQueue\()',
    [System.Text.RegularExpressions.RegexOptions]::Singleline
)

if (-not $CancelRegex.IsMatch($AdsService)) {
    throw "Metodo cancelRequest nao encontrado para upgrade Stage 5."
}

$AdsService = $CancelRegex.Replace(
    $AdsService,
    $NewCancelMethod,
    1
)

Write-Text `
    -Path $AdsServicePath `
    -Content $AdsService

Write-Host "[OK] AdsService preparado para Stage 5." -ForegroundColor Green

# ============================================================
# WORKER PACKAGE
# ============================================================

$WorkerPackage = @'
{
  "name": "@crm/worker",
  "version": "0.2.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "tsx watch src/main.ts",
    "build": "tsc -p tsconfig.build.json",
    "start": "node dist/main.js",
    "lint": "eslint src",
    "typecheck": "tsc --noEmit -p tsconfig.json",
    "test": "vitest run --config ../../tooling/testing/vitest.config.ts --passWithNoTests",
    "clean": "rimraf dist coverage"
  },
  "dependencies": {
    "@crm/database": "workspace:*",
    "dotenv": "17.4.2"
  }
}
'@

Write-Text `
    -Path $WorkerPackagePath `
    -Content $WorkerPackage

# ============================================================
# WORKER ENVIRONMENT LOADER
# ============================================================

$WorkerEnvironment = @'
import { config } from 'dotenv';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const appDirectory = resolve(dirname(fileURLToPath(import.meta.url)), '..');

config({
  path: resolve(appDirectory, '../../.env'),
  quiet: true,
});
'@

Write-Text `
    -Path ".\apps\worker\src\load-environment.ts" `
    -Content $WorkerEnvironment

# ============================================================
# SCHEDULER CONFIG
# ============================================================

$SchedulerConfig = @'
export type AdsSchedulerConfig = Readonly<{
  intervalMs: number;
  microbatchSize: number;
  maxInflightPerEmployee: number;
  leaseMs: number;
  backpressureDelayMs: number;
  microbatchYieldMs: number;
  maxClaimsPerTick: number;
  maxQueueAttempts: number;
}>;

function readInteger(
  name: string,
  fallback: number,
  minimum: number,
  maximum: number,
): number {
  const raw = process.env[name]?.trim();

  if (!raw) {
    return fallback;
  }

  const value = Number(raw);

  if (!Number.isInteger(value) || value < minimum || value > maximum) {
    throw new Error(
      `${name} must be an integer between ${minimum} and ${maximum}.`,
    );
  }

  return value;
}

export function parseAdsSchedulerConfig(): AdsSchedulerConfig {
  return {
    intervalMs: readInteger('ADS_SCHEDULER_INTERVAL_MS', 1000, 100, 60_000),

    microbatchSize: readInteger('ADS_MICROBATCH_SIZE', 10, 1, 10_000),

    maxInflightPerEmployee: readInteger(
      'ADS_MAX_INFLIGHT_PER_EMPLOYEE',
      100,
      1,
      1_000_000,
    ),

    leaseMs: readInteger('ADS_CLAIM_LEASE_MS', 30_000, 5_000, 900_000),

    backpressureDelayMs: readInteger(
      'ADS_BACKPRESSURE_DELAY_MS',
      5_000,
      100,
      900_000,
    ),

    microbatchYieldMs: readInteger(
      'ADS_MICROBATCH_YIELD_MS',
      250,
      0,
      60_000,
    ),

    maxClaimsPerTick: readInteger(
      'ADS_MAX_CLAIMS_PER_TICK',
      25,
      1,
      1000,
    ),

    maxQueueAttempts: readInteger(
      'ADS_MAX_QUEUE_ATTEMPTS',
      25,
      1,
      1000,
    ),
  };
}
'@

Write-Text `
    -Path ".\apps\worker\src\scheduler.config.ts" `
    -Content $SchedulerConfig

# ============================================================
# PURE SCHEDULER ENGINE
# ============================================================

$SchedulerEngine = @'
export type BatchSizeInput = Readonly<{
  requestedLeadCount: number;
  scheduledLeadCount: number;
  inflightLeadCount: number;
  maxInflightPerEmployee: number;
  microbatchSize: number;
}>;

export function computeBatchSize(input: BatchSizeInput): number {
  const remaining = Math.max(
    0,
    input.requestedLeadCount - input.scheduledLeadCount,
  );

  const availableCapacity = Math.max(
    0,
    input.maxInflightPerEmployee - input.inflightLeadCount,
  );

  return Math.min(
    remaining,
    availableCapacity,
    input.microbatchSize,
  );
}

export type PositionedMember = Readonly<{
  position: number;
}>;

export type RoundRobinSelection<T extends PositionedMember> = Readonly<{
  member: T;
  nextPosition: number;
}>;

export function selectRoundRobinMember<T extends PositionedMember>(
  members: readonly T[],
  nextPosition: number,
): RoundRobinSelection<T> {
  if (members.length === 0) {
    throw new Error('Cannot select a member from an empty Traffic Pool.');
  }

  const ordered = [...members].sort(
    (left, right) => left.position - right.position,
  );

  const selectedIndex = ordered.findIndex(
    (member) => member.position >= nextPosition,
  );

  const normalizedIndex =
    selectedIndex >= 0
      ? selectedIndex
      : 0;

  const member = ordered[normalizedIndex];

  if (!member) {
    throw new Error('Round-robin member selection failed.');
  }

  const followingMember =
    ordered[normalizedIndex + 1] ??
    ordered[0];

  if (!followingMember) {
    throw new Error('Round-robin next member selection failed.');
  }

  return {
    member,
    nextPosition: followingMember.position,
  };
}
'@

Write-Text `
    -Path ".\apps\worker\src\scheduler-engine.ts" `
    -Content $SchedulerEngine

# ============================================================
# ENGINE TESTS
# ============================================================

$SchedulerEngineTests = @'
import { describe, expect, it } from 'vitest';

import {
  computeBatchSize,
  selectRoundRobinMember,
} from './scheduler-engine.js';

describe('computeBatchSize', () => {
  it('limits the batch to the configured microbatch size', () => {
    expect(
      computeBatchSize({
        requestedLeadCount: 100,
        scheduledLeadCount: 0,
        inflightLeadCount: 0,
        maxInflightPerEmployee: 100,
        microbatchSize: 10,
      }),
    ).toBe(10);
  });

  it('respects employee backpressure', () => {
    expect(
      computeBatchSize({
        requestedLeadCount: 100,
        scheduledLeadCount: 30,
        inflightLeadCount: 95,
        maxInflightPerEmployee: 100,
        microbatchSize: 10,
      }),
    ).toBe(5);
  });

  it('does not schedule beyond the remaining request', () => {
    expect(
      computeBatchSize({
        requestedLeadCount: 100,
        scheduledLeadCount: 97,
        inflightLeadCount: 0,
        maxInflightPerEmployee: 100,
        microbatchSize: 10,
      }),
    ).toBe(3);
  });

  it('returns zero when there is no capacity', () => {
    expect(
      computeBatchSize({
        requestedLeadCount: 100,
        scheduledLeadCount: 30,
        inflightLeadCount: 100,
        maxInflightPerEmployee: 100,
        microbatchSize: 10,
      }),
    ).toBe(0);
  });
});

describe('selectRoundRobinMember', () => {
  const members = [
    { id: 'a', position: 1 },
    { id: 'b', position: 2 },
    { id: 'c', position: 3 },
  ];

  it('selects the requested position and advances the cursor', () => {
    const result = selectRoundRobinMember(members, 2);

    expect(result.member.id).toBe('b');
    expect(result.nextPosition).toBe(3);
  });

  it('wraps back to the first member', () => {
    const result = selectRoundRobinMember(members, 3);

    expect(result.member.id).toBe('c');
    expect(result.nextPosition).toBe(1);
  });

  it('recovers when positions contain gaps', () => {
    const result = selectRoundRobinMember(
      [
        { id: 'a', position: 1 },
        { id: 'c', position: 5 },
      ],
      2,
    );

    expect(result.member.id).toBe('c');
    expect(result.nextPosition).toBe(1);
  });
});
'@

Write-Text `
    -Path ".\apps\worker\src\scheduler-engine.spec.ts" `
    -Content $SchedulerEngineTests

# ============================================================
# ADS SCHEDULER SERVICE
# ============================================================

$SchedulerService = @'
import type { CrmDatabaseClient } from '@crm/database';

import {
  computeBatchSize,
  selectRoundRobinMember,
} from './scheduler-engine.js';

import type { AdsSchedulerConfig } from './scheduler.config.js';

type ClaimedQueueItem = Readonly<{
  id: string;
  employeeId: string;
  trafficPoolId: string;
}>;

type ProcessResult =
  | 'PLANNED'
  | 'DEFERRED'
  | 'FAILED'
  | 'LOST_LEASE'
  | 'SKIPPED';

export type SchedulerTickSummary = Readonly<{
  claimed: number;
  planned: number;
  deferred: number;
  failed: number;
  lostLease: number;
}>;

function addMilliseconds(
  date: Date,
  milliseconds: number,
): Date {
  return new Date(date.getTime() + milliseconds);
}

function getErrorMessage(error: unknown): string {
  if (error instanceof Error) {
    return error.message.slice(0, 500);
  }

  return String(error).slice(0, 500);
}

export class AdsSchedulerService {
  constructor(
    private readonly database: CrmDatabaseClient,
    private readonly workerId: string,
    private readonly config: AdsSchedulerConfig,
  ) {}

  async runTick(): Promise<SchedulerTickSummary> {
    let claimedCount = 0;
    let plannedCount = 0;
    let deferredCount = 0;
    let failedCount = 0;
    let lostLeaseCount = 0;

    for (
      let index = 0;
      index < this.config.maxClaimsPerTick;
      index += 1
    ) {
      const claimed = await this.claimNextQueueItem();

      if (!claimed) {
        break;
      }

      claimedCount += 1;

      try {
        const result = await this.processClaimedQueueItem(
          claimed,
        );

        if (result === 'PLANNED') {
          plannedCount += 1;
        }

        if (result === 'DEFERRED') {
          deferredCount += 1;
        }

        if (result === 'FAILED') {
          failedCount += 1;
        }

        if (result === 'LOST_LEASE') {
          lostLeaseCount += 1;
        }
      } catch (error) {
        const recoveryResult = await this.handleProcessingError(
          claimed,
          error,
        );

        if (recoveryResult === 'FAILED') {
          failedCount += 1;
        }

        if (recoveryResult === 'DEFERRED') {
          deferredCount += 1;
        }

        if (recoveryResult === 'LOST_LEASE') {
          lostLeaseCount += 1;
        }
      }
    }

    return {
      claimed: claimedCount,
      planned: plannedCount,
      deferred: deferredCount,
      failed: failedCount,
      lostLease: lostLeaseCount,
    };
  }

  private async claimNextQueueItem(): Promise<ClaimedQueueItem | null> {
    const rows =
      await this.database.$queryRawUnsafe<ClaimedQueueItem[]>(
        `
          WITH candidate AS (
            SELECT
              "id"
            FROM
              "ads_queue_items"
            WHERE
              (
                (
                  "status" = 'WAITING'
                  AND "availableAt" <= NOW()
                )
                OR
                (
                  "status" = 'CLAIMED'
                  AND "leaseExpiresAt" IS NOT NULL
                  AND "leaseExpiresAt" <= NOW()
                )
              )
            ORDER BY
              "priority" ASC,
              "availableAt" ASC,
              "enqueuedAt" ASC,
              "id" ASC
            FOR UPDATE SKIP LOCKED
            LIMIT 1
          )
          UPDATE
            "ads_queue_items" AS queue
          SET
            "status" = 'CLAIMED',
            "claimedAt" = NOW(),
            "claimedByWorkerId" = $1,
            "leaseExpiresAt" =
              NOW() + ($2::int * INTERVAL '1 millisecond'),
            "lastAttemptAt" = NOW(),
            "attempts" = queue."attempts" + 1,
            "updatedAt" = NOW()
          FROM
            candidate
          WHERE
            queue."id" = candidate."id"
          RETURNING
            queue."id",
            queue."employeeId",
            queue."trafficPoolId"
        `,
        this.workerId,
        this.config.leaseMs,
      );

    return rows[0] ?? null;
  }

  private async processClaimedQueueItem(
    claimed: ClaimedQueueItem,
  ): Promise<ProcessResult> {
    return this.database.$transaction(async (transaction) => {
      await transaction.$queryRawUnsafe(
        'SELECT pg_advisory_xact_lock(hashtextextended($1, 0))',
        `employee:${claimed.employeeId}`,
      );

      await transaction.$queryRawUnsafe(
        'SELECT pg_advisory_xact_lock(hashtextextended($1, 0))',
        `traffic-pool:${claimed.trafficPoolId}`,
      );

      const now = new Date();

      const queueItem =
        await transaction.adsQueueItem.findFirst({
          where: {
            id: claimed.id,
            status: 'CLAIMED',
            claimedByWorkerId: this.workerId,
            leaseExpiresAt: {
              gt: now,
            },
          },

          include: {
            adsRequest: true,

            trafficPool: {
              include: {
                site: true,
              },
            },
          },
        });

      if (!queueItem) {
        return 'LOST_LEASE';
      }

      const request = queueItem.adsRequest;

      if (request.status === 'CANCELLED') {
        await transaction.adsQueueItem.update({
          where: {
            id: queueItem.id,
          },

          data: {
            status: 'CANCELLED',
            cancelledAt: request.cancelledAt ?? now,
            claimedAt: null,
            claimedByWorkerId: null,
            leaseExpiresAt: null,
          },
        });

        return 'SKIPPED';
      }

      if (
        request.status === 'FULFILLED' ||
        request.status === 'FAILED'
      ) {
        await transaction.adsQueueItem.update({
          where: {
            id: queueItem.id,
          },

          data: {
            status:
              request.status === 'FULFILLED'
                ? 'COMPLETED'
                : 'FAILED',

            completedAt:
              request.status === 'FULFILLED'
                ? now
                : null,

            claimedAt: null,
            claimedByWorkerId: null,
            leaseExpiresAt: null,
          },
        });

        return 'SKIPPED';
      }

      if (
        request.scheduledLeadCount >=
        request.requestedLeadCount
      ) {
        await transaction.adsQueueItem.update({
          where: {
            id: queueItem.id,
          },

          data: {
            status: 'COMPLETED',
            completedAt: queueItem.completedAt ?? now,
            claimedAt: null,
            claimedByWorkerId: null,
            leaseExpiresAt: null,
          },
        });

        return 'SKIPPED';
      }

      const employee =
        await transaction.employee.findFirst({
          where: {
            id: queueItem.employeeId,
            organizationId: queueItem.organizationId,
            status: 'ACTIVE',
            deletedAt: null,
          },

          select: {
            id: true,
          },
        });

      if (!employee) {
        await this.deferClaimedQueueItem(
          transaction,
          queueItem.id,
          queueItem.organizationId,
          request.id,
          now,
          this.config.backpressureDelayMs,
          'ads_queue.employee_unavailable',
        );

        return 'DEFERRED';
      }

      if (
        queueItem.trafficPool.status !== 'ACTIVE' ||
        queueItem.trafficPool.deletedAt !== null ||
        queueItem.trafficPool.site.status !== 'ACTIVE' ||
        queueItem.trafficPool.site.deletedAt !== null
      ) {
        await this.deferClaimedQueueItem(
          transaction,
          queueItem.id,
          queueItem.organizationId,
          request.id,
          now,
          this.config.backpressureDelayMs,
          'ads_queue.pool_unavailable',
        );

        return 'DEFERRED';
      }

      const eligibleMembers =
        await transaction.trafficPoolMember.findMany({
          where: {
            organizationId: queueItem.organizationId,
            trafficPoolId: queueItem.trafficPoolId,
            status: 'ACTIVE',

            whatsAppNumber: {
              deletedAt: null,
              status: 'ACTIVE',
              assignedEmployeeId: queueItem.employeeId,
            },
          },

          include: {
            whatsAppNumber: true,
          },

          orderBy: {
            position: 'asc',
          },
        });

      if (eligibleMembers.length === 0) {
        await this.deferClaimedQueueItem(
          transaction,
          queueItem.id,
          queueItem.organizationId,
          request.id,
          now,
          this.config.backpressureDelayMs,
          'ads_queue.no_eligible_number',
        );

        return 'DEFERRED';
      }

      const inflightAggregate =
        await transaction.adsMicrobatch.aggregate({
          where: {
            organizationId: queueItem.organizationId,
            employeeId: queueItem.employeeId,

            status: {
              in: ['PLANNED', 'DELIVERING'],
            },
          },

          _sum: {
            reservedLeadCount: true,
            deliveredLeadCount: true,
          },
        });

      const reservedLeadCount =
        inflightAggregate._sum.reservedLeadCount ??
        0;

      const deliveredLeadCount =
        inflightAggregate._sum.deliveredLeadCount ??
        0;

      const inflightLeadCount = Math.max(
        0,
        reservedLeadCount - deliveredLeadCount,
      );

      const batchSize = computeBatchSize({
        requestedLeadCount: request.requestedLeadCount,
        scheduledLeadCount: request.scheduledLeadCount,
        inflightLeadCount,
        maxInflightPerEmployee:
          this.config.maxInflightPerEmployee,
        microbatchSize: this.config.microbatchSize,
      });

      if (batchSize <= 0) {
        await this.deferClaimedQueueItem(
          transaction,
          queueItem.id,
          queueItem.organizationId,
          request.id,
          now,
          this.config.backpressureDelayMs,
          'ads_queue.backpressure',
        );

        return 'DEFERRED';
      }

      const schedulerState =
        await transaction.trafficPoolSchedulerState.findUnique({
          where: {
            organizationId_trafficPoolId: {
              organizationId: queueItem.organizationId,
              trafficPoolId: queueItem.trafficPoolId,
            },
          },
        });

      const initialNextPosition =
        schedulerState?.nextPosition ??
        eligibleMembers[0]?.position ??
        1;

      const selection = selectRoundRobinMember(
        eligibleMembers,
        initialNextPosition,
      );

      const maxSequence =
        await transaction.adsMicrobatch.aggregate({
          where: {
            adsRequestId: request.id,
          },

          _max: {
            sequence: true,
          },
        });

      const sequence =
        (maxSequence._max.sequence ?? 0) + 1;

      const microbatch =
        await transaction.adsMicrobatch.create({
          data: {
            organizationId: queueItem.organizationId,
            adsRequestId: request.id,
            adsQueueItemId: queueItem.id,
            employeeId: queueItem.employeeId,
            trafficPoolId: queueItem.trafficPoolId,
            trafficPoolMemberId: selection.member.id,
            whatsAppNumberId:
              selection.member.whatsAppNumberId,
            sequence,
            reservedLeadCount: batchSize,
          },
        });

      await transaction.trafficPoolSchedulerState.upsert({
        where: {
          organizationId_trafficPoolId: {
            organizationId: queueItem.organizationId,
            trafficPoolId: queueItem.trafficPoolId,
          },
        },

        create: {
          organizationId: queueItem.organizationId,
          trafficPoolId: queueItem.trafficPoolId,
          nextPosition: selection.nextPosition,
        },

        update: {
          nextPosition: selection.nextPosition,
        },
      });

      const scheduledLeadCount =
        request.scheduledLeadCount + batchSize;

      await transaction.adsRequest.update({
        where: {
          id: request.id,
        },

        data: {
          scheduledLeadCount: {
            increment: batchSize,
          },

          status:
            request.fulfilledLeadCount > 0
              ? 'PARTIALLY_FULFILLED'
              : 'PROCESSING',

          startedAt:
            request.startedAt ??
            now,
        },
      });

      const schedulingCompleted =
        scheduledLeadCount >=
        request.requestedLeadCount;

      await transaction.adsQueueItem.update({
        where: {
          id: queueItem.id,
        },

        data: schedulingCompleted
          ? {
              status: 'COMPLETED',
              completedAt: now,
              claimedAt: null,
              claimedByWorkerId: null,
              leaseExpiresAt: null,
            }
          : {
              status: 'WAITING',
              availableAt: addMilliseconds(
                now,
                this.config.microbatchYieldMs,
              ),
              claimedAt: null,
              claimedByWorkerId: null,
              leaseExpiresAt: null,
            },
      });

      await transaction.auditLog.create({
        data: {
          organizationId: queueItem.organizationId,
          actorType: 'SYSTEM',
          action: 'ads_microbatch.planned',
          resourceType: 'ads_microbatch',
          resourceId: microbatch.id,
          outcome: 'SUCCESS',

          metadata: {
            adsRequestId: request.id,
            adsQueueItemId: queueItem.id,
            employeeId: queueItem.employeeId,
            trafficPoolId: queueItem.trafficPoolId,
            trafficPoolMemberId:
              selection.member.id,
            whatsAppNumberId:
              selection.member.whatsAppNumberId,
            sequence,
            reservedLeadCount: batchSize,
            scheduledLeadCount,
            requestedLeadCount:
              request.requestedLeadCount,
            nextPosition:
              selection.nextPosition,
          },
        },
      });

      if (schedulingCompleted) {
        await transaction.auditLog.create({
          data: {
            organizationId: queueItem.organizationId,
            actorType: 'SYSTEM',
            action: 'ads_queue.scheduling_completed',
            resourceType: 'ads_queue_item',
            resourceId: queueItem.id,
            outcome: 'SUCCESS',

            metadata: {
              adsRequestId: request.id,
              scheduledLeadCount,
            },
          },
        });
      }

      return 'PLANNED';
    });
  }

  private async deferClaimedQueueItem(
    transaction: Parameters<
      Parameters<CrmDatabaseClient['$transaction']>[0]
    >[0],
    queueItemId: string,
    organizationId: string,
    adsRequestId: string,
    now: Date,
    delayMs: number,
    auditAction: string,
  ): Promise<void> {
    await transaction.adsQueueItem.update({
      where: {
        id: queueItemId,
      },

      data: {
        status: 'WAITING',
        availableAt: addMilliseconds(
          now,
          delayMs,
        ),
        claimedAt: null,
        claimedByWorkerId: null,
        leaseExpiresAt: null,
      },
    });

    await transaction.auditLog.create({
      data: {
        organizationId,
        actorType: 'SYSTEM',
        action: auditAction,
        resourceType: 'ads_queue_item',
        resourceId: queueItemId,
        outcome: 'SUCCESS',

        metadata: {
          adsRequestId,
          retryAfterMs: delayMs,
        },
      },
    });
  }

  private async handleProcessingError(
    claimed: ClaimedQueueItem,
    error: unknown,
  ): Promise<
    'DEFERRED' | 'FAILED' | 'LOST_LEASE'
  > {
    const message = getErrorMessage(error);

    const queueItem =
      await this.database.adsQueueItem.findFirst({
        where: {
          id: claimed.id,
          status: 'CLAIMED',
          claimedByWorkerId: this.workerId,
        },

        select: {
          id: true,
          organizationId: true,
          adsRequestId: true,
          attempts: true,
        },
      });

    if (!queueItem) {
      return 'LOST_LEASE';
    }

    if (
      queueItem.attempts >=
      this.config.maxQueueAttempts
    ) {
      await this.database.$transaction(
        async (transaction) => {
          const now = new Date();

          await transaction.adsQueueItem.update({
            where: {
              id: queueItem.id,
            },

            data: {
              status: 'FAILED',
              claimedAt: null,
              claimedByWorkerId: null,
              leaseExpiresAt: null,
            },
          });

          await transaction.adsRequest.updateMany({
            where: {
              id: queueItem.adsRequestId,

              status: {
                notIn: ['CANCELLED', 'FULFILLED'],
              },
            },

            data: {
              status: 'FAILED',
              failureReason: message,
            },
          });

          await transaction.auditLog.create({
            data: {
              organizationId:
                queueItem.organizationId,
              actorType: 'SYSTEM',
              action: 'ads_queue.failed',
              resourceType: 'ads_queue_item',
              resourceId: queueItem.id,
              outcome: 'FAILURE',

              metadata: {
                adsRequestId:
                  queueItem.adsRequestId,
                attempts:
                  queueItem.attempts,
                reason:
                  message,
              },
            },
          });
        },
      );

      return 'FAILED';
    }

    await this.database.adsQueueItem.updateMany({
      where: {
        id: queueItem.id,
        status: 'CLAIMED',
        claimedByWorkerId: this.workerId,
      },

      data: {
        status: 'WAITING',

        availableAt: addMilliseconds(
          new Date(),
          this.config.backpressureDelayMs,
        ),

        claimedAt: null,
        claimedByWorkerId: null,
        leaseExpiresAt: null,
      },
    });

    return 'DEFERRED';
  }
}
'@

Write-Text `
    -Path ".\apps\worker\src\ads-scheduler.service.ts" `
    -Content $SchedulerService

# ============================================================
# WORKER MAIN
# ============================================================

$WorkerMain = @'
import './load-environment.js';

import { randomUUID } from 'node:crypto';
import { hostname } from 'node:os';

import { createDatabaseClient } from '@crm/database';

import { AdsSchedulerService } from './ads-scheduler.service.js';

import { parseAdsSchedulerConfig } from './scheduler.config.js';

const service = 'worker' as const;

const heartbeatIntervalMs = 30_000;

const config =
  parseAdsSchedulerConfig();

const workerId =
  process.env.ADS_WORKER_ID?.trim() ||
  `${hostname()}-${process.pid}-${randomUUID()}`;

const database =
  createDatabaseClient();

const scheduler =
  new AdsSchedulerService(
    database,
    workerId,
    config,
  );

let schedulerRunning = false;
let shuttingDown = false;

function log(
  event: string,
  extra: Record<string, unknown> = {},
): void {
  console.log(
    JSON.stringify({
      event,
      service,
      workerId,
      timestamp: new Date().toISOString(),
      ...extra,
    }),
  );
}

async function runSchedulerTick(): Promise<void> {
  if (
    schedulerRunning ||
    shuttingDown
  ) {
    return;
  }

  schedulerRunning = true;

  try {
    const summary =
      await scheduler.runTick();

    if (
      summary.claimed > 0 ||
      summary.failed > 0 ||
      summary.lostLease > 0
    ) {
      log(
        'ads.scheduler.tick',
        summary,
      );
    }
  } catch (error) {
    log(
      'ads.scheduler.error',
      {
        message:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );
  } finally {
    schedulerRunning = false;
  }
}

log('service.started', {
  heartbeatIntervalMs,
  schedulerIntervalMs:
    config.intervalMs,
  microbatchSize:
    config.microbatchSize,
  maxInflightPerEmployee:
    config.maxInflightPerEmployee,
  leaseMs:
    config.leaseMs,
});

await runSchedulerTick();

const schedulerTimer =
  setInterval(
    () => {
      void runSchedulerTick();
    },
    config.intervalMs,
  );

const heartbeatTimer =
  setInterval(
    () => {
      log('service.heartbeat', {
        schedulerRunning,
      });
    },
    heartbeatIntervalMs,
  );

async function shutdown(
  signal: NodeJS.Signals,
): Promise<void> {
  if (shuttingDown) {
    return;
  }

  shuttingDown = true;

  clearInterval(
    schedulerTimer,
  );

  clearInterval(
    heartbeatTimer,
  );

  log('service.stopping', {
    signal,
  });

  while (schedulerRunning) {
    await new Promise<void>(
      (resolve) => {
        setTimeout(
          resolve,
          50,
        );
      },
    );
  }

  await database.$disconnect();

  log('service.stopped', {
    signal,
  });

  process.exit(0);
}

process.once(
  'SIGINT',
  () => {
    void shutdown('SIGINT');
  },
);

process.once(
  'SIGTERM',
  () => {
    void shutdown('SIGTERM');
  },
);
'@

Write-Text `
    -Path ".\apps\worker\src\main.ts" `
    -Content $WorkerMain

Write-Host "[OK] Worker scheduler Stage 5 criado." -ForegroundColor Green

# ============================================================
# ENV EXAMPLE
# ============================================================

$EnvExample = Read-Text -Path $EnvExamplePath

if (-not $EnvExample.Contains("ADS_MICROBATCH_SIZE=")) {
    $Stage5Environment = @(
        "",
        "# ADS Scheduler - Etapa 5",
        "ADS_SCHEDULER_INTERVAL_MS=1000",
        "ADS_MICROBATCH_SIZE=10",
        "ADS_MAX_INFLIGHT_PER_EMPLOYEE=100",
        "ADS_CLAIM_LEASE_MS=30000",
        "ADS_BACKPRESSURE_DELAY_MS=5000",
        "ADS_MICROBATCH_YIELD_MS=250",
        "ADS_MAX_CLAIMS_PER_TICK=25",
        "ADS_MAX_QUEUE_ATTEMPTS=25",
        "ADS_WORKER_ID="
    )

    $EnvExample = (
        $EnvExample.TrimEnd() +
        "`r`n" +
        ($Stage5Environment -join "`r`n") +
        "`r`n"
    )

    Write-Text `
        -Path $EnvExamplePath `
        -Content $EnvExample
}

Write-Host "[OK] .env.example atualizado." -ForegroundColor Green

# ============================================================
# STRUCTURAL VALIDATION
# ============================================================

$RequiredFiles = @(
    ".\apps\worker\src\load-environment.ts",
    ".\apps\worker\src\scheduler.config.ts",
    ".\apps\worker\src\scheduler-engine.ts",
    ".\apps\worker\src\scheduler-engine.spec.ts",
    ".\apps\worker\src\ads-scheduler.service.ts",
    ".\apps\worker\src\main.ts"
)

foreach ($RequiredFile in $RequiredFiles) {
    if (-not (Test-Path $RequiredFile)) {
        throw "Arquivo Stage 5 ausente: $RequiredFile"
    }
}

$SchemaFinal = Read-Text -Path $SchemaPath

$RequiredMarkers = @(
    "enum AdsMicrobatchStatus",
    "model TrafficPoolSchedulerState",
    "model AdsMicrobatch",
    "scheduledLeadCount",
    "claimedByWorkerId",
    "leaseExpiresAt",
    "lastAttemptAt"
)

foreach ($Marker in $RequiredMarkers) {
    if (-not $SchemaFinal.Contains($Marker)) {
        throw "Marker Stage 5 ausente no schema: $Marker"
    }
}

$WorkerMainFinal = Read-Text `
    -Path ".\apps\worker\src\main.ts"

if (-not $WorkerMainFinal.Contains("AdsSchedulerService")) {
    throw "Worker principal nao possui AdsSchedulerService."
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host "[OK] MACROBLOCO 5.1 CRIADO." -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Implementado:" -ForegroundColor Cyan
Write-Host "- AdsMicrobatch"
Write-Host "- TrafficPoolSchedulerState"
Write-Host "- scheduledLeadCount"
Write-Host "- claim atomico com SKIP LOCKED"
Write-Host "- lease de worker"
Write-Host "- recovery de lease expirado"
Write-Host "- advisory lock por Employee"
Write-Host "- advisory lock por Traffic Pool"
Write-Host "- round-robin persistente"
Write-Host "- microbatch configuravel"
Write-Host "- backpressure por Employee"
Write-Host "- overflow via availableAt"
Write-Host "- max queue attempts"
Write-Host "- worker scheduler real"
Write-Host "- cancelamento de request em processamento"
Write-Host "- cancelamento de microbatches"
Write-Host "- unit tests do engine"
Write-Host ""
Write-Host "Migration ainda NAO executada." -ForegroundColor Yellow
Write-Host "Proximo: Macrobloco 5.2." -ForegroundColor Yellow