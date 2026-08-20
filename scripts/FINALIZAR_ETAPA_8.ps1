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
Write-Host " ETAPA 8 - MACROBLOCO 8.2" -ForegroundColor Cyan
Write-Host " META CLOUD API AUDIT + CLOSURE" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

# ============================================================
# PREFLIGHT
# ============================================================

$RequiredFiles = @(
    ".\packages\meta-cloud-api\package.json",
    ".\packages\meta-cloud-api\src\index.ts",
    ".\packages\meta-cloud-api\src\config.ts",
    ".\packages\meta-cloud-api\src\client.ts",
    ".\packages\meta-cloud-api\src\webhook-security.ts",
    ".\packages\meta-cloud-api\src\webhook-payload.ts",
    ".\packages\contracts\src\meta-cloud.ts",
    ".\packages\validation\src\meta-cloud.ts",
    ".\apps\webhook-ingress\src\database.service.ts",
    ".\apps\webhook-ingress\src\meta-webhook.config.ts",
    ".\apps\webhook-ingress\src\meta-webhook.service.ts",
    ".\apps\webhook-ingress\src\meta-webhook.controller.ts",
    ".\apps\api\src\whatsapp-numbers\whatsapp-numbers.service.ts",
    ".\packages\database\prisma\schema.prisma"
)

foreach ($RequiredFile in $RequiredFiles) {
    if (-not (Test-Path $RequiredFile)) {
        throw "Macrobloco 8.1 incompleto: $RequiredFile"
    }
}

Write-Host "[OK] Preflight 8.1." -ForegroundColor Green

# ============================================================
# WEBHOOK HEALTH VERSION
# ============================================================

$HealthPath = ".\apps\webhook-ingress\src\health.controller.ts"
$Health = Read-Text -Path $HealthPath

$Health = $Health.Replace(
    "version: '0.1.0';",
    "version: '0.2.0';"
)

$Health = $Health.Replace(
    "version: '0.1.0',",
    "version: '0.2.0',"
)

Write-Text `
    -Path $HealthPath `
    -Content $Health

Write-Host "[OK] webhook-ingress health version atualizado." -ForegroundColor Green

# ============================================================
# META CLIENT TESTS
# ============================================================

$ClientTests = @'
import {
  describe,
  expect,
  it,
} from 'vitest';

import {
  MetaCloudApiClient,
  MetaCloudApiError,
} from './client.js';

import {
  parseMetaCloudApiConfig,
} from './config.js';

describe('parseMetaCloudApiConfig', () => {
  it('requires an explicit Graph API version', () => {
    expect(() =>
      parseMetaCloudApiConfig({
        META_ACCESS_TOKEN:
          'stage8-test-token',
      }),
    ).toThrow(
      'META_GRAPH_API_VERSION is required.',
    );
  });

  it('accepts an explicit version and HTTPS base URL', () => {
    const config =
      parseMetaCloudApiConfig({
        META_GRAPH_API_VERSION:
          'v99.0',

        META_ACCESS_TOKEN:
          'stage8-test-token',

        META_GRAPH_BASE_URL:
          'https://graph.example.test',

        META_HTTP_TIMEOUT_MS:
          '5000',
      });

    expect(
      config.graphApiVersion,
    ).toBe(
      'v99.0',
    );

    expect(
      config.timeoutMs,
    ).toBe(
      5000,
    );
  });

  it('rejects non-HTTPS Graph base URLs', () => {
    expect(() =>
      parseMetaCloudApiConfig({
        META_GRAPH_API_VERSION:
          'v99.0',

        META_ACCESS_TOKEN:
          'stage8-test-token',

        META_GRAPH_BASE_URL:
          'http://graph.example.test',
      }),
    ).toThrow(
      'META_GRAPH_BASE_URL must use HTTPS.',
    );
  });
});

