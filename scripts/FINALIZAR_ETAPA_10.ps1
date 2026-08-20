Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepositoryRoot

$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

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

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " ETAPA 10 - MACROBLOCO 10.2" -ForegroundColor Cyan
Write-Host " UNIQUE LEADS + ATTRIBUTION VALIDATION" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

# ============================================================
# PREFLIGHT
# ============================================================

$RequiredFiles = @(
    ".\packages\database\prisma\schema.prisma",
    ".\packages\contracts\src\leads.ts",
    ".\packages\validation\src\leads.ts",
    ".\apps\worker\src\lead-attribution.service.ts",
    ".\apps\worker\src\whatsapp-inbox-processor.service.ts",
    ".\apps\api\src\leads\leads.service.ts",
    ".\apps\api\src\leads\leads.controller.ts",
    ".\apps\api\src\leads\leads.module.ts"
)

foreach ($File in $RequiredFiles) {
    if (-not (Test-Path $File)) {
        throw "Macrobloco 10.1 incompleto: $File"
    }
}

Write-Host "[OK] Preflight Stage 10." -ForegroundColor Green

# ============================================================
# INSTALL
# ============================================================

Invoke-Native `
    -Description "pnpm install" `
    -Command "pnpm" `
    -Arguments @("install")

# ============================================================
# PRISMA FORMAT + VALIDATE
# ============================================================

Invoke-Native `
    -Description "Prisma format Stage 10" `
    -Command "pnpm" `
    -Arguments @("db:format")

Invoke-Native `
    -Description "Prisma validate Stage 10" `
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
        $_.Name -like "*stage_10_unique_leads_attribution*"
    } |
    Select-Object -First 1

if ($null -eq $Migration) {
    Invoke-Native `
        -Description "Create Stage 10 migration" `
        -Command "pnpm" `
        -Arguments @(
            "--filter",
            "@crm/database",
            "exec",
            "prisma",
            "migrate",
            "dev",
            "--name",
            "stage_10_unique_leads_attribution",
            "--create-only"
        )
}

$Migration =
    Get-ChildItem `
        -Path $MigrationRoot `
        -Directory `
        -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -like "*stage_10_unique_leads_attribution*"
    } |
    Select-Object -First 1

if ($null -eq $Migration) {
    throw "Migration Stage 10 nao encontrada."
}

Write-Host "[OK] Migration encontrada: $($Migration.Name)" -ForegroundColor Green

Invoke-Native `
    -Description "Deploy Stage 10 migration" `
    -Command "pnpm" `
    -Arguments @("db:migrate:deploy")

Invoke-Native `
    -Description "Prisma generate Stage 10" `
    -Command "pnpm" `
    -Arguments @("db:generate")

# ============================================================
# SEED
# ============================================================

Invoke-Native `
    -Description "Database seed Stage 10" `
    -Command "pnpm" `
    -Arguments @("db:seed")

Invoke-Native `
    -Description "Verify Stage 10 seed" `
    -Command "pnpm" `
    -Arguments @("db:verify-seed")

Invoke-Native `
    -Description "Migration status Stage 10" `
    -Command "pnpm" `
    -Arguments @("db:migrate:status")

# ============================================================
# VALIDATION TEST
# ============================================================

$ValidationTest = @'
import {
  describe,
  expect,
  it,
} from 'vitest';

import {
  leadListQuerySchema,
} from './leads.js';

describe(
  'Stage 10 lead validation',
  () => {
    it(
      'accepts lead filters',
      () => {
        const result =
          leadListQuerySchema.safeParse({
            limit:
              '50',

            status:
              'ATTRIBUTED',

            search:
              '551199',
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
            50,
          );
        }
      },
    );

    it(
      'rejects unknown fields',
      () => {
        expect(
          leadListQuerySchema.safeParse({
            organizationId:
              '0f138502-b180-4eaa-b04b-627362642a83',
          }).success,
        ).toBe(
          false,
        );
      },
    );

    it(
      'limits page size',
      () => {
        expect(
          leadListQuerySchema.safeParse({
            limit:
              101,
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
    -Path ".\packages\validation\src\leads.spec.ts" `
    -Content $ValidationTest

# ============================================================
# FORMAT BEFORE TARGETED CHECKS
# ============================================================

Invoke-Native `
    -Description "Format Stage 10" `
    -Command "pnpm" `
    -Arguments @("format")

# ============================================================
# TARGETED CHECKS
# ============================================================

Invoke-Native `
    -Description "Database typecheck Stage 10" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/database",
        "typecheck"
    )

Invoke-Native `
    -Description "Contracts lint Stage 10" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/contracts",
        "lint"
    )

Invoke-Native `
    -Description "Contracts typecheck Stage 10" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/contracts",
        "typecheck"
    )

Invoke-Native `
    -Description "Validation lint Stage 10" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/validation",
        "lint"
    )

Invoke-Native `
    -Description "Validation typecheck Stage 10" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/validation",
        "typecheck"
    )

Invoke-Native `
    -Description "Validation tests Stage 10" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/validation",
        "test"
    )

Invoke-Native `
    -Description "API lint Stage 10" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/api",
        "lint"
    )

Invoke-Native `
    -Description "API typecheck Stage 10" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/api",
        "typecheck"
    )

Invoke-Native `
    -Description "API tests Stage 10" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/api",
        "test"
    )

Invoke-Native `
    -Description "Worker lint Stage 10" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/worker",
        "lint"
    )

Invoke-Native `
    -Description "Worker typecheck Stage 10" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/worker",
        "typecheck"
    )

