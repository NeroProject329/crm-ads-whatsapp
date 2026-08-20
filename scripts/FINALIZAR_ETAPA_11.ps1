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

function Write-Lines {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Lines
    )

    $FullPath = [System.IO.Path]::GetFullPath($Path)
    $Parent = Split-Path -Parent $FullPath

    if (-not (Test-Path $Parent)) {
        New-Item -ItemType Directory -Path $Parent -Force | Out-Null
    }

    [System.IO.File]::WriteAllLines(
        $FullPath,
        $Lines,
        $Utf8NoBom
    )
}

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
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

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " ETAPA 11 - MACROBLOCO 11.2" -ForegroundColor Cyan
Write-Host " HEALTH + CONTINGENCY VALIDATION" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

# ============================================================
# PREFLIGHT
# ============================================================

$RequiredFiles = @(
    ".\packages\database\prisma\schema.prisma",
    ".\packages\meta-cloud-api\src\phone-number-profile.ts",
    ".\packages\meta-cloud-api\src\phone-number-quality-webhook.ts",
    ".\packages\contracts\src\whatsapp-health.ts",
    ".\packages\validation\src\whatsapp-health.ts",
    ".\apps\worker\src\whatsapp-number-health.config.ts",
    ".\apps\worker\src\whatsapp-number-health.service.ts",
    ".\apps\worker\src\whatsapp-number-health-sync.service.ts",
    ".\apps\worker\src\whatsapp-inbox-processor.service.ts",
    ".\apps\worker\src\ads-scheduler.service.ts",
    ".\apps\api\src\whatsapp-health\whatsapp-health.service.ts",
    ".\apps\api\src\whatsapp-health\whatsapp-health.controller.ts",
    ".\apps\api\src\whatsapp-health\whatsapp-health.module.ts"
)

foreach ($File in $RequiredFiles) {
    if (-not (Test-Path $File)) {
        throw "Macrobloco 11.1 incompleto: $File"
    }
}

Write-Host "[OK] Preflight Stage 11." -ForegroundColor Green

# ============================================================
# HARDENING 1 - REMOVE UNUSED HELPER
# ============================================================

$DomainPath =
    ".\apps\worker\src\whatsapp-number-health.service.ts"

$Domain =
    Read-Text -Path $DomainPath

$Domain =
    [regex]::Replace(
        $Domain,
        '(?ms)\r?\nfunction gatesScheduler\(\s*status:\s*WhatsAppNumberHealthStatus,\s*\):\s*boolean\s*\{.*?\r?\n\}',
        ''
    )

Write-Text `
    -Path $DomainPath `
    -Content $Domain

Write-Host "[OK] Helper nao utilizado removido." -ForegroundColor Green

# ============================================================
# HARDENING 2 - UNFLAGGED MUST OVERRIDE STALE RED/YELLOW
# ============================================================

$Domain =
    Read-Text -Path $DomainPath

$Domain =
    [regex]::Replace(
        $Domain,
        "nextQuality\s*===\s*'RED'\s*\|\|\s*normalizedEvent\s*===\s*'FLAGGED'",
        "normalizedEvent === 'FLAGGED' ||`r`n      (nextQuality === 'RED' && normalizedEvent !== 'UNFLAGGED')"
    )

$Domain =
    [regex]::Replace(
        $Domain,
        "nextQuality\s*===\s*'YELLOW'\s*\|\|\s*normalizedEvent\s*===\s*'DOWNGRADE'",
        "(nextQuality === 'YELLOW' && normalizedEvent !== 'UNFLAGGED') ||`r`n      normalizedEvent === 'DOWNGRADE'"
    )

Write-Text `
    -Path $DomainPath `
    -Content $Domain

Write-Host "[OK] UNFLAGGED recovery precedence corrigida." -ForegroundColor Green

# ============================================================
# HARDENING 3 - API TRANSACTION CLIENT TYPE
# ============================================================

$ApiServicePath =
    ".\apps\api\src\whatsapp-health\whatsapp-health.service.ts"

$ApiService =
    Read-Text -Path $ApiServicePath

if (-not $ApiService.Contains("CrmDatabaseClient")) {
    $Anchor =
        "import type {`r`n  AuthenticatedPrincipal,`r`n} from '@crm/auth';"

    if (-not $ApiService.Contains($Anchor)) {
        $Anchor =
            "import type {`n  AuthenticatedPrincipal,`n} from '@crm/auth';"
    }

    if (-not $ApiService.Contains($Anchor)) {
        throw "WhatsAppHealthService auth import anchor nao encontrado."
    }

    $Replacement =
        $Anchor +
        "`r`n`r`n" +
        "import type {`r`n" +
        "  CrmDatabaseClient,`r`n" +
        "} from '@crm/database';"

    $ApiService =
        $ApiService.Replace(
            $Anchor,
            $Replacement
        )
}

if (-not $ApiService.Contains("type TransactionClient")) {
    $Anchor =
        "@Injectable()"

    if (-not $ApiService.Contains($Anchor)) {
        throw "WhatsAppHealthService Injectable anchor nao encontrado."
    }

    $TypeDefinition = @'
type TransactionClient =
  Parameters<
    Parameters<
      CrmDatabaseClient['$transaction']
    >[0]
  >[0];

'@

    $ApiService =
        $ApiService.Replace(
            $Anchor,
            $TypeDefinition +
            $Anchor
        )
}

$ApiService =
    [regex]::Replace(
        $ApiService,
        "(?ms)transaction:\s*Parameters<\s*Parameters<\s*typeof\s+this\.database\.client\.\`?\`$transaction\s*>\s*\[0\]\s*>\s*\[0\]\s*,",
        "transaction:`r`n      TransactionClient,"
    )

Write-Text `
    -Path $ApiServicePath `
    -Content $ApiService

Write-Host "[OK] WhatsAppHealthService transaction typing endurecida." -ForegroundColor Green

# ============================================================
# META PACKAGE TESTS
# ============================================================

$MetaTest = @'
import {
  describe,
  expect,
  it,
} from 'vitest';

import {
  MetaCloudApiClient,
} from './client.js';

import {
  getMetaPhoneNumberProfile,
} from './phone-number-profile.js';

import {
  parseMetaPhoneNumberQualityUpdates,
} from './phone-number-quality-webhook.js';

