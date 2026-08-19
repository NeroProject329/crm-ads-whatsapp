Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Set-Location "C:\Projetos\crm-ads-whatsapp"

function Read-Text {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return Get-Content -Path $Path -Raw
}

function Write-Text {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    Set-Content `
        -Path $Path `
        -Value $Content `
        -Encoding UTF8
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

function Add-Lines-To-PrismaModel {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$ModelName,

        [Parameter(Mandatory = $true)]
        [string]$AnchorLine,

        [Parameter(Mandatory = $true)]
        [string]$Lines,

        [Parameter(Mandatory = $true)]
        [string]$Marker
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

    if (-not $Block.Contains($AnchorLine)) {
        throw "Anchor nao encontrado em model ${ModelName}: $AnchorLine"
    }

    $UpdatedBlock = $Block.Replace(
        $AnchorLine,
        $AnchorLine + "`r`n" + $Lines
    )

    $UpdatedContent = (
        $Content.Substring(
            0,
            $Match.Index
        ) +
        $UpdatedBlock +
        $Content.Substring(
            $Match.Index +
            $Match.Length
        )
    )

    Write-Text `
        -Path $Path `
        -Content $UpdatedContent
}

function Insert-After-PrismaBlock {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateSet("model", "enum")]
        [string]$Kind,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Insertion,

        [Parameter(Mandatory = $true)]
        [string]$Marker
    )

    $Content = Read-Text -Path $Path

    if ($Content.Contains($Marker)) {
        return
    }

    $Match = Get-PrismaBlock `
        -Content $Content `
        -Kind $Kind `
        -Name $Name

    $InsertAt = (
        $Match.Index +
        $Match.Length
    )

    $UpdatedContent = (
        $Content.Substring(
            0,
            $InsertAt
        ) +
        "`r`n`r`n" +
        $Insertion.Trim() +
        "`r`n" +
        $Content.Substring(
            $InsertAt
        )
    )

    Write-Text `
        -Path $Path `
        -Content $UpdatedContent
}

function Insert-Before-PrismaBlock {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateSet("model", "enum")]
        [string]$Kind,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Insertion,

        [Parameter(Mandatory = $true)]
        [string]$Marker
    )

    $Content = Read-Text -Path $Path

    if ($Content.Contains($Marker)) {
        return
    }

    $Match = Get-PrismaBlock `
        -Content $Content `
        -Kind $Kind `
        -Name $Name

    $UpdatedContent = (
        $Content.Substring(
            0,
            $Match.Index
        ) +
        $Insertion.Trim() +
        "`r`n`r`n" +
        $Content.Substring(
            $Match.Index
        )
    )

    Write-Text `
        -Path $Path `
        -Content $UpdatedContent
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " ETAPA 4 - MACROBLOCO 4.1" -ForegroundColor Cyan
Write-Host " ADS REQUESTS + PERSISTENT QUEUE" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

$SchemaPath = ".\packages\database\prisma\schema.prisma"
$SeedPath = ".\packages\database\prisma\seed.ts"
$VerifySeedPath = ".\packages\database\prisma\verify-seed.ts"
$ValidationIndexPath = ".\packages\validation\src\index.ts"
$ContractsIndexPath = ".\packages\contracts\src\index.ts"
$AuthorizationTypesPath = ".\apps\api\src\authorization\authorization.types.ts"
$AppModulePath = ".\apps\api\src\app.module.ts"

$BackupDirectory = ".\tmp\stage4-macroblock1-backup"

New-Item `
    -ItemType Directory `
    -Path $BackupDirectory `
    -Force |
    Out-Null

$BackupFiles = @(
    $SchemaPath,
    $SeedPath,
    $VerifySeedPath,
    $ValidationIndexPath,
    $ContractsIndexPath,
    $AuthorizationTypesPath,
    $AppModulePath
)