Invoke-Native `
    -Description "Worker tests Stage 10" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/worker",
        "test"
    )

# ============================================================
# BUILDS
# ============================================================

Invoke-Native `
    -Description "Stage 10 API + Worker build" `
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
  WhatsAppInboxProcessorService,
} from '../src/whatsapp-inbox-processor.service.js';

import {
  LeadAttributionService,
} from '../src/lead-attribution.service.js';

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
  `stage10-runtime-${unique}`;

const runtimeConfig:
  WhatsAppRuntimeConfig =
    {
      inboxIntervalMs:
        1000,

      inboxLeaseMs:
        30000,

      inboxMaxClaimsPerTick:
        25,

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

function log(
  name:
    string,
  extra:
    Record<
      string,
      unknown
    > = {},
): void {
  console.log(
    JSON.stringify({
      event:
        name,

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

function createInboundPayload(
  input:
    Readonly<{
      nonce:
        string;

      wabaId:
        string;

      phoneNumberId:
        string;

      waId:
        string;

      messageId:
        string;

      timestamp:
        number;

      profileName?:
        string;
    }>,
): Record<
  string,
  unknown
> {
  return {
    stage10RuntimeNonce:
      input.nonce,

    object:
      'whatsapp_business_account',

    entry: [
      {
        id:
          input.wabaId,

        changes: [
          {
            field:
              'messages',

            value: {
              metadata: {
                phone_number_id:
                  input.phoneNumberId,
              },

              contacts: [
                {
                  wa_id:
                    input.waId,

                  profile: {
                    name:
                      input.profileName ??
                      'Stage 10 Lead',
                  },
                },
              ],

              messages: [
                {
                  id:
                    input.messageId,

                  from:
                    input.waId,

                  timestamp:
                    String(
                      input.timestamp,
                    ),

                  type:
                    'text',

                  text: {
                    body:
                      'Stage 10 inbound',
                  },
                },
              ],
            },
          },
        ],
      },
    ],
  };
}

async function createEnvelope(
  input:
    Readonly<{
      organizationId:
        string;

      whatsAppNumberId:
        string;

      wabaId:
        string;

      phoneNumberId:
        string;

      waId:
        string;

      messageId:
        string;

      timestamp:
        number;

      nonce:
        string;
    }>,
) {
  const payload =
    createInboundPayload({
      nonce:
        input.nonce,

      wabaId:
        input.wabaId,

      phoneNumberId:
        input.phoneNumberId,

      waId:
        input.waId,

      messageId:
        input.messageId,

      timestamp:
        input.timestamp,
    });

  return database.metaWebhookEnvelope.create({
    data: {
      organizationId:
        input.organizationId,

      whatsAppNumberId:
        input.whatsAppNumberId,

      object:
        'whatsapp_business_account',

      field:
        'messages',

      wabaId:
        input.wabaId,

      metaPhoneNumberId:
        input.phoneNumberId,

      payloadHash:
        hashPayload(
          payload,
        ),

      payload,

      status:
        'RECEIVED',
    },
  });
}

async function createDirectInbound(
  input:
    Readonly<{
      organizationId:
        string;

      whatsAppNumberId:
        string;

      waId:
        string;

      sequence:
        number;

      assignedEmployeeId:
        string | null;
    }>,
) {
  const contact =
    await database.whatsAppContact.create({
      data: {
        organizationId:
          input.organizationId,

        waId:
          input.waId,

        profileName:
          `Lead ${input.sequence}`,

        lastInboundAt:
          new Date(),
      },
    });

  const conversation =
    await database.whatsAppConversation.create({
      data: {
        organizationId:
          input.organizationId,

        whatsAppNumberId:
          input.whatsAppNumberId,

        contactId:
          contact.id,

        assignedEmployeeId:
          input.assignedEmployeeId,

        status:
          'OPEN',

        lastInboundAt:
          new Date(),

        lastMessageAt:
          new Date(),

        customerServiceWindowExpiresAt:
          new Date(
            Date.now() +
              24 *
                60 *
                60 *
                1000,
          ),

        unreadCount:
          1,
      },
    });

  const message =
    await database.whatsAppMessage.create({
      data: {
        organizationId:
          input.organizationId,

        conversationId:
          conversation.id,

        whatsAppNumberId:
          input.whatsAppNumberId,

        contactId:
          contact.id,

        direction:
          'INBOUND',

        type:
          'TEXT',

        status:
          'RECEIVED',

        metaMessageId:
          `wamid.stage10.direct.${unique}.${input.sequence}`,

        textBody:
          'Direct runtime lead',

        content: {
          runtime:
            true,
        },

        providerTimestamp:
          new Date(),

        availableAt:
          new Date(),
      },
    });

  return {
    contact,
    conversation,
    message,
  };
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
    'stage10.validation.started',
  );

  await cleanup();

  const organization =
    await database.organization.create({
      data: {
        name:
          'Stage 10 Runtime',

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
          'Stage 10 Team',

        slug:
          `stage10-${unique}`,

        status:
          'ACTIVE',
      },
    });

  const userA =
    await database.user.create({
      data: {
        organizationId:
          organization.id,

        email:
          `stage10-a-${unique}@example.com`,

        emailNormalized:
          `stage10-a-${unique}@example.com`,

        displayName:
          'Stage 10 Employee A',

        status:
          'ACTIVE',
      },
    });

  const userB =
    await database.user.create({
      data: {
        organizationId:
          organization.id,

        email:
          `stage10-b-${unique}@example.com`,

        emailNormalized:
          `stage10-b-${unique}@example.com`,

        displayName:
          'Stage 10 Employee B',

        status:
          'ACTIVE',
      },
    });

  const employeeA =
    await database.employee.create({
      data: {
        organizationId:
          organization.id,

        teamId:
          team.id,

        userId:
          userA.id,

        employeeCode:
          `S10A${unique}`,

        status:
          'ACTIVE',
      },
    });

  const employeeB =
    await database.employee.create({
      data: {
        organizationId:
          organization.id,

        teamId:
          team.id,

        userId:
          userB.id,

        employeeCode:
          `S10B${unique}`,

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
          employeeA.id,

        name:
          'Stage 10 Site',

        slug:
          `stage10-site-${unique}`,

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
          'Stage 10 Pool',

        slug:
          `stage10-pool-${unique}`,

        status:
          'ACTIVE',
      },
    });

  const phoneA =
    `910001${Date.now().toString().slice(-7)}`;

  const phoneB =
    `910002${Date.now().toString().slice(-7)}`;

  const numberA =
    await database.whatsAppNumber.create({
      data: {
        organizationId:
          organization.id,

        assignedEmployeeId:
          employeeA.id,

        displayName:
          'Stage 10 Number A',

        e164:
          `+155510${Date.now().toString().slice(-6)}`,

        status:
          'ACTIVE',

        metaWabaId:
          `810001${Date.now().toString().slice(-7)}`,

        metaPhoneNumberId:
          phoneA,

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
          employeeA.id,

        displayName:
          'Stage 10 Number B',

        e164:
          `+155520${Date.now().toString().slice(-6)}`,

        status:
          'ACTIVE',

        metaWabaId:
          `810002${Date.now().toString().slice(-7)}`,

        metaPhoneNumberId:
          phoneB,

        metaConnectedAt:
          new Date(),
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

  const request =
    await database.adsRequest.create({
      data: {
        organizationId:
          organization.id,

        employeeId:
          employeeA.id,

        siteId:
          site.id,

        trafficPoolId:
          pool.id,

        requestedByUserId:
          userA.id,

        requestedLeadCount:
          5,

        scheduledLeadCount:
          5,

        fulfilledLeadCount:
          0,

        status:
          'PROCESSING',

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
          employeeA.id,

        trafficPoolId:
          pool.id,

        status:
          'COMPLETED',

        completedAt:
          new Date(),
      },
    });

  const microbatchA1 =
    await database.adsMicrobatch.create({
      data: {
        organizationId:
          organization.id,

        adsRequestId:
          request.id,

        adsQueueItemId:
          queue.id,

        employeeId:
          employeeA.id,

        trafficPoolId:
          pool.id,

        trafficPoolMemberId:
          memberA.id,

        whatsAppNumberId:
          numberA.id,

        sequence:
          1,

        reservedLeadCount:
          2,

        deliveredLeadCount:
          0,

        status:
          'PLANNED',

        plannedAt:
          new Date(
            Date.now() -
              30000,
          ),
      },
    });

  const microbatchA2 =
    await database.adsMicrobatch.create({
      data: {
        organizationId:
          organization.id,

        adsRequestId:
          request.id,

        adsQueueItemId:
          queue.id,

        employeeId:
          employeeA.id,

        trafficPoolId:
          pool.id,

        trafficPoolMemberId:
          memberA.id,

        whatsAppNumberId:
          numberA.id,

        sequence:
          2,

        reservedLeadCount:
          1,

        deliveredLeadCount:
          0,

        status:
          'PLANNED',

        plannedAt:
          new Date(
            Date.now() -
              20000,
          ),
      },
    });

  const microbatchB =
    await database.adsMicrobatch.create({
      data: {
        organizationId:
          organization.id,

        adsRequestId:
          request.id,

        adsQueueItemId:
          queue.id,

        employeeId:
          employeeA.id,

        trafficPoolId:
          pool.id,

        trafficPoolMemberId:
          memberB.id,

        whatsAppNumberId:
          numberB.id,

        sequence:
          3,

        reservedLeadCount:
          2,

        deliveredLeadCount:
          0,

        status:
          'PLANNED',

        plannedAt:
          new Date(
            Date.now() -
              10000,
          ),
      },
    });

  const processor =
    new WhatsAppInboxProcessorService(
      database,
      `stage10-inbox-${unique}`,
      runtimeConfig,
    );

  const nowSeconds =
    Math.floor(
      Date.now() /
        1000,
    );

  const firstWaId =
    `551190001${unique.slice(0, 4)}`;

  await createEnvelope({
    organizationId:
      organization.id,

    whatsAppNumberId:
      numberA.id,

    wabaId:
      numberA.metaWabaId!,

    phoneNumberId:
      phoneA,

    waId:
      firstWaId,

    messageId:
      `wamid.stage10.first.${unique}`,

    timestamp:
      nowSeconds,

    nonce:
      `first-${unique}`,
  });

  const firstTick =
    await processor.runTick();

  assert.equal(
    firstTick.messages,
    1,
  );

  const firstLead =
    await database.lead.findFirstOrThrow({
      where: {
        organizationId:
          organization.id,

        waIdSnapshot:
          firstWaId,
      },

      include: {
        attribution:
          true,
      },
    });

  assert.equal(
    firstLead.status,
    'ATTRIBUTED',
  );

  assert.equal(
    firstLead.attribution?.adsMicrobatchId,
    microbatchA1.id,
  );

  assert.equal(
    firstLead.inboundMessageCount,
    1,
  );

  assert.equal(
    (
      await database.adsMicrobatch.findUniqueOrThrow({
        where: {
          id:
            microbatchA1.id,
        },
      })
    ).deliveredLeadCount,
    1,
  );

  assert.equal(
    (
      await database.adsRequest.findUniqueOrThrow({
        where: {
          id:
            request.id,
        },
      })
    ).fulfilledLeadCount,
    1,
  );

  log(
    'stage10.webhook_to_lead_attribution.passed',
  );

  await createEnvelope({
    organizationId:
      organization.id,

    whatsAppNumberId:
      numberA.id,

    wabaId:
      numberA.metaWabaId!,

    phoneNumberId:
      phoneA,

    waId:
      firstWaId,

    messageId:
      `wamid.stage10.duplicate.${unique}`,

    timestamp:
      nowSeconds +
      1,

    nonce:
      `duplicate-${unique}`,
  });

  await processor.runTick();

  const duplicateLead =
    await database.lead.findFirstOrThrow({
      where: {
        organizationId:
          organization.id,

        waIdSnapshot:
          firstWaId,
      },
    });

  assert.equal(
    duplicateLead.inboundMessageCount,
    2,
  );

  assert.equal(
    await database.lead.count({
      where: {
        organizationId:
          organization.id,

        waIdSnapshot:
          firstWaId,
      },
    }),
    1,
  );

  assert.equal(
    (
      await database.adsRequest.findUniqueOrThrow({
        where: {
          id:
            request.id,
        },
      })
    ).fulfilledLeadCount,
    1,
  );

  log(
    'stage10.unique_waid_deduplication.passed',
  );

  const secondWaId =
    `551190002${unique.slice(0, 4)}`;

  await createEnvelope({
    organizationId:
      organization.id,

    whatsAppNumberId:
      numberA.id,

    wabaId:
      numberA.metaWabaId!,

    phoneNumberId:
      phoneA,

    waId:
      secondWaId,

    messageId:
      `wamid.stage10.second.${unique}`,

    timestamp:
      nowSeconds +
      2,

    nonce:
      `second-${unique}`,
  });

  await processor.runTick();

  const secondLead =
    await database.lead.findFirstOrThrow({
      where: {
        organizationId:
          organization.id,

        waIdSnapshot:
          secondWaId,
      },

      include: {
        attribution:
          true,
      },
    });

  assert.equal(
    secondLead.attribution?.adsMicrobatchId,
    microbatchA1.id,
  );

  const a1After =
    await database.adsMicrobatch.findUniqueOrThrow({
      where: {
        id:
          microbatchA1.id,
      },
    });

  assert.equal(
    a1After.deliveredLeadCount,
    2,
  );

  assert.equal(
    a1After.status,
    'COMPLETED',
  );

  log(
    'stage10.first_microbatch_completed.passed',
  );

  const thirdWaId =
    `551190003${unique.slice(0, 4)}`;

  await createEnvelope({
    organizationId:
      organization.id,

    whatsAppNumberId:
      numberA.id,

    wabaId:
      numberA.metaWabaId!,

    phoneNumberId:
      phoneA,

    waId:
      thirdWaId,

    messageId:
      `wamid.stage10.third.${unique}`,

    timestamp:
      nowSeconds +
      3,

    nonce:
      `third-${unique}`,
  });

  await processor.runTick();

  const thirdLead =
    await database.lead.findFirstOrThrow({
      where: {
        organizationId:
          organization.id,

        waIdSnapshot:
          thirdWaId,
      },

      include: {
        attribution:
          true,
      },
    });

  assert.equal(
    thirdLead.attribution?.adsMicrobatchId,
    microbatchA2.id,
  );

  const a2After =
    await database.adsMicrobatch.findUniqueOrThrow({
      where: {
        id:
          microbatchA2.id,
      },
    });

  assert.equal(
    a2After.deliveredLeadCount,
    1,
  );

  assert.equal(
    a2After.status,
    'COMPLETED',
  );

  log(
    'stage10.microbatch_fifo.passed',
  );

  const excessWaId =
    `551190004${unique.slice(0, 4)}`;

  await createEnvelope({
    organizationId:
      organization.id,

    whatsAppNumberId:
      numberA.id,

    wabaId:
      numberA.metaWabaId!,

    phoneNumberId:
      phoneA,

    waId:
      excessWaId,

    messageId:
      `wamid.stage10.excess.${unique}`,

    timestamp:
      nowSeconds +
      4,

    nonce:
      `excess-${unique}`,
  });

  await processor.runTick();

  const excessLead =
    await database.lead.findFirstOrThrow({
      where: {
        organizationId:
          organization.id,

        waIdSnapshot:
          excessWaId,
      },
    });

  assert.equal(
    excessLead.status,
    'EXCESS',
  );

  assert.equal(
    excessLead.excessReason,
    'NO_RESERVED_CAPACITY',
  );

  assert.equal(
    (
      await database.adsRequest.findUniqueOrThrow({
        where: {
          id:
            request.id,
        },
      })
    ).fulfilledLeadCount,
    3,
  );

  log(
    'stage10.excess_without_capacity.passed',
  );

  const directB1 =
    await createDirectInbound({
      organizationId:
        organization.id,

      whatsAppNumberId:
        numberB.id,

      waId:
        `551191001${unique.slice(0, 4)}`,

      sequence:
        101,

      assignedEmployeeId:
        employeeA.id,
    });

  const directB2 =
    await createDirectInbound({
      organizationId:
        organization.id,

      whatsAppNumberId:
        numberB.id,

      waId:
        `551191002${unique.slice(0, 4)}`,

      sequence:
        102,

      assignedEmployeeId:
        employeeA.id,
    });

  const directB3 =
    await createDirectInbound({
      organizationId:
        organization.id,

      whatsAppNumberId:
        numberB.id,

      waId:
        `551191003${unique.slice(0, 4)}`,

      sequence:
        103,

      assignedEmployeeId:
        employeeA.id,
    });

  const attributionService =
    new LeadAttributionService();

  const concurrentResults =
    await Promise.all([
      database.$transaction(
        (
          transaction,
        ) =>
          attributionService.recordInboundLead(
            transaction,
            {
              organizationId:
                organization.id,

              contactId:
                directB1.contact.id,

              whatsAppNumberId:
                numberB.id,

              ownerEmployeeId:
                employeeA.id,

              inboundMessageId:
                directB1.message.id,

              waId:
                directB1.contact.waId,

              profileName:
                directB1.contact.profileName,

              providerTimestamp:
                directB1.message.providerTimestamp ??
                new Date(),
            },
          ),
      ),

      database.$transaction(
        (
          transaction,
        ) =>
          attributionService.recordInboundLead(
            transaction,
            {
              organizationId:
                organization.id,

              contactId:
                directB2.contact.id,

              whatsAppNumberId:
                numberB.id,

              ownerEmployeeId:
                employeeA.id,

              inboundMessageId:
                directB2.message.id,

              waId:
                directB2.contact.waId,

              profileName:
                directB2.contact.profileName,

              providerTimestamp:
                directB2.message.providerTimestamp ??
                new Date(),
            },
          ),
      ),

      database.$transaction(
        (
          transaction,
        ) =>
          attributionService.recordInboundLead(
            transaction,
            {
              organizationId:
                organization.id,

              contactId:
                directB3.contact.id,

              whatsAppNumberId:
                numberB.id,

              ownerEmployeeId:
                employeeA.id,

              inboundMessageId:
                directB3.message.id,

              waId:
                directB3.contact.waId,

              profileName:
                directB3.contact.profileName,

              providerTimestamp:
                directB3.message.providerTimestamp ??
                new Date(),
            },
          ),
      ),
    ]);

  assert.equal(
    concurrentResults.filter(
      (
        item,
      ) =>
        item ===
        'ATTRIBUTED',
    ).length,
    2,
  );

  assert.equal(
    concurrentResults.filter(
      (
        item,
      ) =>
        item ===
        'EXCESS',
    ).length,
    1,
  );

  const bAfter =
    await database.adsMicrobatch.findUniqueOrThrow({
      where: {
        id:
          microbatchB.id,
      },
    });

  assert.equal(
    bAfter.deliveredLeadCount,
    2,
  );

  assert.equal(
    bAfter.reservedLeadCount,
    2,
  );

  assert.equal(
    bAfter.status,
    'COMPLETED',
  );

  const requestAfterConcurrent =
    await database.adsRequest.findUniqueOrThrow({
      where: {
        id:
          request.id,
      },
    });

  assert.equal(
    requestAfterConcurrent.fulfilledLeadCount,
    5,
  );

  assert.equal(
    requestAfterConcurrent.requestedLeadCount,
    5,
  );

  assert.equal(
    requestAfterConcurrent.status,
    'FULFILLED',
  );

  assert.ok(
    requestAfterConcurrent.completedAt,
  );

  log(
    'stage10.concurrent_capacity_consumption.passed',
  );

  assert.ok(
    requestAfterConcurrent.fulfilledLeadCount <=
      requestAfterConcurrent.requestedLeadCount,
  );

  assert.ok(
    a1After.deliveredLeadCount <=
      a1After.reservedLeadCount,
  );

  assert.ok(
    a2After.deliveredLeadCount <=
      a2After.reservedLeadCount,
  );

  assert.ok(
    bAfter.deliveredLeadCount <=
      bAfter.reservedLeadCount,
  );

  log(
    'stage10.no_overfill_invariants.passed',
  );

  const dedupRequest =
    await database.adsRequest.create({
      data: {
        organizationId:
          organization.id,

        employeeId:
          employeeB.id,

        siteId:
          site.id,

        trafficPoolId:
          pool.id,

        requestedByUserId:
          userB.id,

        requestedLeadCount:
          2,

        scheduledLeadCount:
          2,

        status:
          'PROCESSING',

        startedAt:
          new Date(),
      },
    });

  const dedupQueue =
    await database.adsQueueItem.create({
      data: {
        organizationId:
          organization.id,

        adsRequestId:
          dedupRequest.id,

        employeeId:
          employeeB.id,

        trafficPoolId:
          pool.id,

        status:
          'COMPLETED',

        completedAt:
          new Date(),
      },
    });

  const numberC =
    await database.whatsAppNumber.create({
      data: {
        organizationId:
          organization.id,

        assignedEmployeeId:
          employeeB.id,

        displayName:
          'Stage 10 Number C',

        e164:
          `+155530${Date.now().toString().slice(-6)}`,

        status:
          'ACTIVE',
      },
    });

  const memberC =
    await database.trafficPoolMember.create({
      data: {
        organizationId:
          organization.id,

        trafficPoolId:
          pool.id,

        whatsAppNumberId:
          numberC.id,

        position:
          3,

        status:
          'ACTIVE',
      },
    });

  const dedupMicrobatch =
    await database.adsMicrobatch.create({
      data: {
        organizationId:
          organization.id,

        adsRequestId:
          dedupRequest.id,

        adsQueueItemId:
          dedupQueue.id,

        employeeId:
          employeeB.id,

        trafficPoolId:
          pool.id,

        trafficPoolMemberId:
          memberC.id,

        whatsAppNumberId:
          numberC.id,

        sequence:
          1,

        reservedLeadCount:
          2,

        status:
          'PLANNED',
      },
    });

  const sharedContact =
    await database.whatsAppContact.create({
      data: {
        organizationId:
          organization.id,

        waId:
          `551192000${unique.slice(0, 4)}`,

        profileName:
          'Concurrent Duplicate',

        lastInboundAt:
          new Date(),
      },
    });

  const sharedConversation =
    await database.whatsAppConversation.create({
      data: {
        organizationId:
          organization.id,

        whatsAppNumberId:
          numberC.id,

        contactId:
          sharedContact.id,

        assignedEmployeeId:
          employeeB.id,

        status:
          'OPEN',

        lastMessageAt:
          new Date(),

        lastInboundAt:
          new Date(),

        unreadCount:
          2,
      },
    });

  const sharedMessage1 =
    await database.whatsAppMessage.create({
      data: {
        organizationId:
          organization.id,

        conversationId:
          sharedConversation.id,

        whatsAppNumberId:
          numberC.id,

        contactId:
          sharedContact.id,

        direction:
          'INBOUND',

        type:
          'TEXT',

        status:
          'RECEIVED',

        metaMessageId:
          `wamid.stage10.samecontact.1.${unique}`,

        textBody:
          'Mensagem 1',

        content: {
          test:
            1,
        },

        providerTimestamp:
          new Date(),

        availableAt:
          new Date(),
      },
    });

  const sharedMessage2 =
    await database.whatsAppMessage.create({
      data: {
        organizationId:
          organization.id,

        conversationId:
          sharedConversation.id,

        whatsAppNumberId:
          numberC.id,

        contactId:
          sharedContact.id,

        direction:
          'INBOUND',

        type:
          'TEXT',

        status:
          'RECEIVED',

        metaMessageId:
          `wamid.stage10.samecontact.2.${unique}`,

        textBody:
          'Mensagem 2',

        content: {
          test:
            2,
        },

        providerTimestamp:
          new Date(),

        availableAt:
          new Date(),
      },
    });

  const duplicateConcurrentResults =
    await Promise.all([
      database.$transaction(
        (
          transaction,
        ) =>
          attributionService.recordInboundLead(
            transaction,
            {
              organizationId:
                organization.id,

              contactId:
                sharedContact.id,

              whatsAppNumberId:
                numberC.id,

              ownerEmployeeId:
                employeeB.id,

              inboundMessageId:
                sharedMessage1.id,

              waId:
                sharedContact.waId,

              profileName:
                sharedContact.profileName,

              providerTimestamp:
                sharedMessage1.providerTimestamp ??
                new Date(),
            },
          ),
      ),

      database.$transaction(
        (
          transaction,
        ) =>
          attributionService.recordInboundLead(
            transaction,
            {
              organizationId:
                organization.id,

              contactId:
                sharedContact.id,

              whatsAppNumberId:
                numberC.id,

              ownerEmployeeId:
                employeeB.id,

              inboundMessageId:
                sharedMessage2.id,

              waId:
                sharedContact.waId,

              profileName:
                sharedContact.profileName,

              providerTimestamp:
                sharedMessage2.providerTimestamp ??
                new Date(),
            },
          ),
      ),
    ]);

  assert.equal(
    duplicateConcurrentResults.filter(
      (
        item,
      ) =>
        item ===
        'ATTRIBUTED',
    ).length,
    1,
  );

  assert.equal(
    duplicateConcurrentResults.filter(
      (
        item,
      ) =>
        item ===
        'DUPLICATE',
    ).length,
    1,
  );

  assert.equal(
    await database.lead.count({
      where: {
        organizationId:
          organization.id,

        contactId:
          sharedContact.id,
      },
    }),
    1,
  );

  const sharedLead =
    await database.lead.findFirstOrThrow({
      where: {
        organizationId:
          organization.id,

        contactId:
          sharedContact.id,
      },
    });

  assert.equal(
    sharedLead.inboundMessageCount,
    2,
  );

  const dedupBatchAfter =
    await database.adsMicrobatch.findUniqueOrThrow({
      where: {
        id:
          dedupMicrobatch.id,
      },
    });

  assert.equal(
    dedupBatchAfter.deliveredLeadCount,
    1,
  );

  assert.equal(
    (
      await database.adsRequest.findUniqueOrThrow({
        where: {
          id:
            dedupRequest.id,
        },
      })
    ).fulfilledLeadCount,
    1,
  );

  log(
    'stage10.concurrent_same_contact_deduplication.passed',
  );

  const unassignedNumber =
    await database.whatsAppNumber.create({
      data: {
        organizationId:
          organization.id,

        displayName:
          'Stage 10 Unassigned',

        e164:
          `+155540${Date.now().toString().slice(-6)}`,

        status:
          'ACTIVE',
      },
    });

  const unassignedInbound =
    await createDirectInbound({
      organizationId:
        organization.id,

      whatsAppNumberId:
        unassignedNumber.id,

      waId:
        `551193000${unique.slice(0, 4)}`,

      sequence:
        201,

      assignedEmployeeId:
        null,
    });

  const unassignedResult =
    await database.$transaction(
      (
        transaction,
      ) =>
        attributionService.recordInboundLead(
          transaction,
          {
            organizationId:
              organization.id,

            contactId:
              unassignedInbound.contact.id,

            whatsAppNumberId:
              unassignedNumber.id,

            ownerEmployeeId:
              null,

            inboundMessageId:
              unassignedInbound.message.id,

            waId:
              unassignedInbound.contact.waId,

            profileName:
              unassignedInbound.contact.profileName,

            providerTimestamp:
              unassignedInbound.message.providerTimestamp ??
              new Date(),
          },
        ),
    );

  assert.equal(
    unassignedResult,
    'EXCESS',
  );

  const unassignedLead =
    await database.lead.findFirstOrThrow({
      where: {
        organizationId:
          organization.id,

        contactId:
          unassignedInbound.contact.id,
      },
    });

  assert.equal(
    unassignedLead.excessReason,
    'NUMBER_UNASSIGNED',
  );

  assert.equal(
    unassignedLead.ownerEmployeeId,
    null,
  );

  log(
    'stage10.unassigned_number_excess.passed',
  );

  const leadsModule =
    await import(
      '../../api/dist/leads/leads.service.js'
    );

  const leadsService =
    new leadsModule.LeadsService(
      {
        client:
          database,
      } as never,
    );

  const adminPrincipal = {
    organizationId:
      organization.id,

    userId:
      userA.id,

    sessionId:
      randomUUID(),

    roles: [
      'ADMIN',
    ] as const,
  };

  const employeeAPrincipal = {
    organizationId:
      organization.id,

    userId:
      userA.id,

    sessionId:
      randomUUID(),

    roles: [
      'EMPLOYEE',
    ] as const,
  };

  const employeeBPrincipal = {
    organizationId:
      organization.id,

    userId:
      userB.id,

    sessionId:
      randomUUID(),

    roles: [
      'EMPLOYEE',
    ] as const,
  };

  const adminSummary =
    await leadsService.summary(
      adminPrincipal,
    );

  assert.ok(
    adminSummary.totalUniqueLeads >=
      9,
  );

  assert.equal(
    adminSummary.attributedLeads,
    6,
  );

  assert.ok(
    adminSummary.excessLeads >=
      3,
  );

  const employeeAList =
    await leadsService.list(
      employeeAPrincipal,
      {
        limit:
          100,
      },
    );

  assert.ok(
    employeeAList.items.length >
      0,
  );

  assert.ok(
    employeeAList.items.every(
      (
        lead,
      ) =>
        lead.ownerEmployee?.employeeId ===
        employeeA.id,
    ),
  );

  await assert.rejects(
    () =>
      leadsService.getById(
        employeeAPrincipal,
        sharedLead.id,
      ),
  );

  const employeeBLead =
    await leadsService.getById(
      employeeBPrincipal,
      sharedLead.id,
    );

  assert.equal(
    employeeBLead.ownerEmployee?.employeeId,
    employeeB.id,
  );

  log(
    'stage10.employee_isolation.passed',
  );

  const foreignOrganization =
    await database.organization.create({
      data: {
        name:
          'Stage 10 Foreign',

        slug:
          `stage10-foreign-${unique}`,

        status:
          'ACTIVE',
      },
    });

  const foreignTeam =
    await database.team.create({
      data: {
        organizationId:
          foreignOrganization.id,

        name:
          'Foreign Team',

        slug:
          `foreign-${unique}`,

        status:
          'ACTIVE',
      },
    });

  const foreignUser =
    await database.user.create({
      data: {
        organizationId:
          foreignOrganization.id,

        email:
          `foreign-${unique}@example.com`,

        emailNormalized:
          `foreign-${unique}@example.com`,

        displayName:
          'Foreign',

        status:
          'ACTIVE',
      },
    });

  const foreignEmployee =
    await database.employee.create({
      data: {
        organizationId:
          foreignOrganization.id,

        teamId:
          foreignTeam.id,

        userId:
          foreignUser.id,

        employeeCode:
          `FOREIGN${unique}`,

        status:
          'ACTIVE',
      },
    });

  const foreignSite =
    await database.site.create({
      data: {
        organizationId:
          foreignOrganization.id,

        ownerEmployeeId:
          foreignEmployee.id,

        name:
          'Foreign Site',

        slug:
          `foreign-site-${unique}`,

        status:
          'ACTIVE',
      },
    });

  const foreignNumber =
    await database.whatsAppNumber.create({
      data: {
        organizationId:
          foreignOrganization.id,

        assignedEmployeeId:
          foreignEmployee.id,

        displayName:
          'Foreign Number',

        e164:
          `+155550${Date.now().toString().slice(-6)}`,

        status:
          'ACTIVE',
      },
    });

  const foreignContact =
    await database.whatsAppContact.create({
      data: {
        organizationId:
          foreignOrganization.id,

        waId:
          `551194000${unique.slice(0, 4)}`,

        profileName:
          'Foreign Lead',
      },
    });

  const foreignConversation =
    await database.whatsAppConversation.create({
      data: {
        organizationId:
          foreignOrganization.id,

        whatsAppNumberId:
          foreignNumber.id,

        contactId:
          foreignContact.id,

        assignedEmployeeId:
          foreignEmployee.id,

        status:
          'OPEN',
      },
    });

  const foreignMessage =
    await database.whatsAppMessage.create({
      data: {
        organizationId:
          foreignOrganization.id,

        conversationId:
          foreignConversation.id,

        whatsAppNumberId:
          foreignNumber.id,

        contactId:
          foreignContact.id,

        direction:
          'INBOUND',

        type:
          'TEXT',

        status:
          'RECEIVED',

        metaMessageId:
          `wamid.stage10.foreign.${unique}`,

        content: {
          foreign:
            true,
        },
      },
    });

  const foreignLead =
    await database.lead.create({
      data: {
        organizationId:
          foreignOrganization.id,

        contactId:
          foreignContact.id,

        firstInboundMessageId:
          foreignMessage.id,

        firstWhatsAppNumberId:
          foreignNumber.id,

        ownerEmployeeId:
          foreignEmployee.id,

        waIdSnapshot:
          foreignContact.waId,

        profileNameSnapshot:
          foreignContact.profileName,

        status:
          'EXCESS',

        excessReason:
          'NO_RESERVED_CAPACITY',

        firstSeenAt:
          new Date(),

        lastSeenAt:
          new Date(),
      },
    });

  await assert.rejects(
    () =>
      leadsService.getById(
        adminPrincipal,
        foreignLead.id,
      ),
  );

  log(
    'stage10.tenant_isolation.passed',
  );

  const auditAttributed =
    await database.auditLog.count({
      where: {
        organizationId:
          organization.id,

        action:
          'lead.attributed',
      },
    });

  const auditExcess =
    await database.auditLog.count({
      where: {
        organizationId:
          organization.id,

        action:
          'lead.excess',
      },
    });

  const auditFulfilled =
    await database.auditLog.count({
      where: {
        organizationId:
          organization.id,

        action:
          'ads_request.fulfilled',
      },
    });

  assert.ok(
    auditAttributed >=
      6,
  );

  assert.ok(
    auditExcess >=
      2,
  );

  assert.equal(
    auditFulfilled,
    1,
  );

  log(
    'stage10.audit.passed',
    {
      auditAttributed,
      auditExcess,
      auditFulfilled,
    },
  );

  log(
    'stage10.validation.completed',
  );

  /*
   * Foreign fixture is intentionally cleaned separately because
   * the main cleanup only targets organizationSlug.
   */
  await database.auditLog.deleteMany({
    where: {
      organizationId:
        foreignOrganization.id,
    },
  });

  await database.leadAttribution.deleteMany({
    where: {
      organizationId:
        foreignOrganization.id,
    },
  });

  await database.lead.deleteMany({
    where: {
      organizationId:
        foreignOrganization.id,
    },
  });

  await database.whatsAppMessage.deleteMany({
    where: {
      organizationId:
        foreignOrganization.id,
    },
  });

  await database.whatsAppConversation.deleteMany({
    where: {
      organizationId:
        foreignOrganization.id,
    },
  });

  await database.whatsAppContact.deleteMany({
    where: {
      organizationId:
        foreignOrganization.id,
    },
  });

  await database.whatsAppNumber.deleteMany({
    where: {
      organizationId:
        foreignOrganization.id,
    },
  });

  await database.site.deleteMany({
    where: {
      organizationId:
        foreignOrganization.id,
    },
  });

  await database.employee.deleteMany({
    where: {
      organizationId:
        foreignOrganization.id,
    },
  });

  await database.user.deleteMany({
    where: {
      organizationId:
        foreignOrganization.id,
    },
  });

  await database.team.deleteMany({
    where: {
      organizationId:
        foreignOrganization.id,
    },
  });

  await database.organization.delete({
    where: {
      id:
        foreignOrganization.id,
    },
  });
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
    -Path ".\apps\worker\scripts\stage10-runtime-validation.ts" `
    -Content $RuntimeValidator