describe('MetaCloudApiClient', () => {
  it('sends Bearer authentication and the configured version', async () => {
    let capturedUrl =
      '';

    let capturedAuthorization:
      string | null = null;

    const fetchMock:
      typeof fetch =
      async (
        input,
        init,
      ) => {
        capturedUrl =
          String(
            input,
          );

        const headers =
          new Headers(
            init?.headers,
          );

        capturedAuthorization =
          headers.get(
            'authorization',
          );

        return new Response(
          JSON.stringify({
            id:
              '9988776655',
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
      };

    const client =
      new MetaCloudApiClient(
        {
          graphBaseUrl:
            'https://graph.example.test',

          graphApiVersion:
            'v99.0',

          accessToken:
            'stage8-test-access-token',

          timeoutMs:
            5000,
        },
        fetchMock,
      );

    const result =
      await client.get<{
        id: string;
      }>(
        '9988776655',
        {
          fields:
            'id',
        },
      );

    expect(
      result.id,
    ).toBe(
      '9988776655',
    );

    expect(
      capturedUrl,
    ).toContain(
      '/v99.0/9988776655',
    );

    expect(
      capturedUrl,
    ).toContain(
      'fields=id',
    );

    expect(
      capturedAuthorization,
    ).toBe(
      'Bearer stage8-test-access-token',
    );
  });

  it('normalizes Meta Graph API errors', async () => {
    const fetchMock:
      typeof fetch =
      async () =>
        new Response(
          JSON.stringify({
            error: {
              message:
                'Invalid OAuth access token.',

              type:
                'OAuthException',

              code:
                190,

              error_subcode:
                463,

              fbtrace_id:
                'stage8-trace',
            },
          }),
          {
            status:
              400,

            headers: {
              'content-type':
                'application/json',

              'x-fb-request-id':
                'stage8-request',
            },
          },
        );

    const client =
      new MetaCloudApiClient(
        {
          graphBaseUrl:
            'https://graph.example.test',

          graphApiVersion:
            'v99.0',

          accessToken:
            'stage8-test-access-token',

          timeoutMs:
            5000,
        },
        fetchMock,
      );

    try {
      await client.get(
        'me',
      );

      throw new Error(
        'Expected MetaCloudApiError.',
      );
    }
    catch (error) {
      expect(
        error,
      ).toBeInstanceOf(
        MetaCloudApiError,
      );

      const metaError =
        error as MetaCloudApiError;

      expect(
        metaError.status,
      ).toBe(
        400,
      );

      expect(
        metaError.code,
      ).toBe(
        190,
      );

      expect(
        metaError.errorSubcode,
      ).toBe(
        463,
      );

      expect(
        metaError.fbtraceId,
      ).toBe(
        'stage8-trace',
      );

      expect(
        metaError.requestId,
      ).toBe(
        'stage8-request',
      );

      expect(
        metaError.message,
      ).not.toContain(
        'stage8-test-access-token',
      );
    }
  });
});
'@

Write-Text `
    -Path ".\packages\meta-cloud-api\src\client.spec.ts" `
    -Content $ClientTests

# ============================================================
# META VALIDATION TESTS
# ============================================================

$ValidationTests = @'
import {
  describe,
  expect,
  it,
} from 'vitest';

import {
  configureWhatsAppMetaSchema,
} from './meta-cloud.js';

describe('configureWhatsAppMetaSchema', () => {
  it('accepts numeric WABA and Phone Number IDs', () => {
    expect(
      configureWhatsAppMetaSchema.safeParse({
        wabaId:
          '1234567890',

        phoneNumberId:
          '9988776655',
      }).success,
    ).toBe(true);
  });

  it('accepts disconnect with both fields null', () => {
    expect(
      configureWhatsAppMetaSchema.safeParse({
        wabaId:
          null,

        phoneNumberId:
          null,
      }).success,
    ).toBe(true);
  });

  it('rejects partial connection data', () => {
    expect(
      configureWhatsAppMetaSchema.safeParse({
        wabaId:
          '1234567890',

        phoneNumberId:
          null,
      }).success,
    ).toBe(false);
  });

  it('rejects organization injection', () => {
    expect(
      configureWhatsAppMetaSchema.safeParse({
        wabaId:
          '1234567890',

        phoneNumberId:
          '9988776655',

        organizationId:
          '123e4567-e89b-42d3-a456-426614174000',
      }).success,
    ).toBe(false);
  });
});
'@

Write-Text `
    -Path ".\packages\validation\src\meta-cloud.spec.ts" `
    -Content $ValidationTests

# ============================================================
# INSTALL
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
        $_.Name -like "*stage_8_meta_cloud_api_foundation*"
    } |
    Select-Object -First 1

if ($null -eq $Migration) {
    Invoke-Native `
        -Description "Create Stage 8 migration" `
        -Command "pnpm" `
        -Arguments @(
            "--filter",
            "@crm/database",
            "exec",
            "prisma",
            "migrate",
            "dev",
            "--name",
            "stage_8_meta_cloud_api_foundation",
            "--create-only"
        )
}

$Migration = Get-ChildItem `
    -Path $MigrationRoot `
    -Directory `
    -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -like "*stage_8_meta_cloud_api_foundation*"
    } |
    Select-Object -First 1

if ($null -eq $Migration) {
    throw "Migration Stage 8 nao encontrada."
}

Write-Host "[OK] Migration: $($Migration.Name)" -ForegroundColor Green

Invoke-Native `
    -Description "Deploy Stage 8 migration" `
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
# PACKAGE CHECKS
# ============================================================

Invoke-Native `
    -Description "Meta Cloud API lint" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/meta-cloud-api",
        "lint"
    )

Invoke-Native `
    -Description "Meta Cloud API typecheck" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/meta-cloud-api",
        "typecheck"
    )

Invoke-Native `
    -Description "Meta Cloud API tests" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/meta-cloud-api",
        "test"
    )

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
    -Description "Webhook ingress lint" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/webhook-ingress",
        "lint"
    )

Invoke-Native `
    -Description "Webhook ingress typecheck" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/webhook-ingress",
        "typecheck"
    )

# ============================================================
# BUILDS
# ============================================================

