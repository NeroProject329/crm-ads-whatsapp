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
Write-Host " ETAPA 7 - MACROBLOCO 7.2" -ForegroundColor Cyan
Write-Host " PWA + ONESIGNAL AUDIT + CLOSURE" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

# ============================================================
# PREFLIGHT
# ============================================================

$RequiredFiles = @(
    ".\packages\contracts\src\notifications.ts",
    ".\packages\validation\src\notifications.ts",
    ".\apps\api\src\notifications\notifications.service.ts",
    ".\apps\api\src\notifications\notifications.controller.ts",
    ".\apps\api\src\notifications\notifications.module.ts",
    ".\apps\worker\src\notification-dispatcher.config.ts",
    ".\apps\worker\src\notification-dispatcher.service.ts",
    ".\apps\worker\src\onesignal-sender.ts",
    ".\apps\web\src\app\manifest.ts",
    ".\apps\web\src\components\pwa-bootstrap.tsx",
    ".\apps\web\src\components\onesignal-bootstrap.tsx",
    ".\apps\web\src\lib\push-client.ts",
    ".\apps\web\public\sw.js",
    ".\apps\web\public\push\onesignal\OneSignalSDKWorker.js",
    ".\packages\database\prisma\schema.prisma"
)

foreach ($RequiredFile in $RequiredFiles) {
    if (-not (Test-Path $RequiredFile)) {
        throw "Macrobloco 7.1 incompleto: $RequiredFile"
    }
}

Write-Host "[OK] Preflight 7.1." -ForegroundColor Green

# ============================================================
# HARDEN ENQUEUE PUSH IDEMPOTENCY
# ============================================================

$NotificationServicePath = ".\apps\api\src\notifications\notifications.service.ts"
$NotificationService = Read-Text -Path $NotificationServicePath

$NewEnqueueMethod = @'
  async enqueuePush(
    input: EnqueuePushNotificationInput,
  ): Promise<string> {
    if (input.idempotencyKey) {
      const notification =
        await this.database.client.notification.upsert({
          where: {
            organizationId_idempotencyKey: {
              organizationId:
                input.organizationId,

              idempotencyKey:
                input.idempotencyKey,
            },
          },

          create: {
            organizationId:
              input.organizationId,

            userId:
              input.userId,

            channel:
              'PUSH',

            type:
              input.type,

            title:
              input.title,

            body:
              input.body,

            url:
              input.url ??
              null,

            ...(input.data !== undefined
              ? {
                  data: {
                    ...input.data,
                  },
                }
              : {}),

            idempotencyKey:
              input.idempotencyKey,
          },

          update: {},
        });

      await this.database.client.notificationDelivery.upsert({
        where: {
          notificationId_provider: {
            notificationId:
              notification.id,

            provider:
              'ONESIGNAL',
          },
        },

        create: {
          organizationId:
            notification.organizationId,

          notificationId:
            notification.id,

          userId:
            notification.userId,

          provider:
            'ONESIGNAL',
        },

        update: {},
      });

      return notification.id;
    }

    const notification =
      await this.database.client.$transaction(
        async (transaction) => {
          const created =
            await transaction.notification.create({
              data: {
                organizationId:
                  input.organizationId,

                userId:
                  input.userId,

                channel:
                  'PUSH',

                type:
                  input.type,

                title:
                  input.title,

                body:
                  input.body,

                url:
                  input.url ??
                  null,

                ...(input.data !== undefined
                  ? {
                      data: {
                        ...input.data,
                      },
                    }
                  : {}),
              },
            });

          await transaction.notificationDelivery.create({
            data: {
              organizationId:
                input.organizationId,

              notificationId:
                created.id,

              userId:
                input.userId,

              provider:
                'ONESIGNAL',
            },
          });

          return created;
        },
      );

    return notification.id;
  }

'@

$EnqueueRegex = New-Object System.Text.RegularExpressions.Regex(
    '  async enqueuePush\([\s\S]*?(?=  private mapDevice\()',
    [System.Text.RegularExpressions.RegexOptions]::Singleline
)

if (-not $EnqueueRegex.IsMatch($NotificationService)) {
    throw "Metodo enqueuePush nao encontrado."
}

$NotificationService = $EnqueueRegex.Replace(
    $NotificationService,
    $NewEnqueueMethod,
    1
)

Write-Text `
    -Path $NotificationServicePath `
    -Content $NotificationService

Write-Host "[OK] enqueuePush com idempotencia concorrente." -ForegroundColor Green

# ============================================================
# HARDEN ONESIGNAL SERVICE WORKER PATH
# ============================================================

$PushClientPath = ".\apps\web\src\lib\push-client.ts"
$PushClient = Read-Text -Path $PushClientPath

$PushClient = $PushClient.Replace(
    "serviceWorkerPath:`r`n          'push/onesignal/OneSignalSDKWorker.js'",
    "serviceWorkerPath:`r`n          '/push/onesignal/OneSignalSDKWorker.js'"
)

Write-Text `
    -Path $PushClientPath `
    -Content $PushClient

Write-Host "[OK] OneSignal worker path normalizado." -ForegroundColor Green

# ============================================================
# VALIDATION TESTS
# ============================================================

$ValidationTests = @'
import {
  describe,
  expect,
  it,
} from 'vitest';

import {
  registerPushDeviceSchema,
  updateNotificationPreferenceSchema,
} from './notifications.js';

describe('registerPushDeviceSchema', () => {
  it('accepts a valid OneSignal subscription', () => {
    const parsed =
      registerPushDeviceSchema.safeParse({
        subscriptionId:
          '123e4567-e89b-42d3-a456-426614174000',

        oneSignalId:
          '123e4567-e89b-42d3-a456-426614174001',

        optedIn:
          true,

        platform:
          'iPhone',

        browser:
          'Safari',
      });

    expect(
      parsed.success,
    ).toBe(true);
  });

  it('rejects unknown properties', () => {
    const parsed =
      registerPushDeviceSchema.safeParse({
        subscriptionId:
          '123e4567-e89b-42d3-a456-426614174000',

        optedIn:
          true,

        organizationId:
          '123e4567-e89b-42d3-a456-426614174099',
      });

    expect(
      parsed.success,
    ).toBe(false);
  });
});