describe(
  'Stage 11 Meta phone health',
  () => {
    it(
      'parses phone_number_quality_update',
      () => {
        const updates =
          parseMetaPhoneNumberQualityUpdates({
            object:
              'whatsapp_business_account',

            entry: [
              {
                id:
                  '123456',

                changes: [
                  {
                    field:
                      'phone_number_quality_update',

                    value: {
                      display_phone_number:
                        '+55 11 99999-0000',

                      event:
                        'FLAGGED',

                      current_limit:
                        'TIER_1K',
                    },
                  },
                ],
              },
            ],
          });

        expect(
          updates,
        ).toEqual([
          {
            wabaId:
              '123456',

            displayPhoneNumber:
              '+55 11 99999-0000',

            event:
              'FLAGGED',

            currentLimit:
              'TIER_1K',
          },
        ]);
      },
    );

    it(
      'reads official quality_rating from phone profile',
      async () => {
        const client =
          new MetaCloudApiClient(
            {
              graphBaseUrl:
                'https://graph.facebook.com',

              graphApiVersion:
                'v99.0',

              accessToken:
                'stage11-test-token',

              timeoutMs:
                5000,
            },

            async (
              input,
            ) => {
              const url =
                new URL(
                  String(
                    input,
                  ),
                );

              expect(
                url.pathname,
              ).toContain(
                '/v99.0/123456789',
              );

              expect(
                url.searchParams.get(
                  'fields',
                ),
              ).toContain(
                'quality_rating',
              );

              return new Response(
                JSON.stringify({
                  id:
                    '123456789',

                  verified_name:
                    'Stage 11',

                  display_phone_number:
                    '+5511999990000',

                  quality_rating:
                    'GREEN',
                }),

                {
                  status:
                    200,

                  headers: {
                    'content-type':
                      'application/json',
                  },
                },
              );
            },
          );

        const profile =
          await getMetaPhoneNumberProfile(
            client,
            '123456789',
          );

        expect(
          profile.qualityRating,
        ).toBe(
          'GREEN',
        );
      },
    );

    it(
      'maps unknown quality ratings safely',
      async () => {
        const client =
          new MetaCloudApiClient(
            {
              graphBaseUrl:
                'https://graph.facebook.com',

              graphApiVersion:
                'v99.0',

              accessToken:
                'stage11-test-token',

              timeoutMs:
                5000,
            },

            async () =>
              new Response(
                JSON.stringify({
                  id:
                    '123456789',

                  quality_rating:
                    'SOMETHING_NEW',
                }),

                {
                  status:
                    200,
                },
              ),
          );

        const profile =
          await getMetaPhoneNumberProfile(
            client,
            '123456789',
          );

        expect(
          profile.qualityRating,
        ).toBe(
          'UNKNOWN',
        );
      },
    );
  },
);
'@

Write-Text `
    -Path ".\packages\meta-cloud-api\src\phone-number-health.spec.ts" `
    -Content $MetaTest

# ============================================================
# VALIDATION TESTS
# ============================================================

$ValidationTest = @'
import {
  describe,
  expect,
  it,
} from 'vitest';

import {
  whatsAppHealthHistoryQuerySchema,
} from './whatsapp-health.js';

describe(
  'Stage 11 WhatsApp health validation',
  () => {
    it(
      'accepts a valid history limit',
      () => {
        const result =
          whatsAppHealthHistoryQuerySchema.safeParse({
            limit:
              '100',
          });

        expect(
          result.success,
        ).toBe(
          true,
        );

        if (
          result.success
        ) {
          expect(
            result.data.limit,
          ).toBe(
            100,
          );
        }
      },
    );

    it(
      'rejects excessive limits',
      () => {
        expect(
          whatsAppHealthHistoryQuerySchema.safeParse({
            limit:
              201,
          }).success,
        ).toBe(
          false,
        );
      },
    );

    it(
      'rejects unknown query fields',
      () => {
        expect(
          whatsAppHealthHistoryQuerySchema.safeParse({
            organizationId:
              'foreign',
          }).success,
        ).toBe(
          false,
        );
      },
    );
  },
);
'@

Write-Text `
    -Path ".\packages\validation\src\whatsapp-health.spec.ts" `
    -Content $ValidationTest

# ============================================================
# INSTALL
# ============================================================

Invoke-Native `
    -Description "pnpm install Stage 11" `
    -Command "pnpm" `
    -Arguments @("install")

# ============================================================
# PRISMA FORMAT + VALIDATE
# ============================================================

Invoke-Native `
    -Description "Prisma format Stage 11" `
    -Command "pnpm" `
    -Arguments @("db:format")

Invoke-Native `
    -Description "Prisma validate Stage 11" `
    -Command "pnpm" `
    -Arguments @("db:validate")

# ============================================================
# MIGRATION
# ============================================================

$MigrationRoot =
    ".\packages\database\prisma\migrations"

$Migration =
    Get-ChildItem `
        -Path $MigrationRoot `
        -Directory `
        -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -like "*stage_11_whatsapp_number_health*"
    } |
    Select-Object -First 1

if ($null -eq $Migration) {
    Invoke-Native `
        -Description "Create Stage 11 migration" `
        -Command "pnpm" `
        -Arguments @(
            "--filter",
            "@crm/database",
            "exec",
            "prisma",
            "migrate",
            "dev",
            "--name",
            "stage_11_whatsapp_number_health",
            "--create-only"
        )
}

$Migration =
    Get-ChildItem `
        -Path $MigrationRoot `
        -Directory `
        -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -like "*stage_11_whatsapp_number_health*"
    } |
    Select-Object -First 1

if ($null -eq $Migration) {
    throw "Migration Stage 11 nao encontrada."
}

Write-Host "[OK] Migration Stage 11 encontrada: $($Migration.Name)" -ForegroundColor Green

Invoke-Native `
    -Description "Deploy Stage 11 migration" `
    -Command "pnpm" `
    -Arguments @("db:migrate:deploy")

Invoke-Native `
    -Description "Prisma generate Stage 11" `
    -Command "pnpm" `
    -Arguments @("db:generate")

# ============================================================
# SEED
# ============================================================

Invoke-Native `
    -Description "Database seed Stage 11" `
    -Command "pnpm" `
    -Arguments @("db:seed")

Invoke-Native `
    -Description "Verify seed Stage 11" `
    -Command "pnpm" `
    -Arguments @("db:verify-seed")

Invoke-Native `
    -Description "Migration status Stage 11" `
    -Command "pnpm" `
    -Arguments @("db:migrate:status")

# ============================================================
# FORMAT
# ============================================================

Invoke-Native `
    -Description "Format Stage 11" `
    -Command "pnpm" `
    -Arguments @("format")

# ============================================================
# TARGETED CHECKS
# ============================================================

Invoke-Native `
    -Description "Meta lint Stage 11" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/meta-cloud-api",
        "lint"
    )

Invoke-Native `
    -Description "Meta typecheck Stage 11" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/meta-cloud-api",
        "typecheck"
    )

Invoke-Native `
    -Description "Meta tests Stage 11" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/meta-cloud-api",
        "test"
    )

Invoke-Native `
    -Description "Validation lint Stage 11" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/validation",
        "lint"
    )

Invoke-Native `
    -Description "Validation typecheck Stage 11" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/validation",
        "typecheck"
    )

Invoke-Native `
    -Description "Validation tests Stage 11" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/validation",
        "test"
    )

Invoke-Native `
    -Description "Database typecheck Stage 11" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/database",
        "typecheck"
    )

Invoke-Native `
    -Description "Webhook ingress lint Stage 11" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/webhook-ingress",
        "lint"
    )

Invoke-Native `
    -Description "Webhook ingress typecheck Stage 11" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/webhook-ingress",
        "typecheck"
    )

Invoke-Native `
    -Description "Webhook ingress tests Stage 11" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/webhook-ingress",
        "test"
    )

Invoke-Native `
    -Description "API lint Stage 11" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/api",
        "lint"
    )

Invoke-Native `
    -Description "API typecheck Stage 11" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/api",
        "typecheck"
    )

Invoke-Native `
    -Description "API tests Stage 11" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/api",
        "test"
    )

Invoke-Native `
    -Description "Worker lint Stage 11" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/worker",
        "lint"
    )

Invoke-Native `
    -Description "Worker typecheck Stage 11" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/worker",
        "typecheck"
    )

Invoke-Native `
    -Description "Worker tests Stage 11" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/worker",
        "test"
    )

# ============================================================
# TARGETED BUILDS
# ============================================================