Invoke-Native `
    -Description "Meta Cloud API build" `
    -Command "pnpm" `
    -Arguments @(
        "exec",
        "turbo",
        "run",
        "build",
        "--filter=@crm/meta-cloud-api"
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
    -Description "Webhook ingress build" `
    -Command "pnpm" `
    -Arguments @(
        "exec",
        "turbo",
        "run",
        "build",
        "--filter=@crm/webhook-ingress"
    )

# ============================================================
# RUNTIME VALIDATOR
# ============================================================

$RuntimeValidator = @'
import '../src/load-environment.js';

import assert from 'node:assert/strict';
import {
  createHmac,
  randomUUID,
} from 'node:crypto';

type AuthenticatedPrincipal = Readonly<{
  organizationId: string;
  userId: string;
  sessionId: string;
  roles: readonly ('ADMIN' | 'EMPLOYEE')[];
}>;

import {
  MetaCloudApiClient,
  MetaCloudApiError,
  verifyMetaWebhookChallenge,
  verifyMetaWebhookSignature,
} from '@crm/meta-cloud-api';

import {
  DatabaseService as ApiDatabaseService,
} from '../../api/src/database/database.service.js';

import {
  WhatsAppNumbersService,
} from '../../api/src/whatsapp-numbers/whatsapp-numbers.service.js';

import {
  DatabaseService as WebhookDatabaseService,
} from '../src/database.service.js';

import {
  MetaWebhookService,
} from '../src/meta-webhook.service.js';

const apiDatabaseService =
  new ApiDatabaseService();

const webhookDatabaseService =
  new WebhookDatabaseService();

const database =
  webhookDatabaseService.client;

const whatsAppService =
  new WhatsAppNumbersService(
    apiDatabaseService,
  );

const webhookService =
  new MetaWebhookService(
    webhookDatabaseService,
  );

const organizationSlug =
  process.env.SEED_ORGANIZATION_SLUG?.trim() ||
  'crm-ads-whatsapp';

const unique =
  randomUUID()
    .replaceAll('-', '')
    .slice(0, 12);

const userEmailPrefix =
  'stage8.runtime.';

const numberNamePrefix =
  'Stage 8 Runtime';

const foreignOrganizationPrefix =
  'stage8-runtime-tenant-';

const metaKnownPrefix =
  '880800';

const metaUnknownPrefix =
  '990800';

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

function numericSuffix(
  suffix: number,
): string {
  return (
    Date.now()
      .toString()
      .slice(-9) +
    suffix.toString()
  );
}

async function cleanupMainFixtures():
Promise<void> {
  const organization =
    await database.organization.findUnique({
      where: {
        slug:
          organizationSlug,
      },
    });

  if (!organization) {
    return;
  }

  await database.metaWebhookEnvelope.deleteMany({
    where: {
      OR: [
        {
          metaPhoneNumberId: {
            startsWith:
              metaKnownPrefix,
          },
        },

        {
          metaPhoneNumberId: {
            startsWith:
              metaUnknownPrefix,
          },
        },
      ],
    },
  });

  const numbers =
    await database.whatsAppNumber.findMany({
      where: {
        organizationId:
          organization.id,

        displayName: {
          startsWith:
            numberNamePrefix,
        },
      },

      select: {
        id: true,
      },
    });

  const numberIds =
    numbers.map(
      (number) =>
        number.id,
    );

  if (numberIds.length > 0) {
    await database.auditLog.deleteMany({
      where: {
        organizationId:
          organization.id,

        resourceId: {
          in:
            numberIds,
        },
      },
    });

    await database.whatsAppNumber.deleteMany({
      where: {
        id: {
          in:
            numberIds,
        },
      },
    });
  }

  const users =
    await database.user.findMany({
      where: {
        organizationId:
          organization.id,

        emailNormalized: {
          startsWith:
            userEmailPrefix,
        },
      },

      select: {
        id: true,
      },
    });

  for (
    const user of users
  ) {
    await database.auditLog.deleteMany({
      where: {
        organizationId:
          organization.id,

        actorUserId:
          user.id,
      },
    });

    await database.session.deleteMany({
      where: {
        organizationId:
          organization.id,

        userId:
          user.id,
      },
    });

    await database.userRole.deleteMany({
      where: {
        organizationId:
          organization.id,

        userId:
          user.id,
      },
    });

    await database.user.delete({
      where: {
        id:
          user.id,
      },
    });
  }
}

async function cleanupForeignFixtures():
Promise<void> {
  const organizations =
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
    const organization of organizations
  ) {
    await database.metaWebhookEnvelope.deleteMany({
      where: {
        organizationId:
          organization.id,
      },
    });

    await database.auditLog.deleteMany({
      where: {
        organizationId:
          organization.id,
      },
    });

    await database.whatsAppNumber.deleteMany({
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

async function cleanupFixtures():
Promise<void> {
  await cleanupMainFixtures();
  await cleanupForeignFixtures();
}

try {
  event(
    'stage8.validation.started',
  );

  await cleanupFixtures();

  const organization =
    await database.organization.findUniqueOrThrow({
      where: {
        slug:
          organizationSlug,
      },
    });

  const user =
    await database.user.create({
      data: {
        organizationId:
          organization.id,

        email:
          `${userEmailPrefix}${unique}@example.com`,

        emailNormalized:
          `${userEmailPrefix}${unique}@example.com`,

        displayName:
          'Stage 8 Runtime User',

        status:
          'ACTIVE',
      },
    });

  const principal:
  AuthenticatedPrincipal = {
    organizationId:
      organization.id,

    userId:
      user.id,

    sessionId:
      randomUUID(),

    roles: [
      'ADMIN',
    ],
  };

  const verification =
    verifyMetaWebhookChallenge({
      mode:
        'subscribe',

      providedToken:
        'stage8-verify',

      expectedToken:
        'stage8-verify',

      challenge:
        'stage8-challenge',
    });

  assert.equal(
    verification,
    'stage8-challenge',
  );

  assert.equal(
    verifyMetaWebhookChallenge({
      mode:
        'subscribe',

      providedToken:
        'wrong',

      expectedToken:
        'stage8-verify',

      challenge:
        'stage8-challenge',
    }),
    null,
  );

  event(
    'stage8.challenge.passed',
  );

  const signatureSecret =
    'stage8-app-secret';

  const signatureBody =
    Buffer.from(
      JSON.stringify({
        object:
          'whatsapp_business_account',
      }),
    );

  const signature =
    createHmac(
      'sha256',
      signatureSecret,
    )
      .update(
        signatureBody,
      )
      .digest(
        'hex',
      );

  assert.equal(
    verifyMetaWebhookSignature(
      signatureSecret,
      signatureBody,
      `sha256=${signature}`,
    ),
    true,
  );

  assert.equal(
    verifyMetaWebhookSignature(
      signatureSecret,
      signatureBody,
      `sha256=${'0'.repeat(64)}`,
    ),
    false,
  );

  event(
    'stage8.signature.passed',
  );

  let graphAuthorization:
    string | null = null;

  let graphUrl =
    '';

  const graphSuccessFetch:
    typeof fetch =
    async (
      input,
      init,
    ) => {
      graphUrl =
        String(
          input,
        );

      graphAuthorization =
        new Headers(
          init?.headers,
        ).get(
          'authorization',
        );

      return new Response(
        JSON.stringify({
          id:
            '88080012345',

          display_phone_number:
            '+15551234567',
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
    };

  const graphClient =
    new MetaCloudApiClient(
      {
        graphBaseUrl:
          'https://graph.example.test',

        graphApiVersion:
          'v99.0',

        accessToken:
          'stage8-runtime-token',

        timeoutMs:
          5000,
      },
      graphSuccessFetch,
    );

  const graphResult =
    await graphClient.get<{
      id: string;
    }>(
      '88080012345',
      {
        fields:
          'id,display_phone_number',
      },
    );

  assert.equal(
    graphResult.id,
    '88080012345',
  );

  assert.ok(
    graphUrl.includes(
      '/v99.0/88080012345',
    ),
  );

  assert.equal(
    graphAuthorization,
    'Bearer stage8-runtime-token',
  );

  event(
    'stage8.graph_client.passed',
  );

  const graphErrorClient =
    new MetaCloudApiClient(
      {
        graphBaseUrl:
          'https://graph.example.test',

        graphApiVersion:
          'v99.0',

        accessToken:
          'stage8-runtime-token',

        timeoutMs:
          5000,
      },

      async () =>
        new Response(
          JSON.stringify({
            error: {
              message:
                'Simulated Meta error',

              type:
                'OAuthException',

              code:
                190,

              error_subcode:
                463,

              fbtrace_id:
                'stage8-runtime-trace',
            },
          }),
          {
            status:
              400,

            headers: {
              'x-fb-request-id':
                'stage8-runtime-request',
            },
          },
        ),
    );

  try {
    await graphErrorClient.get(
      'me',
    );

    assert.fail(
      'MetaCloudApiError expected.',
    );
  }
  catch (error) {
    assert.ok(
      error instanceof
        MetaCloudApiError,
    );

    assert.equal(
      error.code,
      190,
    );

    assert.equal(
      error.errorSubcode,
      463,
    );

    assert.equal(
      error.requestId,
      'stage8-runtime-request',
    );

    assert.equal(
      error.message.includes(
        'stage8-runtime-token',
      ),
      false,
    );
  }

  event(
    'stage8.graph_error_normalization.passed',
  );

  const knownWabaId =
    `${metaKnownPrefix}${numericSuffix(1)}`;

  const knownPhoneId =
    `${metaKnownPrefix}${numericSuffix(2)}`;

  const knownNumber =
    await database.whatsAppNumber.create({
      data: {
        organizationId:
          organization.id,

        displayName:
          `${numberNamePrefix} Known`,

        e164:
          `+1555${numericSuffix(3)}`,

        status:
          'ACTIVE',
      },
    });

  const connected =
    await whatsAppService.configureMetaCloud(
      principal,
      knownNumber.id,
      {
        wabaId:
          knownWabaId,

        phoneNumberId:
          knownPhoneId,
      },
    );

  assert.equal(
    connected.metaWabaId,
    knownWabaId,
  );

  assert.equal(
    connected.metaPhoneNumberId,
    knownPhoneId,
  );

  assert.ok(
    connected.metaConnectedAt,
  );

  event(
    'stage8.number_connect.passed',
  );

  const duplicateNumber =
    await database.whatsAppNumber.create({
      data: {
        organizationId:
          organization.id,

        displayName:
          `${numberNamePrefix} Duplicate`,

        e164:
          `+1555${numericSuffix(4)}`,

        status:
          'ACTIVE',
      },
    });

  await assert.rejects(
    () =>
      whatsAppService.configureMetaCloud(
        principal,
        duplicateNumber.id,
        {
          wabaId:
            knownWabaId,

          phoneNumberId:
            knownPhoneId,
        },
      ),
  );

  event(
    'stage8.phone_id_uniqueness.passed',
  );

  const foreignOrganization =
    await database.organization.create({
      data: {
        name:
          'Stage 8 Foreign Tenant',

        slug:
          `${foreignOrganizationPrefix}${unique}`,

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
          `stage8.foreign.${unique}@example.com`,

        emailNormalized:
          `stage8.foreign.${unique}@example.com`,

        displayName:
          'Stage 8 Foreign User',

        status:
          'ACTIVE',
      },
    });

  const foreignNumber =
    await database.whatsAppNumber.create({
      data: {
        organizationId:
          foreignOrganization.id,

        displayName:
          `${numberNamePrefix} Foreign`,

        e164:
          `+1555${numericSuffix(5)}`,

        status:
          'ACTIVE',
      },
    });

  void foreignUser;

  await assert.rejects(
    () =>
      whatsAppService.configureMetaCloud(
        principal,
        foreignNumber.id,
        {
          wabaId:
            `${metaKnownPrefix}${numericSuffix(6)}`,

          phoneNumberId:
            `${metaKnownPrefix}${numericSuffix(7)}`,
        },
      ),
  );

  event(
    'stage8.number_tenant_isolation.passed',
  );

  const knownPayload = {
    object:
      'whatsapp_business_account',

    entry: [
      {
        id:
          knownWabaId,

        changes: [
          {
            field:
              'messages',

            value: {
              metadata: {
                display_phone_number:
                  knownNumber.e164,

                phone_number_id:
                  knownPhoneId,
              },

              messages: [
                {
                  id:
                    `wamid.stage8.${unique}`,

                  from:
                    '15550001111',

                  timestamp:
                    '1700000000',

                  type:
                    'text',

                  text: {
                    body:
                      'Stage 8 webhook',
                  },
                },
              ],
            },
          },
        ],
      },
    ],
  };

  const knownRawBody =
    Buffer.from(
      JSON.stringify(
        knownPayload,
      ),
    );

  const firstWebhook =
    await webhookService.ingest(
      knownPayload,
      knownRawBody,
    );

  assert.equal(
    firstWebhook.status,
    'RECEIVED',
  );

  assert.equal(
    firstWebhook.organizationId,
    organization.id,
  );

  assert.equal(
    firstWebhook.whatsAppNumberId,
    knownNumber.id,
  );

  const connectedAfterWebhook =
    await database.whatsAppNumber.findUniqueOrThrow({
      where: {
        id:
          knownNumber.id,
      },
    });

  assert.ok(
    connectedAfterWebhook.metaWebhookLastSeenAt,
  );

  event(
    'stage8.matched_webhook.passed',
  );

  const secondWebhook =
    await webhookService.ingest(
      knownPayload,
      knownRawBody,
    );

  assert.equal(
    secondWebhook.envelopeId,
    firstWebhook.envelopeId,
  );

  assert.equal(
    await database.metaWebhookEnvelope.count({
      where: {
        id:
          firstWebhook.envelopeId,
      },
    }),
    1,
  );

  event(
    'stage8.webhook_deduplication.passed',
  );

  const wrongWabaPayload = {
    object:
      'whatsapp_business_account',

    entry: [
      {
        id:
          `${metaUnknownPrefix}${numericSuffix(8)}`,

        changes: [
          {
            field:
              'messages',

            value: {
              metadata: {
                phone_number_id:
                  knownPhoneId,
              },
            },
          },
        ],
      },
    ],
  };

  const wrongWabaResult =
    await webhookService.ingest(
      wrongWabaPayload,
      Buffer.from(
        JSON.stringify(
          wrongWabaPayload,
        ),
      ),
    );

  assert.equal(
    wrongWabaResult.status,
    'UNMATCHED',
  );

  assert.equal(
    wrongWabaResult.organizationId,
    null,
  );

  event(
    'stage8.waba_mismatch.passed',
  );

  const unknownPhoneId =
    `${metaUnknownPrefix}${numericSuffix(9)}`;

  const unknownPayload = {
    object:
      'whatsapp_business_account',

    entry: [
      {
        id:
          `${metaUnknownPrefix}${numericSuffix(10)}`,

        changes: [
          {
            field:
              'messages',

            value: {
              metadata: {
                phone_number_id:
                  unknownPhoneId,
              },
            },
          },
        ],
      },
    ],
  };

  const unknownResult =
    await webhookService.ingest(
      unknownPayload,
      Buffer.from(
        JSON.stringify(
          unknownPayload,
        ),
      ),
    );

  assert.equal(
    unknownResult.status,
    'UNMATCHED',
  );

  assert.equal(
    unknownResult.whatsAppNumberId,
    null,
  );

  event(
    'stage8.unknown_number.passed',
  );

  const ignoredPayload = {
    object:
      'instagram',
    entry: [],
  };

  const ignoredResult =
    await webhookService.ingest(
      ignoredPayload,
      Buffer.from(
        JSON.stringify(
          ignoredPayload,
        ),
      ),
    );

  assert.equal(
    ignoredResult.status,
    'IGNORED',
  );

  assert.equal(
    ignoredResult.organizationId,
    null,
  );

  event(
    'stage8.ignored_object.passed',
  );

  const persistedEnvelope =
    await database.metaWebhookEnvelope.findUniqueOrThrow({
      where: {
        id:
          firstWebhook.envelopeId,
      },
    });

  assert.equal(
    persistedEnvelope.status,
    'RECEIVED',
  );

  assert.equal(
    persistedEnvelope.wabaId,
    knownWabaId,
  );

  assert.equal(
    persistedEnvelope.metaPhoneNumberId,
    knownPhoneId,
  );

  assert.ok(
    persistedEnvelope.payloadHash.length ===
      64,
  );

  event(
    'stage8.envelope_persistence.passed',
  );

  const connectAudit =
    await database.auditLog.count({
      where: {
        organizationId:
          organization.id,

        action:
          'whatsapp_number.meta_connected',

        resourceId:
          knownNumber.id,
      },
    });

  assert.ok(
    connectAudit >= 1,
  );

  const disconnected =
    await whatsAppService.configureMetaCloud(
      principal,
      knownNumber.id,
      {
        wabaId:
          null,

        phoneNumberId:
          null,
      },
    );

  assert.equal(
    disconnected.metaWabaId,
    null,
  );

  assert.equal(
    disconnected.metaPhoneNumberId,
    null,
  );

  assert.equal(
    disconnected.metaConnectedAt,
    null,
  );

  assert.equal(
    disconnected.metaWebhookLastSeenAt,
    null,
  );

  const disconnectAudit =
    await database.auditLog.count({
      where: {
        organizationId:
          organization.id,

        action:
          'whatsapp_number.meta_disconnected',

        resourceId:
          knownNumber.id,
      },
    });

  assert.ok(
    disconnectAudit >= 1,
  );

  event(
    'stage8.number_disconnect.passed',
  );

  event(
    'stage8.audit.passed',
    {
      connectAudit,
      disconnectAudit,
    },
  );

  event(
    'stage8.validation.completed',
  );
}
finally {
  try {
    await cleanupFixtures();
  }
  finally {
    await Promise.all([
      apiDatabaseService.onApplicationShutdown(),
      webhookDatabaseService.onApplicationShutdown(),
    ]);
  }
}
'@

Write-Text `
    -Path ".\apps\webhook-ingress\scripts\stage8-runtime-validation.ts" `
    -Content $RuntimeValidator

$Stage8RuntimePath = ".\apps\webhook-ingress\scripts\stage8-runtime-validation.ts"
$Stage8RuntimeContent = Read-Text -Path $Stage8RuntimePath
if (-not $Stage8RuntimeContent.Contains("async function main(): Promise<void>")) {
    $Stage8TryIndex = $Stage8RuntimeContent.IndexOf("try {")
    if ($Stage8TryIndex -lt 0) { throw "Nenhum try principal encontrado no runtime Stage 8." }
    $Stage8RuntimeContent = $Stage8RuntimeContent.Insert($Stage8TryIndex, "async function main(): Promise<void> {`r`n")
    $Stage8RuntimeContent = $Stage8RuntimeContent.TrimEnd() + "`r`n}`r`n`r`nvoid main().catch((error) => {`r`n  console.error(error);`r`n  process.exitCode = 1;`r`n});`r`n"
    Write-Text -Path $Stage8RuntimePath -Content $Stage8RuntimeContent
}

Write-Host "[OK] Stage 8 runtime validator criado." -ForegroundColor Green

# ============================================================
# FORMAT GENERATED VALIDATOR
# ============================================================

Invoke-Native `
    -Description "Format Stage 8 runtime" `
    -Command "pnpm" `
    -Arguments @("format")

