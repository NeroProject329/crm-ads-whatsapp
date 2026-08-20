Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepositoryRoot

$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

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

    $Pattern =
        "(?ms)^$Kind\s+$([regex]::Escape($Name))\s*\{.*?^\}"

    $Match =
        [regex]::Match(
            $Content,
            $Pattern
        )

    if (-not $Match.Success) {
        throw "Prisma $Kind $Name nao encontrado."
    }

    return $Match
}

function Add-ToPrismaModel {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$Model,

        [Parameter(Mandatory = $true)]
        [string]$Marker,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Members
    )

    $Match =
        Get-PrismaBlock `
            -Content $Content `
            -Kind "model" `
            -Name $Model

    if ($Match.Value.Contains($Marker)) {
        return $Content
    }

    $Block =
        $Match.Value

    $ClosingIndex =
        $Block.LastIndexOf("}")

    if ($ClosingIndex -lt 0) {
        throw "Fechamento do model $Model nao encontrado."
    }

    $NewBlock =
        $Block.Substring(
            0,
            $ClosingIndex
        ).TrimEnd() +
        "`r`n`r`n" +
        $Members.TrimEnd() +
        "`r`n}"

    return (
        $Content.Substring(
            0,
            $Match.Index
        ) +
        $NewBlock +
        $Content.Substring(
            $Match.Index +
            $Match.Length
        )
    )
}

function Insert-AfterPrismaBlock {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [ValidateSet("model", "enum")]
        [string]$Kind,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Marker,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$NewContent
    )

    if ($Content.Contains($Marker)) {
        return $Content
    }

    $Match =
        Get-PrismaBlock `
            -Content $Content `
            -Kind $Kind `
            -Name $Name

    $InsertAt =
        $Match.Index +
        $Match.Length

    return (
        $Content.Substring(
            0,
            $InsertAt
        ) +
        "`r`n`r`n" +
        $NewContent.Trim() +
        "`r`n" +
        $Content.Substring(
            $InsertAt
        ).TrimStart(
            "`r",
            "`n"
        )
    )
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " ETAPA 11 - MACROBLOCO 11.1" -ForegroundColor Cyan
Write-Host " WHATSAPP NUMBER HEALTH + CONTINGENCY" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

# ============================================================
# PREFLIGHT
# ============================================================

$RequiredFiles = @(
    ".\packages\database\prisma\schema.prisma",
    ".\packages\database\prisma\seed.ts",
    ".\packages\database\prisma\verify-seed.ts",
    ".\packages\meta-cloud-api\src\index.ts",
    ".\apps\webhook-ingress\src\meta-webhook.service.ts",
    ".\apps\worker\src\whatsapp-inbox-processor.service.ts",
    ".\apps\worker\src\ads-scheduler.service.ts",
    ".\apps\worker\src\main.ts",
    ".\apps\api\src\app.module.ts",
    ".\apps\api\src\authorization\authorization.types.ts",
    ".\apps\api\src\authorization\access-token.guard.ts"
)

foreach ($File in $RequiredFiles) {
    if (-not (Test-Path $File)) {
        throw "Arquivo necessario ausente: $File"
    }
}

Write-Host "[OK] Preflight Stage 11." -ForegroundColor Green

# ============================================================
# BACKUP
# ============================================================

$BackupRoot =
    ".\tmp\stage11-macroblock1-backup"

Remove-Item `
    $BackupRoot `
    -Recurse `
    -Force `
    -ErrorAction SilentlyContinue

New-Item `
    -ItemType Directory `
    -Path $BackupRoot `
    -Force |
    Out-Null

$BackupFiles = @(
    ".\packages\database\prisma\schema.prisma",
    ".\packages\database\prisma\seed.ts",
    ".\packages\database\prisma\verify-seed.ts",
    ".\packages\contracts\src\index.ts",
    ".\packages\validation\src\index.ts",
    ".\packages\meta-cloud-api\src\index.ts",
    ".\apps\webhook-ingress\src\meta-webhook.service.ts",
    ".\apps\worker\src\whatsapp-inbox-processor.service.ts",
    ".\apps\worker\src\ads-scheduler.service.ts",
    ".\apps\worker\src\main.ts",
    ".\apps\api\src\app.module.ts",
    ".\apps\api\src\authorization\authorization.types.ts",
    ".\apps\api\src\authorization\access-token.guard.ts",
    ".\.env.example",
    ".\docs\ETAPAS.md"
)

foreach ($File in $BackupFiles) {
    if (Test-Path $File) {
        $SafeName =
            $File `
                -replace '^[.\\/]+', '' `
                -replace '[\\/]', '__'

        Copy-Item `
            $File `
            (Join-Path $BackupRoot $SafeName) `
            -Force
    }
}

Write-Host "[OK] Backup Stage 11 preparado." -ForegroundColor Green

# ============================================================
# PRISMA ENUMS
# ============================================================

$SchemaPath =
    ".\packages\database\prisma\schema.prisma"

$Schema =
    Read-Text -Path $SchemaPath

$HealthEnums = @'
enum MetaPhoneQualityRating {
  UNKNOWN
  GREEN
  YELLOW
  RED
  NA
}

enum WhatsAppNumberHealthStatus {
  UNKNOWN
  HEALTHY
  DEGRADED
  CRITICAL
  RECOVERING
  DISABLED
}

enum WhatsAppNumberHealthSource {
  META_API
  META_WEBHOOK
  CRM_SIGNAL
  MANUAL
  SYSTEM
}

enum WhatsAppNumberIncidentStatus {
  OPEN
  RESOLVED
}
'@

$Schema =
    Insert-AfterPrismaBlock `
        -Content $Schema `
        -Kind "enum" `
        -Name "WhatsAppNumberStatus" `
        -Marker "enum WhatsAppNumberHealthStatus" `
        -NewContent $HealthEnums

# ============================================================
# PRISMA RELATIONS
# ============================================================

$Schema =
    Add-ToPrismaModel `
        -Content $Schema `
        -Model "Organization" `
        -Marker "whatsAppNumberHealthStates" `
        -Members @'
  whatsAppNumberHealthStates WhatsAppNumberHealthState[]
  whatsAppNumberHealthEvents WhatsAppNumberHealthEvent[]
  whatsAppNumberIncidents    WhatsAppNumberIncident[]
'@

$Schema =
    Add-ToPrismaModel `
        -Content $Schema `
        -Model "WhatsAppNumber" `
        -Marker "healthState" `
        -Members @'
  healthState     WhatsAppNumberHealthState?
  healthEvents    WhatsAppNumberHealthEvent[]
  healthIncidents WhatsAppNumberIncident[]
'@

$Schema =
    Add-ToPrismaModel `
        -Content $Schema `
        -Model "MetaWebhookEnvelope" `
        -Marker "numberHealthEvents" `
        -Members @'
  numberHealthEvents WhatsAppNumberHealthEvent[]
'@

# ============================================================
# PRISMA MODELS
# ============================================================

$HealthModels = @'
model WhatsAppNumberHealthState {
  id                       String                    @id @default(uuid()) @db.Uuid
  organizationId           String                    @db.Uuid
  whatsAppNumberId         String                    @db.Uuid
  status                   WhatsAppNumberHealthStatus @default(UNKNOWN)
  schedulerEligible        Boolean                   @default(true)
  manualPaused             Boolean                   @default(false)
  metaQualityRating        MetaPhoneQualityRating    @default(UNKNOWN)
  metaQualityEvent         String?                   @db.VarChar(80)
  messagingLimitTier       String?                   @db.VarChar(80)
  lastReasonCode           String?                   @db.VarChar(120)
  lastReasonMessage        String?                   @db.VarChar(500)
  lastMetaSyncAt           DateTime?                 @db.Timestamptz(3)
  lastMetaWebhookAt        DateTime?                 @db.Timestamptz(3)
  lastHealthyAt            DateTime?                 @db.Timestamptz(3)
  degradedSinceAt          DateTime?                 @db.Timestamptz(3)
  criticalSinceAt          DateTime?                 @db.Timestamptz(3)
  recoveringSinceAt        DateTime?                 @db.Timestamptz(3)
  consecutiveHealthyChecks Int                       @default(0)
  consecutiveSyncFailures  Int                       @default(0)
  nextCheckAt              DateTime                  @default(now()) @db.Timestamptz(3)
  claimedAt                DateTime?                 @db.Timestamptz(3)
  claimedByWorkerId        String?                   @db.VarChar(120)
  leaseExpiresAt           DateTime?                 @db.Timestamptz(3)
  createdAt                DateTime                  @default(now()) @db.Timestamptz(3)
  updatedAt                DateTime                  @updatedAt @db.Timestamptz(3)

  organization   Organization   @relation(fields: [organizationId], references: [id], onDelete: Restrict)
  whatsAppNumber WhatsAppNumber @relation(fields: [organizationId, whatsAppNumberId], references: [organizationId, id], onDelete: Cascade)

  @@unique([organizationId, id])
  @@unique([organizationId, whatsAppNumberId])
  @@index([organizationId, status, schedulerEligible])
  @@index([nextCheckAt, leaseExpiresAt])
  @@index([organizationId, manualPaused])
  @@map("whatsapp_number_health_states")
}

model WhatsAppNumberHealthEvent {
  id                  String                     @id @default(uuid()) @db.Uuid
  organizationId      String                     @db.Uuid
  whatsAppNumberId    String                     @db.Uuid
  sourceEnvelopeId    String?                    @db.Uuid
  source              WhatsAppNumberHealthSource
  previousStatus      WhatsAppNumberHealthStatus
  currentStatus       WhatsAppNumberHealthStatus
  metaQualityRating   MetaPhoneQualityRating
  metaQualityEvent    String?                    @db.VarChar(80)
  messagingLimitTier  String?                    @db.VarChar(80)
  schedulerEligible   Boolean
  reasonCode          String?                    @db.VarChar(120)
  reasonMessage       String?                    @db.VarChar(500)
  occurredAt          DateTime                   @default(now()) @db.Timestamptz(3)
  createdAt           DateTime                   @default(now()) @db.Timestamptz(3)

  organization   Organization         @relation(fields: [organizationId], references: [id], onDelete: Restrict)
  whatsAppNumber WhatsAppNumber       @relation(fields: [organizationId, whatsAppNumberId], references: [organizationId, id], onDelete: Cascade)
  sourceEnvelope MetaWebhookEnvelope? @relation(fields: [sourceEnvelopeId], references: [id], onDelete: SetNull)

  @@unique([organizationId, id])
  @@index([organizationId, whatsAppNumberId, occurredAt])
  @@index([organizationId, currentStatus, occurredAt])
  @@index([sourceEnvelopeId])
  @@map("whatsapp_number_health_events")
}

model WhatsAppNumberIncident {
  id                String                       @id @default(uuid()) @db.Uuid
  organizationId    String                       @db.Uuid
  whatsAppNumberId  String                       @db.Uuid
  status            WhatsAppNumberIncidentStatus @default(OPEN)
  type              String                       @db.VarChar(120)
  severity          WhatsAppNumberHealthStatus
  openedReasonCode  String?                      @db.VarChar(120)
  openedReason      String?                      @db.VarChar(500)
  openedAt          DateTime                     @default(now()) @db.Timestamptz(3)
  resolvedReason    String?                      @db.VarChar(500)
  resolvedAt        DateTime?                    @db.Timestamptz(3)
  createdAt         DateTime                     @default(now()) @db.Timestamptz(3)
  updatedAt         DateTime                     @updatedAt @db.Timestamptz(3)

  organization   Organization   @relation(fields: [organizationId], references: [id], onDelete: Restrict)
  whatsAppNumber WhatsAppNumber @relation(fields: [organizationId, whatsAppNumberId], references: [organizationId, id], onDelete: Cascade)

  @@unique([organizationId, id])
  @@index([organizationId, whatsAppNumberId, status, openedAt])
  @@index([organizationId, status, severity])
  @@map("whatsapp_number_incidents")
}
'@

$Schema =
    Insert-AfterPrismaBlock `
        -Content $Schema `
        -Kind "model" `
        -Name "WhatsAppNumber" `
        -Marker "model WhatsAppNumberHealthState {" `
        -NewContent $HealthModels

Write-Text `
    -Path $SchemaPath `
    -Content $Schema

Write-Host "[OK] Prisma health models criados." -ForegroundColor Green

# ============================================================
# META PHONE NUMBER PROFILE
# ============================================================

$PhoneNumberProfile = @'
import type {
  MetaCloudApiClient,
} from './client.js';

export type MetaPhoneNumberQualityRating =
  | 'GREEN'
  | 'YELLOW'
  | 'RED'
  | 'NA'
  | 'UNKNOWN';

export type MetaPhoneNumberProfile =
  Readonly<{
    id: string;
    verifiedName: string | null;
    displayPhoneNumber: string | null;
    qualityRating:
      MetaPhoneNumberQualityRating;
  }>;

function isRecord(
  value:
    unknown,
): value is Record<
  string,
  unknown
