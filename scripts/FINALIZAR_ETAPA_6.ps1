Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepositoryRoot

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    Write-Host ""
    Write-Host "==== $Description ====" -ForegroundColor Cyan

    & $Command @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "$Description falhou com exit code $LASTEXITCODE."
    }

    Write-Host "[OK] $Description" -ForegroundColor Green
}

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

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " ETAPA 6 - MACROBLOCO 6.2" -ForegroundColor Cyan
Write-Host " SITE MONITORING AUDIT + CLOSURE" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

# ============================================================
# PREFLIGHT
# ============================================================

$RequiredFiles = @(
    ".\apps\site-monitor-worker\src\site-monitor.config.ts",
    ".\apps\site-monitor-worker\src\site-monitor-engine.ts",
    ".\apps\site-monitor-worker\src\safe-probe.ts",
    ".\apps\site-monitor-worker\src\site-monitor.service.ts",
    ".\apps\site-monitor-worker\src\main.ts",
    ".\apps\api\src\sites\site-monitoring.service.ts",
    ".\apps\api\src\sites\site-monitoring.controller.ts",
    ".\packages\contracts\src\site-monitoring.ts",
    ".\packages\database\prisma\schema.prisma"
)

foreach ($RequiredFile in $RequiredFiles) {
    if (-not (Test-Path $RequiredFile)) {
        throw "Macrobloco 6.1 incompleto: $RequiredFile"
    }
}

Write-Host "[OK] Preflight 6.1." -ForegroundColor Green

# ============================================================
# HARDEN TESTABILITY: INJECTABLE PROBE + TEST SCOPE
# ============================================================

$MonitorServicePath = ".\apps\site-monitor-worker\src\site-monitor.service.ts"
$MonitorService = Read-Text -Path $MonitorServicePath

if (-not $MonitorService.Contains("export type SiteProbe =")) {
    $OldImportPattern = "import\s*\{\s*probeHostname,\s*\}\s*from './safe-probe\.js';"

    $NewImport = @'
import {
  probeHostname,
  type SiteProbeResult,
} from './safe-probe.js';

export type SiteProbe = (
  hostname: string,
  timeoutMs: number,
) => Promise<SiteProbeResult>;
'@

    if (-not [regex]::IsMatch($MonitorService, $OldImportPattern)) {
        throw "Import probeHostname nao encontrado."
    }

    $MonitorService = [regex]::Replace(
        $MonitorService,
        $OldImportPattern,
        $NewImport.Trim(),
        1
    )
}

if (-not $MonitorService.Contains("private readonly probe: SiteProbe")) {
    $ConstructorPattern = "private readonly config:\s*SiteMonitorConfig,\s*\)\s*\{\}"

    $ConstructorReplacement = @'
private readonly config:
      SiteMonitorConfig,

    private readonly probe:
      SiteProbe = probeHostname,

    private readonly scopeSiteDomainId:
      string | null = null,
  ) {}
'@

    if (-not [regex]::IsMatch($MonitorService, $ConstructorPattern)) {
        throw "Constructor do SiteMonitorService nao encontrado."
    }

    $MonitorService = [regex]::Replace(
        $MonitorService,
        $ConstructorPattern,
        $ConstructorReplacement.TrimEnd(),
        1
    )
}

if (-not $MonitorService.Contains("...(this.scopeSiteDomainId")) {
    $Anchor = "          monitoringEnabled: true,"

    if (-not $MonitorService.Contains($Anchor)) {
        throw "Anchor ensureMonitorStates nao encontrado."
    }

    $ScopedWhere = @'
          monitoringEnabled: true,

          ...(this.scopeSiteDomainId
            ? {
                id: this.scopeSiteDomainId,
              }
            : {}),
'@

    $MonitorService = $MonitorService.Replace(
        $Anchor,
        $ScopedWhere.TrimEnd()
    )
}

if (-not $MonitorService.Contains('$3::uuid IS NULL')) {
    $Anchor = "              domain.`"monitoringEnabled`" = TRUE"

    if (-not $MonitorService.Contains($Anchor)) {
        throw "Anchor SQL monitor claim nao encontrado."
    }

    $Replacement = @'
              domain."monitoringEnabled" = TRUE
              AND (
                $3::uuid IS NULL
                OR state."siteDomainId" = $3::uuid
              )
'@

    $MonitorService = $MonitorService.Replace(
        $Anchor,
        $Replacement.TrimEnd()
    )

    $ArgumentAnchor = "        this.config.leaseMs,"

    if (-not $MonitorService.Contains($ArgumentAnchor)) {
        throw "Anchor argumentos claim nao encontrado."
    }

    $MonitorService = $MonitorService.Replace(
        $ArgumentAnchor,
        $ArgumentAnchor + "`r`n        this.scopeSiteDomainId,"
    )
}

$MonitorService = $MonitorService.Replace(
    "await probeHostname(",
    "await this.probe("
)

Write-Text `
    -Path $MonitorServicePath `
    -Content $MonitorService

Write-Host "[OK] SiteMonitorService preparado para testes deterministas." -ForegroundColor Green

# ============================================================
# API AGGREGATE HEALTH WHEN MONITORING DISABLED
# ============================================================

$MonitoringApiPath = ".\apps\api\src\sites\site-monitoring.service.ts"
$MonitoringApi = Read-Text -Path $MonitoringApiPath

$OldAggregate = @'
    const status =
      primaryDomain?.monitorState?.status ??
      'UNKNOWN';
'@

if ($MonitoringApi.Contains($OldAggregate)) {
    $NewAggregate = @'
    const status =
      primaryDomain?.monitoringEnabled === true
        ? primaryDomain.monitorState?.status ??
          'UNKNOWN'
        : 'UNKNOWN';
'@

    $MonitoringApi = $MonitoringApi.Replace(
        $OldAggregate,
        $NewAggregate
    )

    Write-Text `
        -Path $MonitoringApiPath `
        -Content $MonitoringApi
}

Write-Host "[OK] Aggregate health API hardened." -ForegroundColor Green

# ============================================================
# WORKSPACE INSTALL
# ============================================================

Invoke-Native `
    -Description "pnpm install" `
    -Command "pnpm" `
    -Arguments @("install")

# ============================================================
# PRISMA FORMAT + VALIDATE
# ============================================================

Invoke-Native `
    -Description "Prisma format" `
    -Command "pnpm" `
    -Arguments @("db:format")

Invoke-Native `
    -Description "Prisma validate" `
    -Command "pnpm" `
    -Arguments @("db:validate")

# ============================================================
# MIGRATION
# ============================================================

$MigrationRoot = ".\packages\database\prisma\migrations"

$Migration = Get-ChildItem `
    -Path $MigrationRoot `
    -Directory `
    -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -like "*stage_6_site_monitoring*"
    } |
    Select-Object -First 1

if ($null -eq $Migration) {
    Invoke-Native `
        -Description "Create Stage 6 migration" `
        -Command "pnpm" `
        -Arguments @(
            "--filter",
            "@crm/database",
            "exec",
            "prisma",
            "migrate",
            "dev",
            "--name",
            "stage_6_site_monitoring",
            "--create-only"
        )
}

