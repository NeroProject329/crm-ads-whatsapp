param(
    [Parameter(Mandatory = $true)]
    [string]$EmployeeId,

    [int]$WorkerSmokeSeconds = 3
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepositoryRoot

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$EmployeeId = $EmployeeId.Trim()

if ($EmployeeId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$') {
    throw "EmployeeId invalido."
}

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
Write-Host " ETAPA 5 - MACROBLOCO 5.2" -ForegroundColor Cyan
Write-Host " MIGRATION + CI + SCHEDULER AUDIT" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

# ============================================================
# PREFLIGHT
# ============================================================

$RequiredFiles = @(
    ".\apps\worker\src\scheduler.config.ts",
    ".\apps\worker\src\scheduler-engine.ts",
    ".\apps\worker\src\scheduler-engine.spec.ts",
    ".\apps\worker\src\ads-scheduler.service.ts",
    ".\apps\worker\src\main.ts",
    ".\packages\database\prisma\schema.prisma"
)

foreach ($RequiredFile in $RequiredFiles) {
    if (-not (Test-Path $RequiredFile)) {
        throw "Macrobloco 5.1 incompleto: $RequiredFile"
    }
}

Write-Host "[OK] Preflight 5.1." -ForegroundColor Green

# ============================================================
# HARDEN TRANSACTION TYPE
# ============================================================

$SchedulerServicePath = ".\apps\worker\src\ads-scheduler.service.ts"
$SchedulerService = Read-Text -Path $SchedulerServicePath

$OldTransactionPattern = "transaction:\s*Parameters<\s*Parameters<CrmDatabaseClient\['`$transaction'\]>\[0\]\s*>\[0\],"

if ([regex]::IsMatch($SchedulerService, $OldTransactionPattern)) {
    $SchedulerService = [regex]::Replace(
        $SchedulerService,
        $OldTransactionPattern,
        "transaction: Pick<CrmDatabaseClient, 'adsQueueItem' | 'auditLog'>,",
        1
    )

    Write-Text `
        -Path $SchedulerServicePath `
        -Content $SchedulerService

    Write-Host "[OK] Transaction helper type hardened." -ForegroundColor Green
}

# ============================================================
# INSTALL WORKSPACE LINKS + LOCKFILE
# ============================================================

Invoke-Native `
    -Description "pnpm install" `
    -Command "pnpm" `
    -Arguments @("install")

# ============================================================
# PRISMA
# ============================================================

Invoke-Native `
    -Description "Prisma format" `
    -Command "pnpm" `
    -Arguments @("db:format")

Invoke-Native `
    -Description "Prisma validate" `
    -Command "pnpm" `
    -Arguments @("db:validate")

$MigrationRoot = ".\packages\database\prisma\migrations"

$Migration = Get-ChildItem `
    -Path $MigrationRoot `
    -Directory `
    -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -like "*stage_5_scheduler_microbatches*"
    } |
    Select-Object -First 1

if ($null -eq $Migration) {
    Invoke-Native `
        -Description "Create Stage 5 migration" `
        -Command "pnpm" `
        -Arguments @(
            "--filter",
            "@crm/database",
            "exec",
            "prisma",
            "migrate",
            "dev",
            "--name",
            "stage_5_scheduler_microbatches",
            "--create-only"
        )
}

$Migration = Get-ChildItem `
    -Path $MigrationRoot `
    -Directory `
    -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -like "*stage_5_scheduler_microbatches*"
    } |
    Select-Object -First 1

if ($null -eq $Migration) {
    throw "Migration Stage 5 nao encontrada."
}

Write-Host "[OK] Migration: $($Migration.Name)" -ForegroundColor Green

Invoke-Native `
    -Description "Deploy Stage 5 migration" `
    -Command "pnpm" `
    -Arguments @("db:migrate:deploy")

Invoke-Native `
    -Description "Prisma generate" `
    -Command "pnpm" `
    -Arguments @("db:generate")

Invoke-Native `
    -Description "Migration status" `
    -Command "pnpm" `
    -Arguments @("db:migrate:status")

# ============================================================
# FORMAT + WORKER UNIT VALIDATION
# ============================================================

Invoke-Native `
    -Description "Format repository" `
    -Command "pnpm" `
    -Arguments @("format")