> {
  return (
    typeof value ===
      'object' &&
    value !==
      null &&
    !Array.isArray(
      value,
    )
  );
}

function readString(
  value:
    unknown,
): string | null {
  return typeof value ===
    'string'
    ? value
    : null;
}

function parseQualityRating(
  value:
    unknown,
): MetaPhoneNumberQualityRating {
  const normalized =
    typeof value ===
      'string'
      ? value
          .trim()
          .toUpperCase()
      : '';

  switch (
    normalized
  ) {
    case 'GREEN':
      return 'GREEN';

    case 'YELLOW':
      return 'YELLOW';

    case 'RED':
      return 'RED';

    case 'NA':
      return 'NA';

    default:
      return 'UNKNOWN';
  }
}

export async function getMetaPhoneNumberProfile(
  client:
    MetaCloudApiClient,

  phoneNumberId:
    string,
): Promise<
  MetaPhoneNumberProfile
> {
  const id =
    phoneNumberId.trim();

  if (
    !/^\d+$/.test(
      id,
    )
  ) {
    throw new Error(
      'Invalid Meta phone number id.',
    );
  }

  const payload =
    await client.get<unknown>(
      id,
      {
        fields:
          'id,verified_name,display_phone_number,quality_rating',
      },
    );

  if (
    !isRecord(
      payload,
    )
  ) {
    throw new Error(
      'Invalid Meta phone number profile response.',
    );
  }

  return {
    id:
      readString(
        payload.id,
      ) ??
      id,

    verifiedName:
      readString(
        payload.verified_name,
      ),

    displayPhoneNumber:
      readString(
        payload.display_phone_number,
      ),

    qualityRating:
      parseQualityRating(
        payload.quality_rating,
      ),
  };
}
'@

Write-Text `
    -Path ".\packages\meta-cloud-api\src\phone-number-profile.ts" `
    -Content $PhoneNumberProfile

# ============================================================
# META QUALITY WEBHOOK PARSER
# ============================================================

$QualityWebhookParser = @'
export type MetaPhoneNumberQualityUpdate =
  Readonly<{
    wabaId: string | null;
    displayPhoneNumber: string;
    event: string | null;
    currentLimit: string | null;
  }>;

function isRecord(
  value:
    unknown,
): value is Record<
  string,
  unknown
> {
  return (
    typeof value ===
      'object' &&
    value !==
      null &&
    !Array.isArray(
      value,
    )
  );
}

function readString(
  value:
    unknown,
): string | null {
  return typeof value ===
    'string'
    ? value
    : null;
}

export function parseMetaPhoneNumberQualityUpdates(
  payload:
    unknown,
): readonly MetaPhoneNumberQualityUpdate[] {
  if (
    !isRecord(
      payload,
    )
  ) {
    return [];
  }

  const entries =
    Array.isArray(
      payload.entry,
    )
      ? payload.entry
      : [];

  const result:
    MetaPhoneNumberQualityUpdate[] =
      [];

  for (
    const rawEntry of
      entries
  ) {
    if (
      !isRecord(
        rawEntry,
      )
    ) {
      continue;
    }

    const wabaId =
      readString(
        rawEntry.id,
      );

    const changes =
      Array.isArray(
        rawEntry.changes,
      )
        ? rawEntry.changes
        : [];

    for (
      const rawChange of
        changes
    ) {
      if (
        !isRecord(
          rawChange,
        ) ||
        rawChange.field !==
          'phone_number_quality_update'
      ) {
        continue;
      }

      const value =
        isRecord(
          rawChange.value,
        )
          ? rawChange.value
          : null;

      if (
        !value
      ) {
        continue;
      }

      const displayPhoneNumber =
        readString(
          value.display_phone_number,
        );

      if (
        !displayPhoneNumber
      ) {
        continue;
      }

      result.push({
        wabaId,

        displayPhoneNumber,

        event:
          readString(
            value.event,
          ),

        currentLimit:
          readString(
            value.current_limit,
          ),
      });
    }
  }

  return result;
}
'@

Write-Text `
    -Path ".\packages\meta-cloud-api\src\phone-number-quality-webhook.ts" `
    -Content $QualityWebhookParser

$MetaIndexPath =
    ".\packages\meta-cloud-api\src\index.ts"

$MetaIndex =
    Read-Text -Path $MetaIndexPath

foreach ($Export in @(
    "export * from './phone-number-profile.js';",
    "export * from './phone-number-quality-webhook.js';"
)) {
    if (
        -not $MetaIndex.Contains(
            $Export
        )
    ) {
        $MetaIndex =
            $MetaIndex.TrimEnd() +
            "`r`n" +
            $Export +
            "`r`n"
    }
}

Write-Text `
    -Path $MetaIndexPath `
    -Content $MetaIndex

Write-Host "[OK] Meta phone health parsers criados." -ForegroundColor Green

# ============================================================
# CONTRACTS
# ============================================================

$HealthContracts = @'
export type MetaPhoneQualityRating =
  | 'UNKNOWN'
  | 'GREEN'
  | 'YELLOW'
  | 'RED'
  | 'NA';

export type WhatsAppNumberHealthStatus =
  | 'UNKNOWN'
  | 'HEALTHY'
  | 'DEGRADED'
  | 'CRITICAL'
  | 'RECOVERING'
  | 'DISABLED';

export type WhatsAppNumberHealthSource =
  | 'META_API'
  | 'META_WEBHOOK'
  | 'CRM_SIGNAL'
  | 'MANUAL'
  | 'SYSTEM';

export type WhatsAppNumberHealthResponse =
  Readonly<{
    whatsAppNumberId: string;
    status:
      WhatsAppNumberHealthStatus;
    schedulerEligible: boolean;
    manualPaused: boolean;

    metaQualityRating:
      MetaPhoneQualityRating;

    metaQualityEvent:
      string | null;

    messagingLimitTier:
      string | null;

    lastReasonCode:
      string | null;

    lastReasonMessage:
      string | null;

    lastMetaSyncAt:
      string | null;

    lastMetaWebhookAt:
      string | null;

    lastHealthyAt:
      string | null;

    degradedSinceAt:
      string | null;

    criticalSinceAt:
      string | null;

    recoveringSinceAt:
      string | null;

    consecutiveHealthyChecks:
      number;

    consecutiveSyncFailures:
      number;

    nextCheckAt:
      string;

    updatedAt:
      string;
  }>;

export type WhatsAppNumberHealthEventResponse =
  Readonly<{
    id: string;
    source:
      WhatsAppNumberHealthSource;
    previousStatus:
      WhatsAppNumberHealthStatus;
    currentStatus:
      WhatsAppNumberHealthStatus;
    metaQualityRating:
      MetaPhoneQualityRating;
    metaQualityEvent:
      string | null;
    messagingLimitTier:
      string | null;
    schedulerEligible:
      boolean;
    reasonCode:
      string | null;
    reasonMessage:
      string | null;
    occurredAt:
      string;
  }>;

export type WhatsAppNumberIncidentResponse =
  Readonly<{
    id: string;
    status:
      'OPEN' |
      'RESOLVED';
    type: string;
    severity:
      WhatsAppNumberHealthStatus;
    openedReasonCode:
      string | null;
    openedReason:
      string | null;
    openedAt:
      string;
    resolvedReason:
      string | null;
    resolvedAt:
      string | null;
  }>;
'@

Write-Text `
    -Path ".\packages\contracts\src\whatsapp-health.ts" `
    -Content $HealthContracts

$ContractsIndexPath =
    ".\packages\contracts\src\index.ts"

$ContractsIndex =
    Read-Text -Path $ContractsIndexPath

if (
    -not $ContractsIndex.Contains(
        "export * from './whatsapp-health.js';"
    )
) {
    $ContractsIndex =
        $ContractsIndex.TrimEnd() +
        "`r`n" +
        "export * from './whatsapp-health.js';`r`n"
}

Write-Text `
    -Path $ContractsIndexPath `
    -Content $ContractsIndex

# ============================================================
# VALIDATION
# ============================================================

$HealthValidation = @'
import {
  z,
} from 'zod';

export const whatsAppHealthHistoryQuerySchema =
  z
    .object({
      limit:
        z.coerce
          .number()
          .int()
          .min(1)
          .max(200)
          .default(50),
    })
    .strict();

export type WhatsAppHealthHistoryQuery =
  z.infer<
    typeof whatsAppHealthHistoryQuerySchema
  >;
'@

Write-Text `
    -Path ".\packages\validation\src\whatsapp-health.ts" `
    -Content $HealthValidation

$ValidationIndexPath =
    ".\packages\validation\src\index.ts"

$ValidationIndex =
    Read-Text -Path $ValidationIndexPath

if (
    -not $ValidationIndex.Contains(
        "export * from './whatsapp-health.js';"
    )
) {
    $ValidationIndex =
        $ValidationIndex.TrimEnd() +
        "`r`n" +
        "export * from './whatsapp-health.js';`r`n"
}

Write-Text `
    -Path $ValidationIndexPath `
    -Content $ValidationIndex

Write-Host "[OK] Health contracts + validation criados." -ForegroundColor Green

# ============================================================
# PERMISSIONS
# ============================================================

$SeedPath =
    ".\packages\database\prisma\seed.ts"

$Seed =
    Read-Text -Path $SeedPath

if (
    -not $Seed.Contains(
        "'whatsapp_health.read'"
    )
) {
    $Anchor =
        "  ['whatsapp_number.read',"

    $Index =
        $Seed.IndexOf(
            $Anchor
        )

    if (
        $Index -lt 0
    ) {
        throw "Seed WhatsApp permission anchor nao encontrado."
    }

    $NewPermissions =
        "  ['whatsapp_health.read', 'Visualizar saude dos numeros WhatsApp'],`r`n" +
        "  ['whatsapp_health.manage', 'Gerenciar contingencia dos numeros WhatsApp'],`r`n"

    $Seed =
        $Seed.Insert(
            $Index,
            $NewPermissions
        )
}

if (
    -not [regex]::IsMatch(
        $Seed,
        "(?m)^\s*'whatsapp_health\.read',\s*$"
    )
) {
    $EmployeeAnchor =
        "    'whatsapp_number.read',"

    if (
        -not $Seed.Contains(
            $EmployeeAnchor
        )
    ) {
        throw "Employee WhatsApp permission anchor nao encontrado."
    }

    $Seed =
        $Seed.Replace(
            $EmployeeAnchor,
            "    'whatsapp_health.read',`r`n" +
            $EmployeeAnchor
        )
}

Write-Text `
    -Path $SeedPath `
    -Content $Seed

$VerifySeedPath =
    ".\packages\database\prisma\verify-seed.ts"

$VerifySeed =
    Read-Text -Path $VerifySeedPath

if (
    -not $VerifySeed.Contains(
        "'whatsapp_health.read'"
    )
) {
    $VerifySeed =
        $VerifySeed.Replace(
            "  'whatsapp_number.manage',",
            "  'whatsapp_health.manage',`r`n" +
            "  'whatsapp_health.read',`r`n" +
            "  'whatsapp_number.manage',"
        )

    $VerifySeed =
        $VerifySeed.Replace(
            "  'whatsapp_number.read',`r`n] as const;",
            "  'whatsapp_health.read',`r`n" +
            "  'whatsapp_number.read',`r`n] as const;"
        )
}

Write-Text `
    -Path $VerifySeedPath `
    -Content $VerifySeed

$AuthorizationTypesPath =
    ".\apps\api\src\authorization\authorization.types.ts"

$AuthorizationTypes =
    Read-Text -Path $AuthorizationTypesPath

if (
    -not $AuthorizationTypes.Contains(
        "'whatsapp_health.read'"
    )
) {
    $Anchor =
        "  | 'lead.read';"

    if (
        -not $AuthorizationTypes.Contains(
            $Anchor
        )
    ) {
        throw "PermissionCode lead.read anchor nao encontrado."
    }

    $AuthorizationTypes =
        $AuthorizationTypes.Replace(
            $Anchor,
            "  | 'lead.read'`r`n" +
            "  | 'whatsapp_health.read'`r`n" +
            "  | 'whatsapp_health.manage';"
        )
}

Write-Text `
    -Path $AuthorizationTypesPath `
    -Content $AuthorizationTypes

$GuardPath =
    ".\apps\api\src\authorization\access-token.guard.ts"

$Guard =
    Read-Text -Path $GuardPath

if (
    -not $Guard.Contains(
        "value === 'whatsapp_health.read'"
    )
) {
    $Anchor =
        "      value === 'lead.read'"

    if (
        -not $Guard.Contains(
            $Anchor
        )
    ) {
        throw "AccessTokenGuard lead.read anchor nao encontrado."
    }

    $Guard =
        $Guard.Replace(
            $Anchor,
            $Anchor +
            " ||`r`n" +
            "      value === 'whatsapp_health.read' ||`r`n" +
            "      value === 'whatsapp_health.manage'"
        )
}

Write-Text `
    -Path $GuardPath `
    -Content $Guard