$Migration = Get-ChildItem `
    -Path $MigrationRoot `
    -Directory `
    -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -like "*stage_6_site_monitoring*"
    } |
    Select-Object -First 1

if ($null -eq $Migration) {
    throw "Migration Stage 6 nao encontrada."
}

Write-Host "[OK] Migration encontrada: $($Migration.Name)" -ForegroundColor Green

Invoke-Native `
    -Description "Deploy Stage 6 migration" `
    -Command "pnpm" `
    -Arguments @("db:migrate:deploy")

Invoke-Native `
    -Description "Prisma generate" `
    -Command "pnpm" `
    -Arguments @("db:generate")

Invoke-Native `
    -Description "Verify seed" `
    -Command "pnpm" `
    -Arguments @("db:verify-seed")

Invoke-Native `
    -Description "Migration status" `
    -Command "pnpm" `
    -Arguments @("db:migrate:status")

# ============================================================
# FORMAT
# ============================================================

Invoke-Native `
    -Description "Format repository" `
    -Command "pnpm" `
    -Arguments @("format")

# ============================================================
# PACKAGE VALIDATION
# ============================================================

Invoke-Native `
    -Description "Site monitor lint" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/site-monitor-worker",
        "lint"
    )

Invoke-Native `
    -Description "Site monitor typecheck" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/site-monitor-worker",
        "typecheck"
    )

Invoke-Native `
    -Description "Site monitor tests" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/site-monitor-worker",
        "test"
    )

Invoke-Native `
    -Description "ADS worker typecheck" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/worker",
        "typecheck"
    )

Invoke-Native `
    -Description "API typecheck" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/api",
        "typecheck"
    )

Invoke-Native `
    -Description "Site monitor build" `
    -Command "pnpm" `
    -Arguments @(
        "exec",
        "turbo",
        "run",
        "build",
        "--filter=@crm/site-monitor-worker"
    )

Invoke-Native `
    -Description "ADS worker build" `
    -Command "pnpm" `
    -Arguments @(
        "exec",
        "turbo",
        "run",
        "build",
        "--filter=@crm/worker"
    )

Invoke-Native `
    -Description "API build" `
    -Command "pnpm" `
    -Arguments @(
        "exec",
        "turbo",
        "run",
        "build",
        "--filter=@crm/api"
    )

# ============================================================
# RUNTIME VALIDATOR
# ============================================================

$RuntimeValidator = @'
import '../src/load-environment.js';

import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';

import {
  createDatabaseClient,
} from '@crm/database';

import {
  AdsSchedulerService,
} from '../../worker/src/ads-scheduler.service.js';

import type {
  AdsSchedulerConfig,
} from '../../worker/src/scheduler.config.js';

import {
  probeHostname,
  type SiteProbeResult,
} from '../src/safe-probe.js';

import {
  SiteMonitorService,
  type SiteProbe,
} from '../src/site-monitor.service.js';

import type {
  SiteMonitorConfig,
} from '../src/site-monitor.config.js';

const employeeId =
  process.env.STAGE6_EMPLOYEE_ID?.trim();

if (!employeeId) {
  throw new Error(
    'STAGE6_EMPLOYEE_ID is required.',
  );
}

const database =
  createDatabaseClient();

const organizationSlug =
  process.env.SEED_ORGANIZATION_SLUG?.trim() ||
  'crm-ads-whatsapp';

const unique =
  randomUUID()
    .replaceAll('-', '')
    .slice(0, 16);

const fixturePrefix =
  'stage6-runtime-';

const monitorConfig: SiteMonitorConfig = {
  tickIntervalMs: 100,
  checkIntervalMs: 60_000,
  retryDelayMs: 60_000,
  timeoutMs: 1_000,
  leaseMs: 30_000,
  failureThreshold: 3,
  recoveryThreshold: 2,
  concurrency: 1,
  maxClaimsPerTick: 1,
  stateSyncIntervalMs: 3_600_000,
  checkRetentionDays: 14,
  cleanupIntervalMs: 86_400_000,
};

const schedulerConfig: AdsSchedulerConfig = {
  intervalMs: 100,
  microbatchSize: 5,
  maxInflightPerEmployee: 1_000_000,
  leaseMs: 30_000,
  backpressureDelayMs: 60_000,
  microbatchYieldMs: 0,
  maxClaimsPerTick: 1,
  maxQueueAttempts: 25,
};

function event(
  name: string,
  extra: Record<string, unknown> = {},
): void {
  console.log(
    JSON.stringify({
      event: name,
      timestamp:
        new Date().toISOString(),
      ...extra,
    }),
  );
}

