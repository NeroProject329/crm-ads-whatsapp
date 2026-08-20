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

    $Pattern = "(?ms)^$Kind\s+$([regex]::Escape($Name))\s*\{.*?^\}"

    $Match = [regex]::Match(
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

    $Match = Get-PrismaBlock `
        -Content $Content `
        -Kind "model" `
        -Name $Model

    if ($Match.Value.Contains($Marker)) {
        return $Content
    }

    $Block = $Match.Value
    $ClosingIndex = $Block.LastIndexOf("}")

    if ($ClosingIndex -lt 0) {
        throw "Fechamento do model $Model nao encontrado."
    }

    $NewBlock =
        $Block.Substring(0, $ClosingIndex).TrimEnd() +
        "`r`n`r`n" +
        $Members.TrimEnd() +
        "`r`n" +
        "}"

    return (
        $Content.Substring(0, $Match.Index) +
        $NewBlock +
        $Content.Substring($Match.Index + $Match.Length)
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

    $Match = Get-PrismaBlock `
        -Content $Content `
        -Kind $Kind `
        -Name $Name

    $InsertAt =
        $Match.Index +
        $Match.Length

    return (
        $Content.Substring(0, $InsertAt) +
        "`r`n`r`n" +
        $NewContent.Trim() +
        "`r`n" +
        $Content.Substring($InsertAt).TrimStart("`r", "`n")
    )
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " ETAPA 10 - MACROBLOCO 10.1" -ForegroundColor Cyan
Write-Host " UNIQUE LEADS + ADS ATTRIBUTION" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

# ============================================================
# PREFLIGHT
# ============================================================

$RequiredFiles = @(
    ".\packages\database\prisma\schema.prisma",
    ".\packages\database\prisma\seed.ts",
    ".\packages\database\prisma\verify-seed.ts",
    ".\apps\worker\src\whatsapp-inbox-processor.service.ts",
    ".\apps\worker\src\ads-scheduler.service.ts",
    ".\apps\api\src\app.module.ts",
    ".\apps\api\src\authorization\authorization.types.ts",
    ".\apps\api\src\authorization\access-token.guard.ts"
)

foreach ($File in $RequiredFiles) {
    if (-not (Test-Path $File)) {
        throw "Arquivo necessario da Etapa 9 nao encontrado: $File"
    }
}

Write-Host "[OK] Preflight Stage 10." -ForegroundColor Green

# ============================================================
# BACKUP
# ============================================================

$BackupRoot =
    ".\tmp\stage10-macroblock1-backup"

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
    ".\apps\worker\src\whatsapp-inbox-processor.service.ts",
    ".\apps\api\src\app.module.ts",
    ".\apps\api\src\authorization\authorization.types.ts",
    ".\apps\api\src\authorization\access-token.guard.ts",
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

Write-Host "[OK] Backup Stage 10 preparado." -ForegroundColor Green

# ============================================================
# PRISMA
# ============================================================

$SchemaPath =
    ".\packages\database\prisma\schema.prisma"

$Schema =
    Read-Text -Path $SchemaPath

$LeadEnum = @'
enum LeadStatus {
  ATTRIBUTED
  EXCESS
}
'@

$Schema = Insert-AfterPrismaBlock `
    -Content $Schema `
    -Kind "enum" `
    -Name "WhatsAppMessageStatus" `
    -Marker "enum LeadStatus" `
    -NewContent $LeadEnum

$OrganizationRelations = @'
  leads            Lead[]
  leadAttributions LeadAttribution[]
'@

$Schema = Add-ToPrismaModel `
    -Content $Schema `
    -Model "Organization" `
    -Marker "leadAttributions" `
    -Members $OrganizationRelations

$EmployeeRelations = @'
  ownedLeads       Lead[]            @relation("LeadOwnerEmployee")
  leadAttributions LeadAttribution[]
'@

$Schema = Add-ToPrismaModel `
    -Content $Schema `
    -Model "Employee" `
    -Marker "ownedLeads" `
    -Members $EmployeeRelations

$ContactRelations = @'
  lead Lead?
'@

$Schema = Add-ToPrismaModel `
    -Content $Schema `
    -Model "WhatsAppContact" `
    -Marker "lead Lead?" `
    -Members $ContactRelations

$NumberRelations = @'
  firstSeenLeads   Lead[]            @relation("LeadFirstWhatsAppNumber")
  leadAttributions LeadAttribution[]
'@

$Schema = Add-ToPrismaModel `
    -Content $Schema `
    -Model "WhatsAppNumber" `
    -Marker "firstSeenLeads" `
    -Members $NumberRelations

$MessageRelations = @'
  firstSeenLead   Lead?            @relation("LeadFirstInboundMessage")
  leadAttribution LeadAttribution? @relation("LeadAttributionInboundMessage")
'@

$Schema = Add-ToPrismaModel `
    -Content $Schema `
    -Model "WhatsAppMessage" `
    -Marker "firstSeenLead" `
    -Members $MessageRelations

$AdsRequestRelations = @'
  leadAttributions LeadAttribution[]
'@

$Schema = Add-ToPrismaModel `
    -Content $Schema `
    -Model "AdsRequest" `
    -Marker "leadAttributions" `
    -Members $AdsRequestRelations

$MicrobatchRelations = @'
  leadAttributions LeadAttribution[]
'@

$Schema = Add-ToPrismaModel `
    -Content $Schema `
    -Model "AdsMicrobatch" `
    -Marker "leadAttributions" `
    -Members $MicrobatchRelations

$LeadModels = @'
model Lead {
  id                       String     @id @default(uuid()) @db.Uuid
  organizationId           String     @db.Uuid
  contactId                String     @db.Uuid
  firstInboundMessageId    String     @db.Uuid
  firstWhatsAppNumberId    String     @db.Uuid
  ownerEmployeeId          String?    @db.Uuid
  waIdSnapshot             String     @db.VarChar(64)
  profileNameSnapshot      String?    @db.VarChar(160)
  status                   LeadStatus @default(EXCESS)
  excessReason             String?    @db.VarChar(120)
  firstSeenAt              DateTime   @db.Timestamptz(3)
  lastSeenAt               DateTime   @db.Timestamptz(3)
  inboundMessageCount      Int        @default(1)
  attributedAt             DateTime?  @db.Timestamptz(3)
  createdAt                DateTime   @default(now()) @db.Timestamptz(3)
  updatedAt                DateTime   @updatedAt @db.Timestamptz(3)

  organization          Organization    @relation(fields: [organizationId], references: [id], onDelete: Restrict)
  contact               WhatsAppContact @relation(fields: [organizationId, contactId], references: [organizationId, id], onDelete: Restrict)
  firstInboundMessage   WhatsAppMessage @relation("LeadFirstInboundMessage", fields: [organizationId, firstInboundMessageId], references: [organizationId, id], onDelete: Restrict)
  firstWhatsAppNumber   WhatsAppNumber  @relation("LeadFirstWhatsAppNumber", fields: [organizationId, firstWhatsAppNumberId], references: [organizationId, id], onDelete: Restrict)
  ownerEmployee         Employee?       @relation("LeadOwnerEmployee", fields: [organizationId, ownerEmployeeId], references: [organizationId, id], onDelete: Restrict)
  attribution           LeadAttribution?

  @@unique([organizationId, id])
  @@unique([organizationId, contactId])
  @@unique([organizationId, firstInboundMessageId])
  @@index([organizationId, status, firstSeenAt])
  @@index([organizationId, ownerEmployeeId, status, firstSeenAt])
  @@index([organizationId, firstWhatsAppNumberId, status, firstSeenAt])
  @@index([organizationId, waIdSnapshot])
  @@map("leads")
}

model LeadAttribution {
  id                 String   @id @default(uuid()) @db.Uuid
  organizationId     String   @db.Uuid
  leadId             String   @db.Uuid
  adsRequestId       String   @db.Uuid
  adsMicrobatchId    String   @db.Uuid
  employeeId         String   @db.Uuid
  whatsAppNumberId   String   @db.Uuid
  inboundMessageId   String   @db.Uuid
  attributedAt       DateTime @default(now()) @db.Timestamptz(3)
  createdAt          DateTime @default(now()) @db.Timestamptz(3)

  organization   Organization   @relation(fields: [organizationId], references: [id], onDelete: Restrict)
  lead           Lead           @relation(fields: [organizationId, leadId], references: [organizationId, id], onDelete: Cascade)
  adsRequest     AdsRequest     @relation(fields: [organizationId, adsRequestId], references: [organizationId, id], onDelete: Restrict)
  adsMicrobatch  AdsMicrobatch  @relation(fields: [organizationId, adsMicrobatchId], references: [organizationId, id], onDelete: Restrict)
  employee       Employee       @relation(fields: [organizationId, employeeId], references: [organizationId, id], onDelete: Restrict)
  whatsAppNumber WhatsAppNumber @relation(fields: [organizationId, whatsAppNumberId], references: [organizationId, id], onDelete: Restrict)
  inboundMessage WhatsAppMessage @relation("LeadAttributionInboundMessage", fields: [organizationId, inboundMessageId], references: [organizationId, id], onDelete: Restrict)

  @@unique([organizationId, id])
  @@unique([organizationId, leadId])
  @@unique([organizationId, inboundMessageId])
  @@index([organizationId, adsRequestId, attributedAt])
  @@index([organizationId, adsMicrobatchId, attributedAt])
  @@index([organizationId, employeeId, attributedAt])
  @@index([organizationId, whatsAppNumberId, attributedAt])
  @@map("lead_attributions")
}
'@

$Schema = Insert-AfterPrismaBlock `
    -Content $Schema `
    -Kind "model" `
    -Name "WhatsAppQuickReply" `
    -Marker "model Lead {" `
    -NewContent $LeadModels

Write-Text `
    -Path $SchemaPath `
    -Content $Schema

Write-Host "[OK] Lead + LeadAttribution adicionados ao Prisma." -ForegroundColor Green

# ============================================================
# CONTRACTS
# ============================================================

$LeadContracts = @'
export type LeadStatus =
  | 'ATTRIBUTED'
  | 'EXCESS';

export type LeadContactResponse = Readonly<{
  id: string;
  waId: string;
  profileName: string | null;
}>;

export type LeadEmployeeResponse = Readonly<{
  employeeId: string;
  employeeCode: string;
  userId: string;
  displayName: string;
}>;

export type LeadWhatsAppNumberResponse = Readonly<{
  id: string;
  displayName: string;
  e164: string;
}>;

export type LeadAdsRequestResponse = Readonly<{
  id: string;
  requestedLeadCount: number;
  scheduledLeadCount: number;
  fulfilledLeadCount: number;
  status:
    | 'QUEUED'
    | 'PROCESSING'
    | 'PARTIALLY_FULFILLED'
    | 'FULFILLED'
    | 'CANCELLED'
    | 'FAILED';
}>;

export type LeadMicrobatchResponse = Readonly<{
  id: string;
  sequence: number;
  reservedLeadCount: number;
  deliveredLeadCount: number;
  status:
    | 'PLANNED'
    | 'DELIVERING'
    | 'COMPLETED'
    | 'CANCELLED'
    | 'FAILED';
}>;

export type LeadAttributionResponse = Readonly<{
  id: string;
  adsRequestId: string;
  adsMicrobatchId: string;
  employeeId: string;
  whatsAppNumberId: string;
  inboundMessageId: string;
  attributedAt: string;

  adsRequest: LeadAdsRequestResponse;
  microbatch: LeadMicrobatchResponse;
}>;

export type LeadResponse = Readonly<{
  id: string;
  organizationId: string;

  contact: LeadContactResponse;

  firstInboundMessageId: string;

  firstWhatsAppNumber:
    LeadWhatsAppNumberResponse;

  ownerEmployee:
    LeadEmployeeResponse | null;

  waIdSnapshot: string;
  profileNameSnapshot: string | null;

  status: LeadStatus;

  excessReason: string | null;

  firstSeenAt: string;
  lastSeenAt: string;

  inboundMessageCount: number;

  attributedAt: string | null;

  attribution:
    LeadAttributionResponse | null;

  createdAt: string;
  updatedAt: string;
}>;

export type LeadListResponse = Readonly<{
  items: readonly LeadResponse[];
  nextCursor: string | null;
}>;

export type LeadSummaryResponse = Readonly<{
  totalUniqueLeads: number;
  attributedLeads: number;
  excessLeads: number;
}>;
'@

Write-Text `
    -Path ".\packages\contracts\src\leads.ts" `
    -Content $LeadContracts

$ContractsIndexPath =
    ".\packages\contracts\src\index.ts"

$ContractsIndex =
    Read-Text -Path $ContractsIndexPath

if (-not $ContractsIndex.Contains("export * from './leads.js';")) {
    $ContractsIndex =
        $ContractsIndex.TrimEnd() +
        "`r`n" +
        "export * from './leads.js';`r`n"
}

Write-Text `
    -Path $ContractsIndexPath `
    -Content $ContractsIndex

Write-Host "[OK] Lead contracts criados." -ForegroundColor Green

# ============================================================
# VALIDATION
# ============================================================

$LeadValidation = @'
import {
  z,
} from 'zod';

const uuidSchema =
  z.string().uuid();

const leadStatusSchema =
  z.enum([
    'ATTRIBUTED',
    'EXCESS',
  ]);

export const leadListQuerySchema =
  z
    .object({
      cursor:
        uuidSchema.optional(),

      limit:
        z.coerce
          .number()
          .int()
          .min(1)
          .max(100)
          .default(30),

      status:
        leadStatusSchema.optional(),

      whatsAppNumberId:
        uuidSchema.optional(),

      adsRequestId:
        uuidSchema.optional(),

      search:
        z
          .string()
          .trim()
          .min(1)
          .max(120)
          .optional(),
    })
    .strict();

export type LeadListQuery =
  z.infer<
    typeof leadListQuerySchema
  >;
'@

Write-Text `
    -Path ".\packages\validation\src\leads.ts" `
    -Content $LeadValidation

$ValidationIndexPath =
    ".\packages\validation\src\index.ts"

$ValidationIndex =
    Read-Text -Path $ValidationIndexPath

if (-not $ValidationIndex.Contains("export * from './leads.js';")) {
    $ValidationIndex =
        $ValidationIndex.TrimEnd() +
        "`r`n" +
        "export * from './leads.js';`r`n"
}

Write-Text `
    -Path $ValidationIndexPath `
    -Content $ValidationIndex

Write-Host "[OK] Lead validation criada." -ForegroundColor Green

# ============================================================
# PERMISSION: lead.read
# ============================================================

$SeedPath =
    ".\packages\database\prisma\seed.ts"

$Seed =
    Read-Text -Path $SeedPath

if (-not $Seed.Contains("'lead.read'")) {
    $Anchor =
        "  ['quick_reply.manage', 'Gerenciar respostas rapidas'],"

    if (-not $Seed.Contains($Anchor)) {
        throw "Seed permission anchor nao encontrado."
    }

    $Replacement =
        $Anchor +
        "`r`n" +
        "  ['lead.read', 'Visualizar leads unicos e atribuicoes'],"

    $Seed =
        $Seed.Replace(
            $Anchor,
            $Replacement
        )
}

if (-not [regex]::IsMatch($Seed, "(?m)^\s*'lead\.read',\s*$")) {
    $EmployeeAnchor =
        "    'quick_reply.read',"

    if (-not $Seed.Contains($EmployeeAnchor)) {
        throw "Employee permission anchor nao encontrado."
    }

    $Seed =
        $Seed.Replace(
            $EmployeeAnchor,
            $EmployeeAnchor +
            "`r`n" +
            "    'lead.read',"
        )
}

Write-Text `
    -Path $SeedPath `
    -Content $Seed

$VerifySeedPath =
    ".\packages\database\prisma\verify-seed.ts"

$VerifySeed =
    Read-Text -Path $VerifySeedPath

if (-not $VerifySeed.Contains("'lead.read'")) {
    $VerifySeed =
        $VerifySeed.Replace(
            "  'inbox.read',`r`n  'organization.manage',",
            "  'inbox.read',`r`n  'lead.read',`r`n  'organization.manage',"
        )

    $VerifySeed =
        $VerifySeed.Replace(
            "  'inbox.read',`n  'organization.manage',",
            "  'inbox.read',`n  'lead.read',`n  'organization.manage',"
        )

    $VerifySeed =
        $VerifySeed.Replace(
            "  'inbox.read',`r`n  'profile.read',",
            "  'inbox.read',`r`n  'lead.read',`r`n  'profile.read',"
        )

    $VerifySeed =
        $VerifySeed.Replace(
            "  'inbox.read',`n  'profile.read',",
            "  'inbox.read',`n  'lead.read',`n  'profile.read',"
        )
}

Write-Text `
    -Path $VerifySeedPath `
    -Content $VerifySeed

$AuthorizationTypesPath =
    ".\apps\api\src\authorization\authorization.types.ts"

$AuthorizationTypes =
    Read-Text -Path $AuthorizationTypesPath

if (-not $AuthorizationTypes.Contains("'lead.read'")) {
    $Anchor =
        "  | 'quick_reply.manage';"

    if (-not $AuthorizationTypes.Contains($Anchor)) {
        throw "PermissionCode Stage 9 anchor nao encontrado."
    }

    $AuthorizationTypes =
        $AuthorizationTypes.Replace(
            $Anchor,
            "  | 'quick_reply.manage'`r`n  | 'lead.read';"
        )
}

Write-Text `
    -Path $AuthorizationTypesPath `
    -Content $AuthorizationTypes

$AccessGuardPath =
    ".\apps\api\src\authorization\access-token.guard.ts"

$AccessGuard =
    Read-Text -Path $AccessGuardPath

if (-not $AccessGuard.Contains("value === 'lead.read'")) {
    $Anchor =
        "      value === 'quick_reply.manage'"

    if (-not $AccessGuard.Contains($Anchor)) {
        throw "AccessTokenGuard Stage 9 anchor nao encontrado."
    }

    $AccessGuard =
        $AccessGuard.Replace(
            $Anchor,
            $Anchor +
            " ||`r`n" +
            "      value === 'lead.read'"
        )
}

Write-Text `
    -Path $AccessGuardPath `
    -Content $AccessGuard

Write-Host "[OK] lead.read adicionado ao catalogo de permissoes." -ForegroundColor Green

# ============================================================
# WORKER - LEAD ATTRIBUTION SERVICE
# ============================================================

$LeadAttributionService = @'
import type {
  CrmDatabaseClient,
} from '@crm/database';

type TransactionClient =
  Parameters<
    Parameters<
      CrmDatabaseClient['$transaction']
    >[0]
  >[0];

type CandidateMicrobatch =
  Readonly<{
    id: string;
    adsRequestId: string;
    employeeId: string;
    whatsAppNumberId: string;

    reservedLeadCount: number;
    deliveredLeadCount: number;

    startedAt: Date | null;

    requestedLeadCount: number;
    fulfilledLeadCount: number;
  }>;

export type RecordInboundLeadInput =
  Readonly<{
    organizationId: string;
    contactId: string;
    whatsAppNumberId: string;
    ownerEmployeeId: string | null;
    inboundMessageId: string;

    waId: string;
    profileName: string | null;

    providerTimestamp: Date;
  }>;

export type RecordInboundLeadResult =
  | 'ATTRIBUTED'
  | 'EXCESS'
  | 'DUPLICATE';

export class LeadAttributionService {
  async recordInboundLead(
    transaction:
      TransactionClient,

    input:
      RecordInboundLeadInput,
  ): Promise<
    RecordInboundLeadResult
  > {
    /*
     * A WhatsAppContact is unique by
     * organizationId + waId.
     *
     * Locking the contact identity makes the unique-lead
     * decision deterministic even when separate webhook
     * workers receive simultaneous messages from the same
     * customer.
     */
    await transaction.$queryRawUnsafe(
      'WITH lock_guard AS MATERIALIZED (SELECT pg_advisory_xact_lock(hashtextextended($1, 0))) SELECT TRUE AS locked FROM lock_guard',
      `lead:${input.organizationId}:${input.contactId}`,
    );

    const existing =
      await transaction.lead.findUnique({
        where: {
          organizationId_contactId: {
            organizationId:
              input.organizationId,

            contactId:
              input.contactId,
          },
        },
      });

    if (existing) {
      const nextLastSeenAt =
        existing.lastSeenAt <
        input.providerTimestamp
          ? input.providerTimestamp
          : existing.lastSeenAt;

      await transaction.lead.update({
        where: {
          id:
            existing.id,
        },

        data: {
          lastSeenAt:
            nextLastSeenAt,

          inboundMessageCount: {
            increment:
              1,
          },
        },
      });

      return 'DUPLICATE';
    }

    const lead =
      await transaction.lead.create({
        data: {
          organizationId:
            input.organizationId,

          contactId:
            input.contactId,

          firstInboundMessageId:
            input.inboundMessageId,

          firstWhatsAppNumberId:
            input.whatsAppNumberId,

          ownerEmployeeId:
            input.ownerEmployeeId,

          waIdSnapshot:
            input.waId,

          profileNameSnapshot:
            input.profileName,

          status:
            'EXCESS',

          excessReason:
            input.ownerEmployeeId
              ? 'NO_RESERVED_CAPACITY'
              : 'NUMBER_UNASSIGNED',

          firstSeenAt:
            input.providerTimestamp,

          lastSeenAt:
            input.providerTimestamp,
        },
      });

    if (
      !input.ownerEmployeeId
    ) {
      await transaction.auditLog.create({
        data: {
          organizationId:
            input.organizationId,

          actorType:
            'SYSTEM',

          action:
            'lead.excess',

          resourceType:
            'lead',

          resourceId:
            lead.id,

          outcome:
            'SUCCESS',

          metadata: {
            reason:
              'NUMBER_UNASSIGNED',

            contactId:
              input.contactId,

            whatsAppNumberId:
              input.whatsAppNumberId,

            inboundMessageId:
              input.inboundMessageId,
          },
        },
      });

      return 'EXCESS';
    }

    /*
     * Only one worker at a time may consume a reserved
     * lead slot for a WhatsApp number.
     */
    await transaction.$queryRawUnsafe(
      'WITH lock_guard AS MATERIALIZED (SELECT pg_advisory_xact_lock(hashtextextended($1, 0))) SELECT TRUE AS locked FROM lock_guard',
      `lead-slot:${input.organizationId}:${input.whatsAppNumberId}`,
    );

    const candidates =
      await transaction.$queryRawUnsafe<
        CandidateMicrobatch[]
      >(
        `
        SELECT
          microbatch."id",
          microbatch."adsRequestId",
          microbatch."employeeId",
          microbatch."whatsAppNumberId",
          microbatch."reservedLeadCount",
          microbatch."deliveredLeadCount",
          microbatch."startedAt",
          ads_request."requestedLeadCount",
          ads_request."fulfilledLeadCount"
        FROM
          "ads_microbatches" AS microbatch
        INNER JOIN
          "ads_requests" AS ads_request
          ON ads_request."organizationId" =
             microbatch."organizationId"
          AND ads_request."id" =
              microbatch."adsRequestId"
        WHERE
          microbatch."organizationId" = $1
          AND microbatch."whatsAppNumberId" = $2
          AND microbatch."employeeId" = $3
          AND microbatch."status" IN (
            'PLANNED',
            'DELIVERING'
          )
          AND microbatch."deliveredLeadCount" <
              microbatch."reservedLeadCount"
          AND ads_request."status" IN (
            'PROCESSING',
            'PARTIALLY_FULFILLED'
          )
        ORDER BY
          microbatch."plannedAt" ASC,
          microbatch."sequence" ASC,
          microbatch."id" ASC
        FOR UPDATE OF
          microbatch,
          ads_request
        LIMIT 1
        `,
        input.organizationId,
        input.whatsAppNumberId,
        input.ownerEmployeeId,
      );

    const candidate =
      candidates[0];

    if (!candidate) {
      await transaction.auditLog.create({
        data: {
          organizationId:
            input.organizationId,

          actorType:
            'SYSTEM',

          action:
            'lead.excess',

          resourceType:
            'lead',

          resourceId:
            lead.id,

          outcome:
            'SUCCESS',

          metadata: {
            reason:
              'NO_RESERVED_CAPACITY',

            contactId:
              input.contactId,

            employeeId:
              input.ownerEmployeeId,

            whatsAppNumberId:
              input.whatsAppNumberId,

            inboundMessageId:
              input.inboundMessageId,
          },
        },
      });

      return 'EXCESS';
    }

    const attributedAt =
      new Date();

    const nextDeliveredLeadCount =
      candidate.deliveredLeadCount +
      1;

    const microbatchCompleted =
      nextDeliveredLeadCount >=
      candidate.reservedLeadCount;

    const nextFulfilledLeadCount =
      candidate.fulfilledLeadCount +
      1;

    const requestFulfilled =
      nextFulfilledLeadCount >=
      candidate.requestedLeadCount;

    const attribution =
      await transaction.leadAttribution.create({
        data: {
          organizationId:
            input.organizationId,

          leadId:
            lead.id,

          adsRequestId:
            candidate.adsRequestId,

          adsMicrobatchId:
            candidate.id,

          employeeId:
            candidate.employeeId,

          whatsAppNumberId:
            candidate.whatsAppNumberId,

          inboundMessageId:
            input.inboundMessageId,

          attributedAt,
        },
      });

    await transaction.lead.update({
      where: {
        id:
          lead.id,
      },

      data: {
        status:
          'ATTRIBUTED',

        excessReason:
          null,

        ownerEmployeeId:
          candidate.employeeId,

        attributedAt,
      },
    });

    await transaction.adsMicrobatch.update({
      where: {
        id:
          candidate.id,
      },

      data: {
        deliveredLeadCount: {
          increment:
            1,
        },

        status:
          microbatchCompleted
            ? 'COMPLETED'
            : 'DELIVERING',

        startedAt:
          candidate.startedAt ??
          attributedAt,

        completedAt:
          microbatchCompleted
            ? attributedAt
            : null,
      },
    });

    await transaction.adsRequest.update({
      where: {
        id:
          candidate.adsRequestId,
      },

      data: {
        fulfilledLeadCount: {
          increment:
            1,
        },

        status:
          requestFulfilled
            ? 'FULFILLED'
            : 'PARTIALLY_FULFILLED',

        completedAt:
          requestFulfilled
            ? attributedAt
            : null,

        failureReason:
          null,
      },
    });

    await transaction.auditLog.create({
      data: {
        organizationId:
          input.organizationId,

        actorType:
          'SYSTEM',

        action:
          'lead.attributed',

        resourceType:
          'lead',

        resourceId:
          lead.id,

        outcome:
          'SUCCESS',

        metadata: {
          leadAttributionId:
            attribution.id,

          contactId:
            input.contactId,

          inboundMessageId:
            input.inboundMessageId,

          adsRequestId:
            candidate.adsRequestId,

          adsMicrobatchId:
            candidate.id,

          employeeId:
            candidate.employeeId,

          whatsAppNumberId:
            candidate.whatsAppNumberId,

          microbatchDeliveredLeadCount:
            nextDeliveredLeadCount,

          microbatchReservedLeadCount:
            candidate.reservedLeadCount,

          requestFulfilledLeadCount:
            nextFulfilledLeadCount,

          requestRequestedLeadCount:
            candidate.requestedLeadCount,
        },
      },
    });

    if (
      microbatchCompleted
    ) {
      await transaction.auditLog.create({
        data: {
          organizationId:
            input.organizationId,

          actorType:
            'SYSTEM',

          action:
            'ads_microbatch.completed',

          resourceType:
            'ads_microbatch',

          resourceId:
            candidate.id,

          outcome:
            'SUCCESS',

          metadata: {
            adsRequestId:
              candidate.adsRequestId,

            deliveredLeadCount:
              nextDeliveredLeadCount,

            reservedLeadCount:
              candidate.reservedLeadCount,
          },
        },
      });
    }

    if (
      requestFulfilled
    ) {
      await transaction.auditLog.create({
        data: {
          organizationId:
            input.organizationId,

          actorType:
            'SYSTEM',

          action:
            'ads_request.fulfilled',

          resourceType:
            'ads_request',

          resourceId:
            candidate.adsRequestId,

          outcome:
            'SUCCESS',

          metadata: {
            requestedLeadCount:
              candidate.requestedLeadCount,

            fulfilledLeadCount:
              nextFulfilledLeadCount,
          },
        },
      });
    }

    return 'ATTRIBUTED';
  }
}
'@

Write-Text `
    -Path ".\apps\worker\src\lead-attribution.service.ts" `
    -Content $LeadAttributionService

Write-Host "[OK] LeadAttributionService criado." -ForegroundColor Green

# ============================================================
# INTEGRATE LEAD ATTRIBUTION INTO INBOUND TRANSACTION
# ============================================================

$InboxProcessorPath =
    ".\apps\worker\src\whatsapp-inbox-processor.service.ts"

$InboxProcessor =
    Read-Text -Path $InboxProcessorPath

if (-not $InboxProcessor.Contains("LeadAttributionService")) {
    $ImportAnchor =
        "import type { WhatsAppRuntimeConfig } from './whatsapp-runtime.config.js';"

    if (-not $InboxProcessor.Contains($ImportAnchor)) {
        throw "Inbox processor import anchor nao encontrado."
    }

    $InboxProcessor =
        $InboxProcessor.Replace(
            $ImportAnchor,
            "import { LeadAttributionService } from './lead-attribution.service.js';`r`n`r`n" +
            $ImportAnchor
        )
}

if (-not $InboxProcessor.Contains("private readonly leadAttributionService")) {
    $ClassAnchor =
        "export class WhatsAppInboxProcessorService {"

    if (-not $InboxProcessor.Contains($ClassAnchor)) {
        throw "Inbox processor class anchor nao encontrado."
    }

    $InboxProcessor =
        $InboxProcessor.Replace(
            $ClassAnchor,
            $ClassAnchor +
            "`r`n" +
            "  private readonly leadAttributionService = new LeadAttributionService();"
        )
}

if (-not $InboxProcessor.Contains("const inboundMessage = await transaction.whatsAppMessage.create")) {
    $CreateAnchor =
        "      await transaction.whatsAppMessage.create({"

    if (-not $InboxProcessor.Contains($CreateAnchor)) {
        throw "Inbound WhatsAppMessage create anchor nao encontrado."
    }

    $InboxProcessor =
        $InboxProcessor.Replace(
            $CreateAnchor,
            "      const inboundMessage = await transaction.whatsAppMessage.create({"
        )
}

if (-not $InboxProcessor.Contains("recordInboundLead(transaction")) {
    $TailCRLF = @'
          availableAt: providerTimestamp,
        },
      });

      return true;