Invoke-Native `
    -Description "Worker lint" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/worker",
        "lint"
    )

Invoke-Native `
    -Description "Worker typecheck" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/worker",
        "typecheck"
    )

Invoke-Native `
    -Description "Worker tests" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/worker",
        "test"
    )

Invoke-Native `
    -Description "Worker build" `
    -Command "pnpm" `
    -Arguments @(
        "exec",
        "turbo",
        "run",
        "build",
        "--filter=@crm/worker"
    )

# ============================================================
# CREATE STAGE 5 DATABASE RUNTIME VALIDATOR
# ============================================================

$RuntimeValidator = @'
import '../src/load-environment.js';

import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';

import { createDatabaseClient } from '@crm/database';

import { AdsSchedulerService } from '../src/ads-scheduler.service.js';

import type { AdsSchedulerConfig } from '../src/scheduler.config.js';

const employeeId = process.env.STAGE5_EMPLOYEE_ID?.trim();

if (!employeeId) {
  throw new Error('STAGE5_EMPLOYEE_ID is required.');
}

const database = createDatabaseClient();

const organizationSlug =
  process.env.SEED_ORGANIZATION_SLUG?.trim() ||
  'crm-ads-whatsapp';

const unique = randomUUID().replaceAll('-', '').slice(0, 16);

const config: AdsSchedulerConfig = {
  intervalMs: 100,
  microbatchSize: 5,
  maxInflightPerEmployee: 35,
  leaseMs: 30_000,
  backpressureDelayMs: 60_000,
  microbatchYieldMs: 0,
  maxClaimsPerTick: 25,
  maxQueueAttempts: 25,
};

function event(
  name: string,
  extra: Record<string, unknown> = {},
): void {
  console.log(
    JSON.stringify({
      event: name,
      timestamp: new Date().toISOString(),
      ...extra,
    }),
  );
}

async function createPool(
  label: string,
  memberCount: number,
) {
  const organization =
    await database.organization.findUniqueOrThrow({
      where: {
        slug: organizationSlug,
      },
    });

  const employee =
    await database.employee.findFirstOrThrow({
      where: {
        id: employeeId,
        organizationId: organization.id,
        status: 'ACTIVE',
        deletedAt: null,
      },
    });

  const site =
    await database.site.create({
      data: {
        organizationId: organization.id,
        ownerEmployeeId: employee.id,
        name: `Stage5 ${label}`,
        slug: `stage5-${label}-${unique}`.toLowerCase(),
        status: 'ACTIVE',
      },
    });

  const pool =
    await database.trafficPool.create({
      data: {
        organizationId: organization.id,
        siteId: site.id,
        name: `Stage5 ${label} Pool`,
        slug: `stage5-${label}-pool-${unique}`.toLowerCase(),
        status: 'ACTIVE',
      },
    });

  const numberIds: string[] = [];

  for (
    let index = 0;
    index < memberCount;
    index += 1
  ) {
    const number =
      await database.whatsAppNumber.create({
        data: {
          organizationId: organization.id,
          assignedEmployeeId: employee.id,
          displayName: `Stage5 ${label} Number ${index + 1}`,
          e164: `+1999${Date.now()}${index}${Math.floor(Math.random() * 1000)}`,
          status: 'ACTIVE',
        },
      });

    numberIds.push(number.id);

    await database.trafficPoolMember.create({
      data: {
        organizationId: organization.id,
        trafficPoolId: pool.id,
        whatsAppNumberId: number.id,
        position: index + 1,
        status: 'ACTIVE',
      },
    });
  }

  return {
    organization,
    employee,
    site,
    pool,
    numberIds,
  };
}

async function createRequest(
  organizationId: string,
  employeeIdValue: string,
  userId: string,
  siteId: string,
  poolId: string,
  leadCount: number,
) {
  return database.$transaction(
    async (transaction) => {
      const request =
        await transaction.adsRequest.create({
          data: {
            organizationId,
            employeeId: employeeIdValue,
            siteId,
            trafficPoolId: poolId,
            requestedByUserId: userId,
            requestedLeadCount: leadCount,
          },
        });

      const queueItem =
        await transaction.adsQueueItem.create({
          data: {
            organizationId,
            adsRequestId: request.id,
            employeeId: employeeIdValue,
            trafficPoolId: poolId,
          },
        });

      return {
        request,
        queueItem,
      };
    },
  );
}