describe('updateNotificationPreferenceSchema', () => {
  it('accepts explicit false values', () => {
    const parsed =
      updateNotificationPreferenceSchema.safeParse({
        pushEnabled:
          false,

        siteMonitoring:
          false,
      });

    expect(
      parsed.success,
    ).toBe(true);
  });

  it('rejects an empty update', () => {
    const parsed =
      updateNotificationPreferenceSchema.safeParse({});

    expect(
      parsed.success,
    ).toBe(false);
  });
});
'@

Write-Text `
    -Path ".\packages\validation\src\notifications.spec.ts" `
    -Content $ValidationTests

# ============================================================
# INSTALL / LOCKFILE
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
        $_.Name -like "*stage_7_pwa_onesignal_notifications*"
    } |
    Select-Object -First 1

if ($null -eq $Migration) {
    Invoke-Native `
        -Description "Create Stage 7 migration" `
        -Command "pnpm" `
        -Arguments @(
            "--filter",
            "@crm/database",
            "exec",
            "prisma",
            "migrate",
            "dev",
            "--name",
            "stage_7_pwa_onesignal_notifications",
            "--create-only"
        )
}

$Migration = Get-ChildItem `
    -Path $MigrationRoot `
    -Directory `
    -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -like "*stage_7_pwa_onesignal_notifications*"
    } |
    Select-Object -First 1

if ($null -eq $Migration) {
    throw "Migration Stage 7 nao encontrada."
}

Write-Host "[OK] Migration: $($Migration.Name)" -ForegroundColor Green

Invoke-Native `
    -Description "Deploy Stage 7 migration" `
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
    -Description "Validation tests" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/validation",
        "test"
    )

Invoke-Native `
    -Description "API lint" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/api",
        "lint"
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
    -Description "Web lint" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/web",
        "lint"
    )

Invoke-Native `
    -Description "Web typecheck" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/web",
        "typecheck"
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

Invoke-Native `
    -Description "Web build" `
    -Command "pnpm" `
    -Arguments @(
        "exec",
        "turbo",
        "run",
        "build",
        "--filter=@crm/web"
    )

# ============================================================
# PWA STRUCTURAL VALIDATION
# ============================================================

Write-Host ""
Write-Host "==== PWA structural validation ====" -ForegroundColor Cyan

$ManifestPath = ".\apps\web\src\app\manifest.ts"
$ManifestContent = Read-Text -Path $ManifestPath

foreach ($Marker in @(
    "display:",
    "'standalone'",
    "start_url:",
    "pwa-192.svg",
    "pwa-512.svg",
    "pwa-maskable.svg"
)) {
    if (-not $ManifestContent.Contains($Marker)) {
        throw "Manifest PWA invalido. Marker ausente: $Marker"
    }
}

$RootWorker = Read-Text `
    -Path ".\apps\web\public\sw.js"

if (
    $RootWorker -match '\bcaches\.' -or
    $RootWorker -match "addEventListener\s*\(\s*['""]fetch['""]"
) {
    throw "Root PWA worker possui cache/fetch offline proibido."
}

$OneSignalWorker = Read-Text `
    -Path ".\apps\web\public\push\onesignal\OneSignalSDKWorker.js"

if (-not $OneSignalWorker.Contains("OneSignalSDK.sw.js")) {
    throw "OneSignal service worker invalido."
}

$PushClientFinal = Read-Text `
    -Path ".\apps\web\src\lib\push-client.ts"

foreach ($Marker in @(
    "oneSignal.login(",
    "PushSubscription.id",
    "/push/onesignal/OneSignalSDKWorker.js",
    "oneSignal.logout()"
)) {
    if (-not $PushClientFinal.Contains($Marker)) {
        throw "Push client invalido. Marker ausente: $Marker"
    }
}

$NextConfig = Read-Text `
    -Path ".\apps\web\next.config.ts"

if (-not $NextConfig.Contains("no-cache, no-store, must-revalidate")) {
    throw "Service workers nao possuem no-cache headers."
}

Invoke-Native `
    -Description "PWA service worker syntax" `
    -Command "node" `
    -Arguments @(
        "--check",
        "apps/web/public/sw.js"
    )

Invoke-Native `
    -Description "OneSignal service worker syntax" `
    -Command "node" `
    -Arguments @(
        "--check",
        "apps/web/public/push/onesignal/OneSignalSDKWorker.js"
    )

Invoke-Native `
    -Description "Manifest runtime validation" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/web",
        "exec",
        "tsx",
        "-e",
        "import manifest from './src/app/manifest.ts'; const m=manifest(); if(m.display!=='standalone'||m.start_url!=='/'||!Array.isArray(m.icons)||m.icons.length<3){throw new Error('Invalid PWA manifest')}; console.log('[OK] PWA manifest runtime validado.');"
    )

Write-Host "[OK] PWA estruturalmente validada sem cache offline." -ForegroundColor Green

# ============================================================
# STAGE 7 DATABASE RUNTIME VALIDATOR
# ============================================================

$RuntimeValidator = @'
import '../src/load-environment.js';

import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';

import type {
  AuthenticatedPrincipal,
} from '@crm/auth';

import {
  DatabaseService,
} from '../src/database/database.service.js';

import {
  NotificationsService,
} from '../src/notifications/notifications.service.js';

import {
  NotificationDispatcherService,
  type NotificationSender,
} from '../../worker/src/notification-dispatcher.service.js';

import type {
  NotificationDispatcherConfig,
} from '../../worker/src/notification-dispatcher.config.js';

const databaseService =
  new DatabaseService();

const database =
  databaseService.client;

const notificationsService =
  new NotificationsService(
    databaseService,
  );

const organizationSlug =
  process.env.SEED_ORGANIZATION_SLUG?.trim() ||
  'crm-ads-whatsapp';

const unique =
  randomUUID()
    .replaceAll('-', '')
    .slice(0, 16);