'@

    $TailLF = $TailCRLF.Replace("`r`n", "`n")

    $Replacement = @'
          availableAt: providerTimestamp,
        },
      });

      await this.leadAttributionService.recordInboundLead(
        transaction,
        {
          organizationId,

          contactId:
            contact.id,

          whatsAppNumberId:
            number.id,

          ownerEmployeeId:
            number.assignedEmployeeId,

          inboundMessageId:
            inboundMessage.id,

          waId:
            event.from,

          profileName:
            event.profileName,

          providerTimestamp,
        },
      );

      return true;
'@

    if ($InboxProcessor.Contains($TailCRLF.Trim())) {
        $InboxProcessor =
            $InboxProcessor.Replace(
                $TailCRLF.Trim(),
                $Replacement.Trim()
            )
    }
    elseif ($InboxProcessor.Contains($TailLF.Trim())) {
        $InboxProcessor =
            $InboxProcessor.Replace(
                $TailLF.Trim(),
                $Replacement.Replace("`r`n", "`n").Trim()
            )
    }
    else {
        throw "Inbound message tail anchor nao encontrado."
    }
}

Write-Text `
    -Path $InboxProcessorPath `
    -Content $InboxProcessor

Write-Host "[OK] Lead attribution integrada ao webhook inbound." -ForegroundColor Green