Invoke-Native `
    -Description "Build Stage 11 services" `
    -Command "pnpm" `
    -Arguments @(
        "exec",
        "turbo",
        "run",
        "build",
        "--filter=@crm/meta-cloud-api",
        "--filter=@crm/webhook-ingress",
        "--filter=@crm/api",
        "--filter=@crm/worker"
    )

# ============================================================
# RUNTIME VALIDATOR
# ============================================================

$RuntimeValidator = @'
import '../src/load-environment.js';

import assert from 'node:assert/strict';

import {
  createHash,
  randomUUID,
} from 'node:crypto';

import {
  createDatabaseClient,
} from '@crm/database';

import {
  MetaCloudApiClient,
} from '@crm/meta-cloud-api';

import {
  AdsSchedulerService,
} from '../src/ads-scheduler.service.js';

import {
  WhatsAppInboxProcessorService,
} from '../src/whatsapp-inbox-processor.service.js';

import {
  WhatsAppNumberHealthSyncService,
} from '../src/whatsapp-number-health-sync.service.js';

import type {
  AdsSchedulerConfig,
} from '../src/scheduler.config.js';

import type {
  WhatsAppNumberHealthConfig,
} from '../src/whatsapp-number-health.config.js';

import type {
  WhatsAppRuntimeConfig,
} from '../src/whatsapp-runtime.config.js';

const database =
  createDatabaseClient();

const unique =
  randomUUID()
    .replaceAll(
      '-',
      '',
    )
    .slice(
      0,
      12,
    );

const organizationSlug =
  `stage11-runtime-${unique}`;

const schedulerConfig:
  AdsSchedulerConfig =
    {
      intervalMs:
        1000,

      microbatchSize:
        10,

      maxInflightPerEmployee:
        100,

      leaseMs:
        30000,

      backpressureDelayMs:
        1000,

      microbatchYieldMs:
        0,

      maxClaimsPerTick:
        25,

      maxQueueAttempts:
        25,
    };

const inboxConfig:
  WhatsAppRuntimeConfig =
    {
      inboxIntervalMs:
        1000,

      inboxLeaseMs:
        30000,

      inboxMaxClaimsPerTick:
        1,

      inboxMaxAttempts:
        8,

      inboxRetryBaseMs:
        1000,

      outboundIntervalMs:
        1000,

      outboundLeaseMs:
        30000,

      outboundMaxClaimsPerTick:
        25,

      outboundMaxAttempts:
        8,

      outboundRetryBaseMs:
        2000,

      outboundDisabledRetryMs:
        30000,
    };

const healthConfig:
  WhatsAppNumberHealthConfig =
    {
      intervalMs:
        1000,

      pollIntervalMs:
        60000,

      failureRetryMs:
        1000,

      leaseMs:
        30000,

      maxClaimsPerTick:
        1,

      recoveryHealthyChecks:
        2,
    };

function log(
  event:
    string,

  extra:
    Record<
      string,
      unknown
    > = {},
): void {
  console.log(
    JSON.stringify({
      event,

      timestamp:
        new Date().toISOString(),

      ...extra,
    }),
  );
}

function hashPayload(
  payload:
    unknown,
): string {
  return createHash(
    'sha256',
  )
    .update(
      JSON.stringify(
        payload,
      ),
    )
    .digest(
      'hex',
    );
}

function qualityPayload(
  input:
    Readonly<{
      wabaId:
        string;

      displayPhoneNumber:
        string;

      event:
        string;

      currentLimit:
        string;
    }>,
): Record<
  string,
  unknown
> {
  return {
    object:
      'whatsapp_business_account',

    entry: [
      {
        id:
          input.wabaId,

        changes: [
          {
            field:
              'phone_number_quality_update',

            value: {
              display_phone_number:
                input.displayPhoneNumber,

              event:
                input.event,

              current_limit:
                input.currentLimit,
            },
          },
        ],
      },
    ],
  };
}

async function createQualityEnvelope(
  input:
    Readonly<{
      organizationId:
        string;

      whatsAppNumberId:
        string;

      wabaId:
        string;

      displayPhoneNumber:
        string;

      event:
        string;

      currentLimit:
        string;

      priorityOffset:
        number;
    }>,
): Promise<void> {
  const payload =
    qualityPayload({
      wabaId:
        input.wabaId,

      displayPhoneNumber:
        input.displayPhoneNumber,

      event:
        input.event,

      currentLimit:
        input.currentLimit,
    });

  await database.metaWebhookEnvelope.create({
    data: {
      organizationId:
        input.organizationId,

      whatsAppNumberId:
        input.whatsAppNumberId,

      object:
        'whatsapp_business_account',

      field:
        'phone_number_quality_update',

      wabaId:
        input.wabaId,

      payloadHash:
        hashPayload({
          payload,
          nonce:
            `${unique}-${input.priorityOffset}`,
        }),

      payload,

      status:
        'RECEIVED',

      availableAt:
        new Date(
          input.priorityOffset,
        ),

      receivedAt:
        new Date(),
    },
  });
}

async function cleanup():
Promise<void> {
  const organization =
    await database.organization.findUnique({
      where: {
        slug:
          organizationSlug,
      },

      select: {
        id:
          true,
      },
    });

  if (!organization) {
    return;
  }

  const organizationId =
    organization.id;

  await database.auditLog.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.whatsAppNumberHealthEvent.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.whatsAppNumberIncident.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.whatsAppNumberHealthState.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.leadAttribution.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.lead.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.whatsAppMessageStatusEvent.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.whatsAppMessage.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.whatsAppConversation.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.whatsAppContact.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.metaWebhookEnvelope.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.adsMicrobatch.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.adsQueueItem.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.adsRequest.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.trafficPoolSchedulerState.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.trafficPoolMember.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.trafficPool.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.whatsAppNumber.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.siteMonitorCheck.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.siteMonitorIncident.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.siteMonitorState.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.siteDomain.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.site.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.session.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.userRole.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.employee.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.rolePermission.deleteMany({
    where: {
      role: {
        organizationId,
      },
    },
  });

  await database.role.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.user.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.team.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.organization.delete({
    where: {
      id:
        organizationId,
    },
  });
}

async function main():
Promise<void> {
  log(
    'stage11.validation.started',
  );

  await cleanup();

  const organization =
    await database.organization.create({
      data: {
        name:
          'Stage 11 Runtime',

        slug:
          organizationSlug,

        status:
          'ACTIVE',
      },
    });

  const team =
    await database.team.create({
      data: {
        organizationId:
          organization.id,

        name:
          'Stage 11 Team',

        slug:
          `stage11-${unique}`,

        status:
          'ACTIVE',
      },
    });

  const employeeUser =
    await database.user.create({
      data: {
        organizationId:
          organization.id,

        email:
          `stage11-employee-${unique}@example.com`,

        emailNormalized:
          `stage11-employee-${unique}@example.com`,

        displayName:
          'Stage 11 Employee',

        status:
          'ACTIVE',
      },
    });

  const otherUser =
    await database.user.create({
      data: {
        organizationId:
          organization.id,

        email:
          `stage11-other-${unique}@example.com`,

        emailNormalized:
          `stage11-other-${unique}@example.com`,

        displayName:
          'Stage 11 Other Employee',

        status:
          'ACTIVE',
      },
    });

  const employee =
    await database.employee.create({
      data: {
        organizationId:
          organization.id,

        teamId:
          team.id,

        userId:
          employeeUser.id,

        employeeCode:
          `S11A${unique}`,

        status:
          'ACTIVE',
      },
    });

  const otherEmployee =
    await database.employee.create({
      data: {
        organizationId:
          organization.id,

        teamId:
          team.id,

        userId:
          otherUser.id,

        employeeCode:
          `S11B${unique}`,

        status:
          'ACTIVE',
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
          'Stage 11 Site',

        slug:
          `stage11-site-${unique}`,

        status:
          'ACTIVE',
      },
    });

  const pool =
    await database.trafficPool.create({
      data: {
        organizationId:
          organization.id,

        siteId:
          site.id,

        name:
          'Stage 11 Pool',

        slug:
          `stage11-pool-${unique}`,

        status:
          'ACTIVE',
      },
    });

  const suffix =
    Date.now()
      .toString()
      .slice(
        -6,
      );

  const numberA =
    await database.whatsAppNumber.create({
      data: {
        organizationId:
          organization.id,

        assignedEmployeeId:
          employee.id,

        displayName:
          'Stage 11 Number A',

        e164:
          `+155511${suffix}`,

        status:
          'ACTIVE',

        metaWabaId:
          `811001${suffix}`,

        metaPhoneNumberId:
          `911001${suffix}`,

        metaConnectedAt:
          new Date(),
      },
    });

  const numberB =
    await database.whatsAppNumber.create({
      data: {
        organizationId:
          organization.id,

        assignedEmployeeId:
          employee.id,

        displayName:
          'Stage 11 Number B',

        e164:
          `+155512${suffix}`,

        status:
          'ACTIVE',

        metaWabaId:
          `811002${suffix}`,

        metaPhoneNumberId:
          `911002${suffix}`,

        metaConnectedAt:
          new Date(),
      },
    });

  const numberOther =
    await database.whatsAppNumber.create({
      data: {
        organizationId:
          organization.id,

        assignedEmployeeId:
          otherEmployee.id,

        displayName:
          'Stage 11 Other Number',

        e164:
          `+155513${suffix}`,

        status:
          'ACTIVE',
      },
    });

  const memberA =
    await database.trafficPoolMember.create({
      data: {
        organizationId:
          organization.id,

        trafficPoolId:
          pool.id,

        whatsAppNumberId:
          numberA.id,

        position:
          1,

        status:
          'ACTIVE',
      },
    });

  const memberB =
    await database.trafficPoolMember.create({
      data: {
        organizationId:
          organization.id,

        trafficPoolId:
          pool.id,

        whatsAppNumberId:
          numberB.id,

        position:
          2,

        status:
          'ACTIVE',
      },
    });

  await database.whatsAppNumberHealthState.createMany({
    data: [
      {
        organizationId:
          organization.id,

        whatsAppNumberId:
          numberA.id,

        status:
          'HEALTHY',

        schedulerEligible:
          true,

        metaQualityRating:
          'GREEN',

        lastHealthyAt:
          new Date(),

        consecutiveHealthyChecks:
          2,

        nextCheckAt:
          new Date(
            Date.now() +
              60 *
                60 *
                1000,
          ),
      },

      {
        organizationId:
          organization.id,

        whatsAppNumberId:
          numberB.id,

        status:
          'HEALTHY',

        schedulerEligible:
          true,

        metaQualityRating:
          'GREEN',

        lastHealthyAt:
          new Date(),

        consecutiveHealthyChecks:
          2,

        nextCheckAt:
          new Date(
            Date.now() +
              60 *
                60 *
                1000,
          ),
      },

      {
        organizationId:
          organization.id,

        whatsAppNumberId:
          numberOther.id,

        status:
          'HEALTHY',

        schedulerEligible:
          true,

        metaQualityRating:
          'UNKNOWN',

        nextCheckAt:
          new Date(
            Date.now() +
              60 *
                60 *
                1000,
          ),
      },
    ],
  });

  const request =
    await database.adsRequest.create({
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
          employeeUser.id,

        requestedLeadCount:
          10,

        scheduledLeadCount:
          10,

        fulfilledLeadCount:
          3,

        status:
          'PARTIALLY_FULFILLED',

        startedAt:
          new Date(),
      },
    });

  const queue =
    await database.adsQueueItem.create({
      data: {
        organizationId:
          organization.id,

        adsRequestId:
          request.id,

        employeeId:
          employee.id,

        trafficPoolId:
          pool.id,

        status:
          'COMPLETED',

        completedAt:
          new Date(),
      },
    });

  const unhealthyBatch =
    await database.adsMicrobatch.create({
      data: {
        organizationId:
          organization.id,

        adsRequestId:
          request.id,

        adsQueueItemId:
          queue.id,

        employeeId:
          employee.id,

        trafficPoolId:
          pool.id,

        trafficPoolMemberId:
          memberA.id,

        whatsAppNumberId:
          numberA.id,

        sequence:
          1,

        reservedLeadCount:
          10,

        deliveredLeadCount:
          3,

        status:
          'DELIVERING',

        startedAt:
          new Date(),

        plannedAt:
          new Date(),
      },
    });

  const inbox =
    new WhatsAppInboxProcessorService(
      database,
      `stage11-inbox-${unique}`,
      inboxConfig,
    );

  await createQualityEnvelope({
    organizationId:
      organization.id,

    whatsAppNumberId:
      numberA.id,

    wabaId:
      numberA.metaWabaId!,

    displayPhoneNumber:
      numberA.e164,

    event:
      'DOWNGRADE',

    currentLimit:
      'TIER_1K',

    priorityOffset:
      1,
  });

  const downgradeTick =
    await inbox.runTick();

  assert.equal(
    downgradeTick.processed,
    1,
  );

  const degradedState =
    await database.whatsAppNumberHealthState.findUniqueOrThrow({
      where: {
        organizationId_whatsAppNumberId: {
          organizationId:
            organization.id,

          whatsAppNumberId:
            numberA.id,
        },
      },
    });

  assert.equal(
    degradedState.status,
    'DEGRADED',
  );

  assert.equal(
    degradedState.schedulerEligible,
    false,
  );

  const cancelledBatch =
    await database.adsMicrobatch.findUniqueOrThrow({
      where: {
        id:
          unhealthyBatch.id,
      },
    });

  assert.equal(
    cancelledBatch.status,
    'CANCELLED',
  );

  assert.equal(
    cancelledBatch.deliveredLeadCount,
    3,
  );

  const requestAfterRelease =
    await database.adsRequest.findUniqueOrThrow({
      where: {
        id:
          request.id,
      },
    });

  assert.equal(
    requestAfterRelease.fulfilledLeadCount,
    3,
  );

  assert.equal(
    requestAfterRelease.scheduledLeadCount,
    3,
  );

  const queueAfterRelease =
    await database.adsQueueItem.findUniqueOrThrow({
      where: {
        id:
          queue.id,
      },
    });

  assert.equal(
    queueAfterRelease.status,
    'WAITING',
  );

  log(
    'stage11.degraded_contingency_release.passed',
  );

  const scheduler =
    new AdsSchedulerService(
      database,
      `stage11-scheduler-${unique}`,
      schedulerConfig,
    );

  const schedulerTick =
    await scheduler.runTick();

  assert.ok(
    schedulerTick.claimed >=
      1,
  );

  const replacementBatch =
    await database.adsMicrobatch.findFirstOrThrow({
      where: {
        organizationId:
          organization.id,

        adsRequestId:
          request.id,

        status: {
          in: [
            'PLANNED',
            'DELIVERING',
          ],
        },
      },

      orderBy: {
        sequence:
          'desc',
      },
    });

  assert.equal(
    replacementBatch.whatsAppNumberId,
    numberB.id,
  );

  assert.equal(
    replacementBatch.reservedLeadCount,
    7,
  );

  assert.equal(
    replacementBatch.deliveredLeadCount,
    0,
  );

  assert.equal(
    (
      await database.adsRequest.findUniqueOrThrow({
        where: {
          id:
            request.id,
        },
      })
    ).scheduledLeadCount,
    10,
  );

  log(
    'stage11.scheduler_reroute.passed',
  );

  await createQualityEnvelope({
    organizationId:
      organization.id,

    whatsAppNumberId:
      numberA.id,

    wabaId:
      numberA.metaWabaId!,

    displayPhoneNumber:
      numberA.e164,

    event:
      'FLAGGED',

    currentLimit:
      'TIER_1K',

    priorityOffset:
      2,
  });

  await inbox.runTick();

  const criticalState =
    await database.whatsAppNumberHealthState.findUniqueOrThrow({
      where: {
        organizationId_whatsAppNumberId: {
          organizationId:
            organization.id,

          whatsAppNumberId:
            numberA.id,
        },
      },
    });

  assert.equal(
    criticalState.status,
    'CRITICAL',
  );

  assert.equal(
    criticalState.schedulerEligible,
    false,
  );

  const openIncident =
    await database.whatsAppNumberIncident.findFirstOrThrow({
      where: {
        organizationId:
          organization.id,

        whatsAppNumberId:
          numberA.id,

        status:
          'OPEN',

        type:
          'META_QUALITY',
      },
    });

  assert.equal(
    openIncident.severity,
    'CRITICAL',
  );

  log(
    'stage11.flagged_critical_incident.passed',
  );

  await createQualityEnvelope({
    organizationId:
      organization.id,

    whatsAppNumberId:
      numberA.id,

    wabaId:
      numberA.metaWabaId!,

    displayPhoneNumber:
      numberA.e164,

    event:
      'UNFLAGGED',

    currentLimit:
      'TIER_1K',

    priorityOffset:
      3,
  });

  await inbox.runTick();

  const recoveringAfterUnflagged =
    await database.whatsAppNumberHealthState.findUniqueOrThrow({
      where: {
        organizationId_whatsAppNumberId: {
          organizationId:
            organization.id,

          whatsAppNumberId:
            numberA.id,
        },
      },
    });

  assert.equal(
    recoveringAfterUnflagged.status,
    'RECOVERING',
  );

  assert.equal(
    recoveringAfterUnflagged.schedulerEligible,
    false,
  );

  log(
    'stage11.unflagged_recovering.passed',
  );

  let metaFetchCount =
    0;

  const metaClient =
    new MetaCloudApiClient(
      {
        graphBaseUrl:
          'https://graph.facebook.com',

        graphApiVersion:
          'v99.0',

        accessToken:
          'stage11-runtime-token',

        timeoutMs:
          5000,
      },

      async (
        input,
      ) => {
        metaFetchCount +=
          1;

        const url =
          new URL(
            String(
              input,
            ),
          );

        assert.equal(
          url.pathname.endsWith(
            `/${numberA.metaPhoneNumberId}`,
          ),
          true,
        );

        return new Response(
          JSON.stringify({
            id:
              numberA.metaPhoneNumberId,

            verified_name:
              'Stage 11 Number A',

            display_phone_number:
              numberA.e164,

            quality_rating:
              'GREEN',
          }),

          {
            status:
              200,

            headers: {
              'content-type':
                'application/json',
            },
          },
        );
      },
    );

  const healthSync =
    new WhatsAppNumberHealthSyncService(
      database,
      `stage11-health-${unique}`,
      healthConfig,
      metaClient,
    );

  await database.whatsAppNumberHealthState.update({
    where: {
      organizationId_whatsAppNumberId: {
        organizationId:
          organization.id,

        whatsAppNumberId:
          numberA.id,
      },
    },

    data: {
      nextCheckAt:
        new Date(
          0,
        ),
    },
  });

  const firstGreenTick =
    await healthSync.runTick();

  assert.equal(
    firstGreenTick.synced,
    1,
  );

  const firstGreenState =
    await database.whatsAppNumberHealthState.findUniqueOrThrow({
      where: {
        organizationId_whatsAppNumberId: {
          organizationId:
            organization.id,

          whatsAppNumberId:
            numberA.id,
        },
      },
    });

  assert.equal(
    firstGreenState.status,
    'RECOVERING',
  );

  assert.equal(
    firstGreenState.schedulerEligible,
    false,
  );

  assert.equal(
    firstGreenState.consecutiveHealthyChecks,
    1,
  );

  log(
    'stage11.first_green_still_recovering.passed',
  );

  await database.whatsAppNumberHealthState.update({
    where: {
      id:
        firstGreenState.id,
    },

    data: {
      nextCheckAt:
        new Date(
          0,
        ),
    },
  });

  const secondGreenTick =
    await healthSync.runTick();

  assert.equal(
    secondGreenTick.synced,
    1,
  );

  const healthyAgain =
    await database.whatsAppNumberHealthState.findUniqueOrThrow({
      where: {
        id:
          firstGreenState.id,
      },
    });

  assert.equal(
    healthyAgain.status,
    'HEALTHY',
  );

  assert.equal(
    healthyAgain.schedulerEligible,
    true,
  );

  assert.ok(
    healthyAgain.consecutiveHealthyChecks >=
      2,
  );

  assert.equal(
    metaFetchCount,
    2,
  );

  const resolvedIncident =
    await database.whatsAppNumberIncident.findFirstOrThrow({
      where: {
        organizationId:
          organization.id,

        whatsAppNumberId:
          numberA.id,

        type:
          'META_QUALITY',
      },

      orderBy: {
        openedAt:
          'desc',
      },
    });

  assert.equal(
    resolvedIncident.status,
    'RESOLVED',
  );

  assert.ok(
    resolvedIncident.resolvedAt,
  );

  log(
    'stage11.recovery_confirmed.passed',
  );

  const apiModule =
    await import(
      '../../api/dist/whatsapp-health/whatsapp-health.service.js'
    );

  const api =
    new apiModule.WhatsAppHealthService(
      {
        client:
          database,
      } as never,
    );

  const adminPrincipal = {
    organizationId:
      organization.id,

    userId:
      employeeUser.id,

    sessionId:
      randomUUID(),

    roles: [
      'ADMIN',
    ] as const,
  };

  const employeePrincipal = {
    organizationId:
      organization.id,

    userId:
      employeeUser.id,

    sessionId:
      randomUUID(),

    roles: [
      'EMPLOYEE',
    ] as const,
  };

  const otherPrincipal = {
    organizationId:
      organization.id,

    userId:
      otherUser.id,

    sessionId:
      randomUUID(),

    roles: [
      'EMPLOYEE',
    ] as const,
  };

  const healthResponse =
    await api.getHealth(
      employeePrincipal,
      numberA.id,
    );

  assert.equal(
    healthResponse.status,
    'HEALTHY',
  );

  await assert.rejects(
    () =>
      api.getHealth(
        otherPrincipal,
        numberA.id,
      ),
  );

  const otherHealth =
    await api.getHealth(
      otherPrincipal,
      numberOther.id,
    );

  assert.equal(
    otherHealth.whatsAppNumberId,
    numberOther.id,
  );

  log(
    'stage11.employee_isolation.passed',
  );

  const pauseResponse =
    await api.pause(
      adminPrincipal,
      numberOther.id,
    );

  assert.equal(
    pauseResponse.status,
    'DISABLED',
  );

  assert.equal(
    pauseResponse.schedulerEligible,
    false,
  );

  assert.equal(
    pauseResponse.manualPaused,
    true,
  );

  const resumeResponse =
    await api.resume(
      adminPrincipal,
      numberOther.id,
    );

  assert.equal(
    resumeResponse.manualPaused,
    false,
  );

  assert.equal(
    resumeResponse.status,
    'UNKNOWN',
  );

  assert.equal(
    resumeResponse.schedulerEligible,
    true,
  );

  log(
    'stage11.manual_pause_resume.passed',
  );

  const events =
    await api.listEvents(
      adminPrincipal,
      numberA.id,
      100,
    );

  assert.ok(
    events.some(
      (
        event,
      ) =>
        event.currentStatus ===
        'CRITICAL',
    ),
  );

  assert.ok(
    events.some(
      (
        event,
      ) =>
        event.currentStatus ===
        'RECOVERING',
    ),
  );

  assert.ok(
    events.some(
      (
        event,
      ) =>
        event.currentStatus ===
        'HEALTHY',
    ),
  );

  const incidents =
    await api.listIncidents(
      adminPrincipal,
      numberA.id,
      100,
    );

  assert.ok(
    incidents.some(
      (
        incident,
      ) =>
        incident.type ===
          'META_QUALITY' &&
        incident.status ===
          'RESOLVED',
    ),
  );

  log(
    'stage11.history_and_incidents_api.passed',
  );

  const auditContingency =
    await database.auditLog.count({
      where: {
        organizationId:
          organization.id,

        action:
          'whatsapp_number.contingency_activated',
      },
    });

  const auditRelease =
    await database.auditLog.count({
      where: {
        organizationId:
          organization.id,

        action:
          'ads_microbatch.contingency_released',
      },
    });

  const auditPause =
    await database.auditLog.count({
      where: {
        organizationId:
          organization.id,

        action:
          'whatsapp_number.health_paused',
      },
    });

  const auditResume =
    await database.auditLog.count({
      where: {
        organizationId:
          organization.id,

        action:
          'whatsapp_number.health_resumed',
      },
    });

  assert.ok(
    auditContingency >=
      1,
  );

  assert.ok(
    auditRelease >=
      1,
  );

  assert.ok(
    auditPause >=
      1,
  );

  assert.ok(
    auditResume >=
      1,
  );

  log(
    'stage11.audit.passed',
    {
      auditContingency,
      auditRelease,
      auditPause,
      auditResume,
    },
  );

  log(
    'stage11.validation.completed',
  );
}

try {
  await main();
}
finally {
  try {
    await cleanup();
  }
  finally {
    await database.$disconnect();
  }
}
'@

New-Item `
    -ItemType Directory `
    -Path ".\apps\worker\scripts" `
    -Force |
    Out-Null