async function cleanupFixtures(): Promise<void> {
  const sites =
    await database.site.findMany({
      where: {
        ownerEmployeeId: employeeId,

        slug: {
          startsWith:
            fixturePrefix,
        },
      },

      select: {
        id: true,
      },
    });

  for (const site of sites) {
    const requests =
      await database.adsRequest.findMany({
        where: {
          siteId: site.id,
        },

        select: {
          id: true,
        },
      });

    const requestIds =
      requests.map(
        (request) => request.id,
      );

    const pools =
      await database.trafficPool.findMany({
        where: {
          siteId: site.id,
        },

        select: {
          id: true,
        },
      });

    const poolIds =
      pools.map(
        (pool) => pool.id,
      );

    const members =
      poolIds.length > 0
        ? await database.trafficPoolMember.findMany({
            where: {
              trafficPoolId: {
                in: poolIds,
              },
            },

            select: {
              whatsAppNumberId: true,
            },
          })
        : [];

    const numberIds =
      [
        ...new Set(
          members.map(
            (member) =>
              member.whatsAppNumberId,
          ),
        ),
      ];

    if (requestIds.length > 0) {
      const microbatches =
        await database.adsMicrobatch.findMany({
          where: {
            adsRequestId: {
              in: requestIds,
            },
          },

          select: {
            id: true,
          },
        });

      const queueItems =
        await database.adsQueueItem.findMany({
          where: {
            adsRequestId: {
              in: requestIds,
            },
          },

          select: {
            id: true,
          },
        });

      const auditResourceIds = [
        ...requestIds,
        ...microbatches.map(
          (item) => item.id,
        ),
        ...queueItems.map(
          (item) => item.id,
        ),
      ];

      if (auditResourceIds.length > 0) {
        await database.auditLog.deleteMany({
          where: {
            resourceId: {
              in: auditResourceIds,
            },
          },
        });
      }

      await database.adsMicrobatch.deleteMany({
        where: {
          adsRequestId: {
            in: requestIds,
          },
        },
      });

      await database.adsQueueItem.deleteMany({
        where: {
          adsRequestId: {
            in: requestIds,
          },
        },
      });

      await database.adsRequest.deleteMany({
        where: {
          id: {
            in: requestIds,
          },
        },
      });
    }

    const domains =
      await database.siteDomain.findMany({
        where: {
          siteId: site.id,
        },

        select: {
          id: true,
        },
      });

    const domainIds =
      domains.map(
        (domain) => domain.id,
      );

    if (domainIds.length > 0) {
      await database.auditLog.deleteMany({
        where: {
          resourceId: {
            in: domainIds,
          },
        },
      });

      await database.siteMonitorCheck.deleteMany({
        where: {
          siteDomainId: {
            in: domainIds,
          },
        },
      });

      await database.siteMonitorIncident.deleteMany({
        where: {
          siteDomainId: {
            in: domainIds,
          },
        },
      });

      await database.siteMonitorState.deleteMany({
        where: {
          siteDomainId: {
            in: domainIds,
          },
        },
      });

      await database.siteDomain.deleteMany({
        where: {
          id: {
            in: domainIds,
          },
        },
      });
    }

    if (poolIds.length > 0) {
      await database.trafficPoolMember.deleteMany({
        where: {
          trafficPoolId: {
            in: poolIds,
          },
        },
      });

      await database.trafficPoolSchedulerState.deleteMany({
        where: {
          trafficPoolId: {
            in: poolIds,
          },
        },
      });

      await database.trafficPool.deleteMany({
        where: {
          id: {
            in: poolIds,
          },
        },
      });
    }

    if (numberIds.length > 0) {
      await database.whatsAppNumber.deleteMany({
        where: {
          id: {
            in: numberIds,
          },
        },
      });
    }

    await database.site.delete({
      where: {
        id: site.id,
      },
    });
  }
}

function failureProbe(
  code: string,
): SiteProbeResult {
  return {
    success: false,
    httpStatus: null,
    latencyMs: 25,
    resolvedAddress:
      '8.8.8.8',
    failureCode: code,
    failureMessage:
      `Simulated ${code}`,
  };
}

function successProbe(): SiteProbeResult {
  return {
    success: true,
    httpStatus: 200,
    latencyMs: 20,
    resolvedAddress:
      '8.8.8.8',
    failureCode: null,
    failureMessage: null,
  };
}

async function forceDue(
  siteDomainId: string,
): Promise<void> {
  await database.siteMonitorState.update({
    where: {
      organizationId_siteDomainId: {
        organizationId:
          organization.id,

        siteDomainId,
      },
    },

    data: {
      nextCheckAt:
        new Date(0),

      claimedAt: null,
      claimedByWorkerId: null,
      leaseExpiresAt: null,
    },
  });
}

let organization:
  Awaited<
    ReturnType<
      typeof database.organization.findUniqueOrThrow
    >
  >;