# ============================================================
# LEADS API SERVICE
# ============================================================

$LeadsService = @'
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
  AdsMicrobatchModel,
  AdsRequestModel,
  EmployeeModel,
  LeadAttributionModel,
  LeadModel,
  UserModel,
  WhatsAppContactModel,
  WhatsAppNumberModel,
} from '@crm/database';

import type {
  LeadListResponse,
  LeadResponse,
  LeadSummaryResponse,
} from '@crm/contracts';

import type {
  LeadListQuery,
} from '@crm/validation';

import {
  DatabaseService,
} from '../database/database.service.js';

type LoadedOwnerEmployee =
  Pick<
    EmployeeModel,
    'id' |
    'employeeCode' |
    'userId'
  > & {
    user:
      Pick<
        UserModel,
        'displayName'
      >;
  };

type LoadedAttribution =
  LeadAttributionModel & {
    adsRequest:
      Pick<
        AdsRequestModel,
        | 'id'
        | 'requestedLeadCount'
        | 'scheduledLeadCount'
        | 'fulfilledLeadCount'
        | 'status'
      >;

    adsMicrobatch:
      Pick<
        AdsMicrobatchModel,
        | 'id'
        | 'sequence'
        | 'reservedLeadCount'
        | 'deliveredLeadCount'
        | 'status'
      >;
  };