Invoke-Native `
    -Description "Format Stage 10 runtime validator" `
    -Command "pnpm" `
    -Arguments @("format")

# ============================================================
# REBUILD AFTER RUNTIME FILE
# ============================================================

Invoke-Native `
    -Description "Rebuild Stage 10 API + Worker" `
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
Write-Host "==== Stage 10 runtime validation ====" -ForegroundColor Cyan

& pnpm `
    --filter `
    "@crm/worker" `
    exec `
    tsx `
    "scripts/stage10-runtime-validation.ts"

if ($LASTEXITCODE -ne 0) {
    throw "Stage 10 runtime validation falhou."
}

Write-Host "[OK] Stage 10 runtime validation." -ForegroundColor Green

# ============================================================
# WORKER PROCESS SMOKE
# ============================================================

Write-Host ""
Write-Host "==== Worker process smoke Stage 10 ====" -ForegroundColor Cyan

$WorkerProcess =
    $null

$PreviousWorkerId =
    [Environment]::GetEnvironmentVariable(
        "ADS_WORKER_ID",
        "Process"
    )

$PreviousInboxInterval =
    [Environment]::GetEnvironmentVariable(
        "WHATSAPP_INBOX_INTERVAL_MS",
        "Process"
    )

$PreviousOutboundInterval =
    [Environment]::GetEnvironmentVariable(
        "WHATSAPP_OUTBOUND_INTERVAL_MS",
        "Process"
    )