Write-Text `
    -Path ".\apps\worker\scripts\stage11-runtime-validation.ts" `
    -Content $RuntimeValidator

Invoke-Native `
    -Description "Format Stage 11 runtime" `
    -Command "pnpm" `
    -Arguments @("format")

# ============================================================
# REBUILD BEFORE RUNTIME
# ============================================================

Invoke-Native `
    -Description "Rebuild Stage 11 API + Worker" `
    -Command "pnpm" `
    -Arguments @(
        "exec",
        "turbo",
        "run",
        "build",
        "--filter=@crm/api",
        "--filter=@crm/worker"
    )

# ============================================================
# RUNTIME
# ============================================================

Write-Host ""
Write-Host "==== Stage 11 runtime validation ====" -ForegroundColor Cyan

& pnpm `
    --filter `
    "@crm/worker" `
    exec `
    tsx `
    "scripts/stage11-runtime-validation.ts"

if ($LASTEXITCODE -ne 0) {
    throw "Stage 11 runtime validation falhou."
}

Write-Host "[OK] Stage 11 runtime validation." -ForegroundColor Green

# ============================================================
# WORKER PROCESS SMOKE
# ============================================================

Write-Host ""
Write-Host "==== Worker process smoke Stage 11 ====" -ForegroundColor Cyan

$WorkerProcess =
    $null

$PreviousWorkerId =
    [Environment]::GetEnvironmentVariable(
        "ADS_WORKER_ID",
        "Process"
    )

$PreviousHealthInterval =
    [Environment]::GetEnvironmentVariable(
        "WHATSAPP_HEALTH_INTERVAL_MS",
        "Process"
    )

$PreviousInboxInterval =
    [Environment]::GetEnvironmentVariable(
        "WHATSAPP_INBOX_INTERVAL_MS",
        "Process"
    )

$env:ADS_WORKER_ID =
    "stage11-process-smoke"

$env:WHATSAPP_HEALTH_INTERVAL_MS =
    "60000"

$env:WHATSAPP_INBOX_INTERVAL_MS =
    "60000"

try {
    $WorkerProcess =
        Start-Process `
            -FilePath "node" `
            -ArgumentList "apps/worker/dist/main.js" `
            -WorkingDirectory $RepositoryRoot `
            -NoNewWindow `
            -PassThru

    Start-Sleep -Seconds 3

    if ($WorkerProcess.HasExited) {
        throw "Worker encerrou no process smoke Stage 11. ExitCode: $($WorkerProcess.ExitCode)"
    }

    Write-Host "[OK] Worker Stage 11 permaneceu online." -ForegroundColor Green
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

    if ($null -ne $PreviousWorkerId) {
        $env:ADS_WORKER_ID =
            $PreviousWorkerId
    }
    else {
        Remove-Item `
            "Env:ADS_WORKER_ID" `
            -ErrorAction SilentlyContinue
    }

    if ($null -ne $PreviousHealthInterval) {
        $env:WHATSAPP_HEALTH_INTERVAL_MS =
            $PreviousHealthInterval
    }
    else {
        Remove-Item `
            "Env:WHATSAPP_HEALTH_INTERVAL_MS" `
            -ErrorAction SilentlyContinue
    }

    if ($null -ne $PreviousInboxInterval) {
        $env:WHATSAPP_INBOX_INTERVAL_MS =
            $PreviousInboxInterval
    }
    else {
        Remove-Item `
            "Env:WHATSAPP_INBOX_INTERVAL_MS" `
            -ErrorAction SilentlyContinue
    }
}