try {
  event('stage5.validation.started');

  const staleValidationRequests =
    await database.adsRequest.findMany({
      where: {
        employeeId,
        site: {
          slug: {
            startsWith: 'stage5-',
          },
        },
      },
      select: {
        id: true,
      },
    });

  const staleValidationRequestIds =
    staleValidationRequests.map((request) => request.id);

  if (staleValidationRequestIds.length > 0) {
    const cleanupAt = new Date();

    await database.adsMicrobatch.updateMany({
      where: {
        adsRequestId: {
          in: staleValidationRequestIds,
        },
        status: {
          in: ['PLANNED', 'DELIVERING'],
        },
      },
      data: {
        status: 'CANCELLED',
        cancelledAt: cleanupAt,
      },
    });

    await database.adsQueueItem.updateMany({
      where: {
        adsRequestId: {
          in: staleValidationRequestIds,
        },
        status: {
          in: ['WAITING', 'CLAIMED'],
        },
      },
      data: {
        status: 'CANCELLED',
        cancelledAt: cleanupAt,
        claimedAt: null,
        claimedByWorkerId: null,
        leaseExpiresAt: null,
      },
    });

    await database.adsRequest.updateMany({
      where: {
        id: {
          in: staleValidationRequestIds,
        },
        status: {
          in: ['QUEUED', 'PROCESSING', 'PARTIALLY_FULFILLED'],
        },
      },
      data: {
        status: 'CANCELLED',
        cancelledAt: cleanupAt,
      },
    });

    event('stage5.validation.cleanup', {
      requests: staleValidationRequestIds.length,
    });
  }

  const roundRobinPool =
    await createPool(
      'round-robin',
      3,
    );

  const roundRobinRequest =
    await createRequest(
      roundRobinPool.organization.id,
      roundRobinPool.employee.id,
      roundRobinPool.employee.userId,
      roundRobinPool.site.id,
      roundRobinPool.pool.id,
      30,
    );

  const scheduler =
    new AdsSchedulerService(
      database,
      `stage5-validator-${unique}`,
      config,
    );

  const firstSummary =
    await scheduler.runTick();

  const roundRobinState =
    await database.adsRequest.findUniqueOrThrow({
      where: {
        id: roundRobinRequest.request.id,
      },
    });

  const roundRobinQueue =
    await database.adsQueueItem.findUniqueOrThrow({
      where: {
        id: roundRobinRequest.queueItem.id,
      },
    });

  const roundRobinBatches =
    await database.adsMicrobatch.findMany({
      where: {
        adsRequestId:
          roundRobinRequest.request.id,
      },

      orderBy: {
        sequence: 'asc',
      },
    });

  assert.equal(
    roundRobinState.scheduledLeadCount,
    30,
  );

  assert.equal(
    roundRobinState.status,
    'PROCESSING',
  );

  assert.equal(
    roundRobinQueue.status,
    'COMPLETED',
  );

  assert.equal(
    roundRobinBatches.length,
    6,
  );

  const expectedRoundRobin = [
    roundRobinPool.numberIds[0],
    roundRobinPool.numberIds[1],
    roundRobinPool.numberIds[2],
    roundRobinPool.numberIds[0],
    roundRobinPool.numberIds[1],
    roundRobinPool.numberIds[2],
  ];

  assert.deepEqual(
    roundRobinBatches.map(
      (batch) => batch.whatsAppNumberId,
    ),
    expectedRoundRobin,
  );

  assert.deepEqual(
    roundRobinBatches.map(
      (batch) => batch.reservedLeadCount,
    ),
    [5, 5, 5, 5, 5, 5],
  );

  event(
    'stage5.round_robin.passed',
    {
      firstSummary,
      batches: roundRobinBatches.length,
    },
  );

  const backpressureRequest =
    await createRequest(
      roundRobinPool.organization.id,
      roundRobinPool.employee.id,
      roundRobinPool.employee.userId,
      roundRobinPool.site.id,
      roundRobinPool.pool.id,
      20,
    );

  await scheduler.runTick();

  const backpressureState =
    await database.adsRequest.findUniqueOrThrow({
      where: {
        id: backpressureRequest.request.id,
      },
    });

  const backpressureQueue =
    await database.adsQueueItem.findUniqueOrThrow({
      where: {
        id: backpressureRequest.queueItem.id,
      },
    });

  assert.equal(
    backpressureState.scheduledLeadCount,
    5,
  );

  assert.equal(
    backpressureQueue.status,
    'WAITING',
  );

  event(
    'stage5.backpressure.passed',
    {
      scheduledLeadCount:
        backpressureState.scheduledLeadCount,
    },
  );

  await database.adsMicrobatch.updateMany({
    where: {
      adsRequestId:
        roundRobinRequest.request.id,
    },

    data: {
      status: 'COMPLETED',
      deliveredLeadCount: 5,
      completedAt: new Date(),
    },
  });

  await database.adsQueueItem.update({
    where: {
      id:
        backpressureRequest.queueItem.id,
    },

    data: {
      availableAt: new Date(0),
    },
  });

  await scheduler.runTick();

  const backpressureCompleted =
    await database.adsRequest.findUniqueOrThrow({
      where: {
        id:
          backpressureRequest.request.id,
      },
    });

  const backpressureQueueCompleted =
    await database.adsQueueItem.findUniqueOrThrow({
      where: {
        id:
          backpressureRequest.queueItem.id,
      },
    });

  assert.equal(
    backpressureCompleted.scheduledLeadCount,
    20,
  );

  assert.equal(
    backpressureQueueCompleted.status,
    'COMPLETED',
  );

  event(
    'stage5.backpressure_recovery.passed',
  );

  await database.adsMicrobatch.updateMany({
    where: {
      adsRequestId:
        backpressureRequest.request.id,
    },

    data: {
      status: 'COMPLETED',
      deliveredLeadCount: 5,
      completedAt: new Date(),
    },
  });

  const concurrencyPool =
    await createPool(
      'concurrency',
      2,
    );

  const concurrencyRequest =
    await createRequest(
      concurrencyPool.organization.id,
      concurrencyPool.employee.id,
      concurrencyPool.employee.userId,
      concurrencyPool.site.id,
      concurrencyPool.pool.id,
      10,
    );

  const concurrencyConfig: AdsSchedulerConfig = {
    ...config,
    microbatchSize: 10,
    maxInflightPerEmployee: 1000,
  };

  const workerA =
    new AdsSchedulerService(
      database,
      `stage5-worker-a-${unique}`,
      concurrencyConfig,
    );

  const workerB =
    new AdsSchedulerService(
      database,
      `stage5-worker-b-${unique}`,
      concurrencyConfig,
    );

  await Promise.all([
    workerA.runTick(),
    workerB.runTick(),
  ]);

  const concurrencyState =
    await database.adsRequest.findUniqueOrThrow({
      where: {
        id:
          concurrencyRequest.request.id,
      },
    });

  const concurrencyBatches =
    await database.adsMicrobatch.findMany({
      where: {
        adsRequestId:
          concurrencyRequest.request.id,
      },
    });

  assert.equal(
    concurrencyState.scheduledLeadCount,
    10,
  );

  assert.equal(
    concurrencyBatches.length,
    1,
  );

  event(
    'stage5.concurrent_claim.passed',
    {
      microbatches:
        concurrencyBatches.length,
    },
  );

  await database.adsMicrobatch.updateMany({
    where: {
      adsRequestId:
        concurrencyRequest.request.id,
    },

    data: {
      status: 'COMPLETED',
      deliveredLeadCount: 10,
      completedAt: new Date(),
    },
  });

  const leasePool =
    await createPool(
      'lease',
      1,
    );

  const leaseRequest =
    await createRequest(
      leasePool.organization.id,
      leasePool.employee.id,
      leasePool.employee.userId,
      leasePool.site.id,
      leasePool.pool.id,
      5,
    );

  await database.adsQueueItem.update({
    where: {
      id:
        leaseRequest.queueItem.id,
    },

    data: {
      status: 'CLAIMED',
      claimedAt:
        new Date(
          Date.now() - 60_000,
        ),
      claimedByWorkerId:
        'dead-stage5-worker',
      leaseExpiresAt:
        new Date(
          Date.now() - 30_000,
        ),
      attempts: 1,
    },
  });

  const leaseScheduler =
    new AdsSchedulerService(
      database,
      `stage5-lease-worker-${unique}`,
      {
        ...config,
        maxInflightPerEmployee: 1000,
      },
    );

  await leaseScheduler.runTick();

  const recoveredRequest =
    await database.adsRequest.findUniqueOrThrow({
      where: {
        id:
          leaseRequest.request.id,
      },
    });

  const recoveredQueue =
    await database.adsQueueItem.findUniqueOrThrow({
      where: {
        id:
          leaseRequest.queueItem.id,
      },
    });

  assert.equal(
    recoveredRequest.scheduledLeadCount,
    5,
  );

  assert.equal(
    recoveredQueue.status,
    'COMPLETED',
  );

  assert.ok(
    recoveredQueue.attempts >= 2,
  );

  event(
    'stage5.lease_recovery.passed',
    {
      attempts:
        recoveredQueue.attempts,
    },
  );

  const plannedAuditCount =
    await database.auditLog.count({
      where: {
        organizationId:
          roundRobinPool.organization.id,
        action:
          'ads_microbatch.planned',
      },
    });

  assert.ok(
    plannedAuditCount >= 1,
  );

  event(
    'stage5.audit.passed',
    {
      plannedAuditCount,
    },
  );

  event(
    'stage5.validation.completed',
  );
} finally {
  await database.$disconnect();
}
'@