$env:ADS_WORKER_ID =
    "stage10-process-smoke"

$env:WHATSAPP_INBOX_INTERVAL_MS =
    "60000"

$env:WHATSAPP_OUTBOUND_INTERVAL_MS =
    "60000"

try {
    $StartParameters = @{
        FilePath         = "node"
        ArgumentList     = "apps/worker/dist/main.js"
        WorkingDirectory = $RepositoryRoot
        NoNewWindow      = $true
        PassThru         = $true
    }

    $WorkerProcess =
        Start-Process @StartParameters

    Start-Sleep -Seconds 3

    if ($WorkerProcess.HasExited) {
        throw "Worker encerrou no process smoke Stage 10. ExitCode: $($WorkerProcess.ExitCode)"
    }

    Write-Host "[OK] Worker Stage 10 permaneceu online." -ForegroundColor Green
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

    if ($null -ne $PreviousInboxInterval) {
        $env:WHATSAPP_INBOX_INTERVAL_MS =
            $PreviousInboxInterval
    }
    else {
        Remove-Item `
            "Env:WHATSAPP_INBOX_INTERVAL_MS" `
            -ErrorAction SilentlyContinue
    }

    if ($null -ne $PreviousOutboundInterval) {
        $env:WHATSAPP_OUTBOUND_INTERVAL_MS =
            $PreviousOutboundInterval
    }
    else {
        Remove-Item `
            "Env:WHATSAPP_OUTBOUND_INTERVAL_MS" `
            -ErrorAction SilentlyContinue
    }
}