const fixtureEmailPrefix =
  'stage7.runtime.';

const foreignOrganizationPrefix =
  'stage7-runtime-tenant-';

const dispatcherConfig:
NotificationDispatcherConfig = {
  intervalMs: 100,
  leaseMs: 30_000,
  maxAttempts: 3,
  retryBaseMs: 50,
  maxClaimsPerTick: 1,
  oneSignalAppId:
    'stage7-test-app',
  oneSignalApiKey:
    'stage7-test-key',
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

async function deleteUserFixture(
  userId: string,
  organizationId: string,
): Promise<void> {
  const notifications =
    await database.notification.findMany({
      where: {
        organizationId,
        userId,
      },

      select: {
        id: true,
      },
    });

  const devices =
    await database.pushDevice.findMany({
      where: {
        organizationId,
        userId,
      },

      select: {
        id: true,
      },
    });

  const resourceIds = [
    ...notifications.map(
      (item) => item.id,
    ),
    ...devices.map(
      (item) => item.id,
    ),
  ];

  await database.auditLog.deleteMany({
    where: {
      organizationId,

      OR: [
        {
          actorUserId:
            userId,
        },

        ...(resourceIds.length > 0
          ? [
              {
                resourceId: {
                  in:
                    resourceIds,
                },
              },
            ]
          : []),
      ],
    },
  });

  await database.notificationDelivery.deleteMany({
    where: {
      organizationId,
      userId,
    },
  });

  await database.notification.deleteMany({
    where: {
      organizationId,
      userId,
    },
  });

  await database.notificationPreference.deleteMany({
    where: {
      organizationId,
      userId,
    },
  });

  await database.pushDevice.deleteMany({
    where: {
      organizationId,
      userId,
    },
  });

  await database.session.deleteMany({
    where: {
      organizationId,
      userId,
    },
  });

  await database.userRole.deleteMany({
    where: {
      organizationId,
      userId,
    },
  });

  await database.user.deleteMany({
    where: {
      organizationId,
      id:
        userId,
    },
  });
}

async function cleanupRuntimeFixtures():
Promise<void> {
  const primaryOrganization =
    await database.organization.findUnique({
      where: {
        slug:
          organizationSlug,
      },
    });

  if (primaryOrganization) {
    const fixtureUsers =
      await database.user.findMany({
        where: {
          organizationId:
            primaryOrganization.id,

          emailNormalized: {
            startsWith:
              fixtureEmailPrefix,
          },
        },

        select: {
          id: true,
        },
      });

    for (
      const user of fixtureUsers
    ) {
      await deleteUserFixture(
        user.id,
        primaryOrganization.id,
      );
    }
  }

  const foreignOrganizations =
    await database.organization.findMany({
      where: {
        slug: {
          startsWith:
            foreignOrganizationPrefix,
        },
      },

      select: {
        id: true,
      },
    });

  for (
    const organization of
      foreignOrganizations
  ) {
    await database.auditLog.deleteMany({
      where: {
        organizationId:
          organization.id,
      },
    });

    await database.notificationDelivery.deleteMany({
      where: {
        organizationId:
          organization.id,
      },
    });

    await database.notification.deleteMany({
      where: {
        organizationId:
          organization.id,
      },
    });

    await database.notificationPreference.deleteMany({
      where: {
        organizationId:
          organization.id,
      },
    });

    await database.pushDevice.deleteMany({
      where: {
        organizationId:
          organization.id,
      },
    });

    await database.session.deleteMany({
      where: {
        organizationId:
          organization.id,
      },
    });

    await database.userRole.deleteMany({
      where: {
        organizationId:
          organization.id,
      },
    });

    await database.user.deleteMany({
      where: {
        organizationId:
          organization.id,
      },
    });

    await database.rolePermission.deleteMany({
      where: {
        role: {
          organizationId:
            organization.id,
        },
      },
    });

    await database.role.deleteMany({
      where: {
        organizationId:
          organization.id,
      },
    });

    await database.organization.delete({
      where: {
        id:
          organization.id,
      },
    });
  }
}

async function makeDeliveryDue(
  notificationId: string,
): Promise<void> {
  await database.notificationDelivery.update({
    where: {
      notificationId_provider: {
        notificationId,
        provider:
          'ONESIGNAL',
      },
    },

    data: {
      status:
        'WAITING',

      nextAttemptAt:
        new Date(0),

      claimedAt:
        null,

      claimedByWorkerId:
        null,

      leaseExpiresAt:
        null,
    },
  });
}

async function createNotification(
  organizationId: string,
  userId: string,
  suffix: string,
): Promise<string> {
  const notificationId =
    await notificationsService.enqueuePush({
      organizationId,
      userId,

      type:
        `stage7.runtime.${suffix}`,

      title:
        `Stage 7 ${suffix}`,

      body:
        'Runtime notification',

      url:
        '/',

      data: {
        source:
          'stage7-runtime',
      },

      idempotencyKey:
        `stage7:${unique}:${suffix}`,
    });

  await makeDeliveryDue(
    notificationId,
  );

  return notificationId;
}

try {
  event(
    'stage7.validation.started',
  );

  await cleanupRuntimeFixtures();

  const organization =
    await database.organization.findUniqueOrThrow({
      where: {
        slug:
          organizationSlug,
      },
    });

  const userA =
    await database.user.create({
      data: {
        organizationId:
          organization.id,

        email:
          `${fixtureEmailPrefix}${unique}@example.com`,

        emailNormalized:
          `${fixtureEmailPrefix}${unique}@example.com`,

        displayName:
          'Stage 7 Runtime User',

        status:
          'ACTIVE',
      },
    });

  const noDeviceUser =
    await database.user.create({
      data: {
        organizationId:
          organization.id,

        email:
          `${fixtureEmailPrefix}nodevice.${unique}@example.com`,

        emailNormalized:
          `${fixtureEmailPrefix}nodevice.${unique}@example.com`,

        displayName:
          'Stage 7 No Device',

        status:
          'ACTIVE',
      },
    });

  const foreignOrganization =
    await database.organization.create({
      data: {
        name:
          'Stage 7 Foreign Tenant',

        slug:
          `${foreignOrganizationPrefix}${unique}`,

        status:
          'ACTIVE',
      },
    });

  const userB =
    await database.user.create({
      data: {
        organizationId:
          foreignOrganization.id,

        email:
          `stage7.foreign.${unique}@example.com`,

        emailNormalized:
          `stage7.foreign.${unique}@example.com`,

        displayName:
          'Stage 7 Foreign User',

        status:
          'ACTIVE',
      },
    });

  const principalA:
  AuthenticatedPrincipal = {
    organizationId:
      organization.id,

    userId:
      userA.id,

    sessionId:
      randomUUID(),

    roles: [
      'ADMIN',
    ],
  };

  const principalNoDevice:
  AuthenticatedPrincipal = {
    organizationId:
      organization.id,

    userId:
      noDeviceUser.id,

    sessionId:
      randomUUID(),

    roles: [
      'ADMIN',
    ],
  };

  const principalB:
  AuthenticatedPrincipal = {
    organizationId:
      foreignOrganization.id,

    userId:
      userB.id,

    sessionId:
      randomUUID(),

    roles: [
      'ADMIN',
    ],
  };

  const subscriptionA1 =
    randomUUID();

  const subscriptionA2 =
    randomUUID();

  const subscriptionB =
    randomUUID();

  await notificationsService.registerDevice(
    principalA,
    {
      subscriptionId:
        subscriptionA1,

      oneSignalId:
        randomUUID(),

      optedIn:
        true,

      platform:
        'iPhone',

      browser:
        'Safari',

      deviceLabel:
        'Stage 7 iPhone',
    },
    'Stage7 Runtime Safari',
  );

  await notificationsService.registerDevice(
    principalA,
    {
      subscriptionId:
        subscriptionA2,

      oneSignalId:
        randomUUID(),

      optedIn:
        true,

      platform:
        'Windows',

      browser:
        'Chrome',

      deviceLabel:
        'Stage 7 Desktop',
    },
    'Stage7 Runtime Chrome',
  );

  await notificationsService.registerDevice(
    principalB,
    {
      subscriptionId:
        subscriptionB,

      oneSignalId:
        randomUUID(),

      optedIn:
        true,

      platform:
        'Android',

      browser:
        'Chrome',

      deviceLabel:
        'Foreign Android',
    },
    'Stage7 Foreign Chrome',
  );

  const devicesA =
    await notificationsService.listDevices(
      principalA,
    );

  const devicesB =
    await notificationsService.listDevices(
      principalB,
    );

  assert.equal(
    devicesA.length,
    2,
  );

  assert.equal(
    devicesB.length,
    1,
  );

  assert.ok(
    devicesA.every(
      (device) =>
        device.subscriptionId !==
        subscriptionB,
    ),
  );

  event(
    'stage7.device_registration.passed',
  );

  await assert.rejects(
    () =>
      notificationsService.unregisterDevice(
        principalB,
        subscriptionA1,
      ),
  );

  event(
    'stage7.device_tenant_isolation.passed',
  );

  const switchSubscription =
    randomUUID();

  await notificationsService.registerDevice(
    principalA,
    {
      subscriptionId:
        switchSubscription,

      optedIn:
        true,

      platform:
        'Windows',

      browser:
        'Chrome',

      deviceLabel:
        'Account Switch',
    },
    'Stage7 Switch',
  );

  await notificationsService.registerDevice(
    principalB,
    {
      subscriptionId:
        switchSubscription,

      optedIn:
        true,

      platform:
        'Windows',

      browser:
        'Chrome',

      deviceLabel:
        'Account Switch',
    },
    'Stage7 Switch',
  );

  const transferredDevice =
    await database.pushDevice.findUniqueOrThrow({
      where: {
        subscriptionId:
          switchSubscription,
      },
    });

  assert.equal(
    transferredDevice.organizationId,
    foreignOrganization.id,
  );

  assert.equal(
    transferredDevice.userId,
    userB.id,
  );

  event(
    'stage7.account_switch.passed',
  );

  await notificationsService.unregisterDevice(
    principalA,
    subscriptionA2,
  );

  await notificationsService.unregisterDevice(
    principalA,
    subscriptionA2,
  );

  const revokedDevice =
    await database.pushDevice.findUniqueOrThrow({
      where: {
        subscriptionId:
          subscriptionA2,
      },
    });

  assert.equal(
    revokedDevice.status,
    'REVOKED',
  );

  assert.equal(
    revokedDevice.optedIn,
    false,
  );

  const activeDevicesA =
    await notificationsService.listDevices(
      principalA,
    );

  assert.equal(
    activeDevicesA.length,
    1,
  );

  event(
    'stage7.device_unregister.passed',
  );

  const defaultPreferences =
    await notificationsService.getPreferences(
      principalA,
    );

  assert.equal(
    defaultPreferences.pushEnabled,
    true,
  );

  assert.equal(
    defaultPreferences.siteMonitoring,
    true,
  );

  const disabledPreferences =
    await notificationsService.updatePreferences(
      principalA,
      {
        pushEnabled:
          false,

        siteMonitoring:
          false,
      },
    );

  assert.equal(
    disabledPreferences.pushEnabled,
    false,
  );

  assert.equal(
    disabledPreferences.siteMonitoring,
    false,
  );

  await notificationsService.updatePreferences(
    principalA,
    {
      pushEnabled:
        true,

      siteMonitoring:
        true,
    },
  );

  event(
    'stage7.preferences.passed',
  );

  const idempotencyKey =
    `stage7:${unique}:idempotency`;

  const idempotentResults =
    await Promise.all([
      notificationsService.enqueuePush({
        organizationId:
          organization.id,

        userId:
          userA.id,

        type:
          'stage7.runtime.idempotency',

        title:
          'Idempotency',

        body:
          'First concurrent enqueue',

        idempotencyKey,
      }),

      notificationsService.enqueuePush({
        organizationId:
          organization.id,

        userId:
          userA.id,

        type:
          'stage7.runtime.idempotency',

        title:
          'Idempotency duplicate',

        body:
          'Second concurrent enqueue',

        idempotencyKey,
      }),
    ]);

  assert.equal(
    idempotentResults[0],
    idempotentResults[1],
  );

  const idempotentNotificationId =
    idempotentResults[0];

  assert.ok(
    idempotentNotificationId,
  );

  assert.equal(
    await database.notification.count({
      where: {
        organizationId:
          organization.id,

        idempotencyKey,
      },
    }),
    1,
  );

  assert.equal(
    await database.notificationDelivery.count({
      where: {
        notificationId:
          idempotentNotificationId,
      },
    }),
    1,
  );

  await database.notificationDelivery.update({
    where: {
      notificationId_provider: {
        notificationId:
          idempotentNotificationId,

        provider:
          'ONESIGNAL',
      },
    },

    data: {
      nextAttemptAt:
        new Date(
          Date.now() +
            86_400_000,
        ),
    },
  });

  event(
    'stage7.idempotency.passed',
  );

  const notificationsA =
    await notificationsService.listNotifications(
      principalA,
    );

  const notificationsB =
    await notificationsService.listNotifications(
      principalB,
    );

  assert.ok(
    notificationsA.some(
      (item) =>
        item.id ===
        idempotentNotificationId,
    ),
  );

  assert.ok(
    notificationsB.every(
      (item) =>
        item.id !==
        idempotentNotificationId,
    ),
  );

  event(
    'stage7.notification_tenant_isolation.passed',
  );

  let noDeviceSenderCalls = 0;

  const noDeviceSender:
  NotificationSender =
    async () => {
      noDeviceSenderCalls += 1;

      return {
        providerMessageId:
          randomUUID(),
      };
    };

  const noDeviceNotification =
    await createNotification(
      organization.id,
      noDeviceUser.id,
      'no-device',
    );

  const noDeviceDispatcher =
    new NotificationDispatcherService(
      database,
      `stage7-no-device-${unique}`,
      dispatcherConfig,
      noDeviceSender,
    );

  const noDeviceSummary =
    await noDeviceDispatcher.runTick();

  assert.equal(
    noDeviceSummary.skipped,
    1,
  );

  assert.equal(
    noDeviceSenderCalls,
    0,
  );

  const noDeviceState =
    await database.notification.findUniqueOrThrow({
      where: {
        id:
          noDeviceNotification,
      },
    });

  assert.equal(
    noDeviceState.status,
    'SKIPPED',
  );

  event(
    'stage7.no_device_skip.passed',
  );

  await notificationsService.updatePreferences(
    principalA,
    {
      pushEnabled:
        false,
    },
  );

  let disabledSenderCalls = 0;

  const disabledSender:
  NotificationSender =
    async () => {
      disabledSenderCalls += 1;

      return {
        providerMessageId:
          randomUUID(),
      };
    };

  const disabledNotification =
    await createNotification(
      organization.id,
      userA.id,
      'push-disabled',
    );

  const disabledDispatcher =
    new NotificationDispatcherService(
      database,
      `stage7-disabled-${unique}`,
      dispatcherConfig,
      disabledSender,
    );

  const disabledSummary =
    await disabledDispatcher.runTick();

  assert.equal(
    disabledSummary.skipped,
    1,
  );

  assert.equal(
    disabledSenderCalls,
    0,
  );

  assert.equal(
    (
      await database.notification.findUniqueOrThrow({
        where: {
          id:
            disabledNotification,
        },
      })
    ).status,
    'SKIPPED',
  );

  await notificationsService.updatePreferences(
    principalA,
    {
      pushEnabled:
        true,
    },
  );

  event(
    'stage7.preference_skip.passed',
  );

  let sentExternalId:
    string | null = null;

  const sentSender:
  NotificationSender =
    async (
      _config,
      message,
    ) => {
      sentExternalId =
        message.externalId;

      return {
        providerMessageId:
          'stage7-provider-message',
      };
    };

  const sentNotification =
    await createNotification(
      organization.id,
      userA.id,
      'sent',
    );

  const sentDispatcher =
    new NotificationDispatcherService(
      database,
      `stage7-sent-${unique}`,
      dispatcherConfig,
      sentSender,
    );

  const sentSummary =
    await sentDispatcher.runTick();

  assert.equal(
    sentSummary.sent,
    1,
  );

  assert.equal(
    sentExternalId,
    userA.id,
  );

  const sentState =
    await database.notification.findUniqueOrThrow({
      where: {
        id:
          sentNotification,
      },
    });

  const sentDelivery =
    await database.notificationDelivery.findUniqueOrThrow({
      where: {
        notificationId_provider: {
          notificationId:
            sentNotification,

          provider:
            'ONESIGNAL',
        },
      },
    });

  assert.equal(
    sentState.status,
    'SENT',
  );

  assert.equal(
    sentDelivery.status,
    'SENT',
  );

  assert.equal(
    sentDelivery.providerMessageId,
    'stage7-provider-message',
  );

  event(
    'stage7.mock_onesignal_sent.passed',
  );

  let retryCalls = 0;

  const retryFailureSender:
  NotificationSender =
    async () => {
      retryCalls += 1;

      throw new Error(
        'Simulated temporary provider error.',
      );
    };

  const retryNotification =
    await createNotification(
      organization.id,
      userA.id,
      'retry',
    );

  const retryDispatcher =
    new NotificationDispatcherService(
      database,
      `stage7-retry-${unique}`,
      dispatcherConfig,
      retryFailureSender,
    );

  const retrySummary =
    await retryDispatcher.runTick();

  assert.equal(
    retrySummary.deferred,
    1,
  );

  let retryDelivery =
    await database.notificationDelivery.findUniqueOrThrow({
      where: {
        notificationId_provider: {
          notificationId:
            retryNotification,

          provider:
            'ONESIGNAL',
        },
      },
    });

  assert.equal(
    retryDelivery.status,
    'WAITING',
  );

  assert.equal(
    retryDelivery.attempts,
    1,
  );

  await makeDeliveryDue(
    retryNotification,
  );

  const retrySuccessSender:
  NotificationSender =
    async () => ({
      providerMessageId:
        'retry-recovered',
    });

  const recoveryDispatcher =
    new NotificationDispatcherService(
      database,
      `stage7-retry-recovery-${unique}`,
      dispatcherConfig,
      retrySuccessSender,
    );

  await recoveryDispatcher.runTick();

  retryDelivery =
    await database.notificationDelivery.findUniqueOrThrow({
      where: {
        notificationId_provider: {
          notificationId:
            retryNotification,

          provider:
            'ONESIGNAL',
        },
      },
    });

  assert.equal(
    retryDelivery.status,
    'SENT',
  );

  assert.equal(
    retryDelivery.attempts,
    2,
  );

  assert.equal(
    retryCalls,
    1,
  );

  event(
    'stage7.retry_recovery.passed',
  );

  const failedNotification =
    await createNotification(
      organization.id,
      userA.id,
      'permanent-failure',
    );

  await database.notificationDelivery.update({
    where: {
      notificationId_provider: {
        notificationId:
          failedNotification,

        provider:
          'ONESIGNAL',
      },
    },

    data: {
      attempts:
        dispatcherConfig.maxAttempts - 1,

      nextAttemptAt:
        new Date(0),
    },
  });

  const permanentFailureSender:
  NotificationSender =
    async () => {
      throw new Error(
        'Simulated permanent provider failure.',
      );
    };

  const failedDispatcher =
    new NotificationDispatcherService(
      database,
      `stage7-failed-${unique}`,
      dispatcherConfig,
      permanentFailureSender,
    );

  const failedSummary =
    await failedDispatcher.runTick();

  assert.equal(
    failedSummary.failed,
    1,
  );

  const failedDelivery =
    await database.notificationDelivery.findUniqueOrThrow({
      where: {
        notificationId_provider: {
          notificationId:
            failedNotification,

          provider:
            'ONESIGNAL',
        },
      },
    });

  const failedState =
    await database.notification.findUniqueOrThrow({
      where: {
        id:
          failedNotification,
      },
    });

  assert.equal(
    failedDelivery.status,
    'FAILED',
  );

  assert.equal(
    failedDelivery.attempts,
    dispatcherConfig.maxAttempts,
  );

  assert.equal(
    failedState.status,
    'FAILED',
  );

  event(
    'stage7.mock_onesignal_failed.passed',
  );

  const leaseNotification =
    await createNotification(
      organization.id,
      userA.id,
      'lease-recovery',
    );

  await database.notificationDelivery.update({
    where: {
      notificationId_provider: {
        notificationId:
          leaseNotification,

        provider:
          'ONESIGNAL',
      },
    },

    data: {
      status:
        'CLAIMED',

      attempts:
        1,

      claimedAt:
        new Date(
          Date.now() -
            60_000,
        ),

      claimedByWorkerId:
        'dead-stage7-worker',

      leaseExpiresAt:
        new Date(
          Date.now() -
            30_000,
        ),

      nextAttemptAt:
        new Date(
          Date.now() +
            3_600_000,
        ),
    },
  });

  const leaseSender:
  NotificationSender =
    async () => ({
      providerMessageId:
        'lease-recovered',
    });

  const leaseDispatcher =
    new NotificationDispatcherService(
      database,
      `stage7-lease-${unique}`,
      dispatcherConfig,
      leaseSender,
    );

  await leaseDispatcher.runTick();

  const leaseDelivery =
    await database.notificationDelivery.findUniqueOrThrow({
      where: {
        notificationId_provider: {
          notificationId:
            leaseNotification,

          provider:
            'ONESIGNAL',
        },
      },
    });

  assert.equal(
    leaseDelivery.status,
    'SENT',
  );

  assert.equal(
    leaseDelivery.attempts,
    2,
  );

  assert.equal(
    leaseDelivery.claimedByWorkerId,
    null,
  );

  event(
    'stage7.lease_recovery.passed',
  );

  const concurrentNotification =
    await createNotification(
      organization.id,
      userA.id,
      'concurrency',
    );

  let concurrentSenderCalls =
    0;

  const concurrentSender:
  NotificationSender =
    async () => {
      concurrentSenderCalls += 1;

      await new Promise<void>(
        (resolve) => {
          setTimeout(
            resolve,
            150,
          );
        },
      );

      return {
        providerMessageId:
          'concurrent-message',
      };
    };

  const concurrentA =
    new NotificationDispatcherService(
      database,
      `stage7-worker-a-${unique}`,
      dispatcherConfig,
      concurrentSender,
    );

  const concurrentB =
    new NotificationDispatcherService(
      database,
      `stage7-worker-b-${unique}`,
      dispatcherConfig,
      concurrentSender,
    );

  await Promise.all([
    concurrentA.runTick(),
    concurrentB.runTick(),
  ]);

  const concurrentDelivery =
    await database.notificationDelivery.findUniqueOrThrow({
      where: {
        notificationId_provider: {
          notificationId:
            concurrentNotification,

          provider:
            'ONESIGNAL',
        },
      },
    });

  assert.equal(
    concurrentDelivery.status,
    'SENT',
  );

  assert.equal(
    concurrentSenderCalls,
    1,
  );

  assert.equal(
    concurrentDelivery.attempts,
    1,
  );

  event(
    'stage7.concurrent_claim.passed',
  );

  const sentAudit =
    await database.auditLog.count({
      where: {
        organizationId:
          organization.id,

        action:
          'notification.sent',
      },
    });

  const failedAudit =
    await database.auditLog.count({
      where: {
        organizationId:
          organization.id,

        action:
          'notification.failed',
      },
    });

  assert.ok(
    sentAudit >= 1,
  );

  assert.ok(
    failedAudit >= 1,
  );

  event(
    'stage7.audit.passed',
    {
      sentAudit,
      failedAudit,
    },
  );

  event(
    'stage7.validation.completed',
  );
}
finally {
  try {
    await cleanupRuntimeFixtures();
  }
  finally {
    await database.$disconnect();
  }
}
'@

Write-Text `
    -Path ".\apps\api\scripts\stage7-runtime-validation.ts" `
    -Content $RuntimeValidator

Write-Host "[OK] Stage 7 runtime validator criado." -ForegroundColor Green

# ============================================================
# FORMAT RUNTIME
# ============================================================

Invoke-Native `
    -Description "Format Stage 7 runtime" `
    -Command "pnpm" `
    -Arguments @("format")

# ============================================================
# GLOBAL CI
# ============================================================

Invoke-Native `
    -Description "Global CI Stage 7" `
    -Command "pnpm" `
    -Arguments @("ci:check")

# ============================================================
# DATABASE / DISPATCHER RUNTIME
# ============================================================

Write-Host ""
Write-Host "==== Stage 7 database runtime validation ====" -ForegroundColor Cyan

& pnpm `
    --filter `
    "@crm/api" `
    exec `
    tsx `
    "scripts/stage7-runtime-validation.ts"

if ($LASTEXITCODE -ne 0) {
    throw "Stage 7 database runtime validation falhou."
}

Write-Host "[OK] Stage 7 database runtime validation." -ForegroundColor Green

# ============================================================
# WORKER PROCESS SMOKE
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

    Start-Sleep -Seconds 3

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
Write-Host "==== Stage 7 documentation ====" -ForegroundColor Cyan

$Stage7Document = @(
    "# Etapa 7 - PWA e OneSignal",
    "",
    "## Status",
    "",
    "CONCLUIDA.",
    "",
    "## PWA",
    "",
    "O CRM e instalavel como PWA.",
    "",
    "O PWA e intencionalmente 100% online.",
    "",
    "O service worker raiz nao possui fetch handler e nao utiliza Cache API.",
    "",
    "Dados autenticados, ADS, leads, WhatsApp, dashboards, tokens e demais respostas da API nao sao armazenados para uso offline.",
    "",
    "## OneSignal",
    "",
    "O frontend utiliza o Web SDK v16.",
    "",
    "O User.id do CRM e utilizado como external_id no OneSignal.",
    "",
    "Um mesmo usuario pode possuir multiplas subscriptions/dispositivos.",
    "",
    "O service worker OneSignal utiliza escopo separado em /push/onesignal/.",
    "",
    "## PushDevice",
    "",
    "PushDevice registra cada subscription do navegador/dispositivo.",
    "",
    "O registro e sincronizavel e suporta troca de conta no mesmo navegador.",
    "",
    "Revogacao de um dispositivo nao remove os outros dispositivos do usuario.",
    "",
    "## Preferencias",
    "",
    "NotificationPreference armazena pushEnabled, siteMonitoring, adsUpdates e whatsappInbox.",
    "",
    "## Notification",
    "",
    "Notification representa o evento de notificacao independente do provider.",
    "",
    "NotificationDelivery representa a entrega via provider.",
    "",
    "A arquitetura permite adicionar outros canais futuramente sem acoplar eventos ao OneSignal.",
    "",
    "## Idempotencia",
    "",
    "idempotencyKey e unica dentro da Organization.",
    "",
    "enqueuePush utiliza upsert para garantir idempotencia inclusive sob chamadas concorrentes.",
    "",
    "## Dispatcher",
    "",
    "NotificationDelivery usa PostgreSQL como fonte de verdade.",
    "",
    "Claim utiliza FOR UPDATE SKIP LOCKED.",
    "",
    "Lease permite recovery de workers interrompidos.",
    "",
    "Retry utiliza backoff exponencial.",
    "",
    "Depois do limite de tentativas a entrega e marcada FAILED.",
    "",
    "Sem dispositivo ativo ou com push desabilitado a entrega e SKIPPED.",
    "",
    "## Segredos",
    "",
    "NEXT_PUBLIC_ONESIGNAL_APP_ID e publico e utilizado pelo frontend.",
    "",
    "ONESIGNAL_API_KEY permanece apenas no backend/worker.",
    "",
    "## API",
    "",
    "GET /api/v1/push/devices",
    "",
    "POST /api/v1/push/devices",
    "",
    "DELETE /api/v1/push/devices/:subscriptionId",
    "",
    "GET /api/v1/notifications/preferences",
    "",
    "PATCH /api/v1/notifications/preferences",
    "",
    "GET /api/v1/notifications",
    "",
    "## Validacoes executadas",
    "",
    "- Prisma format e validate",
    "- migration",
    "- Prisma generate",
    "- seed verification",
    "- validation tests",
    "- API lint/typecheck/build",
    "- Worker lint/typecheck/tests/build",
    "- Web lint/typecheck/build",
    "- manifest runtime validation",
    "- service worker syntax",
    "- zero offline cache",
    "- device registration",
    "- tenant isolation",
    "- account switch",
    "- unregister idempotente",
    "- notification preferences",
    "- concurrent enqueue idempotency",
    "- notification tenant isolation",
    "- SKIPPED sem dispositivo",
    "- SKIPPED com push desabilitado",
    "- mock OneSignal SENT",
    "- retry e recovery",
    "- permanent FAILED",
    "- lease recovery",
    "- multi-worker concurrent claim",
    "- audit",
    "- worker process smoke",
    "- global ci:check",
    "",
    "## OneSignal real",
    "",
    "Credenciais reais nao sao necessarias para os testes locais da Etapa 7.",
    "",
    "A configuracao real sera aplicada no ambiente apropriado usando ONESIGNAL_APP_ID, NEXT_PUBLIC_ONESIGNAL_APP_ID e ONESIGNAL_API_KEY.",
    "",
    "## Proxima etapa",
    "",
    "Etapa 8 - Fundacao da Meta Cloud API."
)

[System.IO.File]::WriteAllLines(
    [System.IO.Path]::GetFullPath(
        ".\docs\ETAPA_7_PWA_ONESIGNAL.md"
    ),
    $Stage7Document,
    $Utf8NoBom
)

$Decisions = @(
    "# Decisoes - Etapa 7",
    "",
    "PWA sera utilizado para instalacao e push, nao para operacao offline.",
    "",
    "Nao existe cache offline de respostas autenticadas.",
    "",
    "OneSignal Web SDK v16 e o provider inicial.",
    "",
    "User.id e o external_id do OneSignal.",
    "",
    "PushDevice representa cada subscription individual.",
    "",
    "OneSignal possui service worker separado em /push/onesignal/.",
    "",
    "Notification e independente do provider.",
    "",
    "NotificationDelivery controla a entrega persistente.",
    "",
    "PostgreSQL continua sendo fonte de verdade do dispatcher.",
    "",
    "Claim utiliza FOR UPDATE SKIP LOCKED.",
    "",
    "Lease permite recovery.",
    "",
    "Retry utiliza backoff exponencial.",
    "",
    "Idempotency key e protegida por unique constraint e upsert.",
    "",
    "A OneSignal API key nunca pode ser exposta no frontend.",
    "",
    "Credenciais reais do OneSignal nao fazem parte dos testes deterministas locais."
)

[System.IO.File]::WriteAllLines(
    [System.IO.Path]::GetFullPath(
        ".\docs\DECISOES_ETAPA_7.md"
    ),
    $Decisions,
    $Utf8NoBom
)

$EtapasPath = ".\docs\ETAPAS.md"

if (Test-Path $EtapasPath) {
    $Etapas = Read-Text -Path $EtapasPath

    $Etapas = [regex]::Replace(
        $Etapas,
        '\|\s*7\s*\|\s*PWA e OneSignal\s*\|[^|]*\|',
        '|     7 | PWA e OneSignal                           | CONCLUÍDA                   |'
    )

    if (-not $Etapas.Contains("## Etapa 7 - PWA + OneSignal")) {
        $Summary = @(
            "",
            "## Etapa 7 - PWA + OneSignal",
            "",
            "Status: CONCLUIDA.",
            "",
            "Implementado:",
            "",
            "- PWA instalavel",
            "- zero cache offline autenticado",
            "- OneSignal Web SDK v16",
            "- dedicated OneSignal service worker",
            "- external_id por User.id",
            "- PushDevice multi-device",
            "- NotificationPreference",
            "- Notification",
            "- NotificationDelivery",
            "- register/unregister device",
            "- persistent dispatcher",
            "- claim e lease",
            "- exponential retry",
            "- concurrent idempotency",
            "- tenant isolation",
            "- provider mock validation",
            "",
            "Documentacao:",
            "",
            "- docs/ETAPA_7_PWA_ONESIGNAL.md",
            "- docs/DECISOES_ETAPA_7.md",
            "",
            "Proxima: Etapa 8 - Fundacao da Meta Cloud API."
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

Write-Host "[OK] Stage 7 documentation." -ForegroundColor Green

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
# SECRET SCAN - TRACKED + UNTRACKED
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

[string[]]$TrackedSecretMatches = @(
    & git grep `
        -n `
        -I `
        -E `
        $SecretPattern `
        2>$null
)