Write-Host "[OK] WhatsApp health permissions criadas." -ForegroundColor Green

# ============================================================
# WEBHOOK INGRESS - QUALITY UPDATE RESOLUTION
# ============================================================

$IngressService = @'
import {
  createHash,
} from 'node:crypto';

import {
  Inject,
  Injectable,
} from '@nestjs/common';

import {
  extractMetaWebhookSummary,
  parseMetaPhoneNumberQualityUpdates,
} from '@crm/meta-cloud-api';

import {
  DatabaseService,
} from './database.service.js';

type JsonPrimitive =
  | string
  | number
  | boolean
  | null;

type JsonValue =
  | JsonPrimitive
  | JsonValue[]
  | {
      [key: string]:
        JsonValue;
    };

type JsonObject = {
  [key: string]:
    JsonValue;
};

function normalizeJsonValue(
  value:
    unknown,
): JsonValue {
  if (
    value ===
      null ||
    typeof value ===
      'string' ||
    typeof value ===
      'boolean'
  ) {
    return value;
  }

  if (
    typeof value ===
      'number'
  ) {
    return Number.isFinite(
      value,
    )
      ? value
      : null;
  }

  if (
    Array.isArray(
      value,
    )
  ) {
    return value.map(
      normalizeJsonValue,
    );
  }

  if (
    typeof value ===
      'object' &&
    value !==
      null
  ) {
    const result:
      JsonObject =
        {};

    for (
      const [
        key,
        item,
      ] of Object.entries(
        value,
      )
    ) {
      result[key] =
        normalizeJsonValue(
          item,
        );
    }

    return result;
  }

  return null;
}

function normalizePayload(
  value:
    unknown,
): JsonObject {
  const normalized =
    normalizeJsonValue(
      value,
    );

  if (
    typeof normalized ===
      'object' &&
    normalized !==
      null &&
    !Array.isArray(
      normalized,
    )
  ) {
    return normalized;
  }

  return {
    value:
      normalized,
  };
}

function normalizePhoneDigits(
  value:
    string | null,
): string | null {
  if (
    !value
  ) {
    return null;
  }

  const digits =
    value.replace(
      /\D/g,
      '',
    );

  return digits.length >
    0
    ? digits
    : null;
}

export type MetaWebhookIngestResult =
  Readonly<{
    envelopeId: string;

    status:
      | 'RECEIVED'
      | 'UNMATCHED'
      | 'IGNORED';

    organizationId:
      string | null;

    whatsAppNumberId:
      string | null;
  }>;

@Injectable()
export class MetaWebhookService {
  constructor(
    @Inject(
      DatabaseService,
    )
    private readonly database:
      DatabaseService,
  ) {}

  async ingest(
    payload:
      unknown,

    rawBody:
      Buffer,
  ): Promise<
    MetaWebhookIngestResult
  > {
    const summary =
      extractMetaWebhookSummary(
        payload,
      );

    const qualityUpdates =
      parseMetaPhoneNumberQualityUpdates(
        payload,
      );

    const firstQualityUpdate =
      qualityUpdates.at(
        0,
      );

    const displayDigits =
      normalizePhoneDigits(
        firstQualityUpdate?.displayPhoneNumber ??
          null,
      );

    const payloadHash =
      createHash(
        'sha256',
      )
        .update(
          rawBody,
        )
        .digest(
          'hex',
        );

    const number =
      summary.phoneNumberId
        ? await this.database.client.whatsAppNumber.findFirst({
            where: {
              metaPhoneNumberId:
                summary.phoneNumberId,

              deletedAt:
                null,

              ...(summary.wabaId
                ? {
                    metaWabaId:
                      summary.wabaId,
                  }
                : {}),
            },

            select: {
              id:
                true,

              organizationId:
                true,
            },
          })
        : displayDigits
          ? await this.database.client.whatsAppNumber.findFirst({
              where: {
                e164:
                  `+${displayDigits}`,

                deletedAt:
                  null,

                ...(summary.wabaId
                  ? {
                      metaWabaId:
                        summary.wabaId,
                    }
                  : {}),
              },

              select: {
                id:
                  true,

                organizationId:
                  true,
              },
            })
          : null;

    const status:
      | 'RECEIVED'
      | 'UNMATCHED'
      | 'IGNORED' =
        summary.object !==
          'whatsapp_business_account'
          ? 'IGNORED'
          : number
            ? 'RECEIVED'
            : 'UNMATCHED';

    const receivedAt =
      new Date();

    const envelope =
      await this.database.client.$transaction(
        async (
          transaction,
        ) => {
          const stored =
            await transaction.metaWebhookEnvelope.upsert({
              where: {
                payloadHash,
              },

              create: {
                organizationId:
                  number?.organizationId ??
                  null,

                whatsAppNumberId:
                  number?.id ??
                  null,

                object:
                  summary.object,

                field:
                  summary.field,

                wabaId:
                  summary.wabaId,

                metaPhoneNumberId:
                  summary.phoneNumberId,

                payloadHash,

                payload:
                  normalizePayload(
                    payload,
                  ),

                status,

                receivedAt,
              },

              update:
                {},
            });

          if (
            number
          ) {
            await transaction.whatsAppNumber.update({
              where: {
                id:
                  number.id,
              },

              data: {
                metaWebhookLastSeenAt:
                  receivedAt,
              },
            });

            await transaction.whatsAppNumberHealthState.upsert({
              where: {
                organizationId_whatsAppNumberId: {
                  organizationId:
                    number.organizationId,

                  whatsAppNumberId:
                    number.id,
                },
              },

              create: {
                organizationId:
                  number.organizationId,

                whatsAppNumberId:
                  number.id,

                lastMetaWebhookAt:
                  receivedAt,

                nextCheckAt:
                  receivedAt,
              },

              update: {
                lastMetaWebhookAt:
                  receivedAt,
              },
            });
          }

          return stored;
        },
      );

    return {
      envelopeId:
        envelope.id,

      status:
        envelope.status ===
          'RECEIVED'
          ? 'RECEIVED'
          : envelope.status ===
                'UNMATCHED'
            ? 'UNMATCHED'
            : 'IGNORED',

      organizationId:
        envelope.organizationId,

      whatsAppNumberId:
        envelope.whatsAppNumberId,
    };
  }
}
'@

Write-Text `
    -Path ".\apps\webhook-ingress\src\meta-webhook.service.ts" `
    -Content $IngressService

Write-Host "[OK] Quality webhook agora pode resolver numero por E164." -ForegroundColor Green

# ============================================================
# WORKER HEALTH CONFIG
# ============================================================

$HealthConfig = @'
export type WhatsAppNumberHealthConfig =
  Readonly<{
    intervalMs:
      number;

    pollIntervalMs:
      number;

    failureRetryMs:
      number;

    leaseMs:
      number;

    maxClaimsPerTick:
      number;

    recoveryHealthyChecks:
      number;
  }>;

function parsePositiveInteger(
  name:
    string,

  fallback:
    number,
): number {
  const raw =
    process.env[name]?.trim();

  if (
    !raw
  ) {
    return fallback;
  }

  const value =
    Number(raw);

  if (
    !Number.isInteger(
      value,
    ) ||
    value <=
      0
  ) {
    throw new Error(
      `${name} must be a positive integer.`,
    );
  }

  return value;
}

export function parseWhatsAppNumberHealthConfig():
WhatsAppNumberHealthConfig {
  return {
    intervalMs:
      parsePositiveInteger(
        'WHATSAPP_HEALTH_INTERVAL_MS',
        5000,
      ),

    pollIntervalMs:
      parsePositiveInteger(
        'WHATSAPP_HEALTH_POLL_INTERVAL_MS',
        15 *
          60 *
          1000,
      ),

    failureRetryMs:
      parsePositiveInteger(
        'WHATSAPP_HEALTH_FAILURE_RETRY_MS',
        60 *
          1000,
      ),

    leaseMs:
      parsePositiveInteger(
        'WHATSAPP_HEALTH_LEASE_MS',
        30000,
      ),

    maxClaimsPerTick:
      parsePositiveInteger(
        'WHATSAPP_HEALTH_MAX_CLAIMS_PER_TICK',
        10,
      ),

    recoveryHealthyChecks:
      parsePositiveInteger(
        'WHATSAPP_HEALTH_RECOVERY_GREEN_CHECKS',
        2,
      ),
  };
}
'@

Write-Text `
    -Path ".\apps\worker\src\whatsapp-number-health.config.ts" `
    -Content $HealthConfig

# ============================================================
# WORKER HEALTH DOMAIN
# ============================================================

$HealthDomain = @'
import type {
  CrmDatabaseClient,
  MetaPhoneQualityRating,
  WhatsAppNumberHealthSource,
  WhatsAppNumberHealthStatus,
} from '@crm/database';

import type {
  MetaPhoneNumberQualityRating,
  MetaPhoneNumberQualityUpdate,
} from '@crm/meta-cloud-api';

type TransactionClient =
  Parameters<
    Parameters<
      CrmDatabaseClient['$transaction']
    >[0]
  >[0];

type ApplySignalInput =
  Readonly<{
    organizationId:
      string;

    whatsAppNumberId:
      string;

    source:
      WhatsAppNumberHealthSource;

    sourceEnvelopeId?:
      string | null;

    qualityRating?:
      MetaPhoneNumberQualityRating;

    qualityEvent?:
      string | null;

    currentLimit?:
      string | null;

    observedAt:
      Date;
  }>;

function mapQuality(
  value:
    MetaPhoneNumberQualityRating,
): MetaPhoneQualityRating {
  switch (
    value
  ) {
    case 'GREEN':
      return 'GREEN';

    case 'YELLOW':
      return 'YELLOW';

    case 'RED':
      return 'RED';

    case 'NA':
      return 'NA';

    default:
      return 'UNKNOWN';
  }
}

function gatesScheduler(
  status:
    WhatsAppNumberHealthStatus,
): boolean {
  return (
    status ===
      'DEGRADED' ||
    status ===
      'CRITICAL' ||
    status ===
      'RECOVERING' ||
    status ===
      'DISABLED'
  );
}

export class WhatsAppNumberHealthDomainService {
  constructor(
    private readonly recoveryHealthyChecks:
      number = 2,
  ) {}

  async applyMetaWebhook(
    transaction:
      TransactionClient,

    input:
      Readonly<{
        organizationId:
          string;

        whatsAppNumberId:
          string;

        sourceEnvelopeId:
          string;

        update:
          MetaPhoneNumberQualityUpdate;

        observedAt:
          Date;
      }>,
  ): Promise<void> {
    await this.applySignal(
      transaction,
      {
        organizationId:
          input.organizationId,

        whatsAppNumberId:
          input.whatsAppNumberId,

        source:
          'META_WEBHOOK',

        sourceEnvelopeId:
          input.sourceEnvelopeId,

        qualityEvent:
          input.update.event,

        currentLimit:
          input.update.currentLimit,

        observedAt:
          input.observedAt,
      },
    );
  }

  async applyMetaApi(
    transaction:
      TransactionClient,

    input:
      Readonly<{
        organizationId:
          string;

        whatsAppNumberId:
          string;

        qualityRating:
          MetaPhoneNumberQualityRating;

        observedAt:
          Date;
      }>,
  ): Promise<void> {
    await this.applySignal(
      transaction,
      {
        organizationId:
          input.organizationId,

        whatsAppNumberId:
          input.whatsAppNumberId,

        source:
          'META_API',

        qualityRating:
          input.qualityRating,

        observedAt:
          input.observedAt,
      },
    );
  }