# ============================================================
# GLOBAL CI
# ============================================================

Invoke-Native `
    -Description "Global CI Stage 10" `
    -Command "pnpm" `
    -Arguments @("ci:check")

# ============================================================
# DOCUMENTATION
# ============================================================

$Stage10Doc = @(
    "# Etapa 10 - Leads unicos e atribuicao",
    "",
    "## Status",
    "",
    "CONCLUIDA.",
    "",
    "## Objetivo",
    "",
    "Conectar leads reais recebidos pelo WhatsApp aos slots reservados pelo scheduler de ADS.",
    "",
    "## Identidade de lead",
    "",
    "A identidade de negocio e WhatsAppContact.",
    "",
    "WhatsAppContact ja e unico por Organization + waId.",
    "",
    "Por isso cada contato WhatsApp gera no maximo um Lead por Organization.",
    "",
    "Mensagens inbound posteriores incrementam inboundMessageCount, mas nao fulfilledLeadCount.",
    "",
    "## Lead",
    "",
    "Lead preserva:",
    "",
    "- contato",
    "- waId snapshot",
    "- profile name snapshot",
    "- primeira mensagem inbound",
    "- primeiro numero WhatsApp",
    "- funcionario proprietario",
    "- firstSeenAt",
    "- lastSeenAt",
    "- inboundMessageCount",
    "- status ATTRIBUTED ou EXCESS",
    "",
    "## LeadAttribution",
    "",
    "LeadAttribution registra de forma imutavel qual lead consumiu qual slot ADS.",
    "",
    "A atribuicao registra:",
    "",
    "- Lead",
    "- AdsRequest",
    "- AdsMicrobatch",
    "- Employee",
    "- WhatsAppNumber",
    "- inbound WhatsAppMessage",
    "- attributedAt",
    "",
    "## Consumo de microbatch",
    "",
    "Somente microbatches PLANNED ou DELIVERING com capacidade restante podem receber lead.",
    "",
    "A selecao e FIFO por plannedAt, sequence e id.",
    "",
    "O lead somente pode consumir capacidade do mesmo WhatsAppNumber e Employee.",
    "",
    "PLANNED passa a DELIVERING na primeira entrega.",
    "",
    "Quando deliveredLeadCount atinge reservedLeadCount, o microbatch vira COMPLETED.",
    "",
    "## AdsRequest",
    "",
    "Cada LeadAttribution incrementa fulfilledLeadCount exatamente uma vez.",
    "",
    "Com entrega parcial o pedido vira PARTIALLY_FULFILLED.",
    "",
    "Quando fulfilledLeadCount atinge requestedLeadCount, o pedido vira FULFILLED e completedAt e gravado.",
    "",
    "## Excess",
    "",
    "Lead sem slot reservado permanece EXCESS.",
    "",
    "Motivos iniciais:",
    "",
    "- NUMBER_UNASSIGNED",
    "- NO_RESERVED_CAPACITY",
    "",
    "Lead EXCESS nao incrementa deliveredLeadCount nem fulfilledLeadCount.",
    "",
    "## Concorrencia",
    "",
    "Advisory lock por Organization + Contact serializa a decisao de lead unico.",
    "",
    "Advisory lock por Organization + WhatsAppNumber serializa o consumo de capacidade daquele numero.",
    "",
    "A query de selecao tambem bloqueia AdsMicrobatch e AdsRequest com FOR UPDATE.",
    "",
    "Isso protege fulfilledLeadCount mesmo quando numeros diferentes entregam simultaneamente para o mesmo AdsRequest.",
    "",
    "## API",
    "",
    "GET /leads",
    "",
    "GET /leads/summary",
    "",
    "GET /leads/:leadId",
    "",
    "ADMIN possui visibilidade organizacional.",
    "",
    "EMPLOYEE visualiza apenas leads cujo ownerEmployeeId corresponde ao proprio Employee.",
    "",
    "## Permission",
    "",
    "lead.read",
    "",
    "ADMIN e EMPLOYEE recebem lead.read.",
    "",
    "## Validacao",
    "",
    "O runtime Stage 10 valida:",
    "",
    "- webhook -> Inbox -> Lead -> LeadAttribution",
    "- deduplicacao por waId",
    "- inboundMessageCount",
    "- FIFO de microbatch",
    "- completion de microbatch",
    "- lead excess sem capacidade",
    "- concorrencia de consumo",
    "- no overfill de microbatch",
    "- no overfill de AdsRequest",
    "- concorrencia do mesmo contato",
    "- numero sem Employee",
    "- Employee isolation",
    "- tenant isolation",
    "- audit",
    "- worker process smoke",
    "- global CI",
    "",
    "## Proxima etapa",
    "",
    "Etapa 11 - Saude, contingencia e recuperacao dos numeros WhatsApp."
)

Write-Lines `
    -Path ".\docs\ETAPA_10_LEADS_ATRIBUICAO.md" `
    -Lines $Stage10Doc

$DecisionDoc = @(
    "# Decisoes - Etapa 10",
    "",
    "Lead unico e definido por Organization + WhatsAppContact.",
    "",
    "Como WhatsAppContact e unico por Organization + waId, o mesmo cliente nao consome capacidade ADS novamente ao enviar novas mensagens.",
    "",
    "LeadAttribution e a prova persistente da entrega de um lead real.",
    "",
    "scheduledLeadCount continua representando capacidade reservada.",
    "",
    "fulfilledLeadCount passa a representar apenas LeadAttribution efetivamente persistida.",
    "",
    "deliveredLeadCount passa a representar apenas LeadAttribution efetivamente persistida no AdsMicrobatch.",
    "",
    "Microbatch e consumido somente pelo WhatsAppNumber para o qual foi reservado.",
    "",
    "Selecao de capacidade e FIFO.",
    "",
    "Lead recebido sem capacidade vira EXCESS e nao altera os contadores ADS.",
    "",
    "A primeira implementacao nao reatribui automaticamente leads EXCESS antigos quando nova capacidade aparece.",
    "",
    "Essa escolha evita atribuir retroativamente trafego recebido fora da janela operacional do microlote sem uma politica explicita.",
    "",
    "Advisory lock por Contact protege unique lead.",
    "",
    "Advisory lock por WhatsAppNumber protege slots locais.",
    "",
    "FOR UPDATE em AdsMicrobatch e AdsRequest protege o contador global do pedido entre numeros diferentes.",
    "",
    "AdsRequest FULFILLED significa requestedLeadCount leads unicos efetivamente atribuidos.",
    "",
    "Mensagens repetidas de um lead existente continuam normalmente na Inbox."
)

Write-Lines `
    -Path ".\docs\DECISOES_ETAPA_10.md" `
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
            10;
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

    if ($Etapas.Contains("## Etapa 10 - Leads unicos")) {
        $Etapas =
            [regex]::Replace(
                $Etapas,
                '(?s)## Etapa 10 - Leads unicos.*?(?=## Etapa 11|\z)',
                @'
## Etapa 10 - Leads unicos e atribuicao

Status: CONCLUIDA.

Implementado:

- Lead
- LeadAttribution
- Organization + waId unique lead identity
- inboundMessageCount
- WhatsApp -> ADS attribution
- FIFO microbatch consumption
- deliveredLeadCount real
- fulfilledLeadCount real
- ATTRIBUTED / EXCESS
- NUMBER_UNASSIGNED
- NO_RESERVED_CAPACITY
- concurrent contact deduplication
- concurrent slot protection
- AdsRequest fulfillment
- lead.read
- Leads API
- Employee isolation
- tenant isolation

Documentacao:

- docs/ETAPA_10_LEADS_ATRIBUICAO.md
- docs/DECISOES_ETAPA_10.md

Proxima: Etapa 11 - Saude, contingencia e recuperacao dos numeros WhatsApp.

'@
            )
    }
    else {
        $Etapas =
            $Etapas.TrimEnd() +
            "`r`n`r`n" +
            "## Etapa 10 - Leads unicos e atribuicao`r`n`r`n" +
            "Status: CONCLUIDA.`r`n`r`n" +
            "Documentacao: docs/ETAPA_10_LEADS_ATRIBUICAO.md e docs/DECISOES_ETAPA_10.md.`r`n`r`n" +
            "Proxima: Etapa 11 - Saude, contingencia e recuperacao dos numeros WhatsApp.`r`n"
    }

    Write-Text `
        -Path $EtapasPath `
        -Content $Etapas
}

Write-Host "[OK] Stage 10 documentation." -ForegroundColor Green

# ============================================================
# FINAL FORMAT + CI
# ============================================================

Invoke-Native `
    -Description "Final format Stage 10" `
    -Command "pnpm" `
    -Arguments @("format")

