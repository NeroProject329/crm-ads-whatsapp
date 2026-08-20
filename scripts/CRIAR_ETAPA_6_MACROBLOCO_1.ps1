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
        $InsertAt = $Block.LastIndexOf("}")
    }

    if ($InsertAt -lt 0) {
        throw "Fechamento do model $ModelName nao encontrado."
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

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " ETAPA 6 - MACROBLOCO 6.1" -ForegroundColor Cyan
Write-Host " SITE MONITORING" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

$SchemaPath = ".\packages\database\prisma\schema.prisma"
$ContractsIndexPath = ".\packages\contracts\src\index.ts"
$ValidationIndexPath = ".\packages\validation\src\index.ts"
$SitesServicePath = ".\apps\api\src\sites\sites.service.ts"
$SitesModulePath = ".\apps\api\src\sites\sites.module.ts"
$AdsSchedulerPath = ".\apps\worker\src\ads-scheduler.service.ts"
$MonitorPackagePath = ".\apps\site-monitor-worker\package.json"
$EnvExamplePath = ".\.env.example"

$BackupDirectory = ".\tmp\stage6-macroblock1-backup"

if (-not (Test-Path $BackupDirectory)) {
    New-Item -ItemType Directory -Path $BackupDirectory -Force | Out-Null

    $BackupFiles = @(
        $SchemaPath,
        $ContractsIndexPath,
        $ValidationIndexPath,
        $SitesServicePath,
        $SitesModulePath,
        $AdsSchedulerPath,
        $MonitorPackagePath,
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

Write-Host "[OK] Backup Stage 6 preparado." -ForegroundColor Green

# ============================================================
# PRISMA ENUMS
# ============================================================

$MonitorEnums = @'
enum SiteMonitorStatus {
  UNKNOWN
  HEALTHY
  DEGRADED
  DOWN
}

enum SiteMonitorCheckOutcome {
  SUCCESS
  FAILURE
}

enum SiteMonitorIncidentStatus {
  OPEN
  RESOLVED
}
'@

Insert-AfterPrismaBlock `
    -Path $SchemaPath `
    -Kind "enum" `
    -Name "SiteDomainStatus" `
    -Marker "enum SiteMonitorStatus" `
    -Insertion $MonitorEnums

Write-Host "[OK] Enums de monitoramento adicionados." -ForegroundColor Green

# ============================================================
# PRISMA RELATIONS + DOMAIN SWITCH
# ============================================================

Add-ToPrismaModel `
    -Path $SchemaPath `
    -ModelName "Organization" `
    -Marker "siteMonitorStates" `
    -Insertion @'
  siteMonitorStates    SiteMonitorState[]
  siteMonitorChecks    SiteMonitorCheck[]
  siteMonitorIncidents SiteMonitorIncident[]
'@

Add-ToPrismaModel `
    -Path $SchemaPath `
    -ModelName "Site" `
    -Marker "monitorStates" `
    -Insertion @'
  monitorStates    SiteMonitorState[]
  monitorChecks    SiteMonitorCheck[]
  monitorIncidents SiteMonitorIncident[]
'@

Add-ToPrismaModel `
    -Path $SchemaPath `
    -ModelName "SiteDomain" `
    -Marker "monitoringEnabled" `
    -Insertion @'
  monitoringEnabled Boolean @default(true)

  monitorState     SiteMonitorState?
  monitorChecks    SiteMonitorCheck[]
  monitorIncidents SiteMonitorIncident[]
'@

Write-Host "[OK] Relacoes de monitoramento adicionadas." -ForegroundColor Green

# ============================================================
# PRISMA MONITOR MODELS
# ============================================================

$MonitorModels = @'
model SiteMonitorState {
  id                   String            @id @default(uuid()) @db.Uuid
  organizationId       String            @db.Uuid
  siteId               String            @db.Uuid
  siteDomainId         String            @db.Uuid
  status               SiteMonitorStatus @default(UNKNOWN)
  consecutiveFailures  Int               @default(0)
  consecutiveSuccesses Int               @default(0)
  lastCheckedAt        DateTime?         @db.Timestamptz(3)
  lastSuccessAt        DateTime?         @db.Timestamptz(3)
  lastFailureAt        DateTime?         @db.Timestamptz(3)
  lastHttpStatus       Int?
  lastLatencyMs        Int?
  lastResolvedAddress  String?           @db.VarChar(80)
  lastFailureCode      String?           @db.VarChar(80)
  lastFailureMessage   String?           @db.VarChar(500)
  downSince            DateTime?         @db.Timestamptz(3)
  recoveredAt          DateTime?         @db.Timestamptz(3)
  nextCheckAt          DateTime          @default(now()) @db.Timestamptz(3)
  claimedAt            DateTime?         @db.Timestamptz(3)
  claimedByWorkerId    String?           @db.VarChar(120)
  leaseExpiresAt       DateTime?         @db.Timestamptz(3)
  createdAt            DateTime          @default(now()) @db.Timestamptz(3)
  updatedAt            DateTime          @updatedAt @db.Timestamptz(3)

  organization Organization @relation(fields: [organizationId], references: [id], onDelete: Restrict)
  site         Site         @relation(fields: [organizationId, siteId], references: [organizationId, id], onDelete: Cascade)
  siteDomain   SiteDomain   @relation(fields: [organizationId, siteDomainId], references: [organizationId, id], onDelete: Cascade)

  @@unique([organizationId, id])
  @@unique([organizationId, siteDomainId])
  @@index([organizationId, status, nextCheckAt])
  @@index([organizationId, leaseExpiresAt])
  @@index([siteId, status])
  @@map("site_monitor_states")
}

model SiteMonitorCheck {
  id              String                  @id @default(uuid()) @db.Uuid
  organizationId  String                  @db.Uuid
  siteId          String                  @db.Uuid
  siteDomainId    String                  @db.Uuid
  outcome         SiteMonitorCheckOutcome
  statusBefore    SiteMonitorStatus
  statusAfter     SiteMonitorStatus
  httpStatus      Int?
  latencyMs       Int?
  resolvedAddress String?                 @db.VarChar(80)
  failureCode     String?                 @db.VarChar(80)
  failureMessage  String?                 @db.VarChar(500)
  checkedAt       DateTime                @default(now()) @db.Timestamptz(3)
  createdAt       DateTime                @default(now()) @db.Timestamptz(3)

  organization Organization @relation(fields: [organizationId], references: [id], onDelete: Restrict)
  site         Site         @relation(fields: [organizationId, siteId], references: [organizationId, id], onDelete: Cascade)
  siteDomain   SiteDomain   @relation(fields: [organizationId, siteDomainId], references: [organizationId, id], onDelete: Cascade)

  @@unique([organizationId, id])
  @@index([organizationId, siteDomainId, checkedAt])
  @@index([organizationId, siteId, checkedAt])
  @@index([organizationId, outcome, checkedAt])
  @@map("site_monitor_checks")
}

model SiteMonitorIncident {
  id                  String                    @id @default(uuid()) @db.Uuid
  organizationId      String                    @db.Uuid
  siteId              String                    @db.Uuid
  siteDomainId        String                    @db.Uuid
  status              SiteMonitorIncidentStatus @default(OPEN)
  openedAt            DateTime                  @default(now()) @db.Timestamptz(3)
  resolvedAt          DateTime?                 @db.Timestamptz(3)
  openedAfterFailures Int
  lastFailureCode     String?                   @db.VarChar(80)
  lastFailureMessage  String?                   @db.VarChar(500)
  createdAt           DateTime                  @default(now()) @db.Timestamptz(3)
  updatedAt           DateTime                  @updatedAt @db.Timestamptz(3)

  organization Organization @relation(fields: [organizationId], references: [id], onDelete: Restrict)
  site         Site         @relation(fields: [organizationId, siteId], references: [organizationId, id], onDelete: Cascade)
  siteDomain   SiteDomain   @relation(fields: [organizationId, siteDomainId], references: [organizationId, id], onDelete: Cascade)

  @@unique([organizationId, id])
  @@index([organizationId, siteDomainId, status, openedAt])
  @@index([organizationId, siteId, status])
  @@map("site_monitor_incidents")
}
'@

Insert-AfterPrismaBlock `
    -Path $SchemaPath `
    -Kind "model" `
    -Name "SiteDomain" `
    -Marker "model SiteMonitorState {" `
    -Insertion $MonitorModels

$SchemaContent = Read-Text -Path $SchemaPath
$SchemaContent = $SchemaContent.TrimStart([char]0xFEFF)

Write-Text `
    -Path $SchemaPath `
    -Content $SchemaContent

Write-Host "[OK] Models de monitoramento criados." -ForegroundColor Green

# ============================================================
# VALIDATION - monitoringEnabled
# ============================================================

$Validation = Read-Text -Path $ValidationIndexPath

if (-not $Validation.Contains("monitoringEnabled: z.boolean().default(true)")) {
    $Anchor = "  isPrimary: z.boolean().default(false),"

    if (-not $Validation.Contains($Anchor)) {
        throw "Anchor createSiteDomainSchema nao encontrado."
    }

    $Validation = $Validation.Replace(
        $Anchor,
        $Anchor + "`r`n`r`n  monitoringEnabled: z.boolean().default(true),"
    )
}

if (-not $Validation.Contains("monitoringEnabled: z.boolean().optional()")) {
    $Anchor = "    isPrimary: z.boolean().optional(),"

    if (-not $Validation.Contains($Anchor)) {
        throw "Anchor updateSiteDomainSchema nao encontrado."
    }

    $Validation = $Validation.Replace(
        $Anchor,
        $Anchor + "`r`n`r`n    monitoringEnabled: z.boolean().optional(),"
    )
}

Write-Text `
    -Path $ValidationIndexPath `
    -Content $Validation

Write-Host "[OK] Validation monitoringEnabled adicionada." -ForegroundColor Green

# ============================================================
# CONTRACTS - DOMAIN TOGGLE
# ============================================================

$Contracts = Read-Text -Path $ContractsIndexPath

if (-not $Contracts.Contains("monitoringEnabled: boolean;")) {
    $Anchor = "  status: SiteDomainStatus;"

    if (-not $Contracts.Contains($Anchor)) {
        throw "Anchor SiteDomainResponse nao encontrado."
    }

    $Contracts = $Contracts.Replace(
        $Anchor,
        $Anchor + "`r`n  monitoringEnabled: boolean;"
    )
}

if (-not $Contracts.Contains("  monitoringEnabled?: boolean;")) {
    $CreateAnchor = "  isPrimary?: boolean;"

    $FirstIndex = $Contracts.IndexOf(
        $CreateAnchor,
        $Contracts.IndexOf("export type CreateSiteDomainRequest")
    )

    if ($FirstIndex -lt 0) {
        throw "Anchor CreateSiteDomainRequest nao encontrado."
    }

    $InsertAt = $FirstIndex + $CreateAnchor.Length

    $Contracts = (
        $Contracts.Substring(0, $InsertAt) +
        "`r`n  monitoringEnabled?: boolean;" +
        $Contracts.Substring($InsertAt)
    )

    $UpdateStart = $Contracts.IndexOf("export type UpdateSiteDomainRequest")
    $UpdateAnchorIndex = $Contracts.IndexOf(
        $CreateAnchor,
        $UpdateStart
    )

    if ($UpdateAnchorIndex -lt 0) {
        throw "Anchor UpdateSiteDomainRequest nao encontrado."
    }

    $UpdateInsertAt = $UpdateAnchorIndex + $CreateAnchor.Length

    $Contracts = (
        $Contracts.Substring(0, $UpdateInsertAt) +
        "`r`n  monitoringEnabled?: boolean;" +
        $Contracts.Substring($UpdateInsertAt)
    )
}

if (-not $Contracts.Contains("export * from './site-monitoring.js';")) {
    $Contracts = (
        $Contracts.TrimEnd() +
        "`r`nexport * from './site-monitoring.js';`r`n"
    )
}

Write-Text `
    -Path $ContractsIndexPath `
    -Content $Contracts

# ============================================================
# MONITORING CONTRACTS
# ============================================================

$MonitoringContracts = @'
export type SiteMonitorStatus =
  | 'UNKNOWN'
  | 'HEALTHY'
  | 'DEGRADED'
  | 'DOWN';

export type SiteMonitorIncidentStatus =
  | 'OPEN'
  | 'RESOLVED';

export type SiteMonitorIncidentResponse = Readonly<{
  id: string;
  status: SiteMonitorIncidentStatus;
  openedAt: string;
  resolvedAt: string | null;
  openedAfterFailures: number;
  lastFailureCode: string | null;
  lastFailureMessage: string | null;
}>;

export type SiteMonitorDomainResponse = Readonly<{
  domainId: string;
  hostname: string;
  isPrimary: boolean;
  monitoringEnabled: boolean;
  status: SiteMonitorStatus;
  consecutiveFailures: number;
  consecutiveSuccesses: number;
  lastCheckedAt: string | null;
  lastSuccessAt: string | null;
  lastFailureAt: string | null;
  lastHttpStatus: number | null;
  lastLatencyMs: number | null;
  lastResolvedAddress: string | null;
  lastFailureCode: string | null;
  lastFailureMessage: string | null;
  downSince: string | null;
  recoveredAt: string | null;
  nextCheckAt: string | null;
  openIncident: SiteMonitorIncidentResponse | null;
}>;

export type SiteMonitoringResponse = Readonly<{
  siteId: string;
  status: SiteMonitorStatus;
  primaryDomainId: string | null;
  domains: readonly SiteMonitorDomainResponse[];
}>;

export type SiteMonitorCheckResponse = Readonly<{
  id: string;
  siteId: string;
  siteDomainId: string;
  outcome: 'SUCCESS' | 'FAILURE';
  statusBefore: SiteMonitorStatus;
  statusAfter: SiteMonitorStatus;
  httpStatus: number | null;
  latencyMs: number | null;
  resolvedAddress: string | null;
  failureCode: string | null;
  failureMessage: string | null;
  checkedAt: string;
}>;

export type SiteMonitorCheckListResponse =
  readonly SiteMonitorCheckResponse[];
'@

Write-Text `
    -Path ".\packages\contracts\src\site-monitoring.ts" `
    -Content $MonitoringContracts

Write-Host "[OK] Contracts Stage 6 criados." -ForegroundColor Green

# ============================================================
# SITES SERVICE - monitoringEnabled
# ============================================================

$SitesService = Read-Text -Path $SitesServicePath

if (-not $SitesService.Contains("monitoringEnabled: input.monitoringEnabled")) {
    $Anchor = "            isPrimary: input.isPrimary,"

    if (-not $SitesService.Contains($Anchor)) {
        throw "Anchor createDomain isPrimary nao encontrado."
    }

    $SitesService = $SitesService.Replace(
        $Anchor,
        $Anchor + "`r`n`r`n            monitoringEnabled: input.monitoringEnabled === true,"
    )
}

if (-not $SitesService.Contains("monitoringEnabled: input.monitoringEnabled === true,")) {
    throw "monitoringEnabled create patch falhou."
}

if (-not $SitesService.Contains("...(input.monitoringEnabled !== undefined")) {
    $Anchor = "            ...(input.status !== undefined"

    $Index = $SitesService.IndexOf(
        $Anchor,
        $SitesService.IndexOf("async updateDomain")
    )

    if ($Index -lt 0) {
        throw "Anchor updateDomain status nao encontrado."
    }

    $MonitoringPatch = @'
            ...(input.monitoringEnabled !== undefined
              ? {
                  monitoringEnabled: input.monitoringEnabled === true,
                }
              : {}),

'@

    $SitesService = (
        $SitesService.Substring(0, $Index) +
        $MonitoringPatch +
        $SitesService.Substring($Index)
    )
}

if (-not $SitesService.Contains("monitoringEnabled: domain.monitoringEnabled")) {
    $MapStart = $SitesService.IndexOf("private mapDomain")

    if ($MapStart -lt 0) {
        throw "mapDomain nao encontrado."
    }

    $Anchor = "      status: domain.status,"
    $AnchorIndex = $SitesService.IndexOf(
        $Anchor,
        $MapStart
    )

    if ($AnchorIndex -lt 0) {
        throw "Anchor mapDomain status nao encontrado."
    }

    $InsertAt = $AnchorIndex + $Anchor.Length

    $SitesService = (
        $SitesService.Substring(0, $InsertAt) +
        "`r`n`r`n      monitoringEnabled: domain.monitoringEnabled," +
        $SitesService.Substring($InsertAt)
    )
}

Write-Text `
    -Path $SitesServicePath `
    -Content $SitesService

Write-Host "[OK] SitesService atualizado." -ForegroundColor Green

# ============================================================
# SITE MONITORING API SERVICE
# ============================================================

$MonitoringApiService = @'
import {
  ForbiddenException,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';

import type { AuthenticatedPrincipal } from '@crm/auth';

import type {
  SiteMonitorCheckListResponse,
  SiteMonitoringResponse,
} from '@crm/contracts';

import { DatabaseService } from '../database/database.service.js';

@Injectable()
export class SiteMonitoringService {
  constructor(
    @Inject(DatabaseService)
    private readonly database: DatabaseService,
  ) {}

  async getSiteMonitoring(
    principal: AuthenticatedPrincipal,
    siteId: string,
  ): Promise<SiteMonitoringResponse> {
    await this.assertAccessibleSite(
      principal,
      siteId,
    );

    const domains =
      await this.database.client.siteDomain.findMany({
        where: {
          organizationId: principal.organizationId,
          siteId,
          deletedAt: null,
        },

        include: {
          monitorState: true,

          monitorIncidents: {
            where: {
              status: 'OPEN',
            },

            orderBy: {
              openedAt: 'desc',
            },

            take: 1,
          },
        },

        orderBy: [
          {
            isPrimary: 'desc',
          },
          {
            hostname: 'asc',
          },
        ],
      });

    const primaryDomain =
      domains.find((domain) => domain.isPrimary) ??
      null;

    const status =
      primaryDomain?.monitorState?.status ??
      'UNKNOWN';

    return {
      siteId,
      status,
      primaryDomainId:
        primaryDomain?.id ??
        null,

      domains: domains.map((domain) => {
        const state = domain.monitorState;

        const incident =
          domain.monitorIncidents[0] ??
          null;

        return {
          domainId: domain.id,
          hostname: domain.hostname,
          isPrimary: domain.isPrimary,
          monitoringEnabled:
            domain.monitoringEnabled,

          status:
            state?.status ??
            'UNKNOWN',

          consecutiveFailures:
            state?.consecutiveFailures ??
            0,

          consecutiveSuccesses:
            state?.consecutiveSuccesses ??
            0,

          lastCheckedAt:
            state?.lastCheckedAt?.toISOString() ??
            null,

          lastSuccessAt:
            state?.lastSuccessAt?.toISOString() ??
            null,

          lastFailureAt:
            state?.lastFailureAt?.toISOString() ??
            null,

          lastHttpStatus:
            state?.lastHttpStatus ??
            null,

          lastLatencyMs:
            state?.lastLatencyMs ??
            null,

          lastResolvedAddress:
            state?.lastResolvedAddress ??
            null,

          lastFailureCode:
            state?.lastFailureCode ??
            null,

          lastFailureMessage:
            state?.lastFailureMessage ??
            null,

          downSince:
            state?.downSince?.toISOString() ??
            null,

          recoveredAt:
            state?.recoveredAt?.toISOString() ??
            null,

          nextCheckAt:
            state?.nextCheckAt?.toISOString() ??
            null,

          openIncident: incident
            ? {
                id: incident.id,
                status: incident.status,
                openedAt:
                  incident.openedAt.toISOString(),
                resolvedAt:
                  incident.resolvedAt?.toISOString() ??
                  null,
                openedAfterFailures:
                  incident.openedAfterFailures,
                lastFailureCode:
                  incident.lastFailureCode,
                lastFailureMessage:
                  incident.lastFailureMessage,
              }
            : null,
        };
      }),
    };
  }

  async listChecks(
    principal: AuthenticatedPrincipal,
    siteId: string,
    domainId: string,
  ): Promise<SiteMonitorCheckListResponse> {
    await this.assertAccessibleSite(
      principal,
      siteId,
    );

    const domain =
      await this.database.client.siteDomain.findFirst({
        where: {
          id: domainId,
          organizationId: principal.organizationId,
          siteId,
          deletedAt: null,
        },

        select: {
          id: true,
        },
      });

    if (!domain) {
      throw new NotFoundException({
        code: 'DOMAIN_NOT_FOUND',
        message: 'Domain not found.',
      });
    }

    const checks =
      await this.database.client.siteMonitorCheck.findMany({
        where: {
          organizationId: principal.organizationId,
          siteId,
          siteDomainId: domainId,
        },

        orderBy: {
          checkedAt: 'desc',
        },

        take: 100,
      });

    return checks.map((check) => ({
      id: check.id,
      siteId: check.siteId,
      siteDomainId: check.siteDomainId,
      outcome: check.outcome,
      statusBefore: check.statusBefore,
      statusAfter: check.statusAfter,
      httpStatus: check.httpStatus,
      latencyMs: check.latencyMs,
      resolvedAddress: check.resolvedAddress,
      failureCode: check.failureCode,
      failureMessage: check.failureMessage,
      checkedAt: check.checkedAt.toISOString(),
    }));
  }

  private async assertAccessibleSite(
    principal: AuthenticatedPrincipal,
    siteId: string,
  ): Promise<void> {
    const employeeId =
      principal.roles.includes('ADMIN')
        ? null
        : await this.getCurrentEmployeeId(principal);

    const site =
      await this.database.client.site.findFirst({
        where: {
          id: siteId,
          organizationId: principal.organizationId,
          deletedAt: null,

          ...(employeeId
            ? {
                ownerEmployeeId: employeeId,
              }
            : {}),
        },

        select: {
          id: true,
        },
      });

    if (!site) {
      throw new NotFoundException({
        code: 'SITE_NOT_FOUND',
        message: 'Site not found.',
      });
    }
  }

  private async getCurrentEmployeeId(
    principal: AuthenticatedPrincipal,
  ): Promise<string> {
    const employee =
      await this.database.client.employee.findFirst({
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
        message:
          'An active employee profile is required.',
      });
    }

    return employee.id;
  }
}
'@

Write-Text `
    -Path ".\apps\api\src\sites\site-monitoring.service.ts" `
    -Content $MonitoringApiService

# ============================================================
# SITE MONITORING API CONTROLLER
# ============================================================

$MonitoringController = @'
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
  SiteMonitorCheckListResponse,
  SiteMonitoringResponse,
} from '@crm/contracts';

import { AccessTokenGuard } from '../authorization/access-token.guard.js';
import { AuthorizationGuard } from '../authorization/authorization.guard.js';
import { CurrentPrincipal } from '../authorization/current-principal.decorator.js';
import { RequirePermissions } from '../authorization/require-permissions.decorator.js';

import { SiteMonitoringService } from './site-monitoring.service.js';

@Controller('sites')
@UseGuards(
  AccessTokenGuard,
  AuthorizationGuard,
)
export class SiteMonitoringController {
  constructor(
    @Inject(SiteMonitoringService)
    private readonly siteMonitoringService:
      SiteMonitoringService,
  ) {}

  @Get(':siteId/monitoring')
  @RequirePermissions(
    'site.read',
    'domain.read',
  )
  getSiteMonitoring(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param(
      'siteId',
      new ParseUUIDPipe(),
    )
    siteId: string,
  ): Promise<SiteMonitoringResponse> {
    return this.siteMonitoringService.getSiteMonitoring(
      principal,
      siteId,
    );
  }

  @Get(
    ':siteId/domains/:domainId/monitoring/checks',
  )
  @RequirePermissions(
    'site.read',
    'domain.read',
  )
  listChecks(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param(
      'siteId',
      new ParseUUIDPipe(),
    )
    siteId: string,

    @Param(
      'domainId',
      new ParseUUIDPipe(),
    )
    domainId: string,
  ): Promise<SiteMonitorCheckListResponse> {
    return this.siteMonitoringService.listChecks(
      principal,
      siteId,
      domainId,
    );
  }
}
'@

Write-Text `
    -Path ".\apps\api\src\sites\site-monitoring.controller.ts" `
    -Content $MonitoringController

# ============================================================
# SITES MODULE
# ============================================================

$SitesModule = @'
import { Module } from '@nestjs/common';

import { AuthorizationModule } from '../authorization/authorization.module.js';
import { DatabaseModule } from '../database/database.module.js';

import { SiteMonitoringController } from './site-monitoring.controller.js';
import { SiteMonitoringService } from './site-monitoring.service.js';
import { SitesController } from './sites.controller.js';
import { SitesService } from './sites.service.js';

@Module({
  imports: [
    AuthorizationModule,
    DatabaseModule,
  ],

  controllers: [
    SitesController,
    SiteMonitoringController,
  ],

  providers: [
    SitesService,
    SiteMonitoringService,
  ],

  exports: [
    SitesService,
    SiteMonitoringService,
  ],
})
export class SitesModule {}
'@

Write-Text `
    -Path $SitesModulePath `
    -Content $SitesModule

Write-Host "[OK] API de monitoramento criada." -ForegroundColor Green

# ============================================================
# STAGE 5 SCHEDULER GATE
# ============================================================

$AdsScheduler = Read-Text -Path $AdsSchedulerPath

if (-not $AdsScheduler.Contains("'ads_queue.site_down'")) {
    $Anchor = "      const eligibleMembers = await transaction.trafficPoolMember.findMany({"

    if (-not $AdsScheduler.Contains($Anchor)) {
        throw "Anchor eligibleMembers nao encontrado no scheduler."
    }

    $Gate = @'
      const primaryDomain =
        await transaction.siteDomain.findFirst({
          where: {
            organizationId:
              queueItem.organizationId,

            siteId:
              queueItem.trafficPool.site.id,

            isPrimary: true,
            status: 'ACTIVE',
            deletedAt: null,
          },

          include: {
            monitorState: true,
          },
        });

      if (
        primaryDomain?.monitoringEnabled === true &&
        primaryDomain.monitorState?.status === 'DOWN'
      ) {
        await this.deferClaimedQueueItem(
          transaction,
          queueItem.id,
          queueItem.organizationId,
          request.id,
          now,
          this.config.backpressureDelayMs,
          'ads_queue.site_down',
        );

        return 'DEFERRED';
      }

'@

    $AdsScheduler = $AdsScheduler.Replace(
        $Anchor,
        $Gate + $Anchor
    )
}

Write-Text `
    -Path $AdsSchedulerPath `
    -Content $AdsScheduler

Write-Host "[OK] Scheduler integrado ao Site Monitoring." -ForegroundColor Green

# ============================================================
# SITE MONITOR WORKER PACKAGE
# ============================================================

$MonitorPackage = @'
{
  "name": "@crm/site-monitor-worker",
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
    -Path $MonitorPackagePath `
    -Content $MonitorPackage

# ============================================================
# WORKER ENVIRONMENT LOADER
# ============================================================

$LoadEnvironment = @'
import { config } from 'dotenv';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const appDirectory = resolve(
  dirname(fileURLToPath(import.meta.url)),
  '..',
);

config({
  path: resolve(
    appDirectory,
    '../../.env',
  ),

  quiet: true,
});
'@

Write-Text `
    -Path ".\apps\site-monitor-worker\src\load-environment.ts" `
    -Content $LoadEnvironment

# ============================================================
# MONITOR CONFIG
# ============================================================

$MonitorConfig = @'
export type SiteMonitorConfig = Readonly<{
  tickIntervalMs: number;
  checkIntervalMs: number;
  retryDelayMs: number;
  timeoutMs: number;
  leaseMs: number;
  failureThreshold: number;
  recoveryThreshold: number;
  concurrency: number;
  maxClaimsPerTick: number;
  stateSyncIntervalMs: number;
  checkRetentionDays: number;
  cleanupIntervalMs: number;
}>;

function readInteger(
  name: string,
  fallback: number,
  minimum: number,
  maximum: number,
): number {
  const raw =
    process.env[name]?.trim();

  if (!raw) {
    return fallback;
  }

  const value = Number(raw);

  if (
    !Number.isInteger(value) ||
    value < minimum ||
    value > maximum
  ) {
    throw new Error(
      `${name} must be an integer between ${minimum} and ${maximum}.`,
    );
  }

  return value;
}

export function parseSiteMonitorConfig(): SiteMonitorConfig {
  return {
    tickIntervalMs:
      readInteger(
        'SITE_MONITOR_TICK_INTERVAL_MS',
        1000,
        100,
        60_000,
      ),

    checkIntervalMs:
      readInteger(
        'SITE_MONITOR_CHECK_INTERVAL_MS',
        30_000,
        5_000,
        3_600_000,
      ),

    retryDelayMs:
      readInteger(
        'SITE_MONITOR_RETRY_DELAY_MS',
        5_000,
        1_000,
        300_000,
      ),

    timeoutMs:
      readInteger(
        'SITE_MONITOR_TIMEOUT_MS',
        5_000,
        500,
        60_000,
      ),

    leaseMs:
      readInteger(
        'SITE_MONITOR_LEASE_MS',
        15_000,
        2_000,
        300_000,
      ),

    failureThreshold:
      readInteger(
        'SITE_MONITOR_FAILURE_THRESHOLD',
        3,
        1,
        20,
      ),

    recoveryThreshold:
      readInteger(
        'SITE_MONITOR_RECOVERY_THRESHOLD',
        2,
        1,
        20,
      ),

    concurrency:
      readInteger(
        'SITE_MONITOR_CONCURRENCY',
        5,
        1,
        50,
      ),

    maxClaimsPerTick:
      readInteger(
        'SITE_MONITOR_MAX_CLAIMS_PER_TICK',
        25,
        1,
        1000,
      ),

    stateSyncIntervalMs:
      readInteger(
        'SITE_MONITOR_STATE_SYNC_INTERVAL_MS',
        60_000,
        1_000,
        3_600_000,
      ),

    checkRetentionDays:
      readInteger(
        'SITE_MONITOR_CHECK_RETENTION_DAYS',
        14,
        1,
        365,
      ),

    cleanupIntervalMs:
      readInteger(
        'SITE_MONITOR_CLEANUP_INTERVAL_MS',
        21_600_000,
        60_000,
        86_400_000,
      ),
  };
}
'@

Write-Text `
    -Path ".\apps\site-monitor-worker\src\site-monitor.config.ts" `
    -Content $MonitorConfig

# ============================================================
# MONITOR STATE ENGINE
# ============================================================

$MonitorEngine = @'
export type MonitorStatus =
  | 'UNKNOWN'
  | 'HEALTHY'
  | 'DEGRADED'
  | 'DOWN';

export type MonitorTransitionInput = Readonly<{
  previousStatus: MonitorStatus;
  consecutiveFailures: number;
  consecutiveSuccesses: number;
  hasOpenIncident: boolean;
  success: boolean;
  failureThreshold: number;
  recoveryThreshold: number;
}>;

export type MonitorTransition = Readonly<{
  status: MonitorStatus;
  consecutiveFailures: number;
  consecutiveSuccesses: number;
  openIncident: boolean;
  resolveIncident: boolean;
}>;

export function computeMonitorTransition(
  input: MonitorTransitionInput,
): MonitorTransition {
  if (input.success) {
    const consecutiveSuccesses =
      input.consecutiveSuccesses + 1;

    if (
      input.hasOpenIncident &&
      consecutiveSuccesses <
        input.recoveryThreshold
    ) {
      return {
        status: 'DEGRADED',
        consecutiveFailures: 0,
        consecutiveSuccesses,
        openIncident: false,
        resolveIncident: false,
      };
    }

    return {
      status: 'HEALTHY',
      consecutiveFailures: 0,
      consecutiveSuccesses,
      openIncident: false,

      resolveIncident:
        input.hasOpenIncident &&
        consecutiveSuccesses >=
          input.recoveryThreshold,
    };
  }

  const consecutiveFailures =
    input.consecutiveFailures + 1;

  const status: MonitorStatus =
    consecutiveFailures >=
    input.failureThreshold
      ? 'DOWN'
      : 'DEGRADED';

  return {
    status,
    consecutiveFailures,
    consecutiveSuccesses: 0,

    openIncident:
      status === 'DOWN' &&
      !input.hasOpenIncident,

    resolveIncident: false,
  };
}
'@

Write-Text `
    -Path ".\apps\site-monitor-worker\src\site-monitor-engine.ts" `
    -Content $MonitorEngine

# ============================================================
# ENGINE TESTS
# ============================================================

$MonitorEngineTests = @'
import {
  describe,
  expect,
  it,
} from 'vitest';

import {
  computeMonitorTransition,
} from './site-monitor-engine.js';

describe('computeMonitorTransition', () => {
  it('marks the first failure as DEGRADED', () => {
    const result =
      computeMonitorTransition({
        previousStatus: 'HEALTHY',
        consecutiveFailures: 0,
        consecutiveSuccesses: 10,
        hasOpenIncident: false,
        success: false,
        failureThreshold: 3,
        recoveryThreshold: 2,
      });

    expect(result.status).toBe('DEGRADED');
    expect(result.consecutiveFailures).toBe(1);
    expect(result.openIncident).toBe(false);
  });

  it('opens an incident at the failure threshold', () => {
    const result =
      computeMonitorTransition({
        previousStatus: 'DEGRADED',
        consecutiveFailures: 2,
        consecutiveSuccesses: 0,
        hasOpenIncident: false,
        success: false,
        failureThreshold: 3,
        recoveryThreshold: 2,
      });

    expect(result.status).toBe('DOWN');
    expect(result.consecutiveFailures).toBe(3);
    expect(result.openIncident).toBe(true);
  });

  it('requires consecutive successes to recover an incident', () => {
    const firstSuccess =
      computeMonitorTransition({
        previousStatus: 'DOWN',
        consecutiveFailures: 3,
        consecutiveSuccesses: 0,
        hasOpenIncident: true,
        success: true,
        failureThreshold: 3,
        recoveryThreshold: 2,
      });

    expect(firstSuccess.status).toBe('DEGRADED');
    expect(firstSuccess.resolveIncident).toBe(false);

    const secondSuccess =
      computeMonitorTransition({
        previousStatus: firstSuccess.status,
        consecutiveFailures:
          firstSuccess.consecutiveFailures,
        consecutiveSuccesses:
          firstSuccess.consecutiveSuccesses,
        hasOpenIncident: true,
        success: true,
        failureThreshold: 3,
        recoveryThreshold: 2,
      });

    expect(secondSuccess.status).toBe('HEALTHY');
    expect(secondSuccess.resolveIncident).toBe(true);
  });

  it('marks an unknown successful domain as HEALTHY', () => {
    const result =
      computeMonitorTransition({
        previousStatus: 'UNKNOWN',
        consecutiveFailures: 0,
        consecutiveSuccesses: 0,
        hasOpenIncident: false,
        success: true,
        failureThreshold: 3,
        recoveryThreshold: 2,
      });

    expect(result.status).toBe('HEALTHY');
  });
});
'@

Write-Text `
    -Path ".\apps\site-monitor-worker\src\site-monitor-engine.spec.ts" `
    -Content $MonitorEngineTests

# ============================================================
# SSRF SAFE HTTPS PROBE
# ============================================================

$SafeProbe = @'
import {
  lookup,
} from 'node:dns/promises';

import {
  request as httpsRequest,
} from 'node:https';

import {
  isIP,
} from 'node:net';

export type SiteProbeResult = Readonly<{
  success: boolean;
  httpStatus: number | null;
  latencyMs: number | null;
  resolvedAddress: string | null;
  failureCode: string | null;
  failureMessage: string | null;
}>;

function isPublicIpv4(
  address: string,
): boolean {
  const values =
    address
      .split('.')
      .map((value) => Number(value));

  if (
    values.length !== 4 ||
    values.some(
      (value) =>
        !Number.isInteger(value) ||
        value < 0 ||
        value > 255,
    )
  ) {
    return false;
  }

  const first = values[0] ?? -1;
  const second = values[1] ?? -1;
  const third = values[2] ?? -1;

  if (first === 0) {
    return false;
  }

  if (first === 10) {
    return false;
  }

  if (
    first === 100 &&
    second >= 64 &&
    second <= 127
  ) {
    return false;
  }

  if (first === 127) {
    return false;
  }

  if (
    first === 169 &&
    second === 254
  ) {
    return false;
  }

  if (
    first === 172 &&
    second >= 16 &&
    second <= 31
  ) {
    return false;
  }

  if (
    first === 192 &&
    second === 168
  ) {
    return false;
  }

  if (
    first === 192 &&
    second === 0 &&
    third === 0
  ) {
    return false;
  }

  if (
    first === 192 &&
    second === 0 &&
    third === 2
  ) {
    return false;
  }

  if (
    first === 198 &&
    (second === 18 || second === 19)
  ) {
    return false;
  }

  if (
    first === 198 &&
    second === 51 &&
    third === 100
  ) {
    return false;
  }

  if (
    first === 203 &&
    second === 0 &&
    third === 113
  ) {
    return false;
  }

  if (first >= 224) {
    return false;
  }

  return true;
}

function isPublicIpv6(
  address: string,
): boolean {
  const normalized =
    address.toLowerCase();

  if (
    normalized === '::' ||
    normalized === '::1'
  ) {
    return false;
  }

  if (
    normalized.startsWith('fc') ||
    normalized.startsWith('fd')
  ) {
    return false;
  }

  if (
    normalized.startsWith('fe8') ||
    normalized.startsWith('fe9') ||
    normalized.startsWith('fea') ||
    normalized.startsWith('feb')
  ) {
    return false;
  }

  if (
    normalized.startsWith('ff')
  ) {
    return false;
  }

  if (
    normalized.startsWith('2001:db8')
  ) {
    return false;
  }

  if (
    normalized.startsWith('::ffff:')
  ) {
    const mapped =
      normalized.slice(
        '::ffff:'.length,
      );

    if (
      isIP(mapped) === 4
    ) {
      return isPublicIpv4(mapped);
    }
  }

  return true;
}

export function isPublicIpAddress(
  address: string,
): boolean {
  const version = isIP(address);

  if (version === 4) {
    return isPublicIpv4(address);
  }

  if (version === 6) {
    return isPublicIpv6(address);
  }

  return false;
}

function classifyRequestError(
  error: NodeJS.ErrnoException,
): string {
  const code =
    error.code ??
    '';

  if (
    code.includes('CERT') ||
    code.includes('TLS') ||
    code.includes('SSL')
  ) {
    return 'TLS_ERROR';
  }

  if (
    code === 'ECONNREFUSED' ||
    code === 'ECONNRESET' ||
    code === 'EHOSTUNREACH' ||
    code === 'ENETUNREACH'
  ) {
    return 'CONNECTION_ERROR';
  }

  if (
    code === 'ETIMEDOUT'
  ) {
    return 'TIMEOUT';
  }

  return 'REQUEST_ERROR';
}

export async function probeHostname(
  hostname: string,
  timeoutMs: number,
): Promise<SiteProbeResult> {
  let addresses;

  try {
    addresses =
      await lookup(
        hostname,
        {
          all: true,
          verbatim: true,
        },
      );
  } catch (error) {
    return {
      success: false,
      httpStatus: null,
      latencyMs: null,
      resolvedAddress: null,
      failureCode: 'DNS_ERROR',

      failureMessage:
        error instanceof Error
          ? error.message.slice(0, 500)
          : String(error).slice(0, 500),
    };
  }

  const publicAddress =
    addresses.find((entry) =>
      isPublicIpAddress(entry.address),
    );

  if (!publicAddress) {
    return {
      success: false,
      httpStatus: null,
      latencyMs: null,
      resolvedAddress: null,
      failureCode:
        'SECURITY_BLOCKED_ADDRESS',

      failureMessage:
        'Hostname resolved only to private, reserved, or unsupported addresses.',
    };
  }

  const startedAt = Date.now();

  return new Promise<SiteProbeResult>(
    (resolve) => {
      let settled = false;
      let timedOut = false;

      const finish = (
        result: SiteProbeResult,
      ): void => {
        if (settled) {
          return;
        }

        settled = true;
        resolve(result);
      };

      const request =
        httpsRequest(
          {
            protocol: 'https:',
            hostname:
              publicAddress.address,
            port: 443,
            path: '/',
            method: 'GET',
            servername: hostname,
            rejectUnauthorized: true,

            headers: {
              Host: hostname,
              'User-Agent':
                'CRM-ADS-WhatsApp-Site-Monitor/1.0',
              Accept:
                'text/html,application/xhtml+xml,*/*;q=0.8',
            },
          },

          (response) => {
            const latencyMs =
              Date.now() -
              startedAt;

            const statusCode =
              response.statusCode ??
              0;

            response.destroy();

            if (
              statusCode >= 200 &&
              statusCode < 400
            ) {
              finish({
                success: true,
                httpStatus: statusCode,
                latencyMs,
                resolvedAddress:
                  publicAddress.address,
                failureCode: null,
                failureMessage: null,
              });

              return;
            }

            finish({
              success: false,
              httpStatus: statusCode,
              latencyMs,
              resolvedAddress:
                publicAddress.address,
              failureCode:
                'HTTP_STATUS',
              failureMessage:
                `HTTP ${statusCode}`,
            });
          },
        );

      request.setTimeout(
        timeoutMs,
        () => {
          timedOut = true;
          request.destroy();
        },
      );

      request.on(
        'error',
        (error: NodeJS.ErrnoException) => {
          finish({
            success: false,
            httpStatus: null,

            latencyMs:
              Date.now() -
              startedAt,

            resolvedAddress:
              publicAddress.address,

            failureCode:
              timedOut
                ? 'TIMEOUT'
                : classifyRequestError(error),

            failureMessage:
              timedOut
                ? `Request exceeded ${timeoutMs}ms.`
                : error.message.slice(0, 500),
          });
        },
      );

      request.end();
    },
  );
}
'@

Write-Text `
    -Path ".\apps\site-monitor-worker\src\safe-probe.ts" `
    -Content $SafeProbe

# ============================================================
# SAFE PROBE TESTS
# ============================================================

$SafeProbeTests = @'
import {
  describe,
  expect,
  it,
} from 'vitest';

import {
  isPublicIpAddress,
} from './safe-probe.js';

describe('isPublicIpAddress', () => {
  it('allows public IPv4 addresses', () => {
    expect(
      isPublicIpAddress(
        '8.8.8.8',
      ),
    ).toBe(true);

    expect(
      isPublicIpAddress(
        '1.1.1.1',
      ),
    ).toBe(true);
  });

  it('blocks private IPv4 addresses', () => {
    expect(
      isPublicIpAddress(
        '10.0.0.1',
      ),
    ).toBe(false);

    expect(
      isPublicIpAddress(
        '192.168.1.10',
      ),
    ).toBe(false);

    expect(
      isPublicIpAddress(
        '172.16.0.1',
      ),
    ).toBe(false);
  });

  it('blocks loopback and link-local addresses', () => {
    expect(
      isPublicIpAddress(
        '127.0.0.1',
      ),
    ).toBe(false);

    expect(
      isPublicIpAddress(
        '169.254.169.254',
      ),
    ).toBe(false);

    expect(
      isPublicIpAddress(
        '::1',
      ),
    ).toBe(false);
  });

  it('blocks documentation ranges', () => {
    expect(
      isPublicIpAddress(
        '192.0.2.1',
      ),
    ).toBe(false);

    expect(
      isPublicIpAddress(
        '198.51.100.1',
      ),
    ).toBe(false);

    expect(
      isPublicIpAddress(
        '203.0.113.1',
      ),
    ).toBe(false);
  });
});
'@

Write-Text `
    -Path ".\apps\site-monitor-worker\src\safe-probe.spec.ts" `
    -Content $SafeProbeTests

# ============================================================
# SITE MONITOR SERVICE
# ============================================================

$MonitorService = @'
import type {
  CrmDatabaseClient,
} from '@crm/database';

import {
  computeMonitorTransition,
} from './site-monitor-engine.js';

import type {
  SiteMonitorConfig,
} from './site-monitor.config.js';

import {
  probeHostname,
} from './safe-probe.js';

type ClaimedMonitorState = Readonly<{
  id: string;
  organizationId: string;
  siteId: string;
  siteDomainId: string;
}>;

type ProcessResult = Readonly<{
  checked: boolean;
  success: boolean;
  openedIncident: boolean;
  resolvedIncident: boolean;
  lostLease: boolean;
}>;

export type SiteMonitorTickSummary = Readonly<{
  claimed: number;
  checked: number;
  successes: number;
  failures: number;
  openedIncidents: number;
  resolvedIncidents: number;
  lostLeases: number;
}>;

function addMilliseconds(
  value: Date,
  milliseconds: number,
): Date {
  return new Date(
    value.getTime() +
      milliseconds,
  );
}

function subtractDays(
  value: Date,
  days: number,
): Date {
  return new Date(
    value.getTime() -
      days *
        24 *
        60 *
        60 *
        1000,
  );
}

export class SiteMonitorService {
  private nextStateSyncAt = 0;
  private nextCleanupAt = 0;

  constructor(
    private readonly database:
      CrmDatabaseClient,

    private readonly workerId:
      string,

    private readonly config:
      SiteMonitorConfig,
  ) {}

  async runTick(): Promise<SiteMonitorTickSummary> {
    const now = Date.now();

    if (
      now >=
      this.nextStateSyncAt
    ) {
      await this.ensureMonitorStates();

      this.nextStateSyncAt =
        now +
        this.config.stateSyncIntervalMs;
    }

    if (
      now >=
      this.nextCleanupAt
    ) {
      await this.cleanupOldChecks();

      this.nextCleanupAt =
        now +
        this.config.cleanupIntervalMs;
    }

    let claimedCount = 0;
    let checkedCount = 0;
    let successes = 0;
    let failures = 0;
    let openedIncidents = 0;
    let resolvedIncidents = 0;
    let lostLeases = 0;

    while (
      claimedCount <
      this.config.maxClaimsPerTick
    ) {
      const remaining =
        this.config.maxClaimsPerTick -
        claimedCount;

      const batchSize =
        Math.min(
          this.config.concurrency,
          remaining,
        );

      const claims: ClaimedMonitorState[] = [];

      for (
        let index = 0;
        index < batchSize;
        index += 1
      ) {
        const claimed =
          await this.claimNextState();

        if (!claimed) {
          break;
        }

        claims.push(claimed);
      }

      if (
        claims.length === 0
      ) {
        break;
      }

      claimedCount +=
        claims.length;

      const results =
        await Promise.all(
          claims.map(
            async (claim) => {
              try {
                return await this.processClaim(
                  claim,
                );
              } catch (error) {
                await this.handleProcessingError(
                  claim,
                );

                console.error(
                  JSON.stringify({
                    event:
                      'site_monitor.processing_error',
                    siteDomainId:
                      claim.siteDomainId,
                    message:
                      error instanceof Error
                        ? error.message
                        : String(error),
                  }),
                );

                return {
                  checked: false,
                  success: false,
                  openedIncident: false,
                  resolvedIncident: false,
                  lostLease: false,
                } satisfies ProcessResult;
              }
            },
          ),
        );

      for (
        const result of results
      ) {
        if (result.checked) {
          checkedCount += 1;

          if (result.success) {
            successes += 1;
          } else {
            failures += 1;
          }
        }

        if (
          result.openedIncident
        ) {
          openedIncidents += 1;
        }

        if (
          result.resolvedIncident
        ) {
          resolvedIncidents += 1;
        }

        if (
          result.lostLease
        ) {
          lostLeases += 1;
        }
      }

      if (
        claims.length <
        batchSize
      ) {
        break;
      }
    }

    return {
      claimed: claimedCount,
      checked: checkedCount,
      successes,
      failures,
      openedIncidents,
      resolvedIncidents,
      lostLeases,
    };
  }

  private async ensureMonitorStates(): Promise<void> {
    const domains =
      await this.database.siteDomain.findMany({
        where: {
          monitoringEnabled: true,
          status: 'ACTIVE',
          deletedAt: null,

          site: {
            status: 'ACTIVE',
            deletedAt: null,
          },
        },

        select: {
          organizationId: true,
          siteId: true,
          id: true,
        },
      });

    if (
      domains.length === 0
    ) {
      return;
    }

    await this.database.siteMonitorState.createMany({
      data: domains.map((domain) => ({
        organizationId:
          domain.organizationId,

        siteId:
          domain.siteId,

        siteDomainId:
          domain.id,
      })),

      skipDuplicates: true,
    });
  }

  private async cleanupOldChecks(): Promise<void> {
    const cutoff =
      subtractDays(
        new Date(),
        this.config.checkRetentionDays,
      );

    await this.database.siteMonitorCheck.deleteMany({
      where: {
        checkedAt: {
          lt: cutoff,
        },
      },
    });
  }

  private async claimNextState(): Promise<ClaimedMonitorState | null> {
    const rows =
      await this.database.$queryRawUnsafe<
        ClaimedMonitorState[]
      >(
        `
          WITH candidate AS (
            SELECT
              state."id"
            FROM
              "site_monitor_states" state
            INNER JOIN
              "site_domains" domain
                ON domain."id" = state."siteDomainId"
                AND domain."organizationId" = state."organizationId"
            INNER JOIN
              "sites" site
                ON site."id" = state."siteId"
                AND site."organizationId" = state."organizationId"
            WHERE
              domain."monitoringEnabled" = TRUE
              AND domain."status" = 'ACTIVE'
              AND domain."deletedAt" IS NULL
              AND site."status" = 'ACTIVE'
              AND site."deletedAt" IS NULL
              AND (
                (
                  state."claimedByWorkerId" IS NULL
                  AND state."nextCheckAt" <= NOW()
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
            "site_monitor_states" AS state
          SET
            "claimedAt" = NOW(),
            "claimedByWorkerId" = $1,
            "leaseExpiresAt" =
              NOW() + ($2::int * INTERVAL '1 millisecond'),
            "updatedAt" = NOW()
          FROM
            candidate
          WHERE
            state."id" = candidate."id"
          RETURNING
            state."id",
            state."organizationId",
            state."siteId",
            state."siteDomainId"
        `,
        this.workerId,
        this.config.leaseMs,
      );

    return rows[0] ?? null;
  }

  private async processClaim(
    claimed: ClaimedMonitorState,
  ): Promise<ProcessResult> {
    const now = new Date();

    const state =
      await this.database.siteMonitorState.findFirst({
        where: {
          id: claimed.id,
          claimedByWorkerId:
            this.workerId,

          leaseExpiresAt: {
            gt: now,
          },
        },

        include: {
          siteDomain: {
            include: {
              site: true,
            },
          },
        },
      });

    if (!state) {
      return {
        checked: false,
        success: false,
        openedIncident: false,
        resolvedIncident: false,
        lostLease: true,
      };
    }

    if (
      state.siteDomain.monitoringEnabled !== true ||
      state.siteDomain.status !== 'ACTIVE' ||
      state.siteDomain.deletedAt !== null ||
      state.siteDomain.site.status !== 'ACTIVE' ||
      state.siteDomain.site.deletedAt !== null
    ) {
      await this.database.siteMonitorState.updateMany({
        where: {
          id: state.id,
          claimedByWorkerId:
            this.workerId,
        },

        data: {
          claimedAt: null,
          claimedByWorkerId: null,
          leaseExpiresAt: null,

          nextCheckAt:
            addMilliseconds(
              now,
              this.config.checkIntervalMs,
            ),
        },
      });

      return {
        checked: false,
        success: false,
        openedIncident: false,
        resolvedIncident: false,
        lostLease: false,
      };
    }

    const probe =
      await probeHostname(
        state.siteDomain.hostname,
        this.config.timeoutMs,
      );

    return this.database.$transaction(
      async (transaction) => {
        await transaction.$queryRawUnsafe(
          `
            WITH lock_guard AS MATERIALIZED (
              SELECT
                pg_advisory_xact_lock(
                  hashtextextended($1, 0)
                )
            )
            SELECT TRUE AS locked
            FROM lock_guard
          `,
          `site-domain:${state.siteDomainId}`,
        );

        const current =
          await transaction.siteMonitorState.findFirst({
            where: {
              id: state.id,

              claimedByWorkerId:
                this.workerId,

              leaseExpiresAt: {
                gt: new Date(),
              },
            },

            include: {
              siteDomain: true,
            },
          });

        if (!current) {
          return {
            checked: false,
            success: false,
            openedIncident: false,
            resolvedIncident: false,
            lostLease: true,
          };
        }

        const openIncident =
          await transaction.siteMonitorIncident.findFirst({
            where: {
              organizationId:
                current.organizationId,

              siteDomainId:
                current.siteDomainId,

              status: 'OPEN',
            },

            orderBy: {
              openedAt: 'desc',
            },
          });

        const transition =
          computeMonitorTransition({
            previousStatus:
              current.status,

            consecutiveFailures:
              current.consecutiveFailures,

            consecutiveSuccesses:
              current.consecutiveSuccesses,

            hasOpenIncident:
              Boolean(openIncident),

            success:
              probe.success,

            failureThreshold:
              this.config.failureThreshold,

            recoveryThreshold:
              this.config.recoveryThreshold,
          });

        const checkedAt =
          new Date();

        await transaction.siteMonitorCheck.create({
          data: {
            organizationId:
              current.organizationId,

            siteId:
              current.siteId,

            siteDomainId:
              current.siteDomainId,

            outcome:
              probe.success
                ? 'SUCCESS'
                : 'FAILURE',

            statusBefore:
              current.status,

            statusAfter:
              transition.status,

            httpStatus:
              probe.httpStatus,

            latencyMs:
              probe.latencyMs,

            resolvedAddress:
              probe.resolvedAddress,

            failureCode:
              probe.failureCode,

            failureMessage:
              probe.failureMessage,

            checkedAt,
          },
        });

        const nextDelayMs =
          transition.status === 'HEALTHY'
            ? this.config.checkIntervalMs
            : this.config.retryDelayMs;

        await transaction.siteMonitorState.update({
          where: {
            id: current.id,
          },

          data: {
            status:
              transition.status,

            consecutiveFailures:
              transition.consecutiveFailures,

            consecutiveSuccesses:
              transition.consecutiveSuccesses,

            lastCheckedAt:
              checkedAt,

            lastSuccessAt:
              probe.success
                ? checkedAt
                : current.lastSuccessAt,

            lastFailureAt:
              probe.success
                ? current.lastFailureAt
                : checkedAt,

            lastHttpStatus:
              probe.httpStatus,

            lastLatencyMs:
              probe.latencyMs,

            lastResolvedAddress:
              probe.resolvedAddress,

            lastFailureCode:
              probe.success
                ? null
                : probe.failureCode,

            lastFailureMessage:
              probe.success
                ? null
                : probe.failureMessage,

            downSince:
              transition.status === 'DOWN'
                ? current.downSince ??
                  checkedAt
                : transition.resolveIncident
                  ? null
                  : current.downSince,

            recoveredAt:
              transition.resolveIncident
                ? checkedAt
                : current.recoveredAt,

            nextCheckAt:
              addMilliseconds(
                checkedAt,
                nextDelayMs,
              ),

            claimedAt: null,
            claimedByWorkerId: null,
            leaseExpiresAt: null,
          },
        });

        if (
          transition.openIncident
        ) {
          await transaction.siteMonitorIncident.create({
            data: {
              organizationId:
                current.organizationId,

              siteId:
                current.siteId,

              siteDomainId:
                current.siteDomainId,

              status: 'OPEN',

              openedAfterFailures:
                transition.consecutiveFailures,

              lastFailureCode:
                probe.failureCode,

              lastFailureMessage:
                probe.failureMessage,
            },
          });

          await transaction.auditLog.create({
            data: {
              organizationId:
                current.organizationId,

              actorType: 'SYSTEM',

              action:
                'site_monitor.down',

              resourceType:
                'site_domain',

              resourceId:
                current.siteDomainId,

              outcome: 'SUCCESS',

              metadata: {
                siteId:
                  current.siteId,

                hostname:
                  current.siteDomain.hostname,

                consecutiveFailures:
                  transition.consecutiveFailures,

                failureCode:
                  probe.failureCode,

                httpStatus:
                  probe.httpStatus,
              },
            },
          });
        } else if (
          !probe.success &&
          openIncident
        ) {
          await transaction.siteMonitorIncident.update({
            where: {
              id: openIncident.id,
            },

            data: {
              lastFailureCode:
                probe.failureCode,

              lastFailureMessage:
                probe.failureMessage,
            },
          });
        }

        if (
          transition.resolveIncident &&
          openIncident
        ) {
          await transaction.siteMonitorIncident.update({
            where: {
              id: openIncident.id,
            },

            data: {
              status: 'RESOLVED',
              resolvedAt: checkedAt,
            },
          });

          await transaction.auditLog.create({
            data: {
              organizationId:
                current.organizationId,

              actorType: 'SYSTEM',

              action:
                'site_monitor.recovered',

              resourceType:
                'site_domain',

              resourceId:
                current.siteDomainId,

              outcome: 'SUCCESS',

              metadata: {
                siteId:
                  current.siteId,

                hostname:
                  current.siteDomain.hostname,

                recoverySuccesses:
                  transition.consecutiveSuccesses,

                httpStatus:
                  probe.httpStatus,

                latencyMs:
                  probe.latencyMs,
              },
            },
          });
        }

        return {
          checked: true,
          success: probe.success,
          openedIncident:
            transition.openIncident,
          resolvedIncident:
            transition.resolveIncident,
          lostLease: false,
        };
      },
    );
  }

  private async handleProcessingError(
    claimed: ClaimedMonitorState,
  ): Promise<void> {
    await this.database.siteMonitorState.updateMany({
      where: {
        id: claimed.id,

        claimedByWorkerId:
          this.workerId,
      },

      data: {
        claimedAt: null,
        claimedByWorkerId: null,
        leaseExpiresAt: null,

        nextCheckAt:
          addMilliseconds(
            new Date(),
            this.config.retryDelayMs,
          ),
      },
    });
  }
}
'@

Write-Text `
    -Path ".\apps\site-monitor-worker\src\site-monitor.service.ts" `
    -Content $MonitorService

# ============================================================
# SITE MONITOR WORKER MAIN
# ============================================================

$MonitorMain = @'
import './load-environment.js';

import {
  randomUUID,
} from 'node:crypto';

import {
  hostname,
} from 'node:os';

import {
  createDatabaseClient,
} from '@crm/database';

import {
  parseSiteMonitorConfig,
} from './site-monitor.config.js';

import {
  SiteMonitorService,
} from './site-monitor.service.js';

const service =
  'site-monitor-worker' as const;

const heartbeatIntervalMs =
  60_000;

const config =
  parseSiteMonitorConfig();

const workerId =
  process.env.SITE_MONITOR_WORKER_ID?.trim() ||
  `${hostname()}-${process.pid}-${randomUUID()}`;

const database =
  createDatabaseClient();

const monitor =
  new SiteMonitorService(
    database,
    workerId,
    config,
  );

let tickRunning = false;
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
      timestamp:
        new Date().toISOString(),
      ...extra,
    }),
  );
}

async function runTick(): Promise<void> {
  if (
    tickRunning ||
    shuttingDown
  ) {
    return;
  }

  tickRunning = true;

  try {
    const summary =
      await monitor.runTick();

    if (
      summary.claimed > 0 ||
      summary.openedIncidents > 0 ||
      summary.resolvedIncidents > 0 ||
      summary.lostLeases > 0
    ) {
      log(
        'site_monitor.tick',
        summary,
      );
    }
  } catch (error) {
    log(
      'site_monitor.error',
      {
        message:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );
  } finally {
    tickRunning = false;
  }
}

log(
  'service.started',
  {
    heartbeatIntervalMs,

    tickIntervalMs:
      config.tickIntervalMs,

    checkIntervalMs:
      config.checkIntervalMs,

    timeoutMs:
      config.timeoutMs,

    failureThreshold:
      config.failureThreshold,

    recoveryThreshold:
      config.recoveryThreshold,

    concurrency:
      config.concurrency,
  },
);

await runTick();

const tickTimer =
  setInterval(
    () => {
      void runTick();
    },

    config.tickIntervalMs,
  );

const heartbeatTimer =
  setInterval(
    () => {
      log(
        'service.heartbeat',
        {
          tickRunning,
        },
      );
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
    tickTimer,
  );

  clearInterval(
    heartbeatTimer,
  );

  log(
    'service.stopping',
    {
      signal,
    },
  );

  while (tickRunning) {
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

  log(
    'service.stopped',
    {
      signal,
    },
  );

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
    -Path ".\apps\site-monitor-worker\src\main.ts" `
    -Content $MonitorMain

Write-Host "[OK] Site monitor worker real criado." -ForegroundColor Green

# ============================================================
# ENV EXAMPLE
# ============================================================

$EnvExample = Read-Text -Path $EnvExamplePath

if (-not $EnvExample.Contains("SITE_MONITOR_TICK_INTERVAL_MS=")) {
    $MonitorEnvironment = @(
        "",
        "# Site Monitoring - Etapa 6",
        "SITE_MONITOR_TICK_INTERVAL_MS=1000",
        "SITE_MONITOR_CHECK_INTERVAL_MS=30000",
        "SITE_MONITOR_RETRY_DELAY_MS=5000",
        "SITE_MONITOR_TIMEOUT_MS=5000",
        "SITE_MONITOR_LEASE_MS=15000",
        "SITE_MONITOR_FAILURE_THRESHOLD=3",
        "SITE_MONITOR_RECOVERY_THRESHOLD=2",
        "SITE_MONITOR_CONCURRENCY=5",
        "SITE_MONITOR_MAX_CLAIMS_PER_TICK=25",
        "SITE_MONITOR_STATE_SYNC_INTERVAL_MS=60000",
        "SITE_MONITOR_CHECK_RETENTION_DAYS=14",
        "SITE_MONITOR_CLEANUP_INTERVAL_MS=21600000",
        "SITE_MONITOR_WORKER_ID="
    )

    $EnvExample = (
        $EnvExample.TrimEnd() +
        "`r`n" +
        ($MonitorEnvironment -join "`r`n") +
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
    ".\packages\contracts\src\site-monitoring.ts",
    ".\apps\api\src\sites\site-monitoring.service.ts",
    ".\apps\api\src\sites\site-monitoring.controller.ts",
    ".\apps\site-monitor-worker\src\load-environment.ts",
    ".\apps\site-monitor-worker\src\site-monitor.config.ts",
    ".\apps\site-monitor-worker\src\site-monitor-engine.ts",
    ".\apps\site-monitor-worker\src\site-monitor-engine.spec.ts",
    ".\apps\site-monitor-worker\src\safe-probe.ts",
    ".\apps\site-monitor-worker\src\safe-probe.spec.ts",
    ".\apps\site-monitor-worker\src\site-monitor.service.ts",
    ".\apps\site-monitor-worker\src\main.ts"
)

foreach ($RequiredFile in $RequiredFiles) {
    if (-not (Test-Path $RequiredFile)) {
        throw "Arquivo Stage 6 ausente: $RequiredFile"
    }
}

$SchemaFinal = Read-Text -Path $SchemaPath

$RequiredSchemaMarkers = @(
    "enum SiteMonitorStatus",
    "enum SiteMonitorCheckOutcome",
    "enum SiteMonitorIncidentStatus",
    "model SiteMonitorState",
    "model SiteMonitorCheck",
    "model SiteMonitorIncident",
    "monitoringEnabled Boolean"
)

foreach ($Marker in $RequiredSchemaMarkers) {
    if (-not $SchemaFinal.Contains($Marker)) {
        throw "Marker Stage 6 ausente no schema: $Marker"
    }
}

$SchedulerFinal = Read-Text -Path $AdsSchedulerPath

if (-not $SchedulerFinal.Contains("'ads_queue.site_down'")) {
    throw "Scheduler nao foi integrado ao monitoramento."
}

$MonitorMainFinal = Read-Text `
    -Path ".\apps\site-monitor-worker\src\main.ts"

if (-not $MonitorMainFinal.Contains("SiteMonitorService")) {
    throw "SiteMonitorService nao registrado no worker."
}

$SafeProbeFinal = Read-Text `
    -Path ".\apps\site-monitor-worker\src\safe-probe.ts"

if (-not $SafeProbeFinal.Contains("SECURITY_BLOCKED_ADDRESS")) {
    throw "Protecao SSRF nao encontrada."
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host "[OK] MACROBLOCO 6.1 CRIADO." -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Implementado:" -ForegroundColor Cyan
Write-Host "- SiteMonitorState"
Write-Host "- SiteMonitorCheck"
Write-Host "- SiteMonitorIncident"
Write-Host "- UNKNOWN / HEALTHY / DEGRADED / DOWN"
Write-Host "- monitoringEnabled por dominio"
Write-Host "- checks HTTPS reais"
Write-Host "- DNS resolution"
Write-Host "- bloqueio SSRF/private IP"
Write-Host "- TLS validation"
Write-Host "- HTTP status validation"
Write-Host "- latency tracking"
Write-Host "- failure threshold"
Write-Host "- recovery threshold"
Write-Host "- DOWN incident"
Write-Host "- automatic recovery"
Write-Host "- historical checks"
Write-Host "- check retention"
Write-Host "- worker claim com SKIP LOCKED"
Write-Host "- worker lease"
Write-Host "- multi-worker safety"
Write-Host "- scheduler gate quando primary domain DOWN"
Write-Host "- API GET site monitoring"
Write-Host "- API GET last 100 domain checks"
Write-Host "- ADMIN/EMPLOYEE tenant isolation via existing permissions"
Write-Host "- monitor state separado de SiteStatus"
Write-Host ""
Write-Host "Migration ainda NAO executada." -ForegroundColor Yellow
Write-Host "Proximo: Macrobloco 6.2." -ForegroundColor Yellow