  private async applySignal(
    transaction:
      TransactionClient,

    input:
      ApplySignalInput,
  ): Promise<void> {
    await transaction.$queryRawUnsafe(
      'WITH lock_guard AS MATERIALIZED (SELECT pg_advisory_xact_lock(hashtextextended($1, 0))) SELECT TRUE AS locked FROM lock_guard',
      `whatsapp-number-health:${input.organizationId}:${input.whatsAppNumberId}`,
    );

    const state =
      await transaction.whatsAppNumberHealthState.upsert({
        where: {
          organizationId_whatsAppNumberId: {
            organizationId:
              input.organizationId,

            whatsAppNumberId:
              input.whatsAppNumberId,
          },
        },

        create: {
          organizationId:
            input.organizationId,

          whatsAppNumberId:
            input.whatsAppNumberId,
        },

        update:
          {},
      });

    const nextQuality =
      input.qualityRating
        ? mapQuality(
            input.qualityRating,
          )
        : state.metaQualityRating;

    const normalizedEvent =
      input.qualityEvent
        ?.trim()
        .toUpperCase() ??
      null;

    let nextStatus:
      WhatsAppNumberHealthStatus =
        state.status;

    let nextEligible =
      state.schedulerEligible;

    let healthyChecks =
      state.consecutiveHealthyChecks;

    let reasonCode:
      string | null =
        state.lastReasonCode;

    let reasonMessage:
      string | null =
        state.lastReasonMessage;

    if (
      state.manualPaused
    ) {
      nextStatus =
        'DISABLED';

      nextEligible =
        false;

      reasonCode =
        'MANUAL_PAUSE';

      reasonMessage =
        'WhatsApp number is manually paused.';
    }
    else if (
      nextQuality ===
        'RED' ||
      normalizedEvent ===
        'FLAGGED'
    ) {
      nextStatus =
        'CRITICAL';

      nextEligible =
        false;

      healthyChecks =
        0;

      reasonCode =
        normalizedEvent ===
          'FLAGGED'
          ? 'META_QUALITY_FLAGGED'
          : 'META_QUALITY_RED';

      reasonMessage =
        'Meta reported a critical phone number quality signal.';
    }
    else if (
      nextQuality ===
        'YELLOW' ||
      normalizedEvent ===
        'DOWNGRADE'
    ) {
      nextStatus =
        'DEGRADED';

      nextEligible =
        false;

      healthyChecks =
        0;

      reasonCode =
        normalizedEvent ===
          'DOWNGRADE'
          ? 'META_QUALITY_DOWNGRADE'
          : 'META_QUALITY_YELLOW';

      reasonMessage =
        'Meta reported a degraded phone number quality signal.';
    }
    else if (
      normalizedEvent ===
        'UNFLAGGED'
    ) {
      nextStatus =
        'RECOVERING';

      nextEligible =
        false;

      healthyChecks =
        0;

      reasonCode =
        'META_QUALITY_UNFLAGGED';

      reasonMessage =
        'Meta removed the quality flag; recovery confirmation is required.';
    }
    else if (
      nextQuality ===
        'GREEN'
    ) {
      if (
        state.status ===
          'CRITICAL' ||
        state.status ===
          'DEGRADED' ||
        state.status ===
          'RECOVERING'
      ) {
        healthyChecks =
          state.consecutiveHealthyChecks +
          1;

        if (
          healthyChecks >=
          this.recoveryHealthyChecks
        ) {
          nextStatus =
            'HEALTHY';

          nextEligible =
            true;

          reasonCode =
            'META_QUALITY_GREEN_CONFIRMED';

          reasonMessage =
            'Meta quality recovered and passed consecutive green confirmation.';
        }
        else {
          nextStatus =
            'RECOVERING';

          nextEligible =
            false;

          reasonCode =
            'META_QUALITY_GREEN_RECOVERING';

          reasonMessage =
            'Meta quality is green but recovery confirmation is still in progress.';
        }
      }
      else {
        nextStatus =
          'HEALTHY';

        nextEligible =
          true;

        healthyChecks =
          Math.max(
            1,
            state.consecutiveHealthyChecks,
          );

        reasonCode =
          'META_QUALITY_GREEN';

        reasonMessage =
          'Meta reported high phone number quality.';
      }
    }
    else if (
      state.status ===
        'UNKNOWN' &&
      (
        nextQuality ===
          'NA' ||
        nextQuality ===
          'UNKNOWN'
      )
    ) {
      nextStatus =
        'UNKNOWN';

      nextEligible =
        true;

      reasonCode =
        'META_QUALITY_UNDETERMINED';

      reasonMessage =
        'Meta has not determined phone number quality.';
    }

    if (
      state.schedulerEligible &&
      !nextEligible
    ) {
      await this.releaseReservedCapacity(
        transaction,
        input.organizationId,
        input.whatsAppNumberId,
        nextStatus,
        input.observedAt,
      );
    }

    const statusChanged =
      nextStatus !==
      state.status;

    const qualityChanged =
      nextQuality !==
      state.metaQualityRating;

    const eventChanged =
      normalizedEvent !==
        null &&
      normalizedEvent !==
        state.metaQualityEvent;

    const limitChanged =
      input.currentLimit !==
        undefined &&
      (
        input.currentLimit ??
        null
      ) !==
        state.messagingLimitTier;

    await transaction.whatsAppNumberHealthState.update({
      where: {
        id:
          state.id,
      },

      data: {
        status:
          nextStatus,

        schedulerEligible:
          nextEligible,

        metaQualityRating:
          nextQuality,

        ...(normalizedEvent !==
        null
          ? {
              metaQualityEvent:
                normalizedEvent,
            }
          : {}),

        ...(input.currentLimit !==
        undefined
          ? {
              messagingLimitTier:
                input.currentLimit,
            }
          : {}),

        lastReasonCode:
          reasonCode,

        lastReasonMessage:
          reasonMessage,

        ...(input.source ===
        'META_API'
          ? {
              lastMetaSyncAt:
                input.observedAt,

              consecutiveSyncFailures:
                0,
            }
          : {}),

        ...(input.source ===
        'META_WEBHOOK'
          ? {
              lastMetaWebhookAt:
                input.observedAt,

              nextCheckAt:
                input.observedAt,
            }
          : {}),

        consecutiveHealthyChecks:
          healthyChecks,

        ...(nextStatus ===
        'HEALTHY'
          ? {
              lastHealthyAt:
                input.observedAt,

              degradedSinceAt:
                null,

              criticalSinceAt:
                null,

              recoveringSinceAt:
                null,
            }
          : {}),

        ...(nextStatus ===
          'DEGRADED' &&
        state.status !==
          'DEGRADED'
          ? {
              degradedSinceAt:
                input.observedAt,
            }
          : {}),

        ...(nextStatus ===
          'CRITICAL' &&
        state.status !==
          'CRITICAL'
          ? {
              criticalSinceAt:
                input.observedAt,
            }
          : {}),

        ...(nextStatus ===
          'RECOVERING' &&
        state.status !==
          'RECOVERING'
          ? {
              recoveringSinceAt:
                input.observedAt,
            }
          : {}),
      },
    });

    if (
      statusChanged ||
      qualityChanged ||
      eventChanged ||
      limitChanged
    ) {
      await transaction.whatsAppNumberHealthEvent.create({
        data: {
          organizationId:
            input.organizationId,

          whatsAppNumberId:
            input.whatsAppNumberId,

          sourceEnvelopeId:
            input.sourceEnvelopeId ??
            null,

          source:
            input.source,

          previousStatus:
            state.status,

          currentStatus:
            nextStatus,

          metaQualityRating:
            nextQuality,

          metaQualityEvent:
            normalizedEvent,

          messagingLimitTier:
            input.currentLimit ??
            state.messagingLimitTier,

          schedulerEligible:
            nextEligible,

          reasonCode,

          reasonMessage,

          occurredAt:
            input.observedAt,
        },
      });
    }

    if (
      nextStatus ===
        'DEGRADED' ||
      nextStatus ===
        'CRITICAL'
    ) {
      const openIncident =
        await transaction.whatsAppNumberIncident.findFirst({
          where: {
            organizationId:
              input.organizationId,

            whatsAppNumberId:
              input.whatsAppNumberId,

            status:
              'OPEN',

            type:
              'META_QUALITY',
          },
        });

      if (
        openIncident
      ) {
        await transaction.whatsAppNumberIncident.update({
          where: {
            id:
              openIncident.id,
          },

          data: {
            severity:
              nextStatus,

            openedReasonCode:
              reasonCode,

            openedReason:
              reasonMessage,
          },
        });
      }
      else {
        await transaction.whatsAppNumberIncident.create({
          data: {
            organizationId:
              input.organizationId,

            whatsAppNumberId:
              input.whatsAppNumberId,

            type:
              'META_QUALITY',

            severity:
              nextStatus,

            openedReasonCode:
              reasonCode,

            openedReason:
              reasonMessage,

            openedAt:
              input.observedAt,
          },
        });
      }
    }

    if (
      nextStatus ===
        'HEALTHY'
    ) {
      await transaction.whatsAppNumberIncident.updateMany({
        where: {
          organizationId:
            input.organizationId,

          whatsAppNumberId:
            input.whatsAppNumberId,

          status:
            'OPEN',

          type:
            'META_QUALITY',
        },

        data: {
          status:
            'RESOLVED',

          resolvedAt:
            input.observedAt,

          resolvedReason:
            'Meta quality returned to confirmed GREEN.',
        },
      });
    }
  }

  private async releaseReservedCapacity(
    transaction:
      TransactionClient,

    organizationId:
      string,

    whatsAppNumberId:
      string,

    healthStatus:
      WhatsAppNumberHealthStatus,

    now:
      Date,
  ): Promise<void> {
    const microbatches =
      await transaction.adsMicrobatch.findMany({
        where: {
          organizationId,

          whatsAppNumberId,

          status: {
            in: [
              'PLANNED',
              'DELIVERING',
            ],
          },

          adsRequest: {
            status: {
              in: [
                'PROCESSING',
                'PARTIALLY_FULFILLED',
              ],
            },
          },
        },

        include: {
          adsRequest:
            true,
        },

        orderBy: [
          {
            plannedAt:
              'asc',
          },

          {
            sequence:
              'asc',
          },

          {
            id:
              'asc',
          },
        ],
      });

    let totalReleased =
      0;

    for (
      const microbatch of
        microbatches
    ) {
      const outstanding =
        Math.max(
          0,
          microbatch.reservedLeadCount -
            microbatch.deliveredLeadCount,
        );

      if (
        outstanding <=
        0
      ) {
        continue;
      }

      await transaction.adsMicrobatch.update({
        where: {
          id:
            microbatch.id,
        },

        data: {
          status:
            'CANCELLED',

          cancelledAt:
            now,

          failureReason:
            `WHATSAPP_NUMBER_${healthStatus}`,
        },
      });

      await transaction.adsRequest.update({
        where: {
          id:
            microbatch.adsRequestId,
        },

        data: {
          scheduledLeadCount: {
            decrement:
              outstanding,
          },

          status:
            microbatch.adsRequest.fulfilledLeadCount >
            0
              ? 'PARTIALLY_FULFILLED'
              : 'PROCESSING',

          completedAt:
            null,
        },
      });

      await transaction.adsQueueItem.updateMany({
        where: {
          organizationId,

          adsRequestId:
            microbatch.adsRequestId,

          status: {
            in: [
              'WAITING',
              'CLAIMED',
              'COMPLETED',
            ],
          },
        },

        data: {
          status:
            'WAITING',

          availableAt:
            now,

          completedAt:
            null,

          claimedAt:
            null,

          claimedByWorkerId:
            null,

          leaseExpiresAt:
            null,
        },
      });

      await transaction.auditLog.create({
        data: {
          organizationId,

          actorType:
            'SYSTEM',

          action:
            'ads_microbatch.contingency_released',

          resourceType:
            'ads_microbatch',

          resourceId:
            microbatch.id,

          outcome:
            'SUCCESS',

          metadata: {
            adsRequestId:
              microbatch.adsRequestId,

            whatsAppNumberId,

            healthStatus,

            reservedLeadCount:
              microbatch.reservedLeadCount,

            deliveredLeadCount:
              microbatch.deliveredLeadCount,

            releasedLeadCount:
              outstanding,
          },
        },
      });

      totalReleased +=
        outstanding;
    }

    if (
      totalReleased >
      0
    ) {
      await transaction.auditLog.create({
        data: {
          organizationId,

          actorType:
            'SYSTEM',

          action:
            'whatsapp_number.contingency_activated',

          resourceType:
            'whatsapp_number',

          resourceId:
            whatsAppNumberId,

          outcome:
            'SUCCESS',

          metadata: {
            healthStatus,

            releasedLeadCount:
              totalReleased,

            microbatchesReleased:
              microbatches.length,
          },
        },
      });
    }
  }
}
'@

Write-Text `
    -Path ".\apps\worker\src\whatsapp-number-health.service.ts" `
    -Content $HealthDomain

# ============================================================
# WORKER HEALTH SYNC
# ============================================================

$HealthSync = @'
import type {
  CrmDatabaseClient,
} from '@crm/database';

import {
  getMetaPhoneNumberProfile,
} from '@crm/meta-cloud-api';

import type {
  MetaCloudApiClient,
} from '@crm/meta-cloud-api';

import type {
  WhatsAppNumberHealthConfig,
} from './whatsapp-number-health.config.js';

import {
  WhatsAppNumberHealthDomainService,
} from './whatsapp-number-health.service.js';

type ClaimedHealthState =
  Readonly<{
    id: string;
    organizationId: string;
    whatsAppNumberId: string;
    metaPhoneNumberId: string;
  }>;

export type WhatsAppNumberHealthTickSummary =
  Readonly<{
    claimed: number;
    synced: number;
    failed: number;
  }>;

function addMilliseconds(
  date:
    Date,

  milliseconds:
    number,
): Date {
  return new Date(
    date.getTime() +
      milliseconds,
  );
}

function getErrorMessage(
  error:
    unknown,
): string {
  return (
    error instanceof Error
      ? error.message
      : String(
          error,
        )
  ).slice(
    0,
    500,
  );
}

export class WhatsAppNumberHealthSyncService {
  private readonly domain:
    WhatsAppNumberHealthDomainService;