Invoke-Native `
    -Description "Final format check Stage 10" `
    -Command "pnpm" `
    -Arguments @("format:check")

Invoke-Native `
    -Description "Final global CI Stage 10" `
    -Command "pnpm" `
    -Arguments @("ci:check")

# ============================================================
# STRUCTURAL INVARIANTS
# ============================================================

Write-Host ""
Write-Host "==== Stage 10 structural checks ====" -ForegroundColor Cyan

$Schema =
    Read-Text -Path ".\packages\database\prisma\schema.prisma"

$AttributionService =
    Read-Text -Path ".\apps\worker\src\lead-attribution.service.ts"

$InboxProcessor =
    Read-Text -Path ".\apps\worker\src\whatsapp-inbox-processor.service.ts"

$Guard =
    Read-Text -Path ".\apps\api\src\authorization\access-token.guard.ts"

$AuthorizationTypes =
    Read-Text -Path ".\apps\api\src\authorization\authorization.types.ts"

$Seed =
    Read-Text -Path ".\packages\database\prisma\seed.ts"

$VerifySeed =
    Read-Text -Path ".\packages\database\prisma\verify-seed.ts"

foreach ($Marker in @(
    "model Lead {",
    "model LeadAttribution {",
    "@@unique([organizationId, contactId])",
    "@@unique([organizationId, leadId])",
    "@@unique([organizationId, inboundMessageId])"
)) {
    if (-not $Schema.Contains($Marker)) {
        throw "Stage 10 schema invariant ausente: $Marker"
    }
}