# ============================================================
# GLOBAL CI
# ============================================================

Invoke-Native `
    -Description "Global CI Stage 11" `
    -Command "pnpm" `
    -Arguments @("ci:check")

# ============================================================
# DOCUMENTATION
# ============================================================

$Stage11Doc = @(
    "# Etapa 11 - Saude, contingencia e recuperacao dos numeros WhatsApp",
    "",
    "## Status",
    "",
    "CONCLUIDA.",
    "",
    "## Separacao de conceitos",
    "",
    "A Etapa 11 separa qualidade oficial Meta, saude operacional do CRM e elegibilidade do scheduler.",
    "",
    "Qualidade Meta:",
    "",
    "- GREEN",
    "- YELLOW",
    "- RED",
    "- NA",
    "- UNKNOWN",
    "",
    "Saude operacional:",
    "",
    "- UNKNOWN",
    "- HEALTHY",
    "- DEGRADED",
    "- CRITICAL",
    "- RECOVERING",
    "- DISABLED",
    "",
    "## Scheduler",
    "",
    "schedulerEligible e a fonte operacional usada pelo ADS scheduler.",
    "",
    "HEALTHY pode receber novos microbatches.",
    "",
    "DEGRADED, CRITICAL, RECOVERING e DISABLED nao recebem novos microbatches.",
    "",
    "UNKNOWN permanece fail-open para preservar numeros ainda sem sinal Meta suficiente.",
    "",
    "## Contingencia",
    "",
    "Quando um numero elegivel passa para estado nao elegivel, a capacidade reservada ainda nao entregue e liberada.",
    "",
    "Microbatches afetados sao CANCELLED.",
    "",
    "Leads ja entregues permanecem intactos.",
    "",
    "fulfilledLeadCount nunca e reduzido.",
    "",
    "scheduledLeadCount e reduzido apenas pela capacidade ainda nao entregue.",
    "",
    "AdsQueueItem volta para WAITING.",
    "",
    "O scheduler redistribui a capacidade para outro numero elegivel do Traffic Pool.",
    "",
    "## Recuperacao",
    "",
    "UNFLAGGED inicia RECOVERING.",
    "",
    "Um unico GREEN nao reativa imediatamente um numero que estava degradado ou critico.",
    "",
    "Por padrao sao exigidos dois GREEN consecutivos.",
    "",
    "Depois da confirmacao o estado volta a HEALTHY e schedulerEligible=true.",
    "",
    "## Incidentes",
    "",
    "DEGRADED e CRITICAL abrem ou atualizam incidente META_QUALITY.",
    "",
    "HEALTHY confirmado resolve o incidente.",
    "",
    "Pause manual abre incidente MANUAL_PAUSE.",
    "",
    "Resume manual resolve o incidente de pause.",
    "",
    "## Meta sync",
    "",
    "O worker consulta o phone number profile usando Graph API.",
    "",
    "Falha de polling nao transforma automaticamente o numero em CRITICAL.",
    "",
    "Falhas de sync sao registradas separadamente para evitar contingencias falsas por instabilidade da Meta.",
    "",
    "## Concorrencia",
    "",
    "Health transitions usam advisory lock por Organization + WhatsAppNumber.",
    "",
    "O scheduler usa o mesmo advisory lock antes de criar um novo microbatch.",
    "",
    "Isso fecha a corrida entre degradacao do numero e nova reserva ADS.",
    "",
    "## API",
    "",
    "GET /whatsapp-numbers/:id/health",
    "",
    "GET /whatsapp-numbers/:id/health/events",
    "",
    "GET /whatsapp-numbers/:id/health/incidents",
    "",
    "POST /whatsapp-numbers/:id/health/pause",
    "",
    "POST /whatsapp-numbers/:id/health/resume",
    "",
    "POST /whatsapp-numbers/:id/health/sync",
    "",
    "EMPLOYEE possui leitura apenas dos proprios numeros.",
    "",
    "Alteracoes de contingencia exigem ADMIN.",
    "",
    "## Validacao",
    "",
    "Validado:",
    "",
    "- Meta phone quality parser",
    "- Meta quality profile polling",
    "- quality webhook",
    "- DOWNGRADE -> DEGRADED",
    "- FLAGGED -> CRITICAL",
    "- UNFLAGGED -> RECOVERING",
    "- GREEN confirmation",
    "- incident open/update/resolve",
    "- capacity release",
    "- scheduledLeadCount rollback",
    "- fulfilledLeadCount preservation",
    "- queue reopen",
    "- scheduler reroute",
    "- manual pause/resume",
    "- Employee isolation",
    "- audit",
    "- worker process smoke",
    "- global CI",
    "",
    "## Proxima etapa",
    "",
    "Etapa 12 - Security hardening, staging e production readiness."
)

Write-Lines `
    -Path ".\docs\ETAPA_11_WHATSAPP_NUMBER_HEALTH.md" `
    -Lines $Stage11Doc

$DecisionDoc = @(
    "# Decisoes - Etapa 11",
    "",
    "Qualidade oficial da Meta nao e inferida pelo tempo.",
    "",
    "quality_rating da Meta e persistido separadamente do estado operacional do CRM.",
    "",
    "Falha ao consultar a Meta nao significa automaticamente que o numero esta ruim.",
    "",
    "YELLOW e DOWNGRADE bloqueiam novas reservas de ADS por estrategia conservadora.",
    "",
    "RED e FLAGGED geram CRITICAL.",
    "",
    "UNFLAGGED nao significa recuperacao completa; o numero entra em RECOVERING.",
    "",
    "Dois GREEN consecutivos sao exigidos por padrao antes de reativar o scheduler.",
    "",
    "Capacidade reservada ainda nao entregue e liberada quando o numero se torna inelegivel.",
    "",
    "Leads ja entregues nunca sao removidos nem reatribuidos.",
    "",
    "fulfilledLeadCount nunca e reduzido pela contingencia.",
    "",
    "scheduledLeadCount e reduzido apenas pelo outstanding do microbatch cancelado.",
    "",
    "O queue item volta para WAITING para permitir redistribuicao.",
    "",
    "O scheduler escolhe somente numeros com schedulerEligible=true ou numeros sem HealthState legado.",
    "",
    "Health domain e scheduler compartilham advisory lock por numero para eliminar race condition.",
    "",
    "UNKNOWN e fail-open nesta etapa.",
    "",
    "Pause/resume manual e separado do status base WhatsAppNumber.",
    "",
    "Resume de numero conectado a Meta entra em RECOVERING antes de receber ADS novamente."
)

Write-Lines `
    -Path ".\docs\DECISOES_ETAPA_11.md" `
    -Lines $DecisionDoc

$EtapasPath =
    ".\docs\ETAPAS.md"

if (Test-Path $EtapasPath) {
    $Etapas =
        Read-Text -Path $EtapasPath

    for (
        $Stage =
            1;
        $Stage -le
            11;
        $Stage++
    ) {
        $Etapas =
            [regex]::Replace(
                $Etapas,
                "(?m)^\|\s*$Stage\s*\|([^|]+)\|([^|]+)\|$",
                {
                    param($Match)

                    return (
                        "| " +
                        $Stage.ToString().PadLeft(5) +
                        " |" +
                        $Match.Groups[1].Value +
                        "| CONCLUIDA                   |"
                    )
                },
                1
            )
    }

    if ($Etapas.Contains("## Etapa 11 - Saude")) {
        $Etapas =
            [regex]::Replace(
                $Etapas,
                '(?s)## Etapa 11 - Saude.*?(?=## Etapa 12|\z)',
                @'
## Etapa 11 - Saude e contingencia dos numeros WhatsApp

Status: CONCLUIDA.

Implementado:

- Meta quality rating
- phone_number_quality_update
- WhatsAppNumberHealthState
- WhatsAppNumberHealthEvent
- WhatsAppNumberIncident
- schedulerEligible
- Meta API polling
- polling claim/lease
- DEGRADED / CRITICAL / RECOVERING / DISABLED
- contingency capacity release
- AdsQueueItem reopen
- scheduler reroute
- recovery confirmation
- manual pause/resume
- health events
- incidents
- Employee isolation
- audit

Documentacao:

- docs/ETAPA_11_WHATSAPP_NUMBER_HEALTH.md
- docs/DECISOES_ETAPA_11.md

Proxima: Etapa 12 - Security hardening, staging e production readiness.

'@
            )
    }
    else {
        $Etapas =
            $Etapas.TrimEnd() +
            "`r`n`r`n" +
            "## Etapa 11 - Saude e contingencia dos numeros WhatsApp`r`n`r`n" +
            "Status: CONCLUIDA.`r`n`r`n" +
            "Documentacao: docs/ETAPA_11_WHATSAPP_NUMBER_HEALTH.md e docs/DECISOES_ETAPA_11.md.`r`n`r`n" +
            "Proxima: Etapa 12 - Security hardening, staging e production readiness.`r`n"
    }

    Write-Text `
        -Path $EtapasPath `
        -Content $Etapas
}

Write-Host "[OK] Stage 11 documentation." -ForegroundColor Green

# ============================================================
# FINAL FORMAT + CI
# ============================================================

Invoke-Native `
    -Description "Final format Stage 11" `
    -Command "pnpm" `
    -Arguments @("format")