foreach ($File in $BackupFiles) {
    if (-not (Test-Path $File)) {
        throw "Arquivo obrigatorio nao encontrado: $File"
    }

    $BackupName = $File -replace '^[.][\\/]', ''
    $BackupName = $BackupName -replace '[\\/]', '__'

    $Destination = Join-Path `
        $BackupDirectory `
        $BackupName

    Copy-Item `
        -Path $File `
        -Destination $Destination `
        -Force
}

Write-Host "[OK] Backup criado." -ForegroundColor Green

# ============================================================
# PRISMA ENUMS
# ============================================================

$AdsEnums = @'
enum AdsRequestStatus {
  QUEUED
  PROCESSING
  PARTIALLY_FULFILLED
  FULFILLED
  CANCELLED
  FAILED
}

enum AdsQueueItemStatus {
  WAITING
  CLAIMED
  COMPLETED
  CANCELLED
  FAILED
}
'@

Insert-After-PrismaBlock `
    -Path $SchemaPath `
    -Kind "enum" `
    -Name "TrafficPoolMemberStatus" `
    -Insertion $AdsEnums `
    -Marker "enum AdsRequestStatus"

Write-Host "[OK] Enums ADS adicionados." -ForegroundColor Green

# ============================================================
# PRISMA RELATIONS
# ============================================================

Add-Lines-To-PrismaModel `
    -Path $SchemaPath `
    -ModelName "Organization" `
    -AnchorLine "  trafficPoolMembers TrafficPoolMember[]" `
    -Lines @'
  adsRequests         AdsRequest[]
  adsQueueItems       AdsQueueItem[]
'@ `
    -Marker "adsQueueItems"

Add-Lines-To-PrismaModel `
    -Path $SchemaPath `
    -ModelName "User" `
    -AnchorLine "  auditLogs    AuditLog[]" `
    -Lines @'
  requestedAdsRequests AdsRequest[]
'@ `
    -Marker "requestedAdsRequests"

Add-Lines-To-PrismaModel `
    -Path $SchemaPath `
    -ModelName "Employee" `
    -AnchorLine "  whatsAppNumbers WhatsAppNumber[]" `
    -Lines @'
  adsRequests         AdsRequest[]
  adsQueueItems       AdsQueueItem[]
'@ `
    -Marker "adsQueueItems"

Add-Lines-To-PrismaModel `
    -Path $SchemaPath `
    -ModelName "Site" `
    -AnchorLine "  trafficPools  TrafficPool[]" `
    -Lines @'
  adsRequests   AdsRequest[]
'@ `
    -Marker "adsRequests"

Add-Lines-To-PrismaModel `
    -Path $SchemaPath `
    -ModelName "TrafficPool" `
    -AnchorLine "  members      TrafficPoolMember[]" `
    -Lines @'
  adsRequests   AdsRequest[]
  adsQueueItems AdsQueueItem[]
'@ `
    -Marker "adsQueueItems"

Write-Host "[OK] Relacoes Prisma adicionadas." -ForegroundColor Green

# ============================================================
# PRISMA MODELS
# ============================================================

$AdsModels = @'
model AdsRequest {
  id                 String           @id @default(uuid()) @db.Uuid
  organizationId     String           @db.Uuid
  employeeId         String           @db.Uuid
  siteId             String           @db.Uuid
  trafficPoolId      String           @db.Uuid
  requestedByUserId  String           @db.Uuid
  requestedLeadCount Int
  fulfilledLeadCount Int              @default(0)
  status             AdsRequestStatus @default(QUEUED)
  notes              String?          @db.VarChar(500)
  queuedAt           DateTime         @default(now()) @db.Timestamptz(3)
  startedAt          DateTime?        @db.Timestamptz(3)
  completedAt        DateTime?        @db.Timestamptz(3)
  cancelledAt        DateTime?        @db.Timestamptz(3)
  failureReason      String?          @db.VarChar(500)
  createdAt          DateTime         @default(now()) @db.Timestamptz(3)
  updatedAt          DateTime         @updatedAt @db.Timestamptz(3)

  organization Organization @relation(fields: [organizationId], references: [id], onDelete: Restrict)
  employee     Employee     @relation(fields: [organizationId, employeeId], references: [organizationId, id], onDelete: Restrict)
  site         Site         @relation(fields: [organizationId, siteId], references: [organizationId, id], onDelete: Restrict)
  trafficPool  TrafficPool  @relation(fields: [organizationId, trafficPoolId], references: [organizationId, id], onDelete: Restrict)
  requestedBy  User         @relation(fields: [organizationId, requestedByUserId], references: [organizationId, id], onDelete: Restrict)
  queueItem    AdsQueueItem?

  @@unique([organizationId, id])
  @@index([organizationId, employeeId, status])
  @@index([organizationId, siteId, status])
  @@index([organizationId, trafficPoolId, status])
  @@index([organizationId, status, queuedAt])
  @@map("ads_requests")
}

model AdsQueueItem {
  id             String             @id @default(uuid()) @db.Uuid
  organizationId String             @db.Uuid
  adsRequestId   String             @db.Uuid
  employeeId     String             @db.Uuid
  trafficPoolId  String             @db.Uuid
  status         AdsQueueItemStatus @default(WAITING)
  priority       Int                @default(100)
  enqueuedAt     DateTime           @default(now()) @db.Timestamptz(3)
  availableAt    DateTime           @default(now()) @db.Timestamptz(3)
  claimedAt      DateTime?          @db.Timestamptz(3)
  completedAt    DateTime?          @db.Timestamptz(3)
  cancelledAt    DateTime?          @db.Timestamptz(3)
  attempts       Int                @default(0)
  createdAt      DateTime           @default(now()) @db.Timestamptz(3)
  updatedAt      DateTime           @updatedAt @db.Timestamptz(3)

  organization Organization @relation(fields: [organizationId], references: [id], onDelete: Restrict)
  adsRequest   AdsRequest   @relation(fields: [organizationId, adsRequestId], references: [organizationId, id], onDelete: Cascade)
  employee     Employee     @relation(fields: [organizationId, employeeId], references: [organizationId, id], onDelete: Restrict)
  trafficPool  TrafficPool  @relation(fields: [organizationId, trafficPoolId], references: [organizationId, id], onDelete: Restrict)

  @@unique([organizationId, id])
  @@unique([organizationId, adsRequestId])
  @@index([organizationId, status, priority, availableAt, enqueuedAt])
  @@index([organizationId, employeeId, status])
  @@index([organizationId, trafficPoolId, status])
  @@map("ads_queue_items")
}
'@

Insert-Before-PrismaBlock `
    -Path $SchemaPath `
    -Kind "model" `
    -Name "AuditLog" `
    -Insertion $AdsModels `
    -Marker "model AdsRequest {"

Write-Host "[OK] AdsRequest + AdsQueueItem adicionados." -ForegroundColor Green

# ============================================================
# SEED PERMISSIONS
# ============================================================

$SeedContent = Read-Text -Path $SeedPath

if (-not $SeedContent.Contains("'ads_request.read'")) {
    $PermissionAnchor = "  ['traffic_pool.manage', 'Gerenciar Traffic Pools'],"

    if (-not $SeedContent.Contains($PermissionAnchor)) {
        throw "Anchor das permissions nao encontrado no seed."
    }

    $PermissionReplacement = @'
  ['traffic_pool.manage', 'Gerenciar Traffic Pools'],
  ['ads_request.read', 'Visualizar pedidos de ADS autorizados'],
  ['ads_request.manage', 'Criar e gerenciar pedidos de ADS autorizados'],
  ['ads_queue.read', 'Visualizar fila de ADS autorizada'],
  ['ads_queue.manage', 'Gerenciar fila de ADS'],
'@

    $SeedContent = $SeedContent.Replace(
        $PermissionAnchor,
        $PermissionReplacement.TrimEnd()
    )
}

if (
    $SeedContent -notmatch
    "(?s)const employeePermissionCodes.*?'ads_request.manage'"
) {
    $EmployeePermissionAnchor = "    'traffic_pool.read',"

    if (-not $SeedContent.Contains($EmployeePermissionAnchor)) {
        throw "Anchor das permissions EMPLOYEE nao encontrado."
    }

    $EmployeePermissionReplacement = @'
    'traffic_pool.read',
    'ads_request.read',
    'ads_request.manage',
    'ads_queue.read',
'@

    $SeedContent = $SeedContent.Replace(
        $EmployeePermissionAnchor,
        $EmployeePermissionReplacement.TrimEnd()
    )
}

Write-Text `
    -Path $SeedPath `
    -Content $SeedContent

Write-Host "[OK] Seed atualizado: 23 permissions / EMPLOYEE 9." -ForegroundColor Green

# ============================================================
# VERIFY SEED
# ============================================================

$VerifyContent = Read-Text -Path $VerifySeedPath

$ExpectedPermissions = @'
const expectedPermissionCodes = [
  'ads_queue.manage',
  'ads_queue.read',
  'ads_request.manage',
  'ads_request.read',
  'audit.read',
  'domain.manage',
  'domain.read',
  'employee.manage',
  'employee.read',
  'organization.manage',
  'organization.read',
  'profile.read',
  'profile.update',
  'site.manage',
  'site.read',
  'team.manage',
  'team.read',
  'traffic_pool.manage',
  'traffic_pool.read',
  'user.manage',
  'user.read',
  'whatsapp_number.manage',
  'whatsapp_number.read',
] as const;
'@

$PermissionRegex = New-Object System.Text.RegularExpressions.Regex(
    'const expectedPermissionCodes = \[.*?\] as const;',
    [System.Text.RegularExpressions.RegexOptions]::Singleline
)

if (-not $PermissionRegex.IsMatch($VerifyContent)) {
    throw "expectedPermissionCodes nao encontrado em verify-seed.ts."
}

$VerifyContent = $PermissionRegex.Replace(
    $VerifyContent,
    $ExpectedPermissions.Trim(),
    1
)

$ExpectedEmployeePermissions = @'
const expectedEmployeePermissionCodes = [
  'ads_queue.read',
  'ads_request.manage',
  'ads_request.read',
  'domain.read',
  'profile.read',
  'profile.update',
  'site.read',
  'traffic_pool.read',
  'whatsapp_number.read',
] as const;
'@

$EmployeePermissionRegex = New-Object System.Text.RegularExpressions.Regex(
    'const expectedEmployeePermissionCodes = \[.*?\] as const;',
    [System.Text.RegularExpressions.RegexOptions]::Singleline
)

if (-not $EmployeePermissionRegex.IsMatch($VerifyContent)) {
    throw "expectedEmployeePermissionCodes nao encontrado em verify-seed.ts."
}

$VerifyContent = $EmployeePermissionRegex.Replace(
    $VerifyContent,
    $ExpectedEmployeePermissions.Trim(),
    1
)

$VerifyContent = $VerifyContent.Replace(
    "Permission catalog does not match the Stage 3 seed.",
    "Permission catalog does not match the Stage 4 seed."
)

$VerifyContent = $VerifyContent.Replace(
    "ADMIN must receive every Stage 3 permission.",
    "ADMIN must receive every Stage 4 permission."
)

$VerifyContent = $VerifyContent.Replace(
    "EMPLOYEE permissions do not match Stage 3.",
    "EMPLOYEE permissions do not match Stage 4."
)

Write-Text `
    -Path $VerifySeedPath `
    -Content $VerifyContent

Write-Host "[OK] verify-seed atualizado." -ForegroundColor Green

# ============================================================
# AUTHORIZATION TYPES
# ============================================================

$AuthorizationTypes = Read-Text -Path $AuthorizationTypesPath

if (-not $AuthorizationTypes.Contains("'ads_request.read'")) {
    $PermissionTypeAnchor = "  | 'traffic_pool.manage';"

    if (-not $AuthorizationTypes.Contains($PermissionTypeAnchor)) {
        throw "Anchor PermissionCode nao encontrado."
    }

    $PermissionTypeReplacement = @'
  | 'traffic_pool.manage'
  | 'ads_request.read'
  | 'ads_request.manage'
  | 'ads_queue.read'
  | 'ads_queue.manage';
'@

    $AuthorizationTypes = $AuthorizationTypes.Replace(
        $PermissionTypeAnchor,
        $PermissionTypeReplacement.TrimEnd()
    )

    Write-Text `
        -Path $AuthorizationTypesPath `
        -Content $AuthorizationTypes
}

Write-Host "[OK] PermissionCode atualizado para ADS." -ForegroundColor Green

# ============================================================
# VALIDATION
# ============================================================

$ValidationDirectory = ".\packages\validation\src"

$AdsValidation = @'
import { z } from 'zod';

const uuidSchema = z.string().uuid();

const requestedLeadCountSchema = z.number().int().min(1).max(100_000);

const adsRequestNotesSchema = z.string().trim().max(500).nullable();

export const createAdsRequestSchema = z
  .object({
    siteId: uuidSchema,
    trafficPoolId: uuidSchema,
    requestedLeadCount: requestedLeadCountSchema,
    notes: adsRequestNotesSchema.optional(),
  })
  .strict();

export type CreateAdsRequestInput = z.infer<typeof createAdsRequestSchema>;
'@

Write-Text `
    -Path "$ValidationDirectory\ads.ts" `
    -Content $AdsValidation

$AdsValidationTest = @'
import { describe, expect, it } from 'vitest';

import { createAdsRequestSchema } from './ads.js';

const siteId = '11111111-1111-4111-8111-111111111111';

const trafficPoolId = '22222222-2222-4222-8222-222222222222';

describe('ADS request validation', () => {
  it('accepts a valid request', () => {
    const result = createAdsRequestSchema.safeParse({
      siteId,
      trafficPoolId,
      requestedLeadCount: 100,
      notes: 'Campanha principal',
    });

    expect(result.success).toBe(true);
  });

  it.each([0, -1, 100_001, 1.5])(
    'rejects invalid requestedLeadCount %s',
    (requestedLeadCount) => {
      const result = createAdsRequestSchema.safeParse({
        siteId,
        trafficPoolId,
        requestedLeadCount,
      });

      expect(result.success).toBe(false);
    },
  );

  it('rejects tenant injection', () => {
    const result = createAdsRequestSchema.safeParse({
      siteId,
      trafficPoolId,
      requestedLeadCount: 100,
      organizationId: '33333333-3333-4333-8333-333333333333',
    });

    expect(result.success).toBe(false);
  });
});
'@

Write-Text `
    -Path "$ValidationDirectory\ads.spec.ts" `
    -Content $AdsValidationTest

$ValidationIndex = Read-Text -Path $ValidationIndexPath

if (-not $ValidationIndex.Contains("export * from './ads.js';")) {
    $ValidationIndex = (
        $ValidationIndex.TrimEnd() +
        "`r`n`r`nexport * from './ads.js';`r`n"
    )

    Write-Text `
        -Path $ValidationIndexPath `
        -Content $ValidationIndex
}

Write-Host "[OK] Validation ADS criada." -ForegroundColor Green

# ============================================================
# CONTRACTS
# ============================================================

$ContractsDirectory = ".\packages\contracts\src"

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
  completedAt: string | null;
  cancelledAt: string | null;
  adsRequest: AdsQueueRequestSummaryResponse;
  createdAt: string;
  updatedAt: string;
}>;

export type AdsQueueListResponse = readonly AdsQueueItemResponse[];
'@

Write-Text `
    -Path "$ContractsDirectory\ads.ts" `
    -Content $AdsContracts

$ContractsIndex = Read-Text -Path $ContractsIndexPath

if (-not $ContractsIndex.Contains("export * from './ads.js';")) {
    $ContractsIndex = (
        $ContractsIndex.TrimEnd() +
        "`r`n`r`nexport * from './ads.js';`r`n"
    )

    Write-Text `
        -Path $ContractsIndexPath `
        -Content $ContractsIndex
}

Write-Host "[OK] Contracts ADS criados." -ForegroundColor Green

# ============================================================
# API
# ============================================================

$AdsApiDirectory = ".\apps\api\src\ads"

New-Item `
    -ItemType Directory `
    -Path $AdsApiDirectory `
    -Force |
    Out-Null

$AdsService = @'
import {
  ConflictException,
  ForbiddenException,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';

import type { AuthenticatedPrincipal } from '@crm/auth';

import type {
  AdsQueueItemModel,
  AdsRequestModel,
  EmployeeModel,
  SiteModel,
  TrafficPoolModel,
} from '@crm/database';

import type {
  AdsQueueItemResponse,
  AdsQueueListResponse,
  AdsRequestListResponse,
  AdsRequestResponse,
} from '@crm/contracts';

import type { CreateAdsRequestInput } from '@crm/validation';

import { DatabaseService } from '../database/database.service.js';

type LoadedAdsRequest = AdsRequestModel & {
  employee: EmployeeModel;
  site: SiteModel;
  trafficPool: TrafficPoolModel;
  queueItem: AdsQueueItemModel | null;
};

type LoadedAdsQueueItem = AdsQueueItemModel & {
  adsRequest: AdsRequestModel;
};

type SiteWithOwner = SiteModel & {
  ownerEmployee: EmployeeModel;
};

@Injectable()
export class AdsService {
  constructor(
    @Inject(DatabaseService)
    private readonly database: DatabaseService,
  ) {}

  async listRequests(
    principal: AuthenticatedPrincipal,
  ): Promise<AdsRequestListResponse> {
    const employeeId = this.isAdmin(principal)
      ? null
      : await this.getCurrentEmployeeId(principal);

    const requests = await this.database.client.adsRequest.findMany({
      where: {
        organizationId: principal.organizationId,

        ...(employeeId
          ? {
              employeeId,
            }
          : {}),
      },

      include: {
        employee: true,
        site: true,
        trafficPool: true,
        queueItem: true,
      },

      orderBy: [
        {
          queuedAt: 'desc',
        },
        {
          id: 'desc',
        },
      ],
    });

    return requests.map((request) => this.mapRequest(request));
  }

  async getRequest(
    principal: AuthenticatedPrincipal,
    requestId: string,
  ): Promise<AdsRequestResponse> {
    const request = await this.getAccessibleRequest(principal, requestId);

    return this.mapRequest(request);
  }

  async createRequest(
    principal: AuthenticatedPrincipal,
    input: CreateAdsRequestInput,
  ): Promise<AdsRequestResponse> {
    const site = await this.getRequestSite(
      principal.organizationId,
      input.siteId,
    );

    if (site.status !== 'ACTIVE') {
      throw new ConflictException({
        code: 'ADS_REQUEST_SITE_NOT_ACTIVE',
        message: 'ADS requests require an ACTIVE site.',
      });
    }

    if (
      site.ownerEmployee.status !== 'ACTIVE' ||
      site.ownerEmployee.deletedAt !== null
    ) {
      throw new ConflictException({
        code: 'ADS_REQUEST_EMPLOYEE_NOT_ACTIVE',
        message: 'The site owner must be an ACTIVE employee.',
      });
    }

    if (!this.isAdmin(principal)) {
      const currentEmployeeId = await this.getCurrentEmployeeId(principal);

      if (site.ownerEmployeeId !== currentEmployeeId) {
        throw new ForbiddenException({
          code: 'ADS_REQUEST_SITE_FORBIDDEN',
          message: 'Employees can request ADS only for their own sites.',
        });
      }
    }

    const trafficPool = await this.database.client.trafficPool.findFirst({
      where: {
        id: input.trafficPoolId,
        organizationId: principal.organizationId,
        siteId: site.id,
        deletedAt: null,
      },
    });

    if (!trafficPool) {
      throw new NotFoundException({
        code: 'ADS_REQUEST_TRAFFIC_POOL_NOT_FOUND',
        message: 'Traffic Pool was not found for this site.',
      });
    }

    if (trafficPool.status !== 'ACTIVE') {
      throw new ConflictException({
        code: 'ADS_REQUEST_TRAFFIC_POOL_NOT_ACTIVE',
        message: 'ADS requests require an ACTIVE Traffic Pool.',
      });
    }

    const eligibleMember =
      await this.database.client.trafficPoolMember.findFirst({
        where: {
          organizationId: principal.organizationId,
          trafficPoolId: trafficPool.id,
          status: 'ACTIVE',

          whatsAppNumber: {
            deletedAt: null,
            status: 'ACTIVE',
            assignedEmployeeId: site.ownerEmployeeId,
          },
        },

        select: {
          id: true,
        },
      });

    if (!eligibleMember) {
      throw new ConflictException({
        code: 'ADS_REQUEST_NO_ELIGIBLE_NUMBER',
        message:
          'Traffic Pool does not contain an eligible ACTIVE WhatsApp number.',
      });
    }

    const result = await this.database.client.$transaction(
      async (transaction) => {
        const request = await transaction.adsRequest.create({
          data: {
            organizationId: principal.organizationId,
            employeeId: site.ownerEmployeeId,
            siteId: site.id,
            trafficPoolId: trafficPool.id,
            requestedByUserId: principal.userId,
            requestedLeadCount: input.requestedLeadCount,
            notes: input.notes ?? null,
          },
        });

        const queueItem = await transaction.adsQueueItem.create({
          data: {
            organizationId: principal.organizationId,
            adsRequestId: request.id,
            employeeId: site.ownerEmployeeId,
            trafficPoolId: trafficPool.id,
          },
        });

        await transaction.auditLog.create({
          data: {
            organizationId: principal.organizationId,
            actorType: 'USER',
            actorUserId: principal.userId,
            action: 'ads_request.created',
            resourceType: 'ads_request',
            resourceId: request.id,
            outcome: 'SUCCESS',

            metadata: {
              employeeId: site.ownerEmployeeId,
              siteId: site.id,
              trafficPoolId: trafficPool.id,
              requestedLeadCount: input.requestedLeadCount,
            },
          },
        });

        await transaction.auditLog.create({
          data: {
            organizationId: principal.organizationId,
            actorType: 'USER',
            actorUserId: principal.userId,
            action: 'ads_queue.enqueued',
            resourceType: 'ads_queue_item',
            resourceId: queueItem.id,
            outcome: 'SUCCESS',

            metadata: {
              adsRequestId: request.id,
              employeeId: site.ownerEmployeeId,
              trafficPoolId: trafficPool.id,
              priority: queueItem.priority,
            },
          },
        });

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
      },
    );

    return this.mapRequest(result);
  }

  async cancelRequest(
    principal: AuthenticatedPrincipal,
    requestId: string,
  ): Promise<AdsRequestResponse> {
    const request = await this.getAccessibleRequest(principal, requestId);

    if (request.status === 'CANCELLED') {
      return this.mapRequest(request);
    }

    if (request.status !== 'QUEUED') {
      throw new ConflictException({
        code: 'ADS_REQUEST_NOT_CANCELLABLE',
        message:
          'Only QUEUED ADS requests can be cancelled during Stage 4.',
      });
    }

    if (!request.queueItem || request.queueItem.status !== 'WAITING') {
      throw new ConflictException({
        code: 'ADS_QUEUE_ITEM_NOT_CANCELLABLE',
        message: 'The ADS queue item is no longer WAITING.',
      });
    }

    const queueItemId = request.queueItem.id;
    const now = new Date();

    const updated = await this.database.client.$transaction(
      async (transaction) => {
        await transaction.adsRequest.update({
          where: {
            id: request.id,
          },

          data: {
            status: 'CANCELLED',
            cancelledAt: now,
          },
        });

        const queueUpdate = await transaction.adsQueueItem.updateMany({
          where: {
            organizationId: principal.organizationId,
            adsRequestId: request.id,
            status: 'WAITING',
          },

          data: {
            status: 'CANCELLED',
            cancelledAt: now,
          },
        });

        if (queueUpdate.count !== 1) {
          throw new ConflictException({
            code: 'ADS_QUEUE_CANCEL_CONFLICT',
            message:
              'The queue item changed before cancellation could complete.',
          });
        }

        await transaction.auditLog.create({
          data: {
            organizationId: principal.organizationId,
            actorType: 'USER',
            actorUserId: principal.userId,
            action: 'ads_request.cancelled',
            resourceType: 'ads_request',
            resourceId: request.id,
            outcome: 'SUCCESS',
          },
        });

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
      },
    );

    return this.mapRequest(updated);
  }

  async listQueue(
    principal: AuthenticatedPrincipal,
  ): Promise<AdsQueueListResponse> {
    const employeeId = this.isAdmin(principal)
      ? null
      : await this.getCurrentEmployeeId(principal);

    const items = await this.database.client.adsQueueItem.findMany({
      where: {
        organizationId: principal.organizationId,

        ...(employeeId
          ? {
              employeeId,
            }
          : {}),
      },

      include: {
        adsRequest: true,
      },

      orderBy: [
        {
          priority: 'asc',
        },
        {
          availableAt: 'asc',
        },
        {
          enqueuedAt: 'asc',
        },
        {
          id: 'asc',
        },
      ],
    });

    return items.map((item) => this.mapQueueItem(item));
  }

  async getQueueItem(
    principal: AuthenticatedPrincipal,
    queueItemId: string,
  ): Promise<AdsQueueItemResponse> {
    const employeeId = this.isAdmin(principal)
      ? null
      : await this.getCurrentEmployeeId(principal);

    const item = await this.database.client.adsQueueItem.findFirst({
      where: {
        id: queueItemId,
        organizationId: principal.organizationId,

        ...(employeeId
          ? {
              employeeId,
            }
          : {}),
      },

      include: {
        adsRequest: true,
      },
    });

    if (!item) {
      throw new NotFoundException({
        code: 'ADS_QUEUE_ITEM_NOT_FOUND',
        message: 'ADS queue item not found.',
      });
    }

    return this.mapQueueItem(item);
  }

  private async getAccessibleRequest(
    principal: AuthenticatedPrincipal,
    requestId: string,
  ): Promise<LoadedAdsRequest> {
    const employeeId = this.isAdmin(principal)
      ? null
      : await this.getCurrentEmployeeId(principal);

    const request = await this.database.client.adsRequest.findFirst({
      where: {
        id: requestId,
        organizationId: principal.organizationId,

        ...(employeeId
          ? {
              employeeId,
            }
          : {}),
      },

      include: {
        employee: true,
        site: true,
        trafficPool: true,
        queueItem: true,
      },
    });

    if (!request) {
      throw new NotFoundException({
        code: 'ADS_REQUEST_NOT_FOUND',
        message: 'ADS request not found.',
      });
    }

    return request;
  }

  private async getRequestSite(
    organizationId: string,
    siteId: string,
  ): Promise<SiteWithOwner> {
    const site = await this.database.client.site.findFirst({
      where: {
        id: siteId,
        organizationId,
        deletedAt: null,
      },

      include: {
        ownerEmployee: true,
      },
    });

    if (!site) {
      throw new NotFoundException({
        code: 'ADS_REQUEST_SITE_NOT_FOUND',
        message: 'Site not found.',
      });
    }

    return site;
  }

  private async getCurrentEmployeeId(
    principal: AuthenticatedPrincipal,
  ): Promise<string> {
    const employee = await this.database.client.employee.findFirst({
      where: {
        organizationId: principal.organizationId,
        userId: principal.userId,
        status: 'ACTIVE',
        deletedAt: null,
      },

      select: {
        id: true,
      },
    });

    if (!employee) {
      throw new ForbiddenException({
        code: 'EMPLOYEE_PROFILE_REQUIRED',
        message: 'An active employee profile is required.',
      });
    }

    return employee.id;
  }

  private isAdmin(principal: AuthenticatedPrincipal): boolean {
    return principal.roles.includes('ADMIN');
  }

  private mapRequest(request: LoadedAdsRequest): AdsRequestResponse {
    return {
      id: request.id,
      organizationId: request.organizationId,
      employeeId: request.employeeId,
      siteId: request.siteId,
      trafficPoolId: request.trafficPoolId,
      requestedByUserId: request.requestedByUserId,
      requestedLeadCount: request.requestedLeadCount,
      fulfilledLeadCount: request.fulfilledLeadCount,
      status: request.status,
      notes: request.notes,
      queuedAt: request.queuedAt.toISOString(),
      startedAt: request.startedAt?.toISOString() ?? null,
      completedAt: request.completedAt?.toISOString() ?? null,
      cancelledAt: request.cancelledAt?.toISOString() ?? null,
      failureReason: request.failureReason,

      site: {
        id: request.site.id,
        name: request.site.name,
        slug: request.site.slug,
      },

      trafficPool: {
        id: request.trafficPool.id,
        name: request.trafficPool.name,
        slug: request.trafficPool.slug,
      },

      employee: {
        id: request.employee.id,
        employeeCode: request.employee.employeeCode,
      },

      queueItem: request.queueItem
        ? {
            id: request.queueItem.id,
            status: request.queueItem.status,
            priority: request.queueItem.priority,
            attempts: request.queueItem.attempts,
            enqueuedAt: request.queueItem.enqueuedAt.toISOString(),
            availableAt: request.queueItem.availableAt.toISOString(),
            claimedAt: request.queueItem.claimedAt?.toISOString() ?? null,
            completedAt:
              request.queueItem.completedAt?.toISOString() ?? null,
            cancelledAt:
              request.queueItem.cancelledAt?.toISOString() ?? null,
          }
        : null,

      createdAt: request.createdAt.toISOString(),
      updatedAt: request.updatedAt.toISOString(),
    };
  }

  private mapQueueItem(item: LoadedAdsQueueItem): AdsQueueItemResponse {
    return {
      id: item.id,
      organizationId: item.organizationId,
      adsRequestId: item.adsRequestId,
      employeeId: item.employeeId,
      trafficPoolId: item.trafficPoolId,
      status: item.status,
      priority: item.priority,
      attempts: item.attempts,
      enqueuedAt: item.enqueuedAt.toISOString(),
      availableAt: item.availableAt.toISOString(),
      claimedAt: item.claimedAt?.toISOString() ?? null,
      completedAt: item.completedAt?.toISOString() ?? null,
      cancelledAt: item.cancelledAt?.toISOString() ?? null,

      adsRequest: {
        id: item.adsRequest.id,
        status: item.adsRequest.status,
        requestedLeadCount: item.adsRequest.requestedLeadCount,
        fulfilledLeadCount: item.adsRequest.fulfilledLeadCount,
      },

      createdAt: item.createdAt.toISOString(),
      updatedAt: item.updatedAt.toISOString(),
    };
  }
}
'@

Write-Text `
    -Path "$AdsApiDirectory\ads.service.ts" `
    -Content $AdsService

$AdsRequestsController = @'
import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Inject,
  Param,
  ParseUUIDPipe,
  Post,
  UseGuards,
} from '@nestjs/common';

import type { AuthenticatedPrincipal } from '@crm/auth';

import type {
  AdsRequestListResponse,
  AdsRequestResponse,
} from '@crm/contracts';

import { createAdsRequestSchema } from '@crm/validation';

import { AccessTokenGuard } from '../authorization/access-token.guard.js';
import { AuthorizationGuard } from '../authorization/authorization.guard.js';
import { CurrentPrincipal } from '../authorization/current-principal.decorator.js';
import { RequirePermissions } from '../authorization/require-permissions.decorator.js';

import { AdsService } from './ads.service.js';

@Controller('ads-requests')
@UseGuards(AccessTokenGuard, AuthorizationGuard)
export class AdsRequestsController {
  constructor(
    @Inject(AdsService)
    private readonly service: AdsService,
  ) {}

  @Get()
  @RequirePermissions('ads_request.read')
  list(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,
  ): Promise<AdsRequestListResponse> {
    return this.service.listRequests(principal);
  }

  @Get(':requestId')
  @RequirePermissions('ads_request.read')
  getById(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('requestId', new ParseUUIDPipe())
    requestId: string,
  ): Promise<AdsRequestResponse> {
    return this.service.getRequest(principal, requestId);
  }

  @Post()
  @RequirePermissions('ads_request.manage')
  create(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Body()
    body: unknown,
  ): Promise<AdsRequestResponse> {
    const parsed = createAdsRequestSchema.safeParse(body);

    if (!parsed.success) {
      throw new BadRequestException({
        code: 'ADS_REQUEST_VALIDATION_ERROR',
        message: 'Invalid ADS request payload.',

        issues: parsed.error.issues.map((issue) => ({
          code: issue.code,
          path: issue.path.map(String).join('.'),
        })),
      });
    }

    return this.service.createRequest(principal, parsed.data);
  }

  @Post(':requestId/cancel')
  @RequirePermissions('ads_request.manage')
  cancel(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('requestId', new ParseUUIDPipe())
    requestId: string,
  ): Promise<AdsRequestResponse> {
    return this.service.cancelRequest(principal, requestId);
  }
}
'@

Write-Text `
    -Path "$AdsApiDirectory\ads-requests.controller.ts" `
    -Content $AdsRequestsController

$AdsQueueController = @'
import {
  Controller,
  Get,
  Inject,
  Param,
  ParseUUIDPipe,
  UseGuards,
} from '@nestjs/common';

import type { AuthenticatedPrincipal } from '@crm/auth';

import type {
  AdsQueueItemResponse,
  AdsQueueListResponse,
} from '@crm/contracts';

import { AccessTokenGuard } from '../authorization/access-token.guard.js';
import { AuthorizationGuard } from '../authorization/authorization.guard.js';
import { CurrentPrincipal } from '../authorization/current-principal.decorator.js';
import { RequirePermissions } from '../authorization/require-permissions.decorator.js';

import { AdsService } from './ads.service.js';

@Controller('ads-queue')
@UseGuards(AccessTokenGuard, AuthorizationGuard)
export class AdsQueueController {
  constructor(
    @Inject(AdsService)
    private readonly service: AdsService,
  ) {}

  @Get()
  @RequirePermissions('ads_queue.read')
  list(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,
  ): Promise<AdsQueueListResponse> {
    return this.service.listQueue(principal);
  }

  @Get(':queueItemId')
  @RequirePermissions('ads_queue.read')
  getById(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('queueItemId', new ParseUUIDPipe())
    queueItemId: string,
  ): Promise<AdsQueueItemResponse> {
    return this.service.getQueueItem(principal, queueItemId);
  }
}
'@

Write-Text `
    -Path "$AdsApiDirectory\ads-queue.controller.ts" `
    -Content $AdsQueueController

$AdsModule = @'
import { Module } from '@nestjs/common';

import { AuthorizationModule } from '../authorization/authorization.module.js';
import { DatabaseModule } from '../database/database.module.js';

import { AdsQueueController } from './ads-queue.controller.js';
import { AdsRequestsController } from './ads-requests.controller.js';
import { AdsService } from './ads.service.js';

@Module({
  imports: [AuthorizationModule, DatabaseModule],

  controllers: [AdsRequestsController, AdsQueueController],

  providers: [AdsService],

  exports: [AdsService],
})
export class AdsModule {}
'@

Write-Text `
    -Path "$AdsApiDirectory\ads.module.ts" `
    -Content $AdsModule

Write-Host "[OK] API ADS criada." -ForegroundColor Green

# ============================================================
# APP MODULE
# ============================================================

$AppModule = Read-Text -Path $AppModulePath

$TrafficPoolImport = "import { TrafficPoolsModule } from './traffic-pools/traffic-pools.module.js';"

if (-not $AppModule.Contains("from './ads/ads.module.js';")) {
    if (-not $AppModule.Contains($TrafficPoolImport)) {
        throw "Import TrafficPoolsModule nao encontrado no AppModule."
    }

    $AppModule = $AppModule.Replace(
        $TrafficPoolImport,
        $TrafficPoolImport +
        "`r`n`r`n" +
        "import { AdsModule } from './ads/ads.module.js';"
    )
}

$ImportsRegex = New-Object System.Text.RegularExpressions.Regex(
    'imports:\s*\[(?<body>.*?)\]',
    [System.Text.RegularExpressions.RegexOptions]::Singleline
)

$ImportsMatch = $ImportsRegex.Match($AppModule)

if (-not $ImportsMatch.Success) {
    throw "Array imports do AppModule nao encontrado."
}

if (-not $ImportsMatch.Groups["body"].Value.Contains("AdsModule")) {
    $CurrentImports = $ImportsMatch.Groups["body"].Value.Trim()
    $CurrentImports = $CurrentImports.TrimEnd(",")

    $NewImports = "imports: [" + $CurrentImports + ", AdsModule]"

    $AppModule = (
        $AppModule.Substring(
            0,
            $ImportsMatch.Index
        ) +
        $NewImports +
        $AppModule.Substring(
            $ImportsMatch.Index +
            $ImportsMatch.Length
        )
    )
}

Write-Text `
    -Path $AppModulePath `
    -Content $AppModule

Write-Host "[OK] AdsModule registrado no AppModule." -ForegroundColor Green

# ============================================================
# STRUCTURAL VALIDATION
# ============================================================

$RequiredFiles = @(
    ".\packages\validation\src\ads.ts",
    ".\packages\validation\src\ads.spec.ts",
    ".\packages\contracts\src\ads.ts",
    ".\apps\api\src\ads\ads.service.ts",
    ".\apps\api\src\ads\ads-requests.controller.ts",
    ".\apps\api\src\ads\ads-queue.controller.ts",
    ".\apps\api\src\ads\ads.module.ts"
)

foreach ($RequiredFile in $RequiredFiles) {
    if (-not (Test-Path $RequiredFile)) {
        throw "Arquivo esperado nao criado: $RequiredFile"
    }
}

$SchemaFinal = Read-Text -Path $SchemaPath

$SchemaMarkers = @(
    "enum AdsRequestStatus",
    "enum AdsQueueItemStatus",
    "model AdsRequest",
    "model AdsQueueItem",
    '@@map("ads_requests")',
    '@@map("ads_queue_items")'
)

foreach ($Marker in $SchemaMarkers) {
    if (-not $SchemaFinal.Contains($Marker)) {
        throw "Marker ausente no schema: $Marker"
    }
}

$SeedFinal = Read-Text -Path $SeedPath

$RequiredPermissions = @(
    "ads_request.read",
    "ads_request.manage",
    "ads_queue.read",
    "ads_queue.manage"
)

foreach ($Permission in $RequiredPermissions) {
    if (-not $SeedFinal.Contains($Permission)) {
        throw "Permission ausente no seed: $Permission"
    }
}

$AuthorizationFinal = Read-Text -Path $AuthorizationTypesPath

foreach ($Permission in $RequiredPermissions) {
    if (-not $AuthorizationFinal.Contains($Permission)) {
        throw "Permission ausente em PermissionCode: $Permission"
    }
}

$ValidationFinal = Read-Text -Path $ValidationIndexPath

if (-not $ValidationFinal.Contains("export * from './ads.js';")) {
    throw "Export ADS ausente em validation."
}

$ContractsFinal = Read-Text -Path $ContractsIndexPath

if (-not $ContractsFinal.Contains("export * from './ads.js';")) {
    throw "Export ADS ausente em contracts."
}

$AppModuleFinal = Read-Text -Path $AppModulePath

if (-not $AppModuleFinal.Contains("AdsModule")) {
    throw "AdsModule nao encontrado no AppModule."
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host "[OK] MACROBLOCO 4.1 CRIADO." -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Implementado:" -ForegroundColor Cyan
Write-Host "- AdsRequest"
Write-Host "- AdsQueueItem"
Write-Host "- lifecycle futuro preparado"
Write-Host "- 4 permissions ADS"
Write-Host "- PermissionCode atualizado"
Write-Host "- EMPLOYEE: request read/manage + queue read"
Write-Host "- Zod validation"
Write-Host "- tenant injection bloqueada"
Write-Host "- contracts"
Write-Host "- request + queue transacionais"
Write-Host "- eligibility"
Write-Host "- cancelamento transacional"
Write-Host "- audit logs"
Write-Host "- ADMIN/EMPLOYEE scoping"
Write-Host "- persistent deterministic queue ordering"
Write-Host ""
Write-Host "Migration ainda NAO executada." -ForegroundColor Yellow
Write-Host "Proximo passo: Macrobloco 4.2." -ForegroundColor Yellow