type LoadedLead =
  LeadModel & {
    contact:
      Pick<
        WhatsAppContactModel,
        | 'id'
        | 'waId'
        | 'profileName'
      >;

    firstWhatsAppNumber:
      Pick<
        WhatsAppNumberModel,
        | 'id'
        | 'displayName'
        | 'e164'
      >;

    ownerEmployee:
      LoadedOwnerEmployee |
      null;

    attribution:
      LoadedAttribution |
      null;
  };

@Injectable()
export class LeadsService {
  constructor(
    @Inject(
      DatabaseService,
    )
    private readonly database:
      DatabaseService,
  ) {}

  async list(
    principal:
      AuthenticatedPrincipal,

    query:
      LeadListQuery,
  ): Promise<
    LeadListResponse
  > {
    const employeeId =
      this.isAdmin(
        principal,
      )
        ? null
        : await this.getCurrentEmployeeId(
            principal,
          );

    const leads =
      await this.database.client.lead.findMany({
        where: {
          organizationId:
            principal.organizationId,

          ...(employeeId
            ? {
                ownerEmployeeId:
                  employeeId,
              }
            : {}),

          ...(query.status
            ? {
                status:
                  query.status,
              }
            : {}),

          ...(query.whatsAppNumberId
            ? {
                firstWhatsAppNumberId:
                  query.whatsAppNumberId,
              }
            : {}),

          ...(query.adsRequestId
            ? {
                attribution: {
                  is: {
                    adsRequestId:
                      query.adsRequestId,
                  },
                },
              }
            : {}),

          ...(query.search
            ? {
                OR: [
                  {
                    waIdSnapshot: {
                      contains:
                        query.search,
                    },
                  },

                  {
                    profileNameSnapshot: {
                      contains:
                        query.search,

                      mode:
                        'insensitive',
                    },
                  },
                ],
              }
            : {}),
        },

        include: {
          contact: {
            select: {
              id:
                true,

              waId:
                true,

              profileName:
                true,
            },
          },

          firstWhatsAppNumber: {
            select: {
              id:
                true,

              displayName:
                true,

              e164:
                true,
            },
          },

          ownerEmployee: {
            include: {
              user: {
                select: {
                  displayName:
                    true,
                },
              },
            },
          },

          attribution: {
            include: {
              adsRequest: {
                select: {
                  id:
                    true,

                  requestedLeadCount:
                    true,

                  scheduledLeadCount:
                    true,

                  fulfilledLeadCount:
                    true,

                  status:
                    true,
                },
              },

              adsMicrobatch: {
                select: {
                  id:
                    true,

                  sequence:
                    true,

                  reservedLeadCount:
                    true,

                  deliveredLeadCount:
                    true,

                  status:
                    true,
                },
              },
            },
          },
        },

        orderBy: [
          {
            firstSeenAt:
              'desc',
          },

          {
            id:
              'desc',
          },
        ],

        take:
          query.limit +
          1,

        ...(query.cursor
          ? {
              cursor: {
                id:
                  query.cursor,
              },

              skip:
                1,
            }
          : {}),
      });

    const hasMore =
      leads.length >
      query.limit;

    const page =
      hasMore
        ? leads.slice(
            0,
            query.limit,
          )
        : leads;

    return {
      items:
        page.map(
          (
            lead,
          ) =>
            this.mapLead(
              lead,
            ),
        ),

      nextCursor:
        hasMore
          ? page.at(
              -1,
            )?.id ??
            null
          : null,
    };
  }