  constructor(
    private readonly database:
      CrmDatabaseClient,

    private readonly workerId:
      string,

    private readonly config:
      WhatsAppNumberHealthConfig,

    private readonly metaClient:
      MetaCloudApiClient | null,
  ) {
    this.domain =
      new WhatsAppNumberHealthDomainService(
        config.recoveryHealthyChecks,
      );
  }

  async runTick():
  Promise<
    WhatsAppNumberHealthTickSummary
  > {
    if (
      !this.metaClient
    ) {
      return {
        claimed:
          0,

        synced:
          0,

        failed:
          0,
      };
    }

    await this.ensureMissingStates();

    let claimed =
      0;

    let synced =
      0;

    let failed =
      0;

    for (
      let index =
        0;
      index <
      this.config.maxClaimsPerTick;
      index +=
        1
    ) {
      const item =
        await this.claimNext();

      if (
        !item
      ) {
        break;
      }

      claimed +=
        1;

      try {
        const profile =
          await getMetaPhoneNumberProfile(
            this.metaClient,
            item.metaPhoneNumberId,
          );

        const observedAt =
          new Date();

        await this.database.$transaction(
          async (
            transaction,
          ) => {
            await this.domain.applyMetaApi(
              transaction,
              {
                organizationId:
                  item.organizationId,

                whatsAppNumberId:
                  item.whatsAppNumberId,

                qualityRating:
                  profile.qualityRating,

                observedAt,
              },
            );

            await transaction.whatsAppNumberHealthState.updateMany({
              where: {
                id:
                  item.id,

                claimedByWorkerId:
                  this.workerId,
              },

              data: {
                nextCheckAt:
                  addMilliseconds(
                    observedAt,
                    this.config.pollIntervalMs,
                  ),

                claimedAt:
                  null,

                claimedByWorkerId:
                  null,

                leaseExpiresAt:
                  null,
              },
            });
          },
        );

        synced +=
          1;
      }
      catch (
        error
      ) {
        failed +=
          1;

        const now =
          new Date();

        const current =
          await this.database.whatsAppNumberHealthState.findUnique({
            where: {
              id:
                item.id,
            },
          });

        if (
          current
        ) {
          await this.database.$transaction(
            async (
              transaction,
            ) => {
              await transaction.whatsAppNumberHealthState.updateMany({
                where: {
                  id:
                    item.id,

                  claimedByWorkerId:
                    this.workerId,
                },

                data: {
                  consecutiveSyncFailures: {
                    increment:
                      1,
                  },

                  lastReasonCode:
                    'META_HEALTH_SYNC_FAILED',

                  lastReasonMessage:
                    getErrorMessage(
                      error,
                    ),

                  nextCheckAt:
                    addMilliseconds(
                      now,
                      this.config.failureRetryMs,
                    ),

                  claimedAt:
                    null,

                  claimedByWorkerId:
                    null,

                  leaseExpiresAt:
                    null,
                },
              });

              await transaction.whatsAppNumberHealthEvent.create({
                data: {
                  organizationId:
                    item.organizationId,

                  whatsAppNumberId:
                    item.whatsAppNumberId,

                  source:
                    'META_API',

                  previousStatus:
                    current.status,

                  currentStatus:
                    current.status,

                  metaQualityRating:
                    current.metaQualityRating,

                  metaQualityEvent:
                    current.metaQualityEvent,

                  messagingLimitTier:
                    current.messagingLimitTier,

                  schedulerEligible:
                    current.schedulerEligible,

                  reasonCode:
                    'META_HEALTH_SYNC_FAILED',

                  reasonMessage:
                    getErrorMessage(
                      error,
                    ),

                  occurredAt:
                    now,
                },
              });
            },
          );
        }
      }
    }

    return {
      claimed,
      synced,
      failed,
    };
  }

  private async ensureMissingStates():
  Promise<void> {
    const numbers =
      await this.database.whatsAppNumber.findMany({
        where: {
          deletedAt:
            null,

          status:
            'ACTIVE',

          metaPhoneNumberId: {
            not:
              null,
          },

          healthState: {
            is:
              null,
          },
        },

        select: {
          id:
            true,

          organizationId:
            true,
        },

        take:
          100,
      });

    if (
      numbers.length ===
      0
    ) {
      return;
    }

    await this.database.whatsAppNumberHealthState.createMany({
      data:
        numbers.map(
          (
            number,
          ) => ({
            organizationId:
              number.organizationId,

            whatsAppNumberId:
              number.id,
          }),
        ),

      skipDuplicates:
        true,
    });
  }

  private async claimNext():
  Promise<
    ClaimedHealthState | null
  > {
    const rows =
      await this.database.$queryRawUnsafe<
        ClaimedHealthState[]
      >(
        `
        WITH candidate AS (
          SELECT
            state."id"
          FROM
            "whatsapp_number_health_states" AS state
          INNER JOIN
            "whatsapp_numbers" AS number
            ON number."organizationId" =
               state."organizationId"
            AND number."id" =
                state."whatsAppNumberId"
          WHERE
            number."deletedAt" IS NULL
            AND number."status" = 'ACTIVE'
            AND number."metaPhoneNumberId" IS NOT NULL
            AND (
              (
                state."nextCheckAt" <= NOW()
                AND state."claimedByWorkerId" IS NULL
              )
              OR
              (
                state."leaseExpiresAt" IS NOT NULL
                AND state."leaseExpiresAt" <= NOW()
              )
            )
          ORDER BY
            state."nextCheckAt" ASC,
            state."id" ASC
          FOR UPDATE OF state SKIP LOCKED
          LIMIT 1
        )
        UPDATE
          "whatsapp_number_health_states" AS state
        SET
          "claimedAt" = NOW(),
          "claimedByWorkerId" = $1,
          "leaseExpiresAt" =
            NOW() + ($2::int * INTERVAL '1 millisecond'),
          "updatedAt" = NOW()
        FROM
          candidate,
          "whatsapp_numbers" AS number
        WHERE
          state."id" = candidate."id"
          AND number."organizationId" =
              state."organizationId"
          AND number."id" =
              state."whatsAppNumberId"
        RETURNING
          state."id",
          state."organizationId",
          state."whatsAppNumberId",
          number."metaPhoneNumberId"
        `,
        this.workerId,
        this.config.leaseMs,
      );

    return (
      rows.at(
        0,
      ) ??
      null
    );
  }
}
'@

Write-Text `
    -Path ".\apps\worker\src\whatsapp-number-health-sync.service.ts" `
    -Content $HealthSync

Write-Host "[OK] Meta quality polling worker criado." -ForegroundColor Green

# ============================================================
# INBOX PROCESSOR - QUALITY WEBHOOK
# ============================================================

$InboxPath =
    ".\apps\worker\src\whatsapp-inbox-processor.service.ts"

$Inbox =
    Read-Text -Path $InboxPath

if (
    -not $Inbox.Contains(
        "parseMetaPhoneNumberQualityUpdates"
    )
) {
    $Anchor =
        "import { parseWhatsAppWebhookEvents } from '@crm/meta-cloud-api';"

    if (
        -not $Inbox.Contains(
            $Anchor
        )
    ) {
        throw "Inbox Meta parser import anchor nao encontrado."
    }

    $Inbox =
        $Inbox.Replace(
            $Anchor,
            "import {`r`n" +
            "  parseMetaPhoneNumberQualityUpdates,`r`n" +
            "  parseWhatsAppWebhookEvents,`r`n" +
            "} from '@crm/meta-cloud-api';"
        )
}

if (
    -not $Inbox.Contains(
        "WhatsAppNumberHealthDomainService"
    )
) {
    $Anchor =
        "import type { WhatsAppRuntimeConfig } from './whatsapp-runtime.config.js';"

    if (
        -not $Inbox.Contains(
            $Anchor
        )
    ) {
        throw "Inbox runtime config import anchor nao encontrado."
    }

    $Inbox =
        $Inbox.Replace(
            $Anchor,
            "import { WhatsAppNumberHealthDomainService } from './whatsapp-number-health.service.js';`r`n`r`n" +
            $Anchor
        )
}

if (
    -not $Inbox.Contains(
        "numberHealthService"
    )
) {
    $Anchor =
        "export class WhatsAppInboxProcessorService {"

    if (
        -not $Inbox.Contains(
            $Anchor
        )
    ) {
        throw "Inbox class anchor nao encontrado."
    }

    $Inbox =
        $Inbox.Replace(
            $Anchor,
            $Anchor +
            "`r`n" +
            "  private readonly numberHealthService = new WhatsAppNumberHealthDomainService();"
        )
}

if (
    -not $Inbox.Contains(
        "qualityUpdates = parseMetaPhoneNumberQualityUpdates"
    )
) {
    $Anchor =
        "    const events = parseWhatsAppWebhookEvents(envelope.payload);"

    if (
        -not $Inbox.Contains(
            $Anchor
        )
    ) {
        throw "Inbox events parser anchor nao encontrado."
    }

    $Replacement = @'
    const qualityUpdates = parseMetaPhoneNumberQualityUpdates(envelope.payload);

    for (const update of qualityUpdates) {
      await this.database.$transaction(async (transaction) => {
        await this.numberHealthService.applyMetaWebhook(transaction, {
          organizationId: envelope.organizationId!,
          whatsAppNumberId: envelope.whatsAppNumberId!,
          sourceEnvelopeId: envelope.id,
          update,
          observedAt: envelope.receivedAt,
        });
      });
    }

    const events = parseWhatsAppWebhookEvents(envelope.payload);
'@

    $Inbox =
        $Inbox.Replace(
            $Anchor,
            $Replacement.Trim()
        )
}

Write-Text `
    -Path $InboxPath `
    -Content $Inbox

Write-Host "[OK] Quality webhook ligado ao health domain." -ForegroundColor Green

# ============================================================
# SCHEDULER - HEALTH FILTER + RACE LOCK
# ============================================================

$SchedulerPath =
    ".\apps\worker\src\ads-scheduler.service.ts"

$Scheduler =
    Read-Text -Path $SchedulerPath

if (
    -not $Scheduler.Contains(
        "healthState:"
    )
) {
    $Anchor =
        "            assignedEmployeeId: queueItem.employeeId,"

    if (
        -not $Scheduler.Contains(
            $Anchor
        )
    ) {
        throw "Scheduler WhatsApp eligibility anchor nao encontrado."
    }

    $Scheduler =
        $Scheduler.Replace(
            $Anchor,
            $Anchor +
            "`r`n" +
            "`r`n" +
            "            OR: [`r`n" +
            "              {`r`n" +
            "                healthState: {`r`n" +
            "                  is: null,`r`n" +
            "                },`r`n" +
            "              },`r`n" +
            "`r`n" +
            "              {`r`n" +
            "                healthState: {`r`n" +
            "                  is: {`r`n" +
            "                    schedulerEligible: true,`r`n" +
            "                  },`r`n" +
            "                },`r`n" +
            "              },`r`n" +
            "            ],"
        )
}

if (
    -not $Scheduler.Contains(
        "whatsapp-number-health:"
    )
) {
    $Anchor =
        "      const maxSequence = await transaction.adsMicrobatch.aggregate({"

    if (
        -not $Scheduler.Contains(
            $Anchor
        )
    ) {
        throw "Scheduler sequence anchor nao encontrado."
    }

    $HealthGuard = @'
      await transaction.$queryRawUnsafe(
        'WITH lock_guard AS MATERIALIZED (SELECT pg_advisory_xact_lock(hashtextextended($1, 0))) SELECT TRUE AS locked FROM lock_guard',
        `whatsapp-number-health:${queueItem.organizationId}:${selection.member.whatsAppNumberId}`,
      );

      const selectedNumberHealth = await transaction.whatsAppNumberHealthState.findUnique({
        where: {
          organizationId_whatsAppNumberId: {
            organizationId: queueItem.organizationId,
            whatsAppNumberId: selection.member.whatsAppNumberId,
          },
        },

        select: {
          schedulerEligible: true,
        },
      });

      if (selectedNumberHealth && !selectedNumberHealth.schedulerEligible) {
        await this.deferClaimedQueueItem(
          transaction,
          queueItem.id,
          queueItem.organizationId,
          request.id,
          now,
          this.config.backpressureDelayMs,
          'ads_queue.number_health_unavailable',
        );

        return 'DEFERRED';
      }

'@

    $Scheduler =
        $Scheduler.Replace(
            $Anchor,
            $HealthGuard +
            $Anchor
        )
}

Write-Text `
    -Path $SchedulerPath `
    -Content $Scheduler

Write-Host "[OK] Scheduler agora respeita health + contingency lock." -ForegroundColor Green

# ============================================================
# API HEALTH SERVICE
# ============================================================