try {
  event(
    'stage6.validation.started',
  );

  await cleanupFixtures();

  organization =
    await database.organization.findUniqueOrThrow({
      where: {
        slug: organizationSlug,
      },
    });

  const employee =
    await database.employee.findFirstOrThrow({
      where: {
        id: employeeId,
        organizationId:
          organization.id,
        status: 'ACTIVE',
        deletedAt: null,
      },
    });

  const site =
    await database.site.create({
      data: {
        organizationId:
          organization.id,

        ownerEmployeeId:
          employee.id,

        name:
          'Stage 6 Runtime Site',

        slug:
          `${fixturePrefix}${unique}`,

        status: 'ACTIVE',
      },
    });

  const primaryDomain =
    await database.siteDomain.create({
      data: {
        organizationId:
          organization.id,

        siteId:
          site.id,

        hostname:
          `stage6-${unique}.example.com`,

        status: 'ACTIVE',
        isPrimary: true,
        monitoringEnabled: true,
      },
    });

  await database.siteMonitorState.create({
    data: {
      organizationId:
        organization.id,

      siteId:
        site.id,

      siteDomainId:
        primaryDomain.id,

      nextCheckAt:
        new Date(0),
    },
  });

  const probeSequence:
    SiteProbeResult[] = [
      failureProbe('SIMULATED_1'),
      failureProbe('SIMULATED_2'),
      failureProbe('SIMULATED_3'),
      successProbe(),
      successProbe(),
      successProbe(),
    ];

  const deterministicProbe: SiteProbe =
    async () => {
      const result =
        probeSequence.shift();

      if (!result) {
        return successProbe();
      }

      return result;
    };

  const monitor =
    new SiteMonitorService(
      database,
      `stage6-monitor-${unique}`,
      monitorConfig,
      deterministicProbe,
      primaryDomain.id,
    );

  await monitor.runTick();

  let state =
    await database.siteMonitorState.findUniqueOrThrow({
      where: {
        organizationId_siteDomainId: {
          organizationId:
            organization.id,

          siteDomainId:
            primaryDomain.id,
        },
      },
    });

  assert.equal(
    state.status,
    'DEGRADED',
  );

  assert.equal(
    state.consecutiveFailures,
    1,
  );

  assert.equal(
    await database.siteMonitorIncident.count({
      where: {
        siteDomainId:
          primaryDomain.id,

        status: 'OPEN',
      },
    }),
    0,
  );

  event(
    'stage6.first_failure.passed',
  );

  await forceDue(
    primaryDomain.id,
  );

  await monitor.runTick();

  state =
    await database.siteMonitorState.findUniqueOrThrow({
      where: {
        organizationId_siteDomainId: {
          organizationId:
            organization.id,

          siteDomainId:
            primaryDomain.id,
        },
      },
    });

  assert.equal(
    state.status,
    'DEGRADED',
  );

  assert.equal(
    state.consecutiveFailures,
    2,
  );

  await forceDue(
    primaryDomain.id,
  );

  await monitor.runTick();

  state =
    await database.siteMonitorState.findUniqueOrThrow({
      where: {
        organizationId_siteDomainId: {
          organizationId:
            organization.id,

          siteDomainId:
            primaryDomain.id,
        },
      },
    });

  assert.equal(
    state.status,
    'DOWN',
  );

  assert.equal(
    state.consecutiveFailures,
    3,
  );

  assert.ok(
    state.downSince,
  );

  const openIncident =
    await database.siteMonitorIncident.findFirstOrThrow({
      where: {
        siteDomainId:
          primaryDomain.id,

        status: 'OPEN',
      },
    });

  assert.equal(
    openIncident.openedAfterFailures,
    3,
  );

  event(
    'stage6.down_incident.passed',
    {
      incidentId:
        openIncident.id,
    },
  );

  const downAudit =
    await database.auditLog.count({
      where: {
        action:
          'site_monitor.down',

        resourceId:
          primaryDomain.id,
      },
    });

  assert.ok(
    downAudit >= 1,
  );

  # This line is intentionally replaced below by TypeScript-safe content.
} finally {
  await database.$disconnect();
}
'@

# PowerShell comment above would be invalid TypeScript if left in generated content.
$RuntimeValidator = $RuntimeValidator.Replace(
    "  # This line is intentionally replaced below by TypeScript-safe content.`r`n",
    ""
)