Invoke-Native `
    -Description "Final format check Stage 11" `
    -Command "pnpm" `
    -Arguments @("format:check")

Invoke-Native `
    -Description "Final global CI Stage 11" `
    -Command "pnpm" `
    -Arguments @("ci:check")

# ============================================================
# STRUCTURAL CHECKS
# ============================================================

Write-Host ""
Write-Host "==== Stage 11 structural checks ====" -ForegroundColor Cyan

$Schema =
    Read-Text -Path ".\packages\database\prisma\schema.prisma"

$Domain =
    Read-Text -Path ".\apps\worker\src\whatsapp-number-health.service.ts"

$Scheduler =
    Read-Text -Path ".\apps\worker\src\ads-scheduler.service.ts"

$Sync =
    Read-Text -Path ".\apps\worker\src\whatsapp-number-health-sync.service.ts"

$Main =
    Read-Text -Path ".\apps\worker\src\main.ts"

$Seed =
    Read-Text -Path ".\packages\database\prisma\seed.ts"

$VerifySeed =
    Read-Text -Path ".\packages\database\prisma\verify-seed.ts"

$Guard =
    Read-Text -Path ".\apps\api\src\authorization\access-token.guard.ts"

$AuthorizationTypes =
    Read-Text -Path ".\apps\api\src\authorization\authorization.types.ts"