$ApiHealthService = @'
import {
  ForbiddenException,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';

import type {
  AuthenticatedPrincipal,
} from '@crm/auth';

import type {
  WhatsAppNumberHealthEventResponse,
  WhatsAppNumberHealthResponse,
  WhatsAppNumberIncidentResponse,
} from '@crm/contracts';

import {
  DatabaseService,
} from '../database/database.service.js';

@Injectable()
export class WhatsAppHealthService {
  constructor(
    @Inject(
      DatabaseService,
    )
    private readonly database:
      DatabaseService,
  ) {}

  async getHealth(
    principal:
      AuthenticatedPrincipal,

    whatsAppNumberId:
      string,
  ): Promise<
    WhatsAppNumberHealthResponse
  > {
    const number =
      await this.getAccessibleNumber(
        principal,
        whatsAppNumberId,
      );

    const state =
      await this.database.client.whatsAppNumberHealthState.upsert({
        where: {
          organizationId_whatsAppNumberId: {
            organizationId:
              principal.organizationId,

            whatsAppNumberId:
              number.id,
          },
        },

        create: {
          organizationId:
            principal.organizationId,

          whatsAppNumberId:
            number.id,
        },

        update:
          {},
      });

    return this.mapHealth(
      state,
    );
  }

  async listEvents(
    principal:
      AuthenticatedPrincipal,

    whatsAppNumberId:
      string,

    limit:
      number,
  ): Promise<
    readonly WhatsAppNumberHealthEventResponse[]
  > {
    await this.getAccessibleNumber(
      principal,
      whatsAppNumberId,
    );

    const events =
      await this.database.client.whatsAppNumberHealthEvent.findMany({
        where: {
          organizationId:
            principal.organizationId,

          whatsAppNumberId,
        },

        orderBy: [
          {
            occurredAt:
              'desc',
          },

          {
            id:
              'desc',
          },
        ],

        take:
          limit,
      });

    return events.map(
      (
        event,
      ) => ({
        id:
          event.id,

        source:
          event.source,

        previousStatus:
          event.previousStatus,

        currentStatus:
          event.currentStatus,

        metaQualityRating:
          event.metaQualityRating,

        metaQualityEvent:
          event.metaQualityEvent,

        messagingLimitTier:
          event.messagingLimitTier,

        schedulerEligible:
          event.schedulerEligible,

        reasonCode:
          event.reasonCode,

        reasonMessage:
          event.reasonMessage,

        occurredAt:
          event.occurredAt.toISOString(),
      }),
    );
  }

  async listIncidents(
    principal:
      AuthenticatedPrincipal,

    whatsAppNumberId:
      string,

    limit:
      number,
  ): Promise<
    readonly WhatsAppNumberIncidentResponse[]
  > {
    await this.getAccessibleNumber(
      principal,
      whatsAppNumberId,
    );

    const incidents =
      await this.database.client.whatsAppNumberIncident.findMany({
        where: {
          organizationId:
            principal.organizationId,

          whatsAppNumberId,
        },

        orderBy: [
          {
            openedAt:
              'desc',
          },

          {
            id:
              'desc',
          },
        ],

        take:
          limit,
      });

    return incidents.map(
      (
        incident,
      ) => ({
        id:
          incident.id,

        status:
          incident.status,

        type:
          incident.type,

        severity:
          incident.severity,

        openedReasonCode:
          incident.openedReasonCode,

        openedReason:
          incident.openedReason,

        openedAt:
          incident.openedAt.toISOString(),

        resolvedReason:
          incident.resolvedReason,

        resolvedAt:
          incident.resolvedAt?.toISOString() ??
          null,
      }),
    );
  }

  async pause(
    principal:
      AuthenticatedPrincipal,

    whatsAppNumberId:
      string,
  ): Promise<
    WhatsAppNumberHealthResponse
  > {
    this.assertAdmin(
      principal,
    );

    const number =
      await this.getAccessibleNumber(
        principal,
        whatsAppNumberId,
      );

    const now =
      new Date();

    const state =
      await this.database.client.$transaction(
        async (
          transaction,
        ) => {
          await transaction.$queryRawUnsafe(
            'WITH lock_guard AS MATERIALIZED (SELECT pg_advisory_xact_lock(hashtextextended($1, 0))) SELECT TRUE AS locked FROM lock_guard',
            `whatsapp-number-health:${principal.organizationId}:${number.id}`,
          );

          const current =
            await transaction.whatsAppNumberHealthState.upsert({
              where: {
                organizationId_whatsAppNumberId: {
                  organizationId:
                    principal.organizationId,

                  whatsAppNumberId:
                    number.id,
                },
              },

              create: {
                organizationId:
                  principal.organizationId,

                whatsAppNumberId:
                  number.id,
              },

              update:
                {},
            });

          if (
            !current.manualPaused
          ) {
            await this.releaseReservedCapacity(
              transaction,
              principal.organizationId,
              number.id,
              now,
            );

            await transaction.whatsAppNumberHealthEvent.create({
              data: {
                organizationId:
                  principal.organizationId,

                whatsAppNumberId:
                  number.id,

                source:
                  'MANUAL',

                previousStatus:
                  current.status,

                currentStatus:
                  'DISABLED',

                metaQualityRating:
                  current.metaQualityRating,

                metaQualityEvent:
                  current.metaQualityEvent,

                messagingLimitTier:
                  current.messagingLimitTier,

                schedulerEligible:
                  false,

                reasonCode:
                  'MANUAL_PAUSE',

                reasonMessage:
                  'Number manually paused by administrator.',

                occurredAt:
                  now,
              },
            });

            const incident =
              await transaction.whatsAppNumberIncident.findFirst({
                where: {
                  organizationId:
                    principal.organizationId,

                  whatsAppNumberId:
                    number.id,

                  status:
                    'OPEN',

                  type:
                    'MANUAL_PAUSE',
                },
              });

            if (
              !incident
            ) {
              await transaction.whatsAppNumberIncident.create({
                data: {
                  organizationId:
                    principal.organizationId,

                  whatsAppNumberId:
                    number.id,

                  type:
                    'MANUAL_PAUSE',

                  severity:
                    'DISABLED',

                  openedReasonCode:
                    'MANUAL_PAUSE',

                  openedReason:
                    'Number manually paused by administrator.',

                  openedAt:
                    now,
                },
              });
            }
          }

          const updated =
            await transaction.whatsAppNumberHealthState.update({
              where: {
                id:
                  current.id,
              },

              data: {
                manualPaused:
                  true,

                status:
                  'DISABLED',

                schedulerEligible:
                  false,

                consecutiveHealthyChecks:
                  0,

                lastReasonCode:
                  'MANUAL_PAUSE',

                lastReasonMessage:
                  'Number manually paused by administrator.',
              },
            });

          await transaction.auditLog.create({
            data: {
              organizationId:
                principal.organizationId,

              actorType:
                'USER',

              actorUserId:
                principal.userId,

              action:
                'whatsapp_number.health_paused',

              resourceType:
                'whatsapp_number',

              resourceId:
                number.id,

              outcome:
                'SUCCESS',
            },
          });

          return updated;
        },
      );

    return this.mapHealth(
      state,
    );
  }

  async resume(
    principal:
      AuthenticatedPrincipal,

    whatsAppNumberId:
      string,
  ): Promise<
    WhatsAppNumberHealthResponse
  > {
    this.assertAdmin(
      principal,
    );

    const number =
      await this.getAccessibleNumber(
        principal,
        whatsAppNumberId,
      );

    const now =
      new Date();

    const state =
      await this.database.client.$transaction(
        async (
          transaction,
        ) => {
          await transaction.$queryRawUnsafe(
            'WITH lock_guard AS MATERIALIZED (SELECT pg_advisory_xact_lock(hashtextextended($1, 0))) SELECT TRUE AS locked FROM lock_guard',
            `whatsapp-number-health:${principal.organizationId}:${number.id}`,
          );

          const current =
            await transaction.whatsAppNumberHealthState.upsert({
              where: {
                organizationId_whatsAppNumberId: {
                  organizationId:
                    principal.organizationId,

                  whatsAppNumberId:
                    number.id,
                },
              },

              create: {
                organizationId:
                  principal.organizationId,

                whatsAppNumberId:
                  number.id,
              },

              update:
                {},
            });

          const metaConnected =
            Boolean(
              number.metaPhoneNumberId,
            );

          const nextStatus =
            metaConnected
              ? 'RECOVERING'
              : 'UNKNOWN';

          const nextEligible =
            !metaConnected;

          const updated =
            await transaction.whatsAppNumberHealthState.update({
              where: {
                id:
                  current.id,
              },

              data: {
                manualPaused:
                  false,

                status:
                  nextStatus,

                schedulerEligible:
                  nextEligible,

                consecutiveHealthyChecks:
                  0,

                recoveringSinceAt:
                  metaConnected
                    ? now
                    : null,

                nextCheckAt:
                  now,

                lastReasonCode:
                  metaConnected
                    ? 'MANUAL_RESUME_AWAITING_META_CONFIRMATION'
                    : 'MANUAL_RESUME_NO_META_PROFILE',

                lastReasonMessage:
                  metaConnected
                    ? 'Manual pause removed; Meta green confirmation is required before scheduling resumes.'
                    : 'Manual pause removed; no Meta phone profile is connected.',
              },
            });

          await transaction.whatsAppNumberHealthEvent.create({
            data: {
              organizationId:
                principal.organizationId,

              whatsAppNumberId:
                number.id,

              source:
                'MANUAL',

              previousStatus:
                current.status,

              currentStatus:
                nextStatus,

              metaQualityRating:
                current.metaQualityRating,

              metaQualityEvent:
                current.metaQualityEvent,

              messagingLimitTier:
                current.messagingLimitTier,

              schedulerEligible:
                nextEligible,

              reasonCode:
                'MANUAL_RESUME',

              reasonMessage:
                'Manual pause removed.',

              occurredAt:
                now,
            },
          });

          await transaction.whatsAppNumberIncident.updateMany({
            where: {
              organizationId:
                principal.organizationId,

              whatsAppNumberId:
                number.id,

              status:
                'OPEN',

              type:
                'MANUAL_PAUSE',
            },

            data: {
              status:
                'RESOLVED',

              resolvedAt:
                now,

              resolvedReason:
                'Manual pause removed by administrator.',
            },
          });

          await transaction.auditLog.create({
            data: {
              organizationId:
                principal.organizationId,

              actorType:
                'USER',

              actorUserId:
                principal.userId,

              action:
                'whatsapp_number.health_resumed',

              resourceType:
                'whatsapp_number',

              resourceId:
                number.id,

              outcome:
                'SUCCESS',

              metadata: {
                metaConnected,
                nextStatus,
                schedulerEligible:
                  nextEligible,
              },
            },
          });

          return updated;
        },
      );

    return this.mapHealth(
      state,
    );
  }

  async requestSync(
    principal:
      AuthenticatedPrincipal,

    whatsAppNumberId:
      string,
  ): Promise<
    WhatsAppNumberHealthResponse
  > {
    this.assertAdmin(
      principal,
    );

    const number =
      await this.getAccessibleNumber(
        principal,
        whatsAppNumberId,
      );

    const state =
      await this.database.client.whatsAppNumberHealthState.upsert({
        where: {
          organizationId_whatsAppNumberId: {
            organizationId:
              principal.organizationId,

            whatsAppNumberId:
              number.id,
          },
        },

        create: {
          organizationId:
            principal.organizationId,

          whatsAppNumberId:
            number.id,

          nextCheckAt:
            new Date(),
        },

        update: {
          nextCheckAt:
            new Date(),
        },
      });

    await this.database.client.auditLog.create({
      data: {
        organizationId:
          principal.organizationId,

        actorType:
          'USER',

        actorUserId:
          principal.userId,

        action:
          'whatsapp_number.health_sync_requested',

        resourceType:
          'whatsapp_number',

        resourceId:
          number.id,

        outcome:
          'SUCCESS',
      },
    });

    return this.mapHealth(
      state,
    );
  }

  private async getAccessibleNumber(
    principal:
      AuthenticatedPrincipal,

    whatsAppNumberId:
      string,
  ) {
    const employeeId =
      this.isAdmin(
        principal,
      )
        ? null
        : await this.getCurrentEmployeeId(
            principal,
          );

    const number =
      await this.database.client.whatsAppNumber.findFirst({
        where: {
          id:
            whatsAppNumberId,

          organizationId:
            principal.organizationId,

          deletedAt:
            null,

          ...(employeeId
            ? {
                assignedEmployeeId:
                  employeeId,
              }
            : {}),
        },

        select: {
          id:
            true,

          metaPhoneNumberId:
            true,
        },
      });

    if (
      !number
    ) {
      throw new NotFoundException({
        code:
          'WHATSAPP_NUMBER_NOT_FOUND',

        message:
          'WhatsApp number not found.',
      });
    }

    return number;
  }

  private async getCurrentEmployeeId(
    principal:
      AuthenticatedPrincipal,
  ): Promise<
    string
  > {
    const employee =
      await this.database.client.employee.findFirst({
        where: {
          organizationId:
            principal.organizationId,

          userId:
            principal.userId,

          status:
            'ACTIVE',

          deletedAt:
            null,
        },

        select: {
          id:
            true,
        },
      });

    if (
      !employee
    ) {
      throw new ForbiddenException({
        code:
          'EMPLOYEE_PROFILE_REQUIRED',

        message:
          'An active employee profile is required.',
      });
    }

    return employee.id;
  }

  private isAdmin(
    principal:
      AuthenticatedPrincipal,
  ): boolean {
    return principal.roles.includes(
      'ADMIN',
    );
  }

  private assertAdmin(
    principal:
      AuthenticatedPrincipal,
  ): void {
    if (
      !this.isAdmin(
        principal,
      )
    ) {
      throw new ForbiddenException({
        code:
          'WHATSAPP_HEALTH_ADMIN_REQUIRED',

        message:
          'Only administrators can change WhatsApp number health controls.',
      });
    }
  }

  private async releaseReservedCapacity(
    transaction:
      Parameters<
        Parameters<
          typeof this.database.client.$transaction
        >[0]
      >[0],

    organizationId:
      string,

    whatsAppNumberId:
      string,

    now:
      Date,
  ): Promise<void> {
    const batches =
      await transaction.adsMicrobatch.findMany({
        where: {
          organizationId,

          whatsAppNumberId,

          status: {
            in: [
              'PLANNED',
              'DELIVERING',
            ],
          },

          adsRequest: {
            status: {
              in: [
                'PROCESSING',
                'PARTIALLY_FULFILLED',
              ],
            },
          },
        },

        include: {
          adsRequest:
            true,
        },
      });

    for (
      const batch of
        batches
    ) {
      const outstanding =
        Math.max(
          0,
          batch.reservedLeadCount -
            batch.deliveredLeadCount,
        );

      if (
        outstanding <=
        0
      ) {
        continue;
      }

      await transaction.adsMicrobatch.update({
        where: {
          id:
            batch.id,
        },

        data: {
          status:
            'CANCELLED',

          cancelledAt:
            now,

          failureReason:
            'WHATSAPP_NUMBER_MANUAL_PAUSE',
        },
      });

      await transaction.adsRequest.update({
        where: {
          id:
            batch.adsRequestId,
        },

        data: {
          scheduledLeadCount: {
            decrement:
              outstanding,
          },

          status:
            batch.adsRequest.fulfilledLeadCount >
            0
              ? 'PARTIALLY_FULFILLED'
              : 'PROCESSING',

          completedAt:
            null,
        },
      });

      await transaction.adsQueueItem.updateMany({
        where: {
          organizationId,

          adsRequestId:
            batch.adsRequestId,

          status: {
            in: [
              'WAITING',
              'CLAIMED',
              'COMPLETED',
            ],
          },
        },

        data: {
          status:
            'WAITING',

          availableAt:
            now,

          completedAt:
            null,

          claimedAt:
            null,

          claimedByWorkerId:
            null,

          leaseExpiresAt:
            null,
        },
      });
    }
  }

  private mapHealth(
    state:
      Readonly<{
        whatsAppNumberId:
          string;

        status:
          'UNKNOWN' |
          'HEALTHY' |
          'DEGRADED' |
          'CRITICAL' |
          'RECOVERING' |
          'DISABLED';

        schedulerEligible:
          boolean;

        manualPaused:
          boolean;

        metaQualityRating:
          'UNKNOWN' |
          'GREEN' |
          'YELLOW' |
          'RED' |
          'NA';

        metaQualityEvent:
          string | null;

        messagingLimitTier:
          string | null;

        lastReasonCode:
          string | null;

        lastReasonMessage:
          string | null;

        lastMetaSyncAt:
          Date | null;

        lastMetaWebhookAt:
          Date | null;

        lastHealthyAt:
          Date | null;

        degradedSinceAt:
          Date | null;

        criticalSinceAt:
          Date | null;

        recoveringSinceAt:
          Date | null;

        consecutiveHealthyChecks:
          number;

        consecutiveSyncFailures:
          number;

        nextCheckAt:
          Date;

        updatedAt:
          Date;
      }>,
  ): WhatsAppNumberHealthResponse {
    return {
      whatsAppNumberId:
        state.whatsAppNumberId,

      status:
        state.status,

      schedulerEligible:
        state.schedulerEligible,

      manualPaused:
        state.manualPaused,

      metaQualityRating:
        state.metaQualityRating,

      metaQualityEvent:
        state.metaQualityEvent,

      messagingLimitTier:
        state.messagingLimitTier,

      lastReasonCode:
        state.lastReasonCode,

      lastReasonMessage:
        state.lastReasonMessage,

      lastMetaSyncAt:
        state.lastMetaSyncAt?.toISOString() ??
        null,

      lastMetaWebhookAt:
        state.lastMetaWebhookAt?.toISOString() ??
        null,

      lastHealthyAt:
        state.lastHealthyAt?.toISOString() ??
        null,

      degradedSinceAt:
        state.degradedSinceAt?.toISOString() ??
        null,

      criticalSinceAt:
        state.criticalSinceAt?.toISOString() ??
        null,

      recoveringSinceAt:
        state.recoveringSinceAt?.toISOString() ??
        null,

      consecutiveHealthyChecks:
        state.consecutiveHealthyChecks,

      consecutiveSyncFailures:
        state.consecutiveSyncFailures,

      nextCheckAt:
        state.nextCheckAt.toISOString(),

      updatedAt:
        state.updatedAt.toISOString(),
    };
  }
}
'@

New-Item `
    -ItemType Directory `
    -Path ".\apps\api\src\whatsapp-health" `
    -Force |
    Out-Null

Write-Text `
    -Path ".\apps\api\src\whatsapp-health\whatsapp-health.service.ts" `
    -Content $ApiHealthService

# ============================================================
# API CONTROLLER
# ============================================================

$HealthController = @'
import {
  BadRequestException,
  Controller,
  Get,
  Inject,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';

import type {
  AuthenticatedPrincipal,
} from '@crm/auth';

import type {
  WhatsAppNumberHealthEventResponse,
  WhatsAppNumberHealthResponse,
  WhatsAppNumberIncidentResponse,
} from '@crm/contracts';

import {
  whatsAppHealthHistoryQuerySchema,
} from '@crm/validation';

import {
  AccessTokenGuard,
} from '../authorization/access-token.guard.js';

import {
  AuthorizationGuard,
} from '../authorization/authorization.guard.js';

import {
  CurrentPrincipal,
} from '../authorization/current-principal.decorator.js';

import {
  RequirePermissions,
} from '../authorization/require-permissions.decorator.js';

import {
  WhatsAppHealthService,
} from './whatsapp-health.service.js';

@Controller(
  'whatsapp-numbers/:whatsAppNumberId/health',
)
@UseGuards(
  AccessTokenGuard,
  AuthorizationGuard,
)
export class WhatsAppHealthController {
  constructor(
    @Inject(
      WhatsAppHealthService,
    )
    private readonly healthService:
      WhatsAppHealthService,
  ) {}

  @Get()
  @RequirePermissions(
    'whatsapp_health.read',
  )
  getHealth(
    @CurrentPrincipal()
    principal:
      AuthenticatedPrincipal,

    @Param(
      'whatsAppNumberId',
      new ParseUUIDPipe(),
    )
    whatsAppNumberId:
      string,
  ): Promise<
    WhatsAppNumberHealthResponse
  > {
    return this.healthService.getHealth(
      principal,
      whatsAppNumberId,
    );
  }

  @Get('events')
  @RequirePermissions(
    'whatsapp_health.read',
  )
  listEvents(
    @CurrentPrincipal()
    principal:
      AuthenticatedPrincipal,

    @Param(
      'whatsAppNumberId',
      new ParseUUIDPipe(),
    )
    whatsAppNumberId:
      string,

    @Query()
    query:
      unknown,
  ): Promise<
    readonly WhatsAppNumberHealthEventResponse[]
  > {
    const parsed =
      whatsAppHealthHistoryQuerySchema.safeParse(
        query,
      );

    if (
      !parsed.success
    ) {
      throw new BadRequestException({
        code:
          'WHATSAPP_HEALTH_QUERY_VALIDATION_ERROR',

        message:
          'Invalid WhatsApp health query.',
      });
    }

    return this.healthService.listEvents(
      principal,
      whatsAppNumberId,
      parsed.data.limit,
    );
  }

  @Get('incidents')
  @RequirePermissions(
    'whatsapp_health.read',
  )
  listIncidents(
    @CurrentPrincipal()
    principal:
      AuthenticatedPrincipal,

    @Param(
      'whatsAppNumberId',
      new ParseUUIDPipe(),
    )
    whatsAppNumberId:
      string,

    @Query()
    query:
      unknown,
  ): Promise<
    readonly WhatsAppNumberIncidentResponse[]
  > {
    const parsed =
      whatsAppHealthHistoryQuerySchema.safeParse(
        query,
      );

    if (
      !parsed.success
    ) {
      throw new BadRequestException({
        code:
          'WHATSAPP_HEALTH_QUERY_VALIDATION_ERROR',

        message:
          'Invalid WhatsApp health query.',
      });
    }

    return this.healthService.listIncidents(
      principal,
      whatsAppNumberId,
      parsed.data.limit,
    );
  }

  @Post('pause')
  @RequirePermissions(
    'whatsapp_health.manage',
  )
  pause(
    @CurrentPrincipal()
    principal:
      AuthenticatedPrincipal,

    @Param(
      'whatsAppNumberId',
      new ParseUUIDPipe(),
    )
    whatsAppNumberId:
      string,
  ): Promise<
    WhatsAppNumberHealthResponse
  > {
    return this.healthService.pause(
      principal,
      whatsAppNumberId,
    );
  }

  @Post('resume')
  @RequirePermissions(
    'whatsapp_health.manage',
  )
  resume(
    @CurrentPrincipal()
    principal:
      AuthenticatedPrincipal,

    @Param(
      'whatsAppNumberId',
      new ParseUUIDPipe(),
    )
    whatsAppNumberId:
      string,
  ): Promise<
    WhatsAppNumberHealthResponse
  > {
    return this.healthService.resume(
      principal,
      whatsAppNumberId,
    );
  }

  @Post('sync')
  @RequirePermissions(
    'whatsapp_health.manage',
  )
  requestSync(
    @CurrentPrincipal()
    principal:
      AuthenticatedPrincipal,

    @Param(
      'whatsAppNumberId',
      new ParseUUIDPipe(),
    )
    whatsAppNumberId:
      string,
  ): Promise<
    WhatsAppNumberHealthResponse
  > {
    return this.healthService.requestSync(
      principal,
      whatsAppNumberId,
    );
  }
}
'@

Write-Text `
    -Path ".\apps\api\src\whatsapp-health\whatsapp-health.controller.ts" `
    -Content $HealthController

$HealthModule = @'
import {
  Module,
} from '@nestjs/common';

import {
  AuthorizationModule,
} from '../authorization/authorization.module.js';

import {
  DatabaseModule,
} from '../database/database.module.js';

import {
  WhatsAppHealthController,
} from './whatsapp-health.controller.js';

import {
  WhatsAppHealthService,
} from './whatsapp-health.service.js';

@Module({
  imports: [
    AuthorizationModule,
    DatabaseModule,
  ],

  controllers: [
    WhatsAppHealthController,
  ],

  providers: [
    WhatsAppHealthService,
  ],

  exports: [
    WhatsAppHealthService,
  ],
})
export class WhatsAppHealthModule {}
'@

Write-Text `
    -Path ".\apps\api\src\whatsapp-health\whatsapp-health.module.ts" `
    -Content $HealthModule

$AppModulePath =
    ".\apps\api\src\app.module.ts"

$AppModule =
    Read-Text -Path $AppModulePath

if (
    -not $AppModule.Contains(
        "WhatsAppHealthModule"
    )
) {
    $ImportAnchor =
        "import { LeadsModule } from './leads/leads.module.js';"

    if (
        -not $AppModule.Contains(
            $ImportAnchor
        )
    ) {
        throw "AppModule LeadsModule anchor nao encontrado."
    }

    $AppModule =
        $AppModule.Replace(
            $ImportAnchor,
            $ImportAnchor +
            "`r`n`r`n" +
            "import { WhatsAppHealthModule } from './whatsapp-health/whatsapp-health.module.js';"
        )

    $ModuleAnchor =
        "    LeadsModule,"

    if (
        -not $AppModule.Contains(
            $ModuleAnchor
        )
    ) {
        throw "AppModule LeadsModule array anchor nao encontrado."
    }

    $AppModule =
        $AppModule.Replace(
            $ModuleAnchor,
            $ModuleAnchor +
            "`r`n" +
            "    WhatsAppHealthModule,"
        )
}

Write-Text `
    -Path $AppModulePath `
    -Content $AppModule

Write-Host "[OK] WhatsApp Health API criada." -ForegroundColor Green

# ============================================================
# WORKER MAIN
# ============================================================

$MainPath =
    ".\apps\worker\src\main.ts"

$Main =
    Read-Text -Path $MainPath

if (
    -not $Main.Contains(
        "WhatsAppNumberHealthSyncService"
    )
) {
    $ImportAnchor =
        "import { parseWhatsAppRuntimeConfig } from './whatsapp-runtime.config.js';"

    if (
        -not $Main.Contains(
            $ImportAnchor
        )
    ) {
        throw "Worker main runtime import anchor nao encontrado."
    }

    $Main =
        $Main.Replace(
            $ImportAnchor,
            $ImportAnchor +
            "`r`n`r`n" +
            "import { parseWhatsAppNumberHealthConfig } from './whatsapp-number-health.config.js';`r`n`r`n" +
            "import { WhatsAppNumberHealthSyncService } from './whatsapp-number-health-sync.service.js';"
        )
}

if (
    -not $Main.Contains(
        "const numberHealthConfig"
    )
) {
    $Anchor =
        "const whatsAppConfig = parseWhatsAppRuntimeConfig();"

    $Main =
        $Main.Replace(
            $Anchor,
            $Anchor +
            "`r`n`r`n" +
            "const numberHealthConfig = parseWhatsAppNumberHealthConfig();"
        )
}

if (
    -not $Main.Contains(
        "const numberHealthSync"
    )
) {
    $Anchor = @'
const outboundDispatcher = new WhatsAppOutboundDispatcherService(
  database,
  workerId,
  whatsAppConfig,
  metaClient,
);
'@

    if (
        -not $Main.Contains(
            $Anchor.Trim()
        )
    ) {
        throw "Worker outbound dispatcher anchor nao encontrado."
    }

    $Replacement =
        $Anchor.Trim() +
        "`r`n`r`n" +
        "const numberHealthSync = new WhatsAppNumberHealthSyncService(`r`n" +
        "  database,`r`n" +
        "  workerId,`r`n" +
        "  numberHealthConfig,`r`n" +
        "  metaClient,`r`n" +
        ");"

    $Main =
        $Main.Replace(
            $Anchor.Trim(),
            $Replacement
        )
}

if (
    -not $Main.Contains(
        "let numberHealthRunning"
    )
) {
    $Anchor =
        "let outboundRunning = false;"

    $Main =
        $Main.Replace(
            $Anchor,
            $Anchor +
            "`r`n`r`n" +
            "let numberHealthRunning = false;"
        )
}

if (
    -not $Main.Contains(
        "runNumberHealthTick"
    )
) {
    $Anchor =
        "log('service.started', {"

    if (
        -not $Main.Contains(
            $Anchor
        )
    ) {
        throw "Worker service.started anchor nao encontrado."
    }

    $Function = @'
async function runNumberHealthTick(): Promise<void> {
  if (numberHealthRunning || shuttingDown) {
    return;
  }

  numberHealthRunning = true;

  try {
    const summary = await numberHealthSync.runTick();

    if (summary.claimed > 0 || summary.failed > 0) {
      log('whatsapp.number_health.tick', summary);
    }
  } catch (error) {
    log('whatsapp.number_health.error', {
      message: error instanceof Error ? error.message : String(error),
    });
  } finally {
    numberHealthRunning = false;
  }
}

'@

    $Main =
        $Main.Replace(
            $Anchor,
            $Function +
            $Anchor
        )
}

if (
    -not $Main.Contains(
        "whatsAppHealthIntervalMs:"
    )
) {
    $Anchor =
        "  whatsAppOutboundIntervalMs: whatsAppConfig.outboundIntervalMs,"

    $Main =
        $Main.Replace(
            $Anchor,
            $Anchor +
            "`r`n`r`n" +
            "  whatsAppHealthIntervalMs: numberHealthConfig.intervalMs,`r`n" +
            "`r`n" +
            "  whatsAppHealthPollIntervalMs: numberHealthConfig.pollIntervalMs,"
        )
}

$Main =
    $Main.Replace(
        "await Promise.all([runSchedulerTick(), runNotificationTick(), runInboxTick(), runOutboundTick()]);",
        "await Promise.all([`r`n" +
        "  runSchedulerTick(),`r`n" +
        "  runNotificationTick(),`r`n" +
        "  runInboxTick(),`r`n" +
        "  runOutboundTick(),`r`n" +
        "  runNumberHealthTick(),`r`n" +
        "]);"
    )

if (
    -not $Main.Contains(
        "const numberHealthTimer"
    )
) {
    $Anchor = @'
const outboundTimer = setInterval(() => {
  void runOutboundTick();
}, whatsAppConfig.outboundIntervalMs);
'@

    if (
        -not $Main.Contains(
            $Anchor.Trim()
        )
    ) {
        throw "Worker outbound timer anchor nao encontrado."
    }

    $Main =
        $Main.Replace(
            $Anchor.Trim(),
            $Anchor.Trim() +
            "`r`n`r`n" +
            "const numberHealthTimer = setInterval(() => {`r`n" +
            "  void runNumberHealthTick();`r`n" +
            "}, numberHealthConfig.intervalMs);"
        )
}

if (
    -not $Main.Contains(
        "numberHealthRunning,"
    )
) {
    $Anchor =
        "    outboundRunning,"

    $Main =
        $Main.Replace(
            $Anchor,
            $Anchor +
            "`r`n" +
            "    numberHealthRunning,"
        )
}

if (
    -not $Main.Contains(
        "clearInterval(numberHealthTimer)"
    )
) {
    $Anchor =
        "  clearInterval(outboundTimer);"

    $Main =
        $Main.Replace(
            $Anchor,
            $Anchor +
            "`r`n`r`n" +
            "  clearInterval(numberHealthTimer);"
        )
}

$Main =
    $Main.Replace(
        "  while (schedulerRunning || notificationRunning || inboxRunning || outboundRunning) {",
        "  while (`r`n" +
        "    schedulerRunning ||`r`n" +
        "    notificationRunning ||`r`n" +
        "    inboxRunning ||`r`n" +
        "    outboundRunning ||`r`n" +
        "    numberHealthRunning`r`n" +
        "  ) {"
    )

Write-Text `
    -Path $MainPath `
    -Content $Main

Write-Host "[OK] Health worker integrado ao processo principal." -ForegroundColor Green

# ============================================================
# ENV
# ============================================================

$EnvPath =
    ".\.env.example"

if (
    Test-Path $EnvPath
) {
    $Env =
        Read-Text -Path $EnvPath

    if (
        -not $Env.Contains(
            "WHATSAPP_HEALTH_INTERVAL_MS"
        )
    ) {
        $Env =
            $Env.TrimEnd() +
            "`r`n" +
            "`r`n" +
            "# WhatsApp Number Health - Etapa 11`r`n" +
            "WHATSAPP_HEALTH_INTERVAL_MS=5000`r`n" +
            "WHATSAPP_HEALTH_POLL_INTERVAL_MS=900000`r`n" +
            "WHATSAPP_HEALTH_FAILURE_RETRY_MS=60000`r`n" +
            "WHATSAPP_HEALTH_LEASE_MS=30000`r`n" +
            "WHATSAPP_HEALTH_MAX_CLAIMS_PER_TICK=10`r`n" +
            "WHATSAPP_HEALTH_RECOVERY_GREEN_CHECKS=2`r`n"
    }

    Write-Text `
        -Path $EnvPath `
        -Content $Env
}

# ============================================================
# DOC STATUS
# ============================================================

$EtapasPath =
    ".\docs\ETAPAS.md"

if (
    Test-Path $EtapasPath
) {
    $Etapas =
        Read-Text -Path $EtapasPath

    $Etapas =
        [regex]::Replace(
            $Etapas,
            "(?m)^\|\s*11\s*\|([^|]+)\|([^|]+)\|$",
            {
                param(
                    $Match
                )

                return (
                    "|    11 |" +
                    $Match.Groups[1].Value +
                    "| EM ANDAMENTO                 |"
                )
            },
            1
        )

    if (
        -not $Etapas.Contains(
            "## Etapa 11 - Saude"
        )
    ) {
        $Etapas =
            $Etapas.TrimEnd() +
            "`r`n`r`n" +
            "## Etapa 11 - Saude e contingencia dos numeros WhatsApp`r`n`r`n" +
            "Status: EM ANDAMENTO - Macrobloco 11.1 construido.`r`n"
    }

    Write-Text `
        -Path $EtapasPath `
        -Content $Etapas
}

# ============================================================
# STRUCTURAL CHECKS
# ============================================================

$SchemaCheck =
    Read-Text -Path $SchemaPath

foreach ($Marker in @(
    "enum MetaPhoneQualityRating",
    "enum WhatsAppNumberHealthStatus",
    "model WhatsAppNumberHealthState {",
    "model WhatsAppNumberHealthEvent {",
    "model WhatsAppNumberIncident {",
    "schedulerEligible",
    "metaQualityRating",
    "consecutiveHealthyChecks",
    "nextCheckAt"
)) {
    if (
        -not $SchemaCheck.Contains(
            $Marker
        )
    ) {
        throw "Stage 11 schema marker ausente: $Marker"
    }
}

$RequiredStage11Files = @(
    ".\packages\meta-cloud-api\src\phone-number-profile.ts",
    ".\packages\meta-cloud-api\src\phone-number-quality-webhook.ts",
    ".\packages\contracts\src\whatsapp-health.ts",
    ".\packages\validation\src\whatsapp-health.ts",
    ".\apps\worker\src\whatsapp-number-health.config.ts",
    ".\apps\worker\src\whatsapp-number-health.service.ts",
    ".\apps\worker\src\whatsapp-number-health-sync.service.ts",
    ".\apps\api\src\whatsapp-health\whatsapp-health.service.ts",
    ".\apps\api\src\whatsapp-health\whatsapp-health.controller.ts",
    ".\apps\api\src\whatsapp-health\whatsapp-health.module.ts"
)

foreach ($File in $RequiredStage11Files) {
    if (
        -not (
            Test-Path $File
        )
    ) {
        throw "Stage 11 arquivo ausente: $File"
    }
}

$SchedulerCheck =
    Read-Text -Path $SchedulerPath

foreach ($Marker in @(
    "schedulerEligible: true",
    "whatsapp-number-health:",
    "ads_queue.number_health_unavailable"
)) {
    if (
        -not $SchedulerCheck.Contains(
            $Marker
        )
    ) {
        throw "Stage 11 scheduler marker ausente: $Marker"
    }
}

$DomainCheck =
    Read-Text -Path ".\apps\worker\src\whatsapp-number-health.service.ts"

foreach ($Marker in @(
    "META_QUALITY_FLAGGED",
    "META_QUALITY_RED",
    "META_QUALITY_YELLOW",
    "RECOVERING",
    "releaseReservedCapacity",
    "ads_microbatch.contingency_released",
    "whatsapp_number.contingency_activated"
)) {
    if (
        -not $DomainCheck.Contains(
            $Marker
        )
    ) {
        throw "Stage 11 health domain marker ausente: $Marker"
    }
}

foreach ($Path in @(
    $SeedPath,
    $VerifySeedPath,
    $AuthorizationTypesPath,
    $GuardPath
)) {
    $Content =
        Read-Text -Path $Path

    foreach ($Permission in @(
        "whatsapp_health.read",
        "whatsapp_health.manage"
    )) {
        if (
            -not $Content.Contains(
                $Permission
            )
        ) {
            throw "$Permission ausente em $Path"
        }
    }
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host "[OK] MACROBLOCO 11.1 CRIADO." -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Construido:" -ForegroundColor Cyan
Write-Host "- Meta quality rating GREEN/YELLOW/RED/NA"
Write-Host "- phone_number_quality_update webhook"
Write-Host "- WhatsAppNumberHealthState"
Write-Host "- WhatsAppNumberHealthEvent"
Write-Host "- WhatsAppNumberIncident"
Write-Host "- UNKNOWN / HEALTHY / DEGRADED / CRITICAL / RECOVERING / DISABLED"
Write-Host "- schedulerEligible"
Write-Host "- manual pause/resume"
Write-Host "- Meta Graph quality polling"
Write-Host "- polling claim + lease"
Write-Host "- sync failure history"
Write-Host "- two GREEN checks for recovery"
Write-Host "- FLAGGED -> CRITICAL"
Write-Host "- RED -> CRITICAL"
Write-Host "- YELLOW/DOWNGRADE -> DEGRADED"
Write-Host "- UNFLAGGED -> RECOVERING"
Write-Host "- contingency releases outstanding capacity"
Write-Host "- cancelled unhealthy microbatches"
Write-Host "- scheduledLeadCount rollback"
Write-Host "- AdsQueueItem reopen"
Write-Host "- scheduler reroutes to healthy number"
Write-Host "- scheduler race lock"
Write-Host "- health read/manage permissions"
Write-Host "- Health API"
Write-Host "- events API"
Write-Host "- incidents API"
Write-Host "- employee isolation foundation"
Write-Host "- tenant isolation foundation"
Write-Host ""
Write-Host "Migration ainda NAO executada." -ForegroundColor Yellow
Write-Host "Prisma generate ainda NAO executado." -ForegroundColor Yellow
Write-Host "Nao rode CI ainda." -ForegroundColor Yellow
Write-Host ""
Write-Host "Proximo: Macrobloco 11.2 - migration, Meta mocks, contingency runtime e fechamento." -ForegroundColor Yellow