$RuntimeContinuation = @'

  await forceDue(
    primaryDomain.id,
  );

  await monitor.runTick();

  state =
    await database.siteMonitorState.findUniqueOrThrow({
      where: {
        organizationId_siteDomainId: {
          organizationId:
            organization.id,

          siteDomainId:
            primaryDomain.id,
        },
      },
    });

  assert.equal(
    state.status,
    'DEGRADED',
  );

  assert.equal(
    state.consecutiveSuccesses,
    1,
  );

  assert.equal(
    await database.siteMonitorIncident.count({
      where: {
        siteDomainId:
          primaryDomain.id,

        status: 'OPEN',
      },
    }),
    1,
  );

  event(
    'stage6.partial_recovery.passed',
  );

  await forceDue(
    primaryDomain.id,
  );

  await monitor.runTick();

  state =
    await database.siteMonitorState.findUniqueOrThrow({
      where: {
        organizationId_siteDomainId: {
          organizationId:
            organization.id,

          siteDomainId:
            primaryDomain.id,
        },
      },
    });

  assert.equal(
    state.status,
    'HEALTHY',
  );

  assert.equal(
    state.consecutiveSuccesses,
    2,
  );

  assert.equal(
    state.downSince,
    null,
  );

  assert.ok(
    state.recoveredAt,
  );

  const resolvedIncident =
    await database.siteMonitorIncident.findUniqueOrThrow({
      where: {
        id: openIncident.id,
      },
    });

  assert.equal(
    resolvedIncident.status,
    'RESOLVED',
  );

  assert.ok(
    resolvedIncident.resolvedAt,
  );

  const recoveryAudit =
    await database.auditLog.count({
      where: {
        action:
          'site_monitor.recovered',

        resourceId:
          primaryDomain.id,
      },
    });

  assert.ok(
    recoveryAudit >= 1,
  );

  event(
    'stage6.recovery.passed',
  );

  const lifecycleChecks =
    await database.siteMonitorCheck.findMany({
      where: {
        siteDomainId:
          primaryDomain.id,
      },

      orderBy: {
        checkedAt: 'asc',
      },
    });

  assert.equal(
    lifecycleChecks.length,
    5,
  );

  assert.deepEqual(
    lifecycleChecks.map(
      (check) =>
        check.statusAfter,
    ),
    [
      'DEGRADED',
      'DEGRADED',
      'DOWN',
      'DEGRADED',
      'HEALTHY',
    ],
  );

  event(
    'stage6.history.passed',
    {
      checks:
        lifecycleChecks.length,
    },
  );

  const ssrfResult =
    await probeHostname(
      'localhost',
      1_000,
    );

  assert.equal(
    ssrfResult.success,
    false,
  );

  assert.equal(
    ssrfResult.failureCode,
    'SECURITY_BLOCKED_ADDRESS',
  );

  event(
    'stage6.ssrf.passed',
  );

  await database.siteMonitorState.update({
    where: {
      organizationId_siteDomainId: {
        organizationId:
          organization.id,

        siteDomainId:
          primaryDomain.id,
      },
    },

    data: {
      status: 'HEALTHY',

      nextCheckAt:
        new Date(
          Date.now() +
            3_600_000,
        ),

      claimedAt:
        new Date(
          Date.now() -
            60_000,
        ),

      claimedByWorkerId:
        'dead-stage6-worker',

      leaseExpiresAt:
        new Date(
          Date.now() -
            30_000,
        ),
    },
  });

  const checksBeforeLeaseRecovery =
    await database.siteMonitorCheck.count({
      where: {
        siteDomainId:
          primaryDomain.id,
      },
    });

  await monitor.runTick();

  const checksAfterLeaseRecovery =
    await database.siteMonitorCheck.count({
      where: {
        siteDomainId:
          primaryDomain.id,
      },
    });

  assert.equal(
    checksAfterLeaseRecovery,
    checksBeforeLeaseRecovery + 1,
  );

  const recoveredLeaseState =
    await database.siteMonitorState.findUniqueOrThrow({
      where: {
        organizationId_siteDomainId: {
          organizationId:
            organization.id,

          siteDomainId:
            primaryDomain.id,
        },
      },
    });

  assert.equal(
    recoveredLeaseState.claimedByWorkerId,
    null,
  );

  assert.equal(
    recoveredLeaseState.leaseExpiresAt,
    null,
  );

  event(
    'stage6.lease_recovery.passed',
  );

  const secondaryDomain =
    await database.siteDomain.create({
      data: {
        organizationId:
          organization.id,

        siteId:
          site.id,

        hostname:
          `stage6-concurrency-${unique}.example.com`,

        status: 'ACTIVE',
        isPrimary: false,
        monitoringEnabled: true,
      },
    });

  await database.siteMonitorState.create({
    data: {
      organizationId:
        organization.id,

      siteId:
        site.id,

      siteDomainId:
        secondaryDomain.id,

      nextCheckAt:
        new Date(0),
    },
  });

  let concurrentProbeCalls = 0;

  const concurrentProbe: SiteProbe =
    async () => {
      concurrentProbeCalls += 1;

      await new Promise<void>(
        (resolve) => {
          setTimeout(
            resolve,
            150,
          );
        },
      );

      return successProbe();
    };

  const monitorA =
    new SiteMonitorService(
      database,
      `stage6-a-${unique}`,
      monitorConfig,
      concurrentProbe,
      secondaryDomain.id,
    );

  const monitorB =
    new SiteMonitorService(
      database,
      `stage6-b-${unique}`,
      monitorConfig,
      concurrentProbe,
      secondaryDomain.id,
    );

  await Promise.all([
    monitorA.runTick(),
    monitorB.runTick(),
  ]);

  const concurrentChecks =
    await database.siteMonitorCheck.count({
      where: {
        siteDomainId:
          secondaryDomain.id,
      },
    });

  assert.equal(
    concurrentChecks,
    1,
  );

  assert.equal(
    concurrentProbeCalls,
    1,
  );

  event(
    'stage6.concurrent_claim.passed',
  );

  const pool =
    await database.trafficPool.create({
      data: {
        organizationId:
          organization.id,

        siteId:
          site.id,

        name:
          'Stage 6 Scheduler Pool',

        slug:
          `stage6-pool-${unique}`,

        status: 'ACTIVE',
      },
    });

  const whatsAppNumber =
    await database.whatsAppNumber.create({
      data: {
        organizationId:
          organization.id,

        assignedEmployeeId:
          employee.id,

        displayName:
          'Stage 6 Scheduler Number',

        e164:
          `+1998${Date.now()
            .toString()
            .slice(-10)}`,

        status: 'ACTIVE',
      },
    });

  await database.trafficPoolMember.create({
    data: {
      organizationId:
        organization.id,

      trafficPoolId:
        pool.id,

      whatsAppNumberId:
        whatsAppNumber.id,

      position: 1,
      status: 'ACTIVE',
    },
  });

  const requestAndQueue =
    await database.$transaction(
      async (transaction) => {
        const request =
          await transaction.adsRequest.create({
            data: {
              organizationId:
                organization.id,

              employeeId:
                employee.id,

              siteId:
                site.id,

              trafficPoolId:
                pool.id,

              requestedByUserId:
                employee.userId,

              requestedLeadCount:
                5,
            },
          });

        const queue =
          await transaction.adsQueueItem.create({
            data: {
              organizationId:
                organization.id,

              adsRequestId:
                request.id,

              employeeId:
                employee.id,

              trafficPoolId:
                pool.id,

              priority:
                -1_000_000,

              availableAt:
                new Date(0),
            },
          });

        return {
          request,
          queue,
        };
      },
    );

  await database.siteMonitorState.update({
    where: {
      organizationId_siteDomainId: {
        organizationId:
          organization.id,

        siteDomainId:
          primaryDomain.id,
      },
    },

    data: {
      status: 'DOWN',
      downSince: new Date(),
      nextCheckAt:
        new Date(
          Date.now() +
            3_600_000,
        ),
    },
  });

  const scheduler =
    new AdsSchedulerService(
      database,
      `stage6-scheduler-${unique}`,
      schedulerConfig,
    );

  await scheduler.runTick();

  let schedulerRequest =
    await database.adsRequest.findUniqueOrThrow({
      where: {
        id:
          requestAndQueue.request.id,
      },
    });

  let schedulerQueue =
    await database.adsQueueItem.findUniqueOrThrow({
      where: {
        id:
          requestAndQueue.queue.id,
      },
    });

  assert.equal(
    schedulerRequest.scheduledLeadCount,
    0,
  );

  assert.equal(
    schedulerQueue.status,
    'WAITING',
  );

  assert.equal(
    await database.adsMicrobatch.count({
      where: {
        adsRequestId:
          requestAndQueue.request.id,
      },
    }),
    0,
  );

  const siteDownQueueAudit =
    await database.auditLog.count({
      where: {
        action:
          'ads_queue.site_down',

        resourceId:
          requestAndQueue.queue.id,
      },
    });

  assert.ok(
    siteDownQueueAudit >= 1,
  );

  event(
    'stage6.scheduler_blocked.passed',
  );

  await database.siteMonitorState.update({
    where: {
      organizationId_siteDomainId: {
        organizationId:
          organization.id,

        siteDomainId:
          primaryDomain.id,
      },
    },

    data: {
      status: 'HEALTHY',
      downSince: null,
      recoveredAt:
        new Date(),
    },
  });

  await database.adsQueueItem.update({
    where: {
      id:
        requestAndQueue.queue.id,
    },

    data: {
      availableAt:
        new Date(0),
    },
  });

  await scheduler.runTick();

  schedulerRequest =
    await database.adsRequest.findUniqueOrThrow({
      where: {
        id:
          requestAndQueue.request.id,
      },
    });

  schedulerQueue =
    await database.adsQueueItem.findUniqueOrThrow({
      where: {
        id:
          requestAndQueue.queue.id,
      },
    });

  assert.equal(
    schedulerRequest.scheduledLeadCount,
    5,
  );

  assert.equal(
    schedulerRequest.status,
    'PROCESSING',
  );

  assert.equal(
    schedulerQueue.status,
    'COMPLETED',
  );

  assert.equal(
    await database.adsMicrobatch.count({
      where: {
        adsRequestId:
          requestAndQueue.request.id,
      },
    }),
    1,
  );

  event(
    'stage6.scheduler_recovery.passed',
  );

  event(
    'stage6.validation.completed',
  );