Write-Text `
    -Path ".\apps\worker\scripts\stage5-runtime-validation.ts" `
    -Content $RuntimeValidator

Write-Host "[OK] Stage 5 runtime validator criado." -ForegroundColor Green

# ============================================================
# FORMAT AGAIN
# ============================================================

Invoke-Native `
    -Description "Format validation code" `
    -Command "pnpm" `
    -Arguments @("format")

# ============================================================
# GLOBAL CI
# ============================================================

Invoke-Native `
    -Description "Global CI Stage 5" `
    -Command "pnpm" `
    -Arguments @("ci:check")

# ============================================================
# DATABASE INTEGRATION TESTS
# ============================================================

Write-Host ""
Write-Host "==== Stage 5 database runtime validation ====" -ForegroundColor Cyan

$HadEmployeeEnvironment = Test-Path Env:STAGE5_EMPLOYEE_ID
$PreviousEmployeeEnvironment = $null

if ($HadEmployeeEnvironment) {
    $PreviousEmployeeEnvironment = $env:STAGE5_EMPLOYEE_ID
}

$env:STAGE5_EMPLOYEE_ID = $EmployeeId

try {
    & pnpm `
        --filter `
        "@crm/worker" `
        exec `
        tsx `
        "scripts/stage5-runtime-validation.ts"

    if ($LASTEXITCODE -ne 0) {
        throw "Stage 5 database runtime validation falhou."
    }
}
finally {
    if ($HadEmployeeEnvironment) {
        $env:STAGE5_EMPLOYEE_ID = $PreviousEmployeeEnvironment
    }

    if (-not $HadEmployeeEnvironment) {
        Remove-Item `
            Env:STAGE5_EMPLOYEE_ID `
            -ErrorAction SilentlyContinue
    }
}

Write-Host "[OK] Database scheduler integration." -ForegroundColor Green

# ============================================================
# ACTUAL WORKER PROCESS SMOKE
# ============================================================

Write-Host ""
Write-Host "==== Worker process smoke ====" -ForegroundColor Cyan

$WorkerProcess = $null

try {
    $StartParameters = @{
        FilePath         = "node"
        ArgumentList     = "apps/worker/dist/main.js"
        WorkingDirectory = $RepositoryRoot
        NoNewWindow      = $true
        PassThru         = $true
    }

    $WorkerProcess = Start-Process @StartParameters

    Start-Sleep `
        -Seconds $WorkerSmokeSeconds

    if ($WorkerProcess.HasExited) {
        throw "Worker encerrou inesperadamente. ExitCode: $($WorkerProcess.ExitCode)"
    }

    Write-Host "[OK] Worker permaneceu online." -ForegroundColor Green
}
finally {
    if (
        $null -ne $WorkerProcess -and
        -not $WorkerProcess.HasExited
    ) {
        Stop-Process `
            -Id $WorkerProcess.Id `
            -Force `
            -ErrorAction SilentlyContinue
    }
}

# ============================================================
# DOCUMENTATION
# ============================================================

Write-Host ""
Write-Host "==== Stage 5 documentation ====" -ForegroundColor Cyan

$Stage5Document = @(
    "# Etapa 5 - Scheduler, Microbatches e Backpressure",
    "",
    "## Status",
    "",
    "CONCLUIDA.",
    "",
    "## Objetivo",
    "",
    "Transformar a fila persistente da Etapa 4 em um scheduler concorrente e recuperavel.",
    "",
    "## Componentes",
    "",
    "- AdsMicrobatch",
    "- TrafficPoolSchedulerState",
    "- AdsSchedulerService",
    "- worker scheduler",
    "",
    "## Contadores do AdsRequest",
    "",
    "- requestedLeadCount: quantidade solicitada",
    "- scheduledLeadCount: quantidade reservada em microbatches",
    "- fulfilledLeadCount: quantidade efetivamente entregue",
    "",
    "## Claim",
    "",
    "O scheduler usa PostgreSQL FOR UPDATE SKIP LOCKED para claim atomico.",
    "",
    "AdsQueueItem passa de WAITING para CLAIMED.",
    "",
    "## Lease",
    "",
    "O claim grava claimedByWorkerId e leaseExpiresAt.",
    "",
    "CLAIMED com lease expirado pode ser recuperado por outro worker.",
    "",
    "## Concorrencia",
    "",
    "Advisory locks transacionais protegem Employee e Traffic Pool.",
    "",
    "O lock de Employee protege backpressure.",
    "",
    "O lock de Traffic Pool protege o cursor round-robin.",
    "",
    "## Round-robin",
    "",
    "TrafficPoolSchedulerState.nextPosition persiste a proxima posicao.",
    "",
    "O cursor continua corretamente apos reinicio do worker.",
    "",
    "## Microbatches",
    "",
    "O scheduler reserva apenas a quantidade configurada por microlote.",
    "",
    "Microbatches nao representam leads entregues.",
    "",
    "## Backpressure",
    "",
    "A capacidade e calculada por Employee considerando PLANNED e DELIVERING.",
    "",
    "Sem capacidade, o queue item retorna para WAITING com availableAt futuro.",
    "",
    "## Overflow",
    "",
    "Ausencia temporaria de capacidade, pool ou numero elegivel nao causa FAILED.",
    "",
    "O pedido permanece recuperavel.",
    "",
    "## Scheduling completion",
    "",
    "Quando scheduledLeadCount atinge requestedLeadCount, AdsQueueItem vira COMPLETED.",
    "",
    "AdsRequest permanece PROCESSING ate que leads reais sejam entregues.",
    "",
    "## Cancelamento",
    "",
    "QUEUED, PROCESSING e PARTIALLY_FULFILLED podem ser cancelados.",
    "",
    "Microbatches PLANNED ou DELIVERING sao cancelados junto com o pedido.",
    "",
    "## Validacoes executadas",
    "",
    "- unit tests do scheduler engine",
    "- Prisma migration e generate",
    "- round-robin 1-2-3-1-2-3",
    "- backpressure parcial",
    "- recuperacao apos liberar capacidade",
    "- dois workers concorrentes",
    "- FOR UPDATE SKIP LOCKED",
    "- lease expirado recuperado",
    "- audit ads_microbatch.planned",
    "- worker process smoke",
    "- global ci:check",
    "",
    "## Proxima etapa",
    "",
    "Etapa 6 - Site Monitoring."
)

[System.IO.File]::WriteAllLines(
    [System.IO.Path]::GetFullPath(
        ".\docs\ETAPA_5_SCHEDULER_MICROBATCHES.md"
    ),
    $Stage5Document,
    $Utf8NoBom
)

$Decisions = @(
    "# Decisoes - Etapa 5",
    "",
    "PostgreSQL continua sendo a fonte de verdade da fila.",
    "",
    "BullMQ nao e necessario para a autoridade do scheduler.",
    "",
    "Claim utiliza FOR UPDATE SKIP LOCKED.",
    "",
    "Lease permite recovery de workers interrompidos.",
    "",
    "Backpressure e global por Employee.",
    "",
    "Round-robin e persistido por Traffic Pool.",
    "",
    "Ordem do cursor e baseada em TrafficPoolMember.position.",
    "",
    "Microbatch representa capacidade reservada, nao lead entregue.",
    "",
    "scheduledLeadCount e separado de fulfilledLeadCount.",
    "",
    "Queue COMPLETED significa planejamento concluido.",
    "",
    "AdsRequest FULFILLED somente sera usado quando leads reais forem entregues.",
    "",
    "Defaults:",
    "",
    "- ADS_SCHEDULER_INTERVAL_MS=1000",
    "- ADS_MICROBATCH_SIZE=10",
    "- ADS_MAX_INFLIGHT_PER_EMPLOYEE=100",
    "- ADS_CLAIM_LEASE_MS=30000",
    "- ADS_BACKPRESSURE_DELAY_MS=5000",
    "- ADS_MICROBATCH_YIELD_MS=250",
    "- ADS_MAX_CLAIMS_PER_TICK=25",
    "- ADS_MAX_QUEUE_ATTEMPTS=25"
)

[System.IO.File]::WriteAllLines(
    [System.IO.Path]::GetFullPath(
        ".\docs\DECISOES_ETAPA_5.md"
    ),
    $Decisions,
    $Utf8NoBom
)

$EtapasPath = ".\docs\ETAPAS.md"

if (Test-Path $EtapasPath) {
    $Etapas = Read-Text -Path $EtapasPath

    if (-not $Etapas.Contains("## Etapa 5 - Scheduler + Microbatches")) {
        $Stage5Summary = @(
            "",
            "## Etapa 5 - Scheduler + Microbatches",
            "",
            "Status: CONCLUIDA.",
            "",
            "Implementado:",
            "",
            "- claim atomico",
            "- worker lease",
            "- lease recovery",
            "- AdsMicrobatch",
            "- TrafficPoolSchedulerState",
            "- round-robin persistente",
            "- backpressure por Employee",
            "- overflow recuperavel",
            "- multi-worker concurrency",
            "- scheduledLeadCount",
            "- cancellation lifecycle Stage 5",
            "",
            "Documentacao:",
            "",
            "- docs/ETAPA_5_SCHEDULER_MICROBATCHES.md",
            "- docs/DECISOES_ETAPA_5.md",
            "",
            "Proxima: Etapa 6 - Site Monitoring."
        )

        $Etapas = (
            $Etapas.TrimEnd() +
            "`r`n" +
            ($Stage5Summary -join "`r`n") +
            "`r`n"
        )

        Write-Text `
            -Path $EtapasPath `
            -Content $Etapas
    }
}

Write-Host "[OK] Stage 5 docs." -ForegroundColor Green

# ============================================================
# FINAL FORMAT CHECK
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
# GIT DIFF
# ============================================================

Write-Host ""
Write-Host "==== Git diff check ====" -ForegroundColor Cyan

& git diff --check

if ($LASTEXITCODE -ne 0) {
    throw "git diff --check falhou."
}

Write-Host "[OK] git diff --check." -ForegroundColor Green

# ============================================================
# ENV FILE SECURITY
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

$SecretPattern = ('sk-' + 'proj-' + '|AKIA' + '[0-9A-Z]{16}' + '|BEGIN ' + '(RSA|OPENSSH|EC)' + ' PRIVATE KEY')

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
# REMOVE LOCAL BACKUP
# ============================================================

Remove-Item `
    ".\tmp\stage5-macroblock1-backup" `
    -Recurse `
    -Force `
    -ErrorAction SilentlyContinue

# ============================================================
# STATUS
# ============================================================

Write-Host ""
Write-Host "==== Git status ====" -ForegroundColor Cyan

& git status --short

if ($LASTEXITCODE -ne 0) {
    throw "git status falhou."
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host "[OK] ETAPA 5 COMPLETAMENTE VALIDADA." -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Validado:" -ForegroundColor Cyan
Write-Host "- migration"
Write-Host "- Prisma generate"
Write-Host "- worker lint"
Write-Host "- worker typecheck"
Write-Host "- scheduler unit tests"
Write-Host "- worker build"
Write-Host "- global CI"
Write-Host "- round-robin"
Write-Host "- backpressure"
Write-Host "- backpressure recovery"
Write-Host "- concurrent workers"
Write-Host "- SKIP LOCKED"
Write-Host "- lease recovery"
Write-Host "- scheduler audit"
Write-Host "- worker process"
Write-Host "- docs"
Write-Host "- git diff"
Write-Host "- env scan"
Write-Host "- secret scan"
Write-Host ""
Write-Host "Proxima etapa: ETAPA 6." -ForegroundColor Yellow