  async summary(
    principal:
      AuthenticatedPrincipal,
  ): Promise<
    LeadSummaryResponse
  > {
    const employeeId =
      this.isAdmin(
        principal,
      )
        ? null
        : await this.getCurrentEmployeeId(
            principal,
          );

    const visibility = {
      organizationId:
        principal.organizationId,

      ...(employeeId
        ? {
            ownerEmployeeId:
              employeeId,
          }
        : {}),
    };

    const [
      totalUniqueLeads,
      attributedLeads,
      excessLeads,
    ] =
      await Promise.all([
        this.database.client.lead.count({
          where:
            visibility,
        }),

        this.database.client.lead.count({
          where: {
            ...visibility,

            status:
              'ATTRIBUTED',
          },
        }),

        this.database.client.lead.count({
          where: {
            ...visibility,

            status:
              'EXCESS',
          },
        }),
      ]);

    return {
      totalUniqueLeads,
      attributedLeads,
      excessLeads,
    };
  }

  async getById(
    principal:
      AuthenticatedPrincipal,

    leadId:
      string,
  ): Promise<
    LeadResponse
  > {
    const employeeId =
      this.isAdmin(
        principal,
      )
        ? null
        : await this.getCurrentEmployeeId(
            principal,
          );

    const lead =
      await this.database.client.lead.findFirst({
        where: {
          id:
            leadId,

          organizationId:
            principal.organizationId,

          ...(employeeId
            ? {
                ownerEmployeeId:
                  employeeId,
              }
            : {}),
        },

        include: {
          contact: {
            select: {
              id:
                true,

              waId:
                true,

              profileName:
                true,
            },
          },

          firstWhatsAppNumber: {
            select: {
              id:
                true,

              displayName:
                true,

              e164:
                true,
            },
          },

          ownerEmployee: {
            include: {
              user: {
                select: {
                  displayName:
                    true,
                },
              },
            },
          },

          attribution: {
            include: {
              adsRequest: {
                select: {
                  id:
                    true,

                  requestedLeadCount:
                    true,

                  scheduledLeadCount:
                    true,

                  fulfilledLeadCount:
                    true,

                  status:
                    true,
                },
              },

              adsMicrobatch: {
                select: {
                  id:
                    true,

                  sequence:
                    true,

                  reservedLeadCount:
                    true,

                  deliveredLeadCount:
                    true,

                  status:
                    true,
                },
              },
            },
          },
        },
      });

    if (!lead) {
      throw new NotFoundException({
        code:
          'LEAD_NOT_FOUND',

        message:
          'Lead not found.',
      });
    }

    return this.mapLead(
      lead,
    );
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

    if (!employee) {
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

  private mapLead(
    lead:
      LoadedLead,
  ): LeadResponse {
    return {
      id:
        lead.id,

      organizationId:
        lead.organizationId,

      contact: {
        id:
          lead.contact.id,

        waId:
          lead.contact.waId,

        profileName:
          lead.contact.profileName,
      },

      firstInboundMessageId:
        lead.firstInboundMessageId,

      firstWhatsAppNumber: {
        id:
          lead.firstWhatsAppNumber.id,

        displayName:
          lead.firstWhatsAppNumber.displayName,

        e164:
          lead.firstWhatsAppNumber.e164,
      },

      ownerEmployee:
        lead.ownerEmployee
          ? {
              employeeId:
                lead.ownerEmployee.id,

              employeeCode:
                lead.ownerEmployee.employeeCode,

              userId:
                lead.ownerEmployee.userId,

              displayName:
                lead.ownerEmployee.user.displayName,
            }
          : null,

      waIdSnapshot:
        lead.waIdSnapshot,

      profileNameSnapshot:
        lead.profileNameSnapshot,

      status:
        lead.status,

      excessReason:
        lead.excessReason,

      firstSeenAt:
        lead.firstSeenAt.toISOString(),

      lastSeenAt:
        lead.lastSeenAt.toISOString(),

      inboundMessageCount:
        lead.inboundMessageCount,

      attributedAt:
        lead.attributedAt?.toISOString() ??
        null,

      attribution:
        lead.attribution
          ? {
              id:
                lead.attribution.id,

              adsRequestId:
                lead.attribution.adsRequestId,

              adsMicrobatchId:
                lead.attribution.adsMicrobatchId,

              employeeId:
                lead.attribution.employeeId,

              whatsAppNumberId:
                lead.attribution.whatsAppNumberId,

              inboundMessageId:
                lead.attribution.inboundMessageId,

              attributedAt:
                lead.attribution.attributedAt.toISOString(),

              adsRequest: {
                id:
                  lead.attribution.adsRequest.id,

                requestedLeadCount:
                  lead.attribution.adsRequest.requestedLeadCount,

                scheduledLeadCount:
                  lead.attribution.adsRequest.scheduledLeadCount,

                fulfilledLeadCount:
                  lead.attribution.adsRequest.fulfilledLeadCount,

                status:
                  lead.attribution.adsRequest.status,
              },

              microbatch: {
                id:
                  lead.attribution.adsMicrobatch.id,

                sequence:
                  lead.attribution.adsMicrobatch.sequence,

                reservedLeadCount:
                  lead.attribution.adsMicrobatch.reservedLeadCount,

                deliveredLeadCount:
                  lead.attribution.adsMicrobatch.deliveredLeadCount,

                status:
                  lead.attribution.adsMicrobatch.status,
              },
            }
          : null,

      createdAt:
        lead.createdAt.toISOString(),

      updatedAt:
        lead.updatedAt.toISOString(),
    };
  }
}
'@

New-Item `
    -ItemType Directory `
    -Path ".\apps\api\src\leads" `
    -Force |
    Out-Null

Write-Text `
    -Path ".\apps\api\src\leads\leads.service.ts" `
    -Content $LeadsService

# ============================================================
# LEADS API CONTROLLER
# ============================================================

$LeadsController = @'
import {
  BadRequestException,
  Controller,
  Get,
  Inject,
  Param,
  ParseUUIDPipe,
  Query,
  UseGuards,
} from '@nestjs/common';

import type {
  AuthenticatedPrincipal,
} from '@crm/auth';

import type {
  LeadListResponse,
  LeadResponse,
  LeadSummaryResponse,
} from '@crm/contracts';

import {
  leadListQuerySchema,
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
  LeadsService,
} from './leads.service.js';

@Controller('leads')
@UseGuards(
  AccessTokenGuard,
  AuthorizationGuard,
)
export class LeadsController {
  constructor(
    @Inject(
      LeadsService,
    )
    private readonly leadsService:
      LeadsService,
  ) {}

  @Get()
  @RequirePermissions(
    'lead.read',
  )
  list(
    @CurrentPrincipal()
    principal:
      AuthenticatedPrincipal,

    @Query()
    query:
      unknown,
  ): Promise<
    LeadListResponse
  > {
    const parsed =
      leadListQuerySchema.safeParse(
        query,
      );

    if (
      !parsed.success
    ) {
      throw new BadRequestException({
        code:
          'LEAD_QUERY_VALIDATION_ERROR',

        message:
          'Invalid lead query.',

        issues:
          parsed.error.issues.map(
            (
              issue,
            ) => ({
              code:
                issue.code,

              path:
                issue.path.join(
                  '.',
                ),
            }),
          ),
      });
    }

    return this.leadsService.list(
      principal,
      parsed.data,
    );
  }

  @Get('summary')
  @RequirePermissions(
    'lead.read',
  )
  summary(
    @CurrentPrincipal()
    principal:
      AuthenticatedPrincipal,
  ): Promise<
    LeadSummaryResponse
  > {
    return this.leadsService.summary(
      principal,
    );
  }

  @Get(':leadId')
  @RequirePermissions(
    'lead.read',
  )
  getById(
    @CurrentPrincipal()
    principal:
      AuthenticatedPrincipal,

    @Param(
      'leadId',
      new ParseUUIDPipe(),
    )
    leadId:
      string,
  ): Promise<
    LeadResponse
  > {
    return this.leadsService.getById(
      principal,
      leadId,
    );
  }
}
'@

Write-Text `
    -Path ".\apps\api\src\leads\leads.controller.ts" `
    -Content $LeadsController

$LeadsModule = @'
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
  LeadsController,
} from './leads.controller.js';

import {
  LeadsService,
} from './leads.service.js';

@Module({
  imports: [
    AuthorizationModule,
    DatabaseModule,
  ],

  controllers: [
    LeadsController,
  ],

  providers: [
    LeadsService,
  ],

  exports: [
    LeadsService,
  ],
})
export class LeadsModule {}
'@

Write-Text `
    -Path ".\apps\api\src\leads\leads.module.ts" `
    -Content $LeadsModule

$AppModulePath =
    ".\apps\api\src\app.module.ts"

$AppModule =
    Read-Text -Path $AppModulePath

if (-not $AppModule.Contains("LeadsModule")) {
    $ImportAnchor =
        "import { InboxModule } from './inbox/inbox.module.js';"

    if (-not $AppModule.Contains($ImportAnchor)) {
        throw "AppModule InboxModule anchor nao encontrado."
    }

    $AppModule =
        $AppModule.Replace(
            $ImportAnchor,
            $ImportAnchor +
            "`r`n`r`n" +
            "import { LeadsModule } from './leads/leads.module.js';"
        )

    $ArrayAnchor =
        "    InboxModule,"

    if (-not $AppModule.Contains($ArrayAnchor)) {
        throw "AppModule InboxModule array anchor nao encontrado."
    }

    $AppModule =
        $AppModule.Replace(
            $ArrayAnchor,
            $ArrayAnchor +
            "`r`n" +
            "    LeadsModule,"
        )
}

Write-Text `
    -Path $AppModulePath `
    -Content $AppModule

Write-Host "[OK] Leads API criada." -ForegroundColor Green

# ============================================================
# DOC STATUS
# ============================================================

$EtapasPath =
    ".\docs\ETAPAS.md"

if (Test-Path $EtapasPath) {
    $Etapas =
        Read-Text -Path $EtapasPath

    $Etapas =
        [regex]::Replace(
            $Etapas,
            "(?m)^\|\s*10\s*\|([^|]+)\|([^|]+)\|$",
            {
                param($Match)

                return (
                    "|    10 |" +
                    $Match.Groups[1].Value +
                    "| EM ANDAMENTO                 |"
                )
            },
            1
        )

    if (-not $Etapas.Contains("## Etapa 10 - Leads unicos")) {
        $Etapas =
            $Etapas.TrimEnd() +
            "`r`n`r`n" +
            "## Etapa 10 - Leads unicos e atribuicao`r`n`r`n" +
            "Status: EM ANDAMENTO - Macrobloco 10.1 construido.`r`n"
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

$RequiredSchemaMarkers = @(
    "enum LeadStatus",
    "model Lead {",
    "model LeadAttribution {",
    "inboundMessageCount",
    "excessReason",
    "firstInboundMessageId",
    "leadAttributions LeadAttribution[]",
    "@@unique([organizationId, contactId])",
    "@@unique([organizationId, leadId])"
)

foreach ($Marker in $RequiredSchemaMarkers) {
    if (-not $SchemaCheck.Contains($Marker)) {
        throw "Stage 10 schema marker ausente: $Marker"
    }
}

$RequiredStage10Files = @(
    ".\packages\contracts\src\leads.ts",
    ".\packages\validation\src\leads.ts",
    ".\apps\worker\src\lead-attribution.service.ts",
    ".\apps\api\src\leads\leads.service.ts",
    ".\apps\api\src\leads\leads.controller.ts",
    ".\apps\api\src\leads\leads.module.ts"
)

foreach ($File in $RequiredStage10Files) {
    if (-not (Test-Path $File)) {
        throw "Stage 10 arquivo ausente: $File"
    }
}

$InboxCheck =
    Read-Text -Path $InboxProcessorPath

foreach ($Marker in @(
    "LeadAttributionService",
    "const inboundMessage = await transaction.whatsAppMessage.create",
    "recordInboundLead("
)) {
    if (-not $InboxCheck.Contains($Marker)) {
        throw "Stage 10 Inbox integration marker ausente: $Marker"
    }
}

$LeadServiceCheck =
    Read-Text -Path ".\apps\worker\src\lead-attribution.service.ts"

foreach ($Marker in @(
    "lead-slot:",
    "NO_RESERVED_CAPACITY",
    "ads_microbatch.completed",
    "ads_request.fulfilled",
    "fulfilledLeadCount",
    "deliveredLeadCount"
)) {
    if (-not $LeadServiceCheck.Contains($Marker)) {
        throw "Stage 10 attribution marker ausente: $Marker"
    }
}

foreach ($Path in @(
    $SeedPath,
    $VerifySeedPath,
    $AuthorizationTypesPath,
    $AccessGuardPath
)) {
    $Content =
        Read-Text -Path $Path

    if (-not $Content.Contains("lead.read")) {
        throw "lead.read ausente em $Path"
    }
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host "[OK] MACROBLOCO 10.1 CRIADO." -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Construido:" -ForegroundColor Cyan
Write-Host "- Lead"
Write-Host "- LeadAttribution"
Write-Host "- unique lead por Organization + WhatsAppContact"
Write-Host "- WhatsApp waId como identidade de negocio"
Write-Host "- inboundMessageCount"
Write-Host "- primeira mensagem como origem do lead"
Write-Host "- Lead ATTRIBUTED"
Write-Host "- Lead EXCESS"
Write-Host "- NUMBER_UNASSIGNED excess"
Write-Host "- NO_RESERVED_CAPACITY excess"
Write-Host "- lock concorrente por identidade do lead"
Write-Host "- lock concorrente por WhatsApp number slot"
Write-Host "- FIFO dos microbatches"
Write-Host "- PLANNED -> DELIVERING"
Write-Host "- DELIVERING -> COMPLETED"
Write-Host "- deliveredLeadCount real"
Write-Host "- fulfilledLeadCount real"
Write-Host "- PROCESSING -> PARTIALLY_FULFILLED"
Write-Host "- PARTIALLY_FULFILLED -> FULFILLED"
Write-Host "- ads_request.completedAt"
Write-Host "- audit lead.attributed"
Write-Host "- audit lead.excess"
Write-Host "- audit ads_microbatch.completed"
Write-Host "- audit ads_request.fulfilled"
Write-Host "- lead.read"
Write-Host "- Leads API"
Write-Host "- Leads summary"
Write-Host "- Employee lead isolation"
Write-Host "- tenant isolation foundation"
Write-Host ""
Write-Host "Migration ainda NAO executada." -ForegroundColor Yellow
Write-Host "Prisma generate ainda NAO executado." -ForegroundColor Yellow
Write-Host "Nao rode CI ainda." -ForegroundColor Yellow
Write-Host ""
Write-Host "Proximo: Macrobloco 10.2 - migration, concorrencia, runtime e fechamento." -ForegroundColor Yellow