'@

# Replace the original finally section so continuation remains inside try.
$OldFinally = @'
} finally {
  await database.$disconnect();
}
'@

if (-not $RuntimeValidator.Contains($OldFinally)) {
    throw "Runtime validator base finally nao encontrado."
}

$RuntimeValidator = $RuntimeValidator.Replace(
    $OldFinally,
    $RuntimeContinuation + "`r`n} finally {`r`n  try {`r`n    await cleanupFixtures();`r`n  } finally {`r`n    await database.`$disconnect();`r`n  }`r`n}`r`n"
)

Write-Text `
    -Path ".\apps\site-monitor-worker\scripts\stage6-runtime-validation.ts" `
    -Content $RuntimeValidator

Write-Host "[OK] Stage 6 runtime validator criado." -ForegroundColor Green

# ============================================================
# FORMAT VALIDATOR
# ============================================================

Invoke-Native `
    -Description "Format runtime validator" `
    -Command "pnpm" `
    -Arguments @("format")

# ============================================================
# GLOBAL CI
# ============================================================

Invoke-Native `
    -Description "Global CI Stage 6" `
    -Command "pnpm" `
    -Arguments @("ci:check")

# ============================================================
# FIND EMPLOYEE FOR RUNTIME
# ============================================================

Write-Host ""
Write-Host "==== Stage 6 runtime employee ====" -ForegroundColor Cyan

$EmployeeJson = & pnpm `
    --filter `
    "@crm/api" `
    exec `
    tsx `
    -e `
    "import './src/load-environment.ts'; import { createDatabaseClient } from '@crm/database'; const db=createDatabaseClient(); const main=async()=>{const org=await db.organization.findUniqueOrThrow({where:{slug:process.env.SEED_ORGANIZATION_SLUG?.trim()||'crm-ads-whatsapp'}}); const e=await db.employee.findFirst({where:{organizationId:org.id,status:'ACTIVE',deletedAt:null},orderBy:{createdAt:'asc'},select:{id:true}}); if(!e) throw new Error('No active employee'); console.log(JSON.stringify(e));}; main().finally(()=>db.`$disconnect());"

if ($LASTEXITCODE -ne 0) {
    throw "Nao foi possivel localizar Employee para runtime."
}

$EmployeeLine = @(
    $EmployeeJson |
    Where-Object {
        $_ -match '^\{.*"id".*\}$'
    }
) | Select-Object -Last 1

if (-not $EmployeeLine) {
    throw "Employee JSON nao encontrado."
}

$RuntimeEmployee = $EmployeeLine | ConvertFrom-Json
$RuntimeEmployeeId = [string]$RuntimeEmployee.id

if ([string]::IsNullOrWhiteSpace($RuntimeEmployeeId)) {
    throw "EmployeeId runtime vazio."
}

Write-Host "[OK] Employee runtime localizado." -ForegroundColor Green

# ============================================================
# DATABASE RUNTIME VALIDATION
# ============================================================

Write-Host ""
Write-Host "==== Stage 6 database runtime validation ====" -ForegroundColor Cyan

$HadEmployeeEnvironment = Test-Path Env:STAGE6_EMPLOYEE_ID
$PreviousEmployeeEnvironment = $null

if ($HadEmployeeEnvironment) {
    $PreviousEmployeeEnvironment = $env:STAGE6_EMPLOYEE_ID
}

$env:STAGE6_EMPLOYEE_ID = $RuntimeEmployeeId

try {
    & pnpm `
        --filter `
        "@crm/site-monitor-worker" `
        exec `
        tsx `
        "scripts/stage6-runtime-validation.ts"

    if ($LASTEXITCODE -ne 0) {
        throw "Stage 6 database runtime validation falhou."
    }
}
finally {
    if ($HadEmployeeEnvironment) {
        $env:STAGE6_EMPLOYEE_ID = $PreviousEmployeeEnvironment
    }

    if (-not $HadEmployeeEnvironment) {
        Remove-Item `
            Env:STAGE6_EMPLOYEE_ID `
            -ErrorAction SilentlyContinue
    }
}

Write-Host "[OK] Stage 6 database runtime validation." -ForegroundColor Green

# ============================================================
# PROCESS SMOKE
# ============================================================

Write-Host ""
Write-Host "==== Site monitor worker process smoke ====" -ForegroundColor Cyan

$MonitorProcess = $null

try {
    $StartParameters = @{
        FilePath         = "node"
        ArgumentList     = "apps/site-monitor-worker/dist/main.js"
        WorkingDirectory = $RepositoryRoot
        NoNewWindow      = $true
        PassThru         = $true
    }

    $MonitorProcess = Start-Process @StartParameters

    Start-Sleep -Seconds 3

    if ($MonitorProcess.HasExited) {
        throw "Site monitor worker encerrou inesperadamente. ExitCode: $($MonitorProcess.ExitCode)"
    }

    Write-Host "[OK] Site monitor worker permaneceu online." -ForegroundColor Green
}
finally {
    if (
        $null -ne $MonitorProcess -and
        -not $MonitorProcess.HasExited
    ) {
        Stop-Process `
            -Id $MonitorProcess.Id `
            -Force `
            -ErrorAction SilentlyContinue
    }
}