# ============================================================
# GLOBAL CI
# ============================================================

Invoke-Native `
    -Description "Global CI Stage 8" `
    -Command "pnpm" `
    -Arguments @("ci:check")

# ============================================================
# DATABASE RUNTIME
# ============================================================

Write-Host ""
Write-Host "==== Stage 8 database runtime validation ====" -ForegroundColor Cyan

Invoke-Native `
    -Description "Compile Stage 8 runtime validator" `
    -Command "pnpm" `
    -Arguments @(
        "exec",
        "tsc",
        "-p",
        "apps/webhook-ingress/tsconfig.runtime.json"
    )

& node --env-file=.env "apps/webhook-ingress/.stage8-runtime-dist/apps/webhook-ingress/scripts/stage8-runtime-validation.js"

if ($LASTEXITCODE -ne 0) {
    throw "Stage 8 database runtime validation falhou."
}

Write-Host "[OK] Stage 8 database runtime validation." -ForegroundColor Green
Remove-Item `
    ".\apps\webhook-ingress\.stage8-runtime-dist" `
    -Recurse `
    -Force `
    -ErrorAction SilentlyContinue

# ============================================================
# WEBHOOK PROCESS SMOKE
# ============================================================

Write-Host ""
Write-Host "==== Webhook ingress process smoke ====" -ForegroundColor Cyan