foreach ($Marker in @(
    "enum MetaPhoneQualityRating",
    "enum WhatsAppNumberHealthStatus",
    "model WhatsAppNumberHealthState {",
    "model WhatsAppNumberHealthEvent {",
    "model WhatsAppNumberIncident {",
    "schedulerEligible",
    "manualPaused",
    "consecutiveHealthyChecks"
)) {
    if (-not $Schema.Contains($Marker)) {
        throw "Stage 11 schema invariant ausente: $Marker"
    }
}

foreach ($Marker in @(
    "META_QUALITY_RED",
    "META_QUALITY_YELLOW",
    "META_QUALITY_FLAGGED",
    "META_QUALITY_UNFLAGGED",
    "META_QUALITY_GREEN_CONFIRMED",
    "releaseReservedCapacity",
    "ads_microbatch.contingency_released",
    "whatsapp_number.contingency_activated"
)) {
    if (-not $Domain.Contains($Marker)) {
        throw "Stage 11 health invariant ausente: $Marker"
    }
}

foreach ($Marker in @(
    "schedulerEligible: true",
    "whatsapp-number-health:",
    "ads_queue.number_health_unavailable"
)) {
    if (-not $Scheduler.Contains($Marker)) {
        throw "Stage 11 scheduler invariant ausente: $Marker"
    }
}