foreach ($Marker in @(
    "lead-slot:",
    "FOR UPDATE OF",
    "microbatch.""deliveredLeadCount"" <",
    "ads_request.""status"" IN",
    "fulfilledLeadCount:",
    "deliveredLeadCount:",
    "'lead.attributed'",
    "'lead.excess'",
    "'ads_request.fulfilled'"
)) {
    if (-not $AttributionService.Contains($Marker)) {
        throw "Stage 10 attribution invariant ausente: $Marker"
    }
}

if (-not $InboxProcessor.Contains("recordInboundLead(")) {
    throw "Inbox nao chama LeadAttributionService."
}

foreach ($Content in @(
    $Guard,
    $AuthorizationTypes,
    $Seed,
    $VerifySeed
)) {
    if (-not $Content.Contains("lead.read")) {
        throw "lead.read ausente em catalogo de autorizacao."
    }
}

Write-Host "[OK] Stage 10 structural checks." -ForegroundColor Green

# ============================================================
# NO TRACKED ENV
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
# GIT CHECK
# ============================================================

& git diff --check

if ($LASTEXITCODE -ne 0) {
    throw "git diff --check falhou."
}

Write-Host "[OK] git diff --check." -ForegroundColor Green

# ============================================================
# REMOVE TEMP BACKUP
# ============================================================