$TrackedSecretExitCode = $LASTEXITCODE

if (
    $TrackedSecretExitCode -ne 0 -and
    $TrackedSecretExitCode -ne 1
) {
    throw "Tracked secret scan falhou."
}

if (@($TrackedSecretMatches).Count -gt 0) {
    $TrackedSecretMatches

    throw "Possivel segredo encontrado em arquivo versionado."
}

[string[]]$UntrackedFiles = @(
    & git ls-files `
        --others `
        --exclude-standard
)

if ($LASTEXITCODE -ne 0) {
    throw "Nao foi possivel listar arquivos untracked."
}

$TextExtensions = @(
    ".ts",
    ".tsx",
    ".js",
    ".mjs",
    ".cjs",
    ".json",
    ".md",
    ".ps1",
    ".prisma",
    ".sql",
    ".css",
    ".html",
    ".svg",
    ".yml",
    ".yaml"
)

foreach ($File in $UntrackedFiles) {
    if (-not (Test-Path $File)) {
        continue
    }

    $Extension = [System.IO.Path]::GetExtension($File)

    $ShouldScan = (
        $TextExtensions -contains $Extension -or
        $File.EndsWith(".env.example")
    )

    if (-not $ShouldScan) {
        continue
    }

    $Content = [System.IO.File]::ReadAllText(
        [System.IO.Path]::GetFullPath($File)
    )

    if ($Content -match $SecretPattern) {
        throw "Possivel segredo encontrado em arquivo novo: $File"
    }
}