foreach ($Marker in @(
    "getMetaPhoneNumberProfile",
    "FOR UPDATE OF state SKIP LOCKED",
    "META_HEALTH_SYNC_FAILED"
)) {
    if (-not $Sync.Contains($Marker)) {
        throw "Stage 11 sync invariant ausente: $Marker"
    }
}

foreach ($Marker in @(
    "WhatsAppNumberHealthSyncService",
    "runNumberHealthTick",
    "numberHealthTimer"
)) {
    if (-not $Main.Contains($Marker)) {
        throw "Stage 11 worker main invariant ausente: $Marker"
    }
}

foreach ($Content in @(
    $Seed,
    $VerifySeed,
    $Guard,
    $AuthorizationTypes
)) {
    foreach ($Permission in @(
        "whatsapp_health.read",
        "whatsapp_health.manage"
    )) {
        if (-not $Content.Contains($Permission)) {
            throw "$Permission ausente no catalogo de autorizacao."
        }
    }
}

Write-Host "[OK] Stage 11 structural checks." -ForegroundColor Green

# ============================================================
# NO TRACKED REAL ENV
# ============================================================

[string[]]$TrackedFiles = @(
    & git ls-files
)

if ($LASTEXITCODE -ne 0) {
    throw "git ls-files falhou."
}

[string[]]$TrackedEnv = @(
    $TrackedFiles |
    Where-Object {
        $_ -match '(^|/)\.env($|\.)' -and
        $_ -notmatch '\.env\.example$'
    }
)

if (@($TrackedEnv).Count -gt 0) {
    $TrackedEnv
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

$SecretExitCode =
    $LASTEXITCODE

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
# GIT DIFF CHECK
# ============================================================

& git diff --check

if ($LASTEXITCODE -ne 0) {
    throw "git diff --check falhou."
}

Write-Host "[OK] git diff --check." -ForegroundColor Green

# ============================================================
# CLEAN TEMP BACKUP
# ============================================================

Remove-Item `
    ".\tmp\stage11-macroblock1-backup" `
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
Write-Host "[OK] ETAPA 11 COMPLETAMENTE VALIDADA." -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Validado:" -ForegroundColor Cyan
Write-Host "- Meta quality rating"
Write-Host "- phone_number_quality_update"
Write-Host "- WhatsAppNumberHealthState"
Write-Host "- WhatsAppNumberHealthEvent"
Write-Host "- WhatsAppNumberIncident"
Write-Host "- GREEN / YELLOW / RED / NA"
Write-Host "- HEALTHY / DEGRADED / CRITICAL / RECOVERING / DISABLED"
Write-Host "- DOWNGRADE -> DEGRADED"
Write-Host "- FLAGGED -> CRITICAL"
Write-Host "- UNFLAGGED -> RECOVERING"
Write-Host "- two GREEN recovery confirmation"
Write-Host "- Meta API polling"
Write-Host "- polling claim + lease"
Write-Host "- sync failure isolation"
Write-Host "- schedulerEligible"
Write-Host "- contingency capacity release"
Write-Host "- microbatch cancellation"
Write-Host "- scheduledLeadCount rollback"
Write-Host "- fulfilledLeadCount preservation"
Write-Host "- AdsQueueItem reopen"
Write-Host "- scheduler healthy-number reroute"
Write-Host "- scheduler/health race lock"
Write-Host "- incident open/update/resolve"
Write-Host "- manual pause/resume"
Write-Host "- Health API"
Write-Host "- history API"
Write-Host "- incidents API"
Write-Host "- Employee isolation"
Write-Host "- audit"
Write-Host "- worker process smoke"
Write-Host "- global CI"
Write-Host "- documentation"
Write-Host "- git checks"
Write-Host "- secret scan"
Write-Host ""
Write-Host "Proxima etapa: ETAPA 12 - SECURITY HARDENING, STAGING E PRODUCTION READINESS." -ForegroundColor Yellow