# ============================================================
# DOCUMENTATION
# ============================================================

Write-Host ""
Write-Host "==== Stage 6 documentation ====" -ForegroundColor Cyan

$Stage6Document = @(
    "# Etapa 6 - Site Monitoring",
    "",
    "## Status",
    "",
    "CONCLUIDA.",
    "",
    "## Objetivo",
    "",
    "Monitorar a disponibilidade dos dominios dos Sites e impedir novos microlotes quando o dominio primario estiver confirmado como DOWN.",
    "",
    "## Entidades",
    "",
    "- SiteMonitorState",
    "- SiteMonitorCheck",
    "- SiteMonitorIncident",
    "",
    "## Estados",
    "",
    "- UNKNOWN",
    "- HEALTHY",
    "- DEGRADED",
    "- DOWN",
    "",
    "## Threshold de falha",
    "",
    "Uma falha isolada nao derruba o Site.",
    "",
    "Com o default atual, tres falhas consecutivas alteram o dominio para DOWN e abrem um incidente.",
    "",
    "## Recovery",
    "",
    "Com o default atual, dois sucessos consecutivos resolvem o incidente e restauram HEALTHY.",
    "",
    "## Scheduler",
    "",
    "Somente o dominio primario e usado como gate operacional do scheduler.",
    "",
    "UNKNOWN nao bloqueia.",
    "HEALTHY nao bloqueia.",
    "DEGRADED nao bloqueia.",
    "DOWN bloqueia novos microlotes.",
    "",
    "A recuperacao para HEALTHY permite que o scheduler continue automaticamente.",
    "",
    "## Seguranca",
    "",
    "O monitor resolve DNS antes da conexao.",
    "",
    "Enderecos privados, loopback, link-local, metadata cloud, multicast e ranges reservados sao bloqueados.",
    "",
    "HTTPS usa validacao TLS.",
    "",
    "O probe conecta diretamente ao IP publico validado e preserva Host/SNI para reduzir risco de DNS rebinding.",
    "",
    "## Concorrencia",
    "",
    "SiteMonitorState possui claim e lease.",
    "",
    "FOR UPDATE SKIP LOCKED evita normalmente que dois workers processem o mesmo dominio simultaneamente.",
    "",
    "Lease expirado permite recovery por outra instancia.",
    "",
    "## Historico",
    "",
    "Cada probe gera SiteMonitorCheck.",
    "",
    "O default de retencao e 14 dias.",
    "",
    "## API",
    "",
    "GET /api/v1/sites/:siteId/monitoring",
    "",
    "GET /api/v1/sites/:siteId/domains/:domainId/monitoring/checks",
    "",
    "As rotas reutilizam site.read e domain.read e respeitam o tenant e ownership ja existentes.",
    "",
    "## Separacao de estados",
    "",
    "SiteStatus continua representando decisao administrativa.",
    "",
    "SiteMonitorStatus representa telemetria operacional.",
    "",
    "Uma queda nao altera automaticamente SiteStatus.",
    "",
    "## Validacoes executadas",
    "",
    "- Prisma format e validate",
    "- migration",
    "- generate",
    "- seed verification",
    "- state engine unit tests",
    "- SSRF unit tests",
    "- failure 1 -> DEGRADED",
    "- failure 3 -> DOWN",
    "- incidente OPEN",
    "- primeiro success -> DEGRADED",
    "- segundo success -> HEALTHY",
    "- incidente RESOLVED",
    "- check history",
    "- localhost SSRF blocked",
    "- lease recovery",
    "- two-worker concurrent claim",
    "- scheduler blocked while DOWN",
    "- scheduler resumes on HEALTHY",
    "- worker process smoke",
    "- global ci:check",
    "",
    "## Proxima etapa",
    "",
    "Etapa 7 - PWA e OneSignal."
)

[System.IO.File]::WriteAllLines(
    [System.IO.Path]::GetFullPath(
        ".\docs\ETAPA_6_SITE_MONITORING.md"
    ),
    $Stage6Document,
    $Utf8NoBom
)

$Decisions = @(
    "# Decisoes - Etapa 6",
    "",
    "SiteStatus e SiteMonitorStatus permanecem separados.",
    "",
    "Todos os dominios ACTIVE com monitoringEnabled=true podem ser monitorados.",
    "",
    "Somente o dominio primario DOWN bloqueia o scheduler.",
    "",
    "UNKNOWN e DEGRADED nao bloqueiam distribuicao.",
    "",
    "Failure threshold default: 3.",
    "",
    "Recovery threshold default: 2.",
    "",
    "Checks normais: 30 segundos.",
    "",
    "Retry em estado nao saudavel: 5 segundos.",
    "",
    "Timeout HTTPS: 5 segundos.",
    "",
    "Lease: 15 segundos.",
    "",
    "Concorrencia default: 5.",
    "",
    "Retencao de SiteMonitorCheck: 14 dias.",
    "",
    "SSRF e mitigado por resolucao DNS, validacao de IP publico e conexao ao IP validado com Host/SNI preservados.",
    "",
    "Site monitor e separado do monitoramento futuro de qualidade/saude de numeros WhatsApp da Etapa 11."
)

[System.IO.File]::WriteAllLines(
    [System.IO.Path]::GetFullPath(
        ".\docs\DECISOES_ETAPA_6.md"
    ),
    $Decisions,
    $Utf8NoBom
)

$EtapasPath = ".\docs\ETAPAS.md"