Write-Host "[OK] Secret scan tracked + untracked." -ForegroundColor Green

# ============================================================
# CLEAN LOCAL BACKUP
# ============================================================

Remove-Item `
    ".\tmp\stage7-macroblock1-backup" `
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
Write-Host "[OK] ETAPA 7 COMPLETAMENTE VALIDADA." -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Validado:" -ForegroundColor Cyan
Write-Host "- Prisma migration"
Write-Host "- Prisma generate"
Write-Host "- seed verification"
Write-Host "- validation tests"
Write-Host "- API lint/typecheck/build"
Write-Host "- worker lint/typecheck/tests/build"
Write-Host "- web lint/typecheck/build"
Write-Host "- PWA manifest"
Write-Host "- root service worker"
Write-Host "- zero offline cache"
Write-Host "- OneSignal dedicated worker"
Write-Host "- device registration"
Write-Host "- device tenant isolation"
Write-Host "- account switch"
Write-Host "- unregister idempotente"
Write-Host "- notification preferences"
Write-Host "- concurrent enqueue idempotency"
Write-Host "- notification tenant isolation"
Write-Host "- skip sem dispositivo"
Write-Host "- skip com push desabilitado"
Write-Host "- mock OneSignal SENT"
Write-Host "- retry recovery"
Write-Host "- permanent FAILED"
Write-Host "- delivery lease recovery"
Write-Host "- concurrent delivery claim"
Write-Host "- notification audit"
Write-Host "- worker process smoke"
Write-Host "- global CI"
Write-Host "- documentation"
Write-Host "- git checks"
Write-Host "- secret scan"
Write-Host ""
Write-Host "Proxima etapa: ETAPA 8." -ForegroundColor Yellow