$WebhookProcess = $null

$HadVerifyToken =
    Test-Path Env:META_WEBHOOK_VERIFY_TOKEN

$PreviousVerifyToken =
    $null

if ($HadVerifyToken) {
    $PreviousVerifyToken =
        $env:META_WEBHOOK_VERIFY_TOKEN
}

$HadAppSecret =
    Test-Path Env:META_APP_SECRET

$PreviousAppSecret =
    $null

if ($HadAppSecret) {
    $PreviousAppSecret =
        $env:META_APP_SECRET
}

$HadPort =
    Test-Path Env:PORT

$PreviousPort =
    $null

if ($HadPort) {
    $PreviousPort =
        $env:PORT
}

$env:META_WEBHOOK_VERIFY_TOKEN =
    "stage8-process-verify"

$env:META_APP_SECRET =
    "stage8-process-secret"

$env:PORT =
    "31982"

try {
    $StartParameters = @{
        FilePath         = "node"
        ArgumentList     = "apps/webhook-ingress/dist/main.js"
        WorkingDirectory = $RepositoryRoot
        NoNewWindow      = $true
        PassThru         = $true
    }

    $WebhookProcess =
        Start-Process @StartParameters

    Start-Sleep -Seconds 3

    if ($WebhookProcess.HasExited) {
        throw "Webhook ingress encerrou inesperadamente. ExitCode: $($WebhookProcess.ExitCode)"
    }

    Write-Host "[OK] Webhook ingress permaneceu online." -ForegroundColor Green
}
finally {
    if (
        $null -ne $WebhookProcess -and
        -not $WebhookProcess.HasExited
    ) {
        Stop-Process `
            -Id $WebhookProcess.Id `
            -Force `
            -ErrorAction SilentlyContinue
    }

    if ($HadVerifyToken) {
        $env:META_WEBHOOK_VERIFY_TOKEN =
            $PreviousVerifyToken
    }
    else {
        Remove-Item `
            Env:META_WEBHOOK_VERIFY_TOKEN `
            -ErrorAction SilentlyContinue
    }

    if ($HadAppSecret) {
        $env:META_APP_SECRET =
            $PreviousAppSecret
    }
    else {
        Remove-Item `
            Env:META_APP_SECRET `
            -ErrorAction SilentlyContinue
    }

    if ($HadPort) {
        $env:PORT =
            $PreviousPort
    }
    else {
        Remove-Item `
            Env:PORT `
            -ErrorAction SilentlyContinue
    }
}

# ============================================================
# DOCUMENTATION
# ============================================================

Write-Host ""
Write-Host "==== Stage 8 documentation ====" -ForegroundColor Cyan

$Stage8Document = @(
    "# Etapa 8 - Fundacao da Meta Cloud API",
    "",
    "## Status",
    "",
    "CONCLUIDA.",
    "",
    "## Objetivo",
    "",
    "Criar a fundacao segura para integrar numeros oficiais do WhatsApp com a Meta Cloud API e receber webhooks autenticados.",
    "",
    "## Meta Cloud API package",
    "",
    "Foi criado o pacote @crm/meta-cloud-api.",
    "",
    "Responsabilidades:",
    "",
    "- Graph API client",
    "- Bearer authorization",
    "- explicit Graph API version",
    "- configurable Graph base URL",
    "- request timeout",
    "- normalized Meta errors",
    "- webhook challenge verification",
    "- webhook HMAC SHA-256 validation",
    "- webhook metadata extraction",
    "",
    "## Graph API version",
    "",
    "Nenhuma versao da Graph API fica hardcoded no codigo.",
    "",
    "Cada ambiente deve fornecer META_GRAPH_API_VERSION explicitamente.",
    "",
    "Isso permite atualizar a versao da Graph API sem alterar a arquitetura da integracao.",
    "",
    "## Segredos",
    "",
    "META_ACCESS_TOKEN, META_APP_SECRET e META_WEBHOOK_VERIFY_TOKEN sao server-side only.",
    "",
    "Esses segredos nao sao persistidos no PostgreSQL.",
    "",
    "Nenhum deles utiliza prefixo NEXT_PUBLIC_.",
    "",
    "## WhatsAppNumber",
    "",
    "WhatsAppNumber agora pode armazenar:",
    "",
    "- Meta WABA ID",
    "- Meta Phone Number ID",
    "- data de conexao",
    "- ultimo webhook recebido",
    "",
    "Meta Phone Number ID e globalmente unico no CRM.",
    "",
    "## Webhook ingress",
    "",
    "Endpoint:",
    "",
    "GET /webhooks/meta/whatsapp",
    "",
    "Usado para challenge de verificacao.",
    "",
    "POST /webhooks/meta/whatsapp",
    "",
    "Usado para eventos da Meta.",
    "",
    "O POST exige x-hub-signature-256 valido calculado sobre o raw request body.",
    "",
    "## Raw body",
    "",
    "Nest rawBody fica habilitado no webhook-ingress.",
    "",
    "A assinatura e calculada sobre os bytes originais recebidos, nao sobre JSON reserializado.",
    "",
    "## MetaWebhookEnvelope",
    "",
    "Cada payload aceito e persistido em MetaWebhookEnvelope.",
    "",
    "Campos principais:",
    "",
    "- payload hash SHA-256",
    "- raw JSON normalizado",
    "- WABA ID",
    "- Meta Phone Number ID",
    "- Organization resolvida",
    "- WhatsAppNumber resolvido",
    "- status",
    "- receivedAt",
    "- claim/lease foundation",
    "",
    "## Deduplicacao",
    "",
    "payloadHash possui unique constraint.",
    "",
    "Retries da Meta com o mesmo raw payload nao criam um segundo envelope.",
    "",
    "## Resolucao de tenant",
    "",
    "O tenant nunca e aceito do payload como fonte de autoridade.",
    "",
    "Organization e resolvida atraves do Meta Phone Number ID previamente conectado ao WhatsAppNumber.",
    "",
    "Quando WABA ID e informado no webhook, ele tambem deve corresponder ao numero configurado.",
    "",
    "Payload de numero desconhecido recebe status UNMATCHED.",
    "",
    "Objetos fora de whatsapp_business_account recebem status IGNORED.",
    "",
    "## Stage 9 readiness",
    "",
    "MetaWebhookEnvelope ja possui status, availableAt, attempts, claim, lease e failureReason.",
    "",
    "Na Etapa 9 a caixa de atendimento podera consumir os envelopes persistentes sem fazer processamento pesado dentro da request do webhook.",
    "",
    "## Validacoes executadas",
    "",
    "- Prisma format",
    "- Prisma validate",
    "- migration",
    "- Prisma generate",
    "- seed verification",
    "- Meta package lint/typecheck/build",
    "- webhook security tests",
    "- payload extraction tests",
    "- Graph client tests",
    "- Graph error normalization",
    "- validation tests",
    "- API lint/typecheck/build",
    "- webhook ingress lint/typecheck/build",
    "- challenge valid/invalid",
    "- signature valid/invalid",
    "- Meta number connect",
    "- global Meta Phone Number ID uniqueness",
    "- number tenant isolation",
    "- matched webhook",
    "- webhook deduplication",
    "- WABA mismatch",
    "- unknown number",
    "- ignored object",
    "- envelope persistence",
    "- connect/disconnect audit",
    "- global CI",
    "- webhook process smoke",
    "",
    "## Proxima etapa",
    "",
    "Etapa 9 - Inbox e processamento dos webhooks da Meta."
)

[System.IO.File]::WriteAllLines(
    [System.IO.Path]::GetFullPath(
        ".\docs\ETAPA_8_META_CLOUD_API.md"
    ),
    $Stage8Document,
    $Utf8NoBom
)

$Decisions = @(
    "# Decisoes - Etapa 8",
    "",
    "A integracao utiliza a Meta WhatsApp Cloud API oficial.",
    "",
    "Graph API version deve ser configurada por ambiente.",
    "",
    "Nao existe versao Graph hardcoded no codigo.",
    "",
    "Access Token, App Secret e Verify Token permanecem fora do banco.",
    "",
    "Meta Phone Number ID e o identificador tecnico principal para resolver WhatsAppNumber no webhook.",
    "",
    "WABA ID tambem e validado quando presente.",
    "",
    "Webhook POST exige HMAC SHA-256 sobre raw body.",
    "",
    "Webhook ingress deve responder rapidamente e persistir o envelope antes do processamento de dominio.",
    "",
    "Processamento pesado fica fora da request do webhook.",
    "",
    "Payload SHA-256 e usado para deduplicacao de retries identicos.",
    "",
    "Webhook desconhecido nao e atribuido a nenhum tenant.",
    "",
    "UNKNOWN number gera UNMATCHED.",
    "",
    "Objeto que nao seja whatsapp_business_account gera IGNORED.",
    "",
    "MetaWebhookEnvelope ja contem claim e lease para a Etapa 9.",
    "",
    "Nenhum tenant ID enviado pela Meta substitui a resolucao interna do CRM."
)

[System.IO.File]::WriteAllLines(
    [System.IO.Path]::GetFullPath(
        ".\docs\DECISOES_ETAPA_8.md"
    ),
    $Decisions,
    $Utf8NoBom
)

$EtapasPath = ".\docs\ETAPAS.md"

if (Test-Path $EtapasPath) {
    $Etapas = Read-Text -Path $EtapasPath

    $Etapas = [regex]::Replace(
        $Etapas,
        '\|\s*8\s*\|\s*Fundação da Meta Cloud API\s*\|[^|]*\|',
        '|     8 | Fundação da Meta Cloud API                | CONCLUÍDA                   |'
    )

    $Etapas = [regex]::Replace(
        $Etapas,
        '\|\s*8\s*\|\s*Fundacao da Meta Cloud API\s*\|[^|]*\|',
        '|     8 | Fundacao da Meta Cloud API                | CONCLUÍDA                   |'
    )

    if (-not $Etapas.Contains("## Etapa 8 - Meta Cloud API")) {
        $Summary = @(
            "",
            "## Etapa 8 - Meta Cloud API",
            "",
            "Status: CONCLUIDA.",
            "",
            "Implementado:",
            "",
            "- @crm/meta-cloud-api",
            "- Graph API client",
            "- explicit Graph API version",
            "- Meta normalized errors",
            "- webhook verification challenge",
            "- HMAC SHA-256 raw-body validation",
            "- MetaWebhookEnvelope",
            "- SHA-256 webhook deduplication",
            "- WABA mapping",
            "- Meta Phone Number ID mapping",
            "- tenant-safe webhook resolution",
            "- UNMATCHED and IGNORED handling",
            "- connect/disconnect API",
            "- claim/lease foundation for Stage 9",
            "",
            "Documentacao:",
            "",
            "- docs/ETAPA_8_META_CLOUD_API.md",
            "- docs/DECISOES_ETAPA_8.md",
            "",
            "Proxima: Etapa 9 - Inbox."
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

Write-Host "[OK] Stage 8 documentation." -ForegroundColor Green

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
# META SECRET EXPOSURE CHECK
# ============================================================

Write-Host ""
Write-Host "==== Meta secret exposure check ====" -ForegroundColor Cyan

$PublicMetaViolations = @()

foreach ($File in @(
    ".\apps\web",
    ".\packages\contracts",
    ".\packages\validation"
)) {
    if (-not (Test-Path $File)) {
        continue
    }

    $Matches = Get-ChildItem `
        -Path $File `
        -File `
        -Recurse `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Extension -in @(
                ".ts",
                ".tsx",
                ".js",
                ".mjs",
                ".json"
            )
        } |
        Select-String `
            -Pattern "META_ACCESS_TOKEN|META_APP_SECRET|META_WEBHOOK_VERIFY_TOKEN" `
            -SimpleMatch:$false

    if ($Matches) {
        $PublicMetaViolations += $Matches
    }
}

if (@($PublicMetaViolations).Count -gt 0) {
    $PublicMetaViolations
    throw "Segredo Meta referenciado em superficie publica."
}

Write-Host "[OK] Nenhum segredo Meta exposto no frontend/contracts." -ForegroundColor Green

# ============================================================
# GENERIC SECRET SCAN
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
    throw "Secret scan falhou."
}

if (@($TrackedSecretMatches).Count -gt 0) {
    $TrackedSecretMatches
    throw "Possivel segredo encontrado."
}

Write-Host "[OK] Secret scan." -ForegroundColor Green

# ============================================================
# CLEAN BACKUP
# ============================================================

Remove-Item `
    ".\tmp\stage8-macroblock1-backup" `
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
Write-Host "[OK] ETAPA 8 COMPLETAMENTE VALIDADA." -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Validado:" -ForegroundColor Cyan
Write-Host "- Prisma migration"
Write-Host "- Prisma generate"
Write-Host "- seed verification"
Write-Host "- Meta Cloud API lint/typecheck/tests/build"
Write-Host "- Graph API config"
Write-Host "- Graph API client"
Write-Host "- Bearer authorization"
Write-Host "- Meta error normalization"
Write-Host "- webhook challenge"
Write-Host "- HMAC SHA-256 raw-body signature"
Write-Host "- validation tests"
Write-Host "- API lint/typecheck/build"
Write-Host "- webhook ingress lint/typecheck/build"
Write-Host "- Meta number connect"
Write-Host "- Meta phone ID uniqueness"
Write-Host "- tenant isolation"
Write-Host "- matched webhook"
Write-Host "- webhook deduplication"
Write-Host "- WABA mismatch"
Write-Host "- unknown Meta number"
Write-Host "- ignored object"
Write-Host "- webhook persistence"
Write-Host "- webhook last-seen"
Write-Host "- disconnect"
Write-Host "- audit"
Write-Host "- webhook process smoke"
Write-Host "- global CI"
Write-Host "- Meta secret exposure check"
Write-Host "- documentation"
Write-Host "- git checks"
Write-Host "- secret scan"
Write-Host ""
Write-Host "Proxima etapa: ETAPA 9." -ForegroundColor Yellow