if (Test-Path $EtapasPath) {
    $Etapas = Read-Text -Path $EtapasPath

    $Etapas = [regex]::Replace(
        $Etapas,
        '\|\s*3\s*\|\s*Sites, domínios, números e Traffic Pools\s*\|[^|]*\|',
        '|     3 | Sites, domínios, números e Traffic Pools  | CONCLUÍDA                   |'
    )

    $Etapas = [regex]::Replace(
        $Etapas,
        '\|\s*4\s*\|\s*Pedidos e fila de ADS\s*\|[^|]*\|',
        '|     4 | Pedidos e fila de ADS                     | CONCLUÍDA                   |'
    )

    $Etapas = [regex]::Replace(
        $Etapas,
        '\|\s*5\s*\|\s*Scheduler, microlotes e backpressure\s*\|[^|]*\|',
        '|     5 | Scheduler, microlotes e backpressure      | CONCLUÍDA                   |'
    )

    $Etapas = [regex]::Replace(
        $Etapas,
        '\|\s*6\s*\|\s*Monitoramento de sites\s*\|[^|]*\|',
        '|     6 | Monitoramento de sites                    | CONCLUÍDA                   |'
    )

    if (-not $Etapas.Contains("## Etapa 6 - Site Monitoring")) {
        $Summary = @(
            "",
            "## Etapa 6 - Site Monitoring",
            "",
            "Status: CONCLUIDA.",
            "",
            "Implementado:",
            "",
            "- SiteMonitorState",
            "- SiteMonitorCheck",
            "- SiteMonitorIncident",
            "- UNKNOWN / HEALTHY / DEGRADED / DOWN",
            "- HTTPS monitoring",
            "- SSRF protection",
            "- failure and recovery thresholds",
            "- incident lifecycle",
            "- historical checks",
            "- claim and lease",
            "- multi-worker safety",
            "- scheduler DOWN gate",
            "- automatic scheduler recovery",
            "- monitoring API",
            "",
            "Documentacao:",
            "",
            "- docs/ETAPA_6_SITE_MONITORING.md",
            "- docs/DECISOES_ETAPA_6.md",
            "",
            "Proxima: Etapa 7 - PWA e OneSignal."
        )

        $Etapas = (
            $Etapas.TrimEnd() +
            "`r`n" +
            ($Summary -join "`r`n") +
            "`r`n"
        )
    }

    Write-Text `
        -Path $EtapasPath `
        -Content $Etapas
}

Write-Host "[OK] Stage 6 documentation." -ForegroundColor Green

# ============================================================
# FINAL FORMAT
# ============================================================

Invoke-Native `
    -Description "Final format" `
    -Command "pnpm" `
    -Arguments @("format")

Invoke-Native `
    -Description "Final format check" `
    -Command "pnpm" `
    -Arguments @("format:check")

# ============================================================
# GIT DIFF CHECK
# ============================================================

Write-Host ""
Write-Host "==== Git diff check ====" -ForegroundColor Cyan

& git diff --check

if ($LASTEXITCODE -ne 0) {
    throw "git diff --check falhou."
}

Write-Host "[OK] git diff --check." -ForegroundColor Green

# ============================================================
# ENV SECURITY
# ============================================================

[string[]]$TrackedFiles = @(
    & git ls-files
)

if ($LASTEXITCODE -ne 0) {
    throw "git ls-files falhou."
}

[string[]]$TrackedEnvFiles = @(
    $TrackedFiles |
    Where-Object {
        $_ -match '(^|/)\.env($|\.)' -and
        $_ -notmatch '\.env\.example$'
    }
)

if (@($TrackedEnvFiles).Count -gt 0) {
    $TrackedEnvFiles
    throw "Arquivo .env real versionado."
}

Write-Host "[OK] Nenhum .env real versionado." -ForegroundColor Green

# ============================================================
# SECRET SCAN
# ============================================================

$SecretPattern = (
    'sk-' +
    'proj-' +
    '|AKIA' +
    '[0-9A-Z]{16}' +
    '|BEGIN ' +
    '(RSA|OPENSSH|EC)' +
    ' PRIVATE KEY'
)

[string[]]$SecretMatches = @(
    & git grep `
        -n `
        -I `
        -E `
        $SecretPattern `
        2>$null
)

$SecretExitCode = $LASTEXITCODE

if (
    $SecretExitCode -ne 0 -and
    $SecretExitCode -ne 1
) {
    throw "Secret scan falhou."
}

if (@($SecretMatches).Count -gt 0) {
    $SecretMatches
    throw "Possivel segredo encontrado."
}

Write-Host "[OK] Secret scan." -ForegroundColor Green

# ============================================================
# CLEAN LOCAL BACKUP
# ============================================================

Remove-Item `
    ".\tmp\stage6-macroblock1-backup" `
    -Recurse `
    -Force `
    -ErrorAction SilentlyContinue

# ============================================================
# FINAL STATUS
# ============================================================

Write-Host ""
Write-Host "==== Git status ====" -ForegroundColor Cyan

& git status --short

if ($LASTEXITCODE -ne 0) {
    throw "git status falhou."
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host "[OK] ETAPA 6 COMPLETAMENTE VALIDADA." -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Validado:" -ForegroundColor Cyan
Write-Host "- Prisma migration"
Write-Host "- Prisma generate"
Write-Host "- seed verification"
Write-Host "- site monitor lint"
Write-Host "- site monitor typecheck"
Write-Host "- state engine tests"
Write-Host "- SSRF tests"
Write-Host "- API typecheck"
Write-Host "- ADS scheduler typecheck"
Write-Host "- builds"
Write-Host "- global CI"
Write-Host "- DEGRADED lifecycle"
Write-Host "- DOWN lifecycle"
Write-Host "- incident opening"
Write-Host "- recovery threshold"
Write-Host "- incident resolution"
Write-Host "- check history"
Write-Host "- localhost SSRF block"
Write-Host "- lease recovery"
Write-Host "- concurrent monitor claim"
Write-Host "- scheduler site-down block"
Write-Host "- scheduler recovery"
Write-Host "- worker process smoke"
Write-Host "- documentation"
Write-Host "- git checks"
Write-Host "- secret scan"
Write-Host ""
Write-Host "Proxima etapa: ETAPA 7." -ForegroundColor Yellow