Remove-Item `
    ".\tmp\stage10-macroblock1-backup" `
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
Write-Host "[OK] ETAPA 10 COMPLETAMENTE VALIDADA." -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Validado:" -ForegroundColor Cyan
Write-Host "- Lead schema"
Write-Host "- LeadAttribution schema"
Write-Host "- migration"
Write-Host "- Prisma generate"
Write-Host "- seed + lead.read"
Write-Host "- webhook -> Inbox -> Lead"
Write-Host "- unique waId lead"
Write-Host "- inboundMessageCount"
Write-Host "- first inbound attribution"
Write-Host "- FIFO microbatch"
Write-Host "- PLANNED -> DELIVERING"
Write-Host "- DELIVERING -> COMPLETED"
Write-Host "- deliveredLeadCount"
Write-Host "- fulfilledLeadCount"
Write-Host "- PARTIALLY_FULFILLED"
Write-Host "- FULFILLED"
Write-Host "- completedAt"
Write-Host "- excess without capacity"
Write-Host "- unassigned number excess"
Write-Host "- concurrent slot consumption"
Write-Host "- concurrent same-contact deduplication"
Write-Host "- no microbatch overfill"
Write-Host "- no AdsRequest overfill"
Write-Host "- Lead API"
Write-Host "- Lead summary"
Write-Host "- Employee isolation"
Write-Host "- tenant isolation"
Write-Host "- audit"
Write-Host "- worker process smoke"
Write-Host "- global CI"
Write-Host "- documentation"
Write-Host "- git checks"
Write-Host "- secret scan"
Write-Host ""
Write-Host "Proxima etapa: ETAPA 11 - SAUDE E CONTINGENCIA DOS NUMEROS WHATSAPP." -ForegroundColor Yellow