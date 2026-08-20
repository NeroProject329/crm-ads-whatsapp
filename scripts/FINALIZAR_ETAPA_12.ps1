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
Write-Host " ETAPA 12 - MACROBLOCO 12.2" -ForegroundColor Cyan
Write-Host " SECURITY AUDIT + PRODUCTION READINESS" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

# ============================================================
# PREFLIGHT
# ============================================================

$RequiredFiles = @(
    ".\packages\config\src\http-security.ts",
    ".\packages\config\src\production-readiness.ts",
    ".\apps\api\src\security\security.module.ts",
    ".\apps\api\src\main.ts",
    ".\apps\webhook-ingress\src\main.ts",
    ".\apps\webhook-ingress\src\health.controller.ts",
    ".\apps\worker\src\whatsapp-outbound-dispatcher.service.ts",
    ".\apps\worker\src\main.ts",
    ".\apps\site-monitor-worker\src\main.ts",
    ".\apps\web\next.config.ts",
    ".\scripts\validate-production-environment.mjs",
    ".\docs\ETAPA_12_SECURITY_HARDENING.md"
)

foreach ($File in $RequiredFiles) {
    if (-not (Test-Path $File)) {
        throw "Macrobloco 12.1 incompleto: $File"
    }
}

Write-Host "[OK] Preflight Stage 12." -ForegroundColor Green

# ============================================================
# BACKUP
# ============================================================

$BackupRoot =
    ".\tmp\stage12-macroblock2-backup"

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
    ".\packages\database\prisma\seed.ts",
    ".\packages\config\src\http-security.spec.ts",
    ".\apps\web\next.config.ts",
    ".\.github\workflows\ci.yml",
    ".\docs\ETAPA_12_SECURITY_HARDENING.md",
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

Write-Host "[OK] Backup Stage 12.2 preparado." -ForegroundColor Green

# ============================================================
# PRODUCTION SEED HARDENING
# ============================================================

$SeedPath =
    ".\packages\database\prisma\seed.ts"

$Seed =
    Read-Text -Path $SeedPath

if (-not $Seed.Contains("PRODUCTION_SEED_CONFIGURATION_REQUIRED")) {
    $Anchor =
        "const adminEmployeeCode = process.env.SEED_ADMIN_EMPLOYEE_CODE?.trim() || 'ADMIN001';"

    if (-not $Seed.Contains($Anchor)) {
        throw "Seed adminEmployeeCode anchor nao encontrado."
    }

    $SeedGuard = @'

const _PRODUCTION_SEED_CONFIGURATION_REQUIRED = true;

const productionSeedEnvironment =
  process.env.APP_ENV === 'staging' ||
  process.env.APP_ENV === 'production';

if (productionSeedEnvironment) {
  if (process.env.NODE_ENV !== 'production') {
    throw new Error(
      'NODE_ENV must be production when seeding staging or production.',
    );
  }

  const requiredSeedVariables = [
    'SEED_ORGANIZATION_NAME',
    'SEED_ORGANIZATION_SLUG',
    'SEED_TEAM_NAME',
    'SEED_TEAM_SLUG',
    'SEED_ADMIN_EMAIL',
    'SEED_ADMIN_NAME',
    'SEED_ADMIN_EMPLOYEE_CODE',
  ] as const;

  for (const variable of requiredSeedVariables) {
    const value = process.env[variable]?.trim();

    if (!value) {
      throw new Error(
        `${variable} is required when seeding staging or production.`,
      );
    }
  }

  if (adminEmail.endsWith('@example.com')) {
    throw new Error(
      'SEED_ADMIN_EMAIL cannot use example.com in staging or production.',
    );
  }
}
'@

    $Seed =
        $Seed.Replace(
            $Anchor,
            $Anchor +
            $SeedGuard
        )
}

Write-Text `
    -Path $SeedPath `
    -Content $Seed

Write-Host "[OK] Production seed fail-closed criado." -ForegroundColor Green

# ============================================================
# WEB BUILD FAIL-CLOSED
# ============================================================

$NextConfig = @'
import type {
  NextConfig,
} from 'next';

const appEnvironment =
  process.env.APP_ENV?.trim() ??
  'development';

const productionLike =
  appEnvironment ===
    'staging' ||
  appEnvironment ===
    'production';

if (
  productionLike &&
  process.env.NODE_ENV !==
    'production'
) {
  throw new Error(
    'NODE_ENV must be production when APP_ENV is staging or production.',
  );
}

if (
  productionLike &&
  !process.env.NEXT_PUBLIC_ONESIGNAL_APP_ID?.trim()
) {
  throw new Error(
    'NEXT_PUBLIC_ONESIGNAL_APP_ID is required for staging/production web builds.',
  );
}

const securityHeaders = [
  {
    key:
      'X-Content-Type-Options',

    value:
      'nosniff',
  },

  {
    key:
      'X-Frame-Options',

    value:
      'DENY',
  },

  {
    key:
      'Referrer-Policy',

    value:
      'strict-origin-when-cross-origin',
  },

  {
    key:
      'Permissions-Policy',

    value:
      'camera=(), microphone=(), geolocation=(), payment=(), usb=()',
  },

  {
    key:
      'X-Robots-Tag',

    value:
      'noindex, nofollow',
  },

  ...(productionLike
    ? [
        {
          key:
            'Strict-Transport-Security',

          value:
            'max-age=31536000; includeSubDomains',
        },
      ]
    : []),
];

const noCacheHeaders = [
  {
    key:
      'Cache-Control',

    value:
      'no-cache, no-store, must-revalidate',
  },
];

const nextConfig:
  NextConfig =
    {
      output:
        process.env.CRM_STANDALONE ===
        'true'
          ? 'standalone'
          : undefined,

      poweredByHeader:
        false,

      reactStrictMode:
        true,

      async headers() {
        return [
          {
            source:
              '/:path*',

            headers:
              securityHeaders,
          },

          {
            source:
              '/sw.js',

            headers:
              noCacheHeaders,
          },

          {
            source:
              '/push/onesignal/OneSignalSDKWorker.js',

            headers:
              noCacheHeaders,
          },
        ];
      },
    };

export default nextConfig;
'@

Write-Text `
    -Path ".\apps\web\next.config.ts" `
    -Content $NextConfig

Write-Host "[OK] Web production build fail-closed criado." -ForegroundColor Green

# ============================================================
# EXPANDED CONFIG SECURITY TESTS
# ============================================================

$ConfigTests = @'
import {
  describe,
  expect,
  it,
} from 'vitest';

import {
  parseHttpSecurityEnvironment,
} from './http-security.js';

import {
  assertServiceProductionReadiness,
} from './production-readiness.js';

const productionBase =
  {
    NODE_ENV:
      'production',

    APP_ENV:
      'production',

    DATABASE_URL:
      'postgresql://crm:password@postgres.internal:5432/crm',

    API_CORS_ALLOWED_ORIGINS:
      'https://crm.example.com',

    AUTH_ACCESS_TOKEN_SECRET:
      'stage12-access-secret-0123456789abcdef',

    AUTH_REFRESH_TOKEN_PEPPER:
      'stage12-refresh-pepper-0123456789abcdef',

    META_APP_SECRET:
      'stage12-meta-secret-0123456789abcdef',

    META_WEBHOOK_VERIFY_TOKEN:
      'stage12-webhook-token-0123456789',

    META_GRAPH_API_VERSION:
      'v99.0',

    META_ACCESS_TOKEN:
      'stage12-meta-token-0123456789abcdef',

    ONESIGNAL_APP_ID:
      'stage12-onesignal-app',

    ONESIGNAL_API_KEY:
      'stage12-onesignal-key-0123456789',

    NEXT_PUBLIC_ONESIGNAL_APP_ID:
      'stage12-public-onesignal-app',
  } satisfies NodeJS.ProcessEnv;

describe(
  'Stage 12 production security',
  () => {
    it(
      'uses local development CORS defaults',
      () => {
        const config =
          parseHttpSecurityEnvironment({
            NODE_ENV:
              'development',

            APP_ENV:
              'development',
          });

        expect(
          config.corsAllowedOrigins,
        ).toContain(
          'http://localhost:3000',
        );
      },
    );

    it(
      'requires explicit HTTPS CORS in production',
      () => {
        expect(
          () =>
            parseHttpSecurityEnvironment({
              NODE_ENV:
                'production',

              APP_ENV:
                'production',

              API_CORS_ALLOWED_ORIGINS:
                '',
            }),
        ).toThrow();
      },
    );

    it(
      'rejects HTTP origin in production',
      () => {
        expect(
          () =>
            parseHttpSecurityEnvironment({
              NODE_ENV:
                'production',

              APP_ENV:
                'production',

              API_CORS_ALLOWED_ORIGINS:
                'http://crm.example.com',
            }),
        ).toThrow();
      },
    );

    it(
      'rejects CORS origins containing a path',
      () => {
        expect(
          () =>
            parseHttpSecurityEnvironment({
              NODE_ENV:
                'production',

              APP_ENV:
                'production',

              API_CORS_ALLOWED_ORIGINS:
                'https://crm.example.com/app',
            }),
        ).toThrow();
      },
    );

    it(
      'rejects headers timeout above request timeout',
      () => {
        expect(
          () =>
            parseHttpSecurityEnvironment({
              NODE_ENV:
                'development',

              HTTP_REQUEST_TIMEOUT_MS:
                '10000',

              HTTP_HEADERS_TIMEOUT_MS:
                '15000',
            }),
        ).toThrow();
      },
    );

    it(
      'accepts complete production API environment',
      () => {
        expect(
          () =>
            assertServiceProductionReadiness(
              'api',
              productionBase,
            ),
        ).not.toThrow();
      },
    );

    it(
      'rejects equal access and refresh secrets',
      () => {
        expect(
          () =>
            assertServiceProductionReadiness(
              'api',
              {
                ...productionBase,

                AUTH_REFRESH_TOKEN_PEPPER:
                  productionBase.AUTH_ACCESS_TOKEN_SECRET,
              },
            ),
        ).toThrow();
      },
    );

    it(
      'rejects localhost PostgreSQL in production',
      () => {
        expect(
          () =>
            assertServiceProductionReadiness(
              'api',
              {
                ...productionBase,

                DATABASE_URL:
                  'postgresql://crm:password@localhost:5432/crm',
              },
            ),
        ).toThrow();
      },
    );

    it(
      'requires Meta webhook secrets',
      () => {
        expect(
          () =>
            assertServiceProductionReadiness(
              'webhook-ingress',
              {
                ...productionBase,

                META_APP_SECRET:
                  '',
              },
            ),
        ).toThrow();
      },
    );

    it(
      'requires provider configuration for worker',
      () => {
        expect(
          () =>
            assertServiceProductionReadiness(
              'worker',
              productionBase,
            ),
        ).not.toThrow();

        expect(
          () =>
            assertServiceProductionReadiness(
              'worker',
              {
                ...productionBase,

                META_ACCESS_TOKEN:
                  '',
              },
            ),
        ).toThrow();
      },
    );

    it(
      'requires production NODE_ENV for staging',
      () => {
        expect(
          () =>
            assertServiceProductionReadiness(
              'site-monitor-worker',
              {
                ...productionBase,

                APP_ENV:
                  'staging',

                NODE_ENV:
                  'development',
              },
            ),
        ).toThrow();
      },
    );

    it(
      'does not require production secrets during development',
      () => {
        expect(
          () =>
            assertServiceProductionReadiness(
              'worker',
              {
                NODE_ENV:
                  'development',

                APP_ENV:
                  'development',
              },
            ),
        ).not.toThrow();
      },
    );
  },
);
'@

Write-Text `
    -Path ".\packages\config\src\http-security.spec.ts" `
    -Content $ConfigTests

# ============================================================
# CI SECURITY AUDIT
# ============================================================

$CiWorkflow = @'
name: CI

on:
  pull_request:
  push:
    branches:
      - main
      - staging

permissions:
  contents: read

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  validate:
    name: Security, lint, types, tests and build
    runs-on: ubuntu-latest
    timeout-minutes: 25

    steps:
      - name: Checkout
        uses: actions/checkout@v6

      - name: Setup pnpm
        uses: pnpm/action-setup@v4
        with:
          version: 11.15.1
          run_install: false

      - name: Setup Node.js
        uses: actions/setup-node@v6
        with:
          node-version: 24.18.0
          cache: pnpm

      - name: Install dependencies
        run: pnpm install --frozen-lockfile

      - name: Audit production dependencies
        run: pnpm audit --prod --audit-level=high

      - name: Validate workspace structure
        run: pnpm structure:check

      - name: Run complete verification
        run: pnpm ci:check
'@

Write-Text `
    -Path ".\.github\workflows\ci.yml" `
    -Content $CiWorkflow

Write-Host "[OK] CI production dependency audit criado." -ForegroundColor Green

# ============================================================
# REMOTE DEPLOYMENT VERIFIER
# ============================================================

$DeploymentVerifier = @'
const apiBase =
  process.env.DEPLOY_API_BASE_URL?.trim();

const webhookBase =
  process.env.DEPLOY_WEBHOOK_BASE_URL?.trim();

if (
  !apiBase ||
  !webhookBase
) {
  console.error(
    'DEPLOY_API_BASE_URL and DEPLOY_WEBHOOK_BASE_URL are required.',
  );

  process.exit(2);
}

function normalizeBase(
  raw,
  label,
) {
  const url =
    new URL(
      raw,
    );

  if (
    url.protocol !==
    'https:'
  ) {
    throw new Error(
      `${label} must use HTTPS.`,
    );
  }

  return url.origin;
}

async function verify(
  url,
  expectedService,
) {
  const response =
    await fetch(
      url,
      {
        signal:
          AbortSignal.timeout(
            10000,
          ),
      },
    );

  if (
    response.status !==
    200
  ) {
    throw new Error(
      `${url} returned ${response.status}.`,
    );
  }

  const payload =
    await response.json();

  if (
    payload.service !==
    expectedService
  ) {
    throw new Error(
      `${url} returned unexpected service identity.`,
    );
  }

  const noSniff =
    response.headers.get(
      'x-content-type-options',
    );

  if (
    noSniff !==
    'nosniff'
  ) {
    throw new Error(
      `${url} is missing X-Content-Type-Options: nosniff.`,
    );
  }

  const cache =
    response.headers.get(
      'cache-control',
    );

  if (
    !cache?.includes(
      'no-store',
    )
  ) {
    throw new Error(
      `${url} is missing Cache-Control: no-store.`,
    );
  }

  return payload;
}

try {
  const api =
    normalizeBase(
      apiBase,
      'DEPLOY_API_BASE_URL',
    );

  const webhook =
    normalizeBase(
      webhookBase,
      'DEPLOY_WEBHOOK_BASE_URL',
    );

  await verify(
    `${api}/api/v1/health/live`,
    'api',
  );

  await verify(
    `${api}/api/v1/health/ready`,
    'api',
  );

  await verify(
    `${webhook}/health/live`,
    'webhook-ingress',
  );

  await verify(
    `${webhook}/health/ready`,
    'webhook-ingress',
  );

  console.log(
    '[OK] Remote API and webhook health/security checks passed.',
  );
}
catch (
  error
) {
  console.error(
    error instanceof Error
      ? error.message
      : String(
          error,
        ),
  );

  process.exit(1);
}
'@

Write-Text `
    -Path ".\scripts\verify-deployed-services.mjs" `
    -Content $DeploymentVerifier

# ============================================================
# STAGE 12 SECURITY RUNTIME
# ============================================================

$RuntimeValidator = @'
import '../src/load-environment.js';

import assert from 'node:assert/strict';

import {
  createHash,
  createHmac,
  randomUUID,
} from 'node:crypto';

import {
  spawn,
  spawnSync,
} from 'node:child_process';

import {
  createServer,
} from 'node:net';

import {
  dirname,
  resolve,
} from 'node:path';

import {
  fileURLToPath,
} from 'node:url';

import {
  createDatabaseClient,
} from '@crm/database';

import {
  WhatsAppOutboundDispatcherService,
} from '../src/whatsapp-outbound-dispatcher.service.js';

import type {
  WhatsAppRuntimeConfig,
} from '../src/whatsapp-runtime.config.js';

const scriptDirectory =
  dirname(
    fileURLToPath(
      import.meta.url,
    ),
  );

const repositoryRoot =
  resolve(
    scriptDirectory,
    '../../..',
  );

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
  `stage12-runtime-${unique}`;

const allowedOrigin =
  'https://allowed.stage12.test';

const metaAppSecret =
  'stage12-meta-secret-0123456789abcdef';

const verifyToken =
  'stage12-verify-token-0123456789';

const accessSecret =
  'stage12-access-secret-0123456789abcdef';

const refreshPepper =
  'stage12-refresh-pepper-0123456789abcdef';

const outboundConfig:
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

type ManagedProcess =
  Readonly<{
    child:
      ReturnType<
        typeof spawn
      >;

    getLogs:
      () => string;
  }>;

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

function sleep(
  milliseconds:
    number,
): Promise<void> {
  return new Promise(
    (
      resolvePromise,
    ) => {
      setTimeout(
        resolvePromise,
        milliseconds,
      );
    },
  );
}

async function getFreePort():
Promise<number> {
  const server =
    createServer();

  await new Promise<void>(
    (
      resolvePromise,
      reject,
    ) => {
      server.once(
        'error',
        reject,
      );

      server.listen(
        0,
        '127.0.0.1',
        () => {
          resolvePromise();
        },
      );
    },
  );

  const address =
    server.address();

  assert.ok(
    address &&
    typeof address !==
      'string',
  );

  const port =
    address.port;

  await new Promise<void>(
    (
      resolvePromise,
      reject,
    ) => {
      server.close(
        (
          error,
        ) => {
          if (
            error
          ) {
            reject(
              error,
            );

            return;
          }

          resolvePromise();
        },
      );
    },
  );

  return port;
}

function startService(
  entry:
    string,

  environment:
    NodeJS.ProcessEnv,
): ManagedProcess {
  const child =
    spawn(
      process.execPath,
      [
        entry,
      ],
      {
        cwd:
          repositoryRoot,

        env: {
          ...process.env,

          ...environment,
        },

        stdio: [
          'ignore',
          'pipe',
          'pipe',
        ],
      },
    );

  let logs =
    '';

  child.stdout?.on(
    'data',
    (
      chunk:
        Buffer,
    ) => {
      logs +=
        chunk.toString();
    },
  );

  child.stderr?.on(
    'data',
    (
      chunk:
        Buffer,
    ) => {
      logs +=
        chunk.toString();
    },
  );

  return {
    child,

    getLogs:
      () =>
        logs,
  };
}

async function stopService(
  service:
    ManagedProcess,
): Promise<void> {
  if (
    service.child.exitCode !==
    null
  ) {
    return;
  }

  service.child.kill(
    'SIGTERM',
  );

  for (
    let attempt =
      0;
    attempt <
      20;
    attempt +=
      1
  ) {
    if (
      service.child.exitCode !==
      null
    ) {
      return;
    }

    await sleep(
      100,
    );
  }

  if (
    service.child.exitCode ===
    null
  ) {
    service.child.kill();
  }
}

async function waitForHttp(
  service:
    ManagedProcess,

  url:
    string,
): Promise<void> {
  for (
    let attempt =
      0;
    attempt <
      80;
    attempt +=
      1
  ) {
    if (
      service.child.exitCode !==
      null
    ) {
      throw new Error(
        `Service exited before becoming ready.` +
        `\n${service.getLogs()}`,
      );
    }

    try {
      const response =
        await fetch(
          url,
          {
            signal:
              AbortSignal.timeout(
                1000,
              ),
          },
        );

      if (
        response.status ===
        200
      ) {
        return;
      }
    }
    catch {
      // startup retry
    }

    await sleep(
      125,
    );
  }

  throw new Error(
    `Service did not become ready: ${url}` +
    `\n${service.getLogs()}`,
  );
}

function runProductionValidators():
void {
  const common = {
    ...process.env,

    NODE_ENV:
      'production',

    APP_ENV:
      'staging',

    DATABASE_URL:
      'postgresql://crm:password@postgres.internal:5432/crm',

    API_CORS_ALLOWED_ORIGINS:
      'https://crm.stage12.test',

    AUTH_ACCESS_TOKEN_SECRET:
      accessSecret,

    AUTH_REFRESH_TOKEN_PEPPER:
      refreshPepper,

    META_APP_SECRET:
      metaAppSecret,

    META_WEBHOOK_VERIFY_TOKEN:
      verifyToken,

    META_GRAPH_API_VERSION:
      'v99.0',

    META_ACCESS_TOKEN:
      'stage12-meta-access-token-0123456789abcdef',

    ONESIGNAL_APP_ID:
      'stage12-onesignal-app',

    ONESIGNAL_API_KEY:
      'stage12-onesignal-key-0123456789abcdef',

    NEXT_PUBLIC_ONESIGNAL_APP_ID:
      'stage12-public-onesignal-app',
  };

  for (
    const service of [
      'api',
      'webhook-ingress',
      'worker',
      'site-monitor-worker',
      'web',
    ]
  ) {
    const result =
      spawnSync(
        process.execPath,
        [
          'scripts/validate-production-environment.mjs',
          service,
        ],
        {
          cwd:
            repositoryRoot,

          env:
            common,

          encoding:
            'utf8',
        },
      );

    assert.equal(
      result.status,
      0,
      `${service} validator failed:\n${result.stdout}\n${result.stderr}`,
    );
  }

  const invalid =
    spawnSync(
      process.execPath,
      [
        'scripts/validate-production-environment.mjs',
        'api',
      ],
      {
        cwd:
          repositoryRoot,

        env: {
          ...common,

          AUTH_REFRESH_TOKEN_PEPPER:
            accessSecret,
        },

        encoding:
          'utf8',
      },
    );

  assert.notEqual(
    invalid.status,
    0,
  );

  log(
    'stage12.production_environment_validation.passed',
  );
}

async function verifyApiSecurity():
Promise<void> {
  const databaseUrl =
    process.env.DATABASE_URL?.trim();

  assert.ok(
    databaseUrl,
    'DATABASE_URL is required for Stage 12 runtime.',
  );

  const port =
    await getFreePort();

  const service =
    startService(
      'apps/api/dist/main.js',
      {
        NODE_ENV:
          'test',

        APP_ENV:
          'test',

        PORT:
          String(
            port,
          ),

        DATABASE_URL:
          databaseUrl,

        AUTH_ACCESS_TOKEN_SECRET:
          accessSecret,

        AUTH_REFRESH_TOKEN_PEPPER:
          refreshPepper,

        API_CORS_ALLOWED_ORIGINS:
          allowedOrigin,

        HTTP_TRUST_PROXY_HOPS:
          '0',

        API_BODY_LIMIT_BYTES:
          '1024',

        HTTP_REQUEST_TIMEOUT_MS:
          '10000',

        HTTP_HEADERS_TIMEOUT_MS:
          '5000',

        HTTP_KEEP_ALIVE_TIMEOUT_MS:
          '2000',

        HTTP_MAX_HEADERS_COUNT:
          '50',

        API_RATE_LIMIT_TTL_MS:
          '60000',

        API_RATE_LIMIT_DEFAULT:
          '100',

        AUTH_LOGIN_RATE_LIMIT:
          '2',

        AUTH_REFRESH_RATE_LIMIT:
          '3',
      },
    );

  try {
    const base =
      `http://127.0.0.1:${port}`;

    await waitForHttp(
      service,
      `${base}/api/v1/health/live`,
    );

    const live =
      await fetch(
        `${base}/api/v1/health/live`,
        {
          headers: {
            Origin:
              allowedOrigin,
          },
        },
      );

    assert.equal(
      live.status,
      200,
    );

    assert.equal(
      live.headers.get(
        'access-control-allow-origin',
      ),
      allowedOrigin,
    );

    assert.equal(
      live.headers.get(
        'x-content-type-options',
      ),
      'nosniff',
    );

    assert.equal(
      live.headers.get(
        'x-frame-options',
      ),
      'SAMEORIGIN',
    );

    assert.equal(
      live.headers.get(
        'x-robots-tag',
      ),
      'noindex, nofollow',
    );

    assert.ok(
      live.headers
        .get(
          'cache-control',
        )
        ?.includes(
          'no-store',
        ),
    );

    assert.equal(
      live.headers.get(
        'x-powered-by',
      ),
      null,
    );

    const ready =
      await fetch(
        `${base}/api/v1/health/ready`,
      );

    assert.equal(
      ready.status,
      200,
    );

    const disallowed =
      await fetch(
        `${base}/api/v1/health/live`,
        {
          headers: {
            Origin:
              'https://evil.stage12.test',
          },
        },
      );

    assert.equal(
      disallowed.status,
      200,
    );

    assert.equal(
      disallowed.headers.get(
        'access-control-allow-origin',
      ),
      null,
    );

    const oversized =
      await fetch(
        `${base}/api/v1/auth/login`,
        {
          method:
            'POST',

          headers: {
            'content-type':
              'application/json',
          },

          body:
            JSON.stringify({
              padding:
                'x'.repeat(
                  4096,
                ),
            }),
        },
      );

    assert.equal(
      oversized.status,
      413,
    );

    const rateStatuses:
      number[] =
        [];

    for (
      let index =
        0;
      index <
        3;
      index +=
        1
    ) {
      const response =
        await fetch(
          `${base}/api/v1/auth/login`,
          {
            method:
              'POST',

            headers: {
              'content-type':
                'application/json',
            },

            body:
              '{}',
          },
        );

      rateStatuses.push(
        response.status,
      );
    }

    assert.deepEqual(
      rateStatuses,
      [
        400,
        400,
        429,
      ],
    );

    log(
      'stage12.api_http_security.passed',
    );
  }
  finally {
    await stopService(
      service,
    );
  }
}

async function verifyWebhookSecurity():
Promise<void> {
  const databaseUrl =
    process.env.DATABASE_URL?.trim();

  assert.ok(
    databaseUrl,
  );

  const port =
    await getFreePort();

  const service =
    startService(
      'apps/webhook-ingress/dist/main.js',
      {
        NODE_ENV:
          'test',

        APP_ENV:
          'test',

        PORT:
          String(
            port,
          ),

        DATABASE_URL:
          databaseUrl,

        META_APP_SECRET:
          metaAppSecret,

        META_WEBHOOK_VERIFY_TOKEN:
          verifyToken,

        WEBHOOK_BODY_LIMIT_BYTES:
          '1024',

        HTTP_REQUEST_TIMEOUT_MS:
          '10000',

        HTTP_HEADERS_TIMEOUT_MS:
          '5000',

        HTTP_KEEP_ALIVE_TIMEOUT_MS:
          '2000',

        HTTP_MAX_HEADERS_COUNT:
          '50',
      },
    );

  let webhookPayloadHash:
    string | null =
      null;

  try {
    const base =
      `http://127.0.0.1:${port}`;

    await waitForHttp(
      service,
      `${base}/health/live`,
    );

    const live =
      await fetch(
        `${base}/health/live`,
      );

    assert.equal(
      live.status,
      200,
    );

    assert.equal(
      live.headers.get(
        'x-content-type-options',
      ),
      'nosniff',
    );

    assert.ok(
      live.headers
        .get(
          'cache-control',
        )
        ?.includes(
          'no-store',
        ),
    );

    const ready =
      await fetch(
        `${base}/health/ready`,
      );

    assert.equal(
      ready.status,
      200,
    );

    const challenge =
      `stage12-${unique}`;

    const verification =
      await fetch(
        `${base}/webhooks/meta/whatsapp` +
        `?hub.mode=subscribe` +
        `&hub.verify_token=${encodeURIComponent(verifyToken)}` +
        `&hub.challenge=${encodeURIComponent(challenge)}`,
      );

    assert.equal(
      verification.status,
      200,
    );

    assert.equal(
      await verification.text(),
      challenge,
    );

    const denied =
      await fetch(
        `${base}/webhooks/meta/whatsapp` +
        `?hub.mode=subscribe` +
        `&hub.verify_token=wrong-token` +
        `&hub.challenge=${encodeURIComponent(challenge)}`,
      );

    assert.equal(
      denied.status,
      403,
    );

    const raw =
      JSON.stringify({
        object:
          'stage12_security_test',

        nonce:
          unique,
      });

    const invalidSignature =
      await fetch(
        `${base}/webhooks/meta/whatsapp`,
        {
          method:
            'POST',

          headers: {
            'content-type':
              'application/json',

            'x-hub-signature-256':
              'sha256=deadbeef',
          },

          body:
            raw,
        },
      );

    assert.equal(
      invalidSignature.status,
      401,
    );

    const signature =
      'sha256=' +
      createHmac(
        'sha256',
        metaAppSecret,
      )
        .update(
          raw,
        )
        .digest(
          'hex',
        );

    webhookPayloadHash =
      createHash(
        'sha256',
      )
        .update(
          raw,
        )
        .digest(
          'hex',
        );

    const valid =
      await fetch(
        `${base}/webhooks/meta/whatsapp`,
        {
          method:
            'POST',

          headers: {
            'content-type':
              'application/json',

            'x-hub-signature-256':
              signature,
          },

          body:
            raw,
        },
      );

    assert.equal(
      valid.status,
      200,
    );

    assert.equal(
      await valid.text(),
      'EVENT_RECEIVED',
    );

    const oversizedRaw =
      JSON.stringify({
        padding:
          'x'.repeat(
            4096,
          ),
      });

    const oversized =
      await fetch(
        `${base}/webhooks/meta/whatsapp`,
        {
          method:
            'POST',

          headers: {
            'content-type':
              'application/json',
          },

          body:
            oversizedRaw,
        },
      );

    assert.equal(
      oversized.status,
      413,
    );

    const originTest =
      await fetch(
        `${base}/health/live`,
        {
          headers: {
            Origin:
              'https://arbitrary.stage12.test',
          },
        },
      );

    assert.equal(
      originTest.headers.get(
        'access-control-allow-origin',
      ),
      null,
    );

    log(
      'stage12.webhook_http_security.passed',
    );
  }
  finally {
    await stopService(
      service,
    );

    if (
      webhookPayloadHash
    ) {
      await database.metaWebhookEnvelope.deleteMany({
        where: {
          payloadHash:
            webhookPayloadHash,
        },
      });
    }
  }
}

async function cleanupOutboundFixture():
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

  if (
    !organization
  ) {
    return;
  }

  const organizationId =
    organization.id;

  await database.auditLog.deleteMany({
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

  await database.metaWebhookEnvelope.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.whatsAppNumber.deleteMany({
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

async function verifyOutboundLeaseSafety():
Promise<void> {
  await cleanupOutboundFixture();

  const organization =
    await database.organization.create({
      data: {
        name:
          'Stage 12 Runtime',

        slug:
          organizationSlug,

        status:
          'ACTIVE',
      },
    });

  const number =
    await database.whatsAppNumber.create({
      data: {
        organizationId:
          organization.id,

        displayName:
          'Stage 12 Number',

        e164:
          `+1555${Date.now().toString().slice(-7)}`,

        status:
          'ACTIVE',
      },
    });

  const contact =
    await database.whatsAppContact.create({
      data: {
        organizationId:
          organization.id,

        waId:
          `551198${Date.now().toString().slice(-6)}`,

        profileName:
          'Stage 12 Contact',
      },
    });

  const conversation =
    await database.whatsAppConversation.create({
      data: {
        organizationId:
          organization.id,

        whatsAppNumberId:
          number.id,

        contactId:
          contact.id,

        status:
          'OPEN',

        lastMessageAt:
          new Date(),
      },
    });

  const expired =
    await database.whatsAppMessage.create({
      data: {
        organizationId:
          organization.id,

        conversationId:
          conversation.id,

        whatsAppNumberId:
          number.id,

        contactId:
          contact.id,

        direction:
          'OUTBOUND',

        type:
          'TEXT',

        status:
          'SENDING',

        clientMessageId: randomUUID(),

        textBody:
          'Do not resend me',

        content: {
          stage12:
            true,
        },

        attempts:
          1,

        availableAt:
          new Date(
            0,
          ),

        lastAttemptAt:
          new Date(
            Date.now() -
            60000,
          ),

        claimedAt:
          new Date(
            Date.now() -
            60000,
          ),

        claimedByWorkerId:
          'stage12-dead-worker',

        leaseExpiresAt:
          new Date(
            Date.now() -
            5000,
          ),
      },
    });

  const active =
    await database.whatsAppMessage.create({
      data: {
        organizationId:
          organization.id,

        conversationId:
          conversation.id,

        whatsAppNumberId:
          number.id,

        contactId:
          contact.id,

        direction:
          'OUTBOUND',

        type:
          'TEXT',

        status:
          'SENDING',

        clientMessageId: randomUUID(),

        textBody:
          'Active lease',

        content: {
          stage12:
            true,
        },

        attempts:
          1,

        availableAt:
          new Date(
            0,
          ),

        lastAttemptAt:
          new Date(),

        claimedAt:
          new Date(),

        claimedByWorkerId:
          'stage12-live-worker',

        leaseExpiresAt:
          new Date(
            Date.now() +
            60000,
          ),
      },
    });

  const dispatcher =
    new WhatsAppOutboundDispatcherService(
      database,
      `stage12-worker-${unique}`,
      outboundConfig,
      null,
    );

  const summary =
    await dispatcher.runTick();

  assert.equal(
    summary.claimed,
    0,
  );

  const expiredAfter =
    await database.whatsAppMessage.findUniqueOrThrow({
      where: {
        id:
          expired.id,
      },
    });

  assert.equal(
    expiredAfter.status,
    'FAILED',
  );

  assert.equal(
    expiredAfter.errorCode,
    'OUTBOUND_DELIVERY_UNKNOWN_AFTER_LEASE',
  );

  assert.equal(
    expiredAfter.claimedByWorkerId,
    null,
  );

  assert.equal(
    expiredAfter.leaseExpiresAt,
    null,
  );

  const activeAfter =
    await database.whatsAppMessage.findUniqueOrThrow({
      where: {
        id:
          active.id,
      },
    });

  assert.equal(
    activeAfter.status,
    'SENDING',
  );

  assert.equal(
    activeAfter.claimedByWorkerId,
    'stage12-live-worker',
  );

  const audit =
    await database.auditLog.findFirstOrThrow({
      where: {
        organizationId:
          organization.id,

        action:
          'whatsapp.outbound.delivery_unknown_after_lease',

        resourceId:
          expired.id,
      },
    });

  assert.equal(
    audit.outcome,
    'FAILURE',
  );

  log(
    'stage12.outbound_expired_lease_safety.passed',
  );

  await cleanupOutboundFixture();
}

async function main():
Promise<void> {
  log(
    'stage12.validation.started',
  );

  runProductionValidators();

  await verifyApiSecurity();

  await verifyWebhookSecurity();

  await verifyOutboundLeaseSafety();

  log(
    'stage12.validation.completed',
  );
}

try {
  await main();
}
finally {
  try {
    await cleanupOutboundFixture();
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
    -Path ".\apps\worker\scripts\stage12-security-runtime.ts" `
    -Content $RuntimeValidator

Write-Host "[OK] Stage 12 runtime security validator criado." -ForegroundColor Green

# ============================================================
# RUNBOOK
# ============================================================

$Runbook = @(
    "# Staging e Production Runbook",
    "",
    "## Objetivo",
    "",
    "Checklist operacional para publicar CRM ADS WhatsApp sem misturar credenciais, bancos ou callbacks entre ambientes.",
    "",
    "## Regra central",
    "",
    "Staging e production devem possuir configuracoes e credenciais independentes sempre que o provedor permitir.",
    "",
    "Nunca reutilizar banco de production em staging.",
    "",
    "Nunca versionar secrets.",
    "",
    "## API",
    "",
    "Required:",
    "",
    "- NODE_ENV=production",
    "- APP_ENV=staging ou production",
    "- DATABASE_URL",
    "- AUTH_ACCESS_TOKEN_SECRET",
    "- AUTH_REFRESH_TOKEN_PEPPER",
    "- API_CORS_ALLOWED_ORIGINS",
    "- HTTP_TRUST_PROXY_HOPS configurado para a topologia real",
    "",
    "AUTH_ACCESS_TOKEN_SECRET e AUTH_REFRESH_TOKEN_PEPPER devem ser diferentes.",
    "",
    "CORS em staging/producao aceita apenas origins HTTPS explicitas.",
    "",
    "Health:",
    "",
    "- /api/v1/health/live",
    "- /api/v1/health/ready",
    "",
    "## Meta webhook ingress",
    "",
    "Required:",
    "",
    "- NODE_ENV=production",
    "- APP_ENV=staging ou production",
    "- DATABASE_URL",
    "- META_APP_SECRET",
    "- META_WEBHOOK_VERIFY_TOKEN",
    "",
    "Health:",
    "",
    "- /health/live",
    "- /health/ready",
    "",
    "Callback Meta:",
    "",
    "- HTTPS obrigatorio",
    "- X-Hub-Signature-256 obrigatoria para POST",
    "- raw body preservado",
    "- payload limitado",
    "",
    "Nao usar um rate limit humano agressivo por IP no callback da Meta.",
    "",
    "## Worker",
    "",
    "Required:",
    "",
    "- NODE_ENV=production",
    "- APP_ENV=staging ou production",
    "- DATABASE_URL",
    "- META_GRAPH_API_VERSION",
    "- META_ACCESS_TOKEN",
    "- ONESIGNAL_APP_ID",
    "- ONESIGNAL_API_KEY",
    "",
    "Apenas uma configuracao de ambiente deve ser utilizada por processo.",
    "",
    "Nunca compartilhar DATABASE_URL de production com worker staging.",
    "",
    "## Site monitor worker",
    "",
    "Required:",
    "",
    "- NODE_ENV=production",
    "- APP_ENV=staging ou production",
    "- DATABASE_URL",
    "",
    "## Web",
    "",
    "Required em staging/producao:",
    "",
    "- NODE_ENV=production",
    "- APP_ENV=staging ou production",
    "- NEXT_PUBLIC_ONESIGNAL_APP_ID",
    "",
    "## PostgreSQL",
    "",
    "- nao expor credenciais no repositorio",
    "- staging e production separados",
    "- migrations executadas com prisma migrate deploy",
    "- nunca executar prisma migrate dev em production",
    "- backup habilitado no provedor",
    "- acesso publico desabilitado quando a plataforma permitir rede privada entre servicos",
    "",
    "## Seed",
    "",
    "Seed em staging/producao exige explicitamente:",
    "",
    "- SEED_ORGANIZATION_NAME",
    "- SEED_ORGANIZATION_SLUG",
    "- SEED_TEAM_NAME",
    "- SEED_TEAM_SLUG",
    "- SEED_ADMIN_EMAIL",
    "- SEED_ADMIN_NAME",
    "- SEED_ADMIN_EMPLOYEE_CODE",
    "",
    "admin@example.com e proibido em staging/producao.",
    "",
    "Seed deve ser uma operacao de release explicita, nunca um comando automatico em todo restart.",
    "",
    "## Edge / WAF",
    "",
    "A API possui rate limiting por processo como defense in depth.",
    "",
    "Em staging/producao deve existir tambem rate limiting distribuido no edge/WAF.",
    "",
    "Aplicar politica mais restritiva em login e refresh.",
    "",
    "Nao aplicar bloqueio agressivo de callback Meta baseado apenas em IP.",
    "",
    "TLS deve ser obrigatorio.",
    "",
    "## Outbound WhatsApp",
    "",
    "SENDING com lease expirado e outcome desconhecido nunca e reenviado automaticamente.",
    "",
    "O registro passa para FAILED / OUTBOUND_DELIVERY_UNKNOWN_AFTER_LEASE.",
    "",
    "Reconciliar manualmente antes de qualquer reenvio.",
    "",
    "## Deploy order",
    "",
    "1. Provisionar PostgreSQL staging.",
    "2. Configurar secrets staging.",
    "3. Executar validate-production-environment para cada servico.",
    "4. Executar prisma migrate deploy.",
    "5. Executar seed explicitamente com valores staging.",
    "6. Subir webhook ingress.",
    "7. Validar /health/live e /health/ready.",
    "8. Configurar callback Meta staging.",
    "9. Subir API.",
    "10. Validar API live/ready e CORS.",
    "11. Subir worker.",
    "12. Subir site monitor worker.",
    "13. Subir web quando a integracao frontend estiver pronta.",
    "14. Executar verify-deployed-services.mjs.",
    "15. Executar smoke funcional.",
    "",
    "## Remote verification",
    "",
    "Configure:",
    "",
    "DEPLOY_API_BASE_URL=https://...",
    "DEPLOY_WEBHOOK_BASE_URL=https://...",
    "",
    "Depois execute:",
    "",
    "node scripts/verify-deployed-services.mjs",
    "",
    "## Production promotion",
    "",
    "Somente promover depois de:",
    "",
    "- CI verde",
    "- pnpm audit sem high/critical",
    "- migrations up-to-date",
    "- staging smoke verde",
    "- webhook HMAC validado",
    "- health/readiness verde",
    "- secrets separados",
    "- rollback definido",
    "",
    "## Rollback",
    "",
    "Rollback de aplicacao deve preferir redeploy da ultima versao conhecida como boa.",
    "",
    "Nao reverter migration destrutivamente sem plano especifico.",
    "",
    "Mantenha migrations forward-compatible sempre que possivel.",
    "",
    "## CSP",
    "",
    "Content-Security-Policy final sera definida junto ao frontend real.",
    "",
    "Nao foi aplicada uma CSP ficticia agora porque OneSignal, assets e chamadas reais do frontend ainda precisam ser conhecidos."
)

Write-Lines `
    -Path ".\docs\STAGING_PRODUCTION_RUNBOOK.md" `
    -Lines $Runbook

# ============================================================
# STAGE 12 DECISIONS
# ============================================================

$DecisionDoc = @(
    "# Decisoes - Etapa 12",
    "",
    "HTTP security, provider security e infrastructure security sao camadas independentes.",
    "",
    "Helmet e security headers sao baseline, nao substituem WAF/TLS.",
    "",
    "CORS e allowlist explicita em staging/producao.",
    "",
    "Authentication permanece bearer-token based; CORS credentials permanece false.",
    "",
    "Login e refresh possuem throttling mais restritivo que a API geral.",
    "",
    "O throttler da aplicacao e process-local e serve como defense in depth.",
    "",
    "Rate limiting distribuido deve existir no edge quando houver mais de uma instancia.",
    "",
    "Meta webhook nao recebe o mesmo throttling agressivo de usuario humano.",
    "",
    "Autenticidade do callback Meta depende principalmente de HMAC sobre raw body.",
    "",
    "Payloads API e webhook possuem limites distintos.",
    "",
    "Request timeout e headers timeout sao explicitamente configurados.",
    "",
    "Trust proxy nunca e habilitado como boolean true; o numero de hops deve corresponder a topologia real.",
    "",
    "Staging e production usam NODE_ENV=production; APP_ENV diferencia os dois ambientes.",
    "",
    "Production-like boot e fail-closed quando secrets obrigatorios estao ausentes.",
    "",
    "Seed production-like nao aceita valores default ou admin@example.com.",
    "",
    "SENDING expirado sem wamid e tratado como outcome desconhecido.",
    "",
    "Automatic resend e proibido nesse estado para evitar duplicidade de mensagem ao cliente.",
    "",
    "CSP final foi adiada ate o frontend real para nao criar uma politica incorreta.",
    "",
    "CI bloqueia dependencias de producao com vulnerabilidades high ou critical.",
    "",
    "Deploy remoto nao e realizado pelo finalizador local.",
    "",
    "O repositorio gera runbook e verifier remoto; a ativacao do ambiente remoto ocorre como operacao de deploy antes do cutover."
)

Write-Lines `
    -Path ".\docs\DECISOES_ETAPA_12.md" `
    -Lines $DecisionDoc

# ============================================================
# FORMAT
# ============================================================

Invoke-Native `
    -Description "Format Stage 12" `
    -Command "pnpm" `
    -Arguments @("format")

# ============================================================
# DATABASE RELEASE CHECKS
# ============================================================

Invoke-Native `
    -Description "Prisma validate Stage 12" `
    -Command "pnpm" `
    -Arguments @("db:validate")

Invoke-Native `
    -Description "Prisma generate Stage 12" `
    -Command "pnpm" `
    -Arguments @("db:generate")

Invoke-Native `
    -Description "Migration status Stage 12" `
    -Command "pnpm" `
    -Arguments @("db:migrate:status")

Invoke-Native `
    -Description "Database health Stage 12" `
    -Command "pnpm" `
    -Arguments @("db:health")

Invoke-Native `
    -Description "Seed regression Stage 12" `
    -Command "pnpm" `
    -Arguments @("db:seed")

Invoke-Native `
    -Description "Verify seed Stage 12" `
    -Command "pnpm" `
    -Arguments @("db:verify-seed")

# ============================================================
# TARGETED SECURITY CHECKS
# ============================================================

Invoke-Native `
    -Description "Config lint Stage 12" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/config",
        "lint"
    )

Invoke-Native `
    -Description "Config typecheck Stage 12" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/config",
        "typecheck"
    )

Invoke-Native `
    -Description "Config security tests Stage 12" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/config",
        "test"
    )

Invoke-Native `
    -Description "Security package lint Stage 12" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/security",
        "lint"
    )

Invoke-Native `
    -Description "Security package typecheck Stage 12" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/security",
        "typecheck"
    )

Invoke-Native `
    -Description "Security package tests Stage 12" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/security",
        "test"
    )

Invoke-Native `
    -Description "API lint Stage 12" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/api",
        "lint"
    )

Invoke-Native `
    -Description "API typecheck Stage 12" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/api",
        "typecheck"
    )

Invoke-Native `
    -Description "API tests Stage 12" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/api",
        "test"
    )

Invoke-Native `
    -Description "Webhook lint Stage 12" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/webhook-ingress",
        "lint"
    )

Invoke-Native `
    -Description "Webhook typecheck Stage 12" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/webhook-ingress",
        "typecheck"
    )

Invoke-Native `
    -Description "Webhook tests Stage 12" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/webhook-ingress",
        "test"
    )

Invoke-Native `
    -Description "Worker lint Stage 12" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/worker",
        "lint"
    )

Invoke-Native `
    -Description "Worker typecheck Stage 12" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/worker",
        "typecheck"
    )

Invoke-Native `
    -Description "Worker tests Stage 12" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/worker",
        "test"
    )

Invoke-Native `
    -Description "Site monitor lint Stage 12" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/site-monitor-worker",
        "lint"
    )

Invoke-Native `
    -Description "Site monitor typecheck Stage 12" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/site-monitor-worker",
        "typecheck"
    )

Invoke-Native `
    -Description "Site monitor tests Stage 12" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/site-monitor-worker",
        "test"
    )

# ============================================================
# PRODUCTION DEPENDENCY AUDIT
# ============================================================

Invoke-Native `
    -Description "Production dependency security audit" `
    -Command "pnpm" `
    -Arguments @(
        "audit",
        "--prod",
        "--audit-level=high"
    )

# ============================================================
# STRUCTURE + COMPLETE BUILD
# ============================================================

Invoke-Native `
    -Description "Workspace structure Stage 12" `
    -Command "pnpm" `
    -Arguments @("structure:check")

Invoke-Native `
    -Description "Complete monorepo build Stage 12" `
    -Command "pnpm" `
    -Arguments @("build")

# ============================================================
# RUNTIME SECURITY VALIDATION
# ============================================================

Write-Host ""
Write-Host "==== Stage 12 runtime security validation ====" -ForegroundColor Cyan

& pnpm `
    --filter `
    "@crm/worker" `
    exec `
    tsx `
    "scripts/stage12-security-runtime.ts"

if ($LASTEXITCODE -ne 0) {
    throw "Stage 12 runtime security validation falhou."
}

Write-Host "[OK] Stage 12 runtime security validation." -ForegroundColor Green

# ============================================================
# GLOBAL CI
# ============================================================

Invoke-Native `
    -Description "Global CI Stage 12" `
    -Command "pnpm" `
    -Arguments @("ci:check")

# ============================================================
# COMPLETE STAGE 12 DOCUMENTATION
# ============================================================

$Stage12Doc = @(
    "# Etapa 12 - Security Hardening, Staging e Production Readiness",
    "",
    "## Status",
    "",
    "CONCLUIDA NO REPOSITORIO.",
    "",
    "O codigo, validadores e runbook para staging/producao estao prontos.",
    "",
    "A ativacao de infraestrutura remota e uma operacao de deploy e deve usar docs/STAGING_PRODUCTION_RUNBOOK.md antes do cutover.",
    "",
    "## API security",
    "",
    "- Helmet",
    "- explicit HTTPS CORS allowlist em production-like",
    "- global process-local throttling",
    "- stricter login throttling",
    "- stricter refresh throttling",
    "- explicit body limit",
    "- request timeout",
    "- headers timeout",
    "- keep-alive timeout",
    "- max incoming headers count",
    "- explicit trusted proxy hops",
    "- no-store",
    "- noindex/nofollow",
    "- fail-closed production environment validation",
    "",
    "## Webhook security",
    "",
    "- raw body preserved",
    "- HMAC X-Hub-Signature-256 mandatory",
    "- explicit body size limit",
    "- Helmet",
    "- no-store",
    "- noindex/nofollow",
    "- HTTP timeouts",
    "- liveness",
    "- database readiness",
    "- fail-closed Meta secrets",
    "",
    "## Authentication",
    "",
    "- existing password hashing preserved",
    "- failed-login lock preserved",
    "- access token secret validation preserved",
    "- opaque refresh token preserved",
    "- refresh token hash preserved",
    "- refresh token family rotation preserved",
    "- reuse detection preserved",
    "- live session lookup preserved",
    "- login and refresh throttling added",
    "",
    "## Outbound safety",
    "",
    "Expired SENDING without Meta message id is never automatically reclaimed.",
    "",
    "It transitions to FAILED with OUTBOUND_DELIVERY_UNKNOWN_AFTER_LEASE.",
    "",
    "The transition generates an audit event.",
    "",
    "This prevents blind duplicate customer messages after crash/lost lease.",
    "",
    "## Environment hardening",
    "",
    "APP_ENV differentiates development/test/staging/production.",
    "",
    "Staging and production require NODE_ENV=production.",
    "",
    "Server-side PostgreSQL cannot point to localhost in production-like environments.",
    "",
    "API CORS requires explicit HTTPS origins.",
    "",
    "Service-specific provider secrets are validated before production-like boot.",
    "",
    "## Seed hardening",
    "",
    "Production-like seed requires explicit organization/team/admin values.",
    "",
    "admin@example.com is rejected.",
    "",
    "## Web security",
    "",
    "- poweredByHeader disabled",
    "- X-Content-Type-Options",
    "- X-Frame-Options",
    "- Referrer-Policy",
    "- Permissions-Policy",
    "- X-Robots-Tag",
    "- HSTS in staging/production",
    "- production-like OneSignal public app id validation",
    "",
    "CSP final is intentionally deferred until the real frontend integration exists.",
    "",
    "## Supply-chain security",
    "",
    "CI executes pnpm audit against production dependencies and blocks high/critical advisories.",
    "",
    "Existing pnpm lockfile supply-chain policies remain active.",
    "",
    "## Runtime validation",
    "",
    "Validated:",
    "",
    "- production environment validators",
    "- API process boot",
    "- API liveness",
    "- API database readiness",
    "- Helmet headers",
    "- no-store",
    "- CORS allowed origin",
    "- CORS denied origin",
    "- API oversized payload -> 413",
    "- login throttling -> 429",
    "- webhook process boot",
    "- webhook liveness",
    "- webhook database readiness",
    "- Meta verification token",
    "- invalid Meta signature -> 401",
    "- valid Meta HMAC",
    "- webhook oversized payload -> 413",
    "- no arbitrary webhook CORS",
    "- expired SENDING -> FAILED",
    "- no automatic resend",
    "- active SENDING lease preserved",
    "- outbound unknown-outcome audit",
    "- dependency audit",
    "- complete monorepo build",
    "- global CI",
    "- secret scan",
    "- git checks",
    "",
    "## Deployment",
    "",
    "Use docs/STAGING_PRODUCTION_RUNBOOK.md.",
    "",
    "After remote staging is provisioned, run scripts/verify-deployed-services.mjs.",
    "",
    "## Proxima etapa",
    "",
    "Etapa 13 - Cutover, release e substituicao controlada dos sistemas antigos."
)

Write-Lines `
    -Path ".\docs\ETAPA_12_SECURITY_HARDENING.md" `
    -Lines $Stage12Doc

$EtapasPath =
    ".\docs\ETAPAS.md"

if (Test-Path $EtapasPath) {
    $Etapas =
        Read-Text -Path $EtapasPath

    for (
        $Stage =
            1;
        $Stage -le
            12;
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

    if ($Etapas.Contains("## Etapa 12 - Security")) {
        $Etapas =
            [regex]::Replace(
                $Etapas,
                '(?s)## Etapa 12 - Security.*?(?=## Etapa 13|\z)',
                @'
## Etapa 12 - Security Hardening, Staging e Production Readiness

Status: CONCLUIDA.

Implementado:

- HTTP security
- Helmet
- strict CORS
- API throttling
- auth throttling
- request size limits
- request/header timeouts
- trusted proxy policy
- API readiness
- webhook readiness
- Meta HMAC protection
- production environment fail-closed
- production seed fail-closed
- outbound unknown-outcome safety
- Next.js baseline headers
- dependency audit
- remote deployment verifier
- staging/production runbook

Documentacao:

- docs/ETAPA_12_SECURITY_HARDENING.md
- docs/DECISOES_ETAPA_12.md
- docs/STAGING_PRODUCTION_RUNBOOK.md

Proxima: Etapa 13 - Cutover, release e substituicao controlada.

'@
            )
    }
    else {
        $Etapas =
            $Etapas.TrimEnd() +
            "`r`n`r`n" +
            "## Etapa 12 - Security Hardening, Staging e Production Readiness`r`n`r`n" +
            "Status: CONCLUIDA.`r`n`r`n" +
            "Documentacao: docs/ETAPA_12_SECURITY_HARDENING.md, docs/DECISOES_ETAPA_12.md e docs/STAGING_PRODUCTION_RUNBOOK.md.`r`n`r`n" +
            "Proxima: Etapa 13 - Cutover, release e substituicao controlada.`r`n"
    }

    Write-Text `
        -Path $EtapasPath `
        -Content $Etapas
}

# ============================================================
# FINAL FORMAT + CI AFTER DOCS
# ============================================================

Invoke-Native `
    -Description "Final format Stage 12" `
    -Command "pnpm" `
    -Arguments @("format")

Invoke-Native `
    -Description "Final format check Stage 12" `
    -Command "pnpm" `
    -Arguments @("format:check")

Invoke-Native `
    -Description "Final global CI Stage 12" `
    -Command "pnpm" `
    -Arguments @("ci:check")

# ============================================================
# STRUCTURAL SECURITY AUDIT
# ============================================================

Write-Host ""
Write-Host "==== Stage 12 structural security audit ====" -ForegroundColor Cyan

$ApiMain =
    Read-Text -Path ".\apps\api\src\main.ts"

$WebhookMain =
    Read-Text -Path ".\apps\webhook-ingress\src\main.ts"

$Outbound =
    Read-Text -Path ".\apps\worker\src\whatsapp-outbound-dispatcher.service.ts"

$Seed =
    Read-Text -Path ".\packages\database\prisma\seed.ts"

$Ci =
    Read-Text -Path ".\.github\workflows\ci.yml"

$Next =
    Read-Text -Path ".\apps\web\next.config.ts"

$ProductionReadiness =
    Read-Text -Path ".\packages\config\src\production-readiness.ts"

foreach ($Marker in @(
    "helmet(",
    "enableCors",
    "apiBodyLimitBytes",
    "requestTimeout",
    "headersTimeout",
    "keepAliveTimeout",
    "maxHeadersCount",
    "trust proxy",
    "assertServiceProductionReadiness"
)) {
    if (-not $ApiMain.Contains($Marker)) {
        throw "API security invariant ausente: $Marker"
    }
}

foreach ($Marker in @(
    "rawBody:",
    "helmet(",
    "webhookBodyLimitBytes",
    "requestTimeout",
    "headersTimeout",
    "assertServiceProductionReadiness"
)) {
    if (-not $WebhookMain.Contains($Marker)) {
        throw "Webhook security invariant ausente: $Marker"
    }
}

foreach ($Marker in @(
    "failExpiredSendingMessages",
    "OUTBOUND_DELIVERY_UNKNOWN_AFTER_LEASE",
    "automaticResendBlocked",
    "whatsapp.outbound.delivery_unknown_after_lease"
)) {
    if (-not $Outbound.Contains($Marker)) {
        throw "Outbound safety invariant ausente: $Marker"
    }
}

$UnsafeClaimPattern =
    'AND\s*\(\s*\(\s*"status"\s*=\s*''QUEUED''\s*AND\s*"availableAt"\s*<=\s*NOW\(\)\s*\)\s*OR\s*\(\s*"status"\s*=\s*''SENDING''\s*AND\s*"leaseExpiresAt"\s*IS\s*NOT\s*NULL\s*AND\s*"leaseExpiresAt"\s*<=\s*NOW\(\)\s*AND\s*"metaMessageId"\s*IS\s*NULL\s*\)\s*\)'

if ([regex]::IsMatch($Outbound, $UnsafeClaimPattern)) {
    throw "Unsafe expired SENDING auto-claim ainda presente."
}

if (-not $Seed.Contains("PRODUCTION_SEED_CONFIGURATION_REQUIRED")) {
    throw "Production seed guard ausente."
}

foreach ($Marker in @(
    "pnpm audit --prod --audit-level=high",
    "Run complete verification"
)) {
    if (-not $Ci.Contains($Marker)) {
        throw "CI security invariant ausente: $Marker"
    }
}

foreach ($Marker in @(
    "X-Content-Type-Options",
    "X-Frame-Options",
    "Referrer-Policy",
    "Permissions-Policy",
    "Strict-Transport-Security",
    "NEXT_PUBLIC_ONESIGNAL_APP_ID"
)) {
    if (-not $Next.Contains($Marker)) {
        throw "Web security invariant ausente: $Marker"
    }
}

foreach ($Marker in @(
    "AUTH_ACCESS_TOKEN_SECRET",
    "AUTH_REFRESH_TOKEN_PEPPER",
    "META_APP_SECRET",
    "META_WEBHOOK_VERIFY_TOKEN",
    "META_ACCESS_TOKEN",
    "ONESIGNAL_API_KEY"
)) {
    if (-not $ProductionReadiness.Contains($Marker)) {
        throw "Production secret validation ausente: $Marker"
    }
}

Write-Host "[OK] Stage 12 structural security audit." -ForegroundColor Green

# ============================================================
# TRACKED ENV CHECK
# ============================================================

[string[]]$TrackedFiles = @(
    & git ls-files
)

if ($LASTEXITCODE -ne 0) {
    throw "git ls-files falhou."
}

[string[]]$TrackedRealEnv = @(
    $TrackedFiles |
    Where-Object {
        $_ -match '(^|/)\.env($|\.)' -and
        $_ -notmatch '\.env\.example$'
    }
)

if (@($TrackedRealEnv).Count -gt 0) {
    $TrackedRealEnv
    throw "Arquivo .env real versionado."
}

Write-Host "[OK] Nenhum .env real versionado." -ForegroundColor Green

# ============================================================
# SECRET SCAN INCLUDING UNTRACKED STAGE FILES
# ============================================================

Write-Host ""
Write-Host "==== Stage 12 secret scan ====" -ForegroundColor Cyan

[string[]]$CandidateFiles = @(
    & git ls-files --cached --others --exclude-standard
)

if ($LASTEXITCODE -ne 0) {
    throw "git ls-files para secret scan falhou."
}

$TextExtensions = @(
    ".ts",
    ".tsx",
    ".js",
    ".mjs",
    ".cjs",
    ".json",
    ".md",
    ".yml",
    ".yaml",
    ".ps1",
    ".css",
    ".html",
    ".txt"
)

$SecretRegex =
    [regex]::new(
        '(sk-proj-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN (RSA|OPENSSH|EC) PRIVATE KEY-----|EAA[A-Za-z0-9]{30,}|os_v2_app_[A-Za-z0-9_-]{20,})',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

$SecretFindings =
    New-Object System.Collections.Generic.List[string]

foreach ($File in $CandidateFiles) {
    if (-not (Test-Path $File -PathType Leaf)) {
        continue
    }

    $Extension =
        [System.IO.Path]::GetExtension(
            $File
        ).ToLowerInvariant()

    $Leaf =
        [System.IO.Path]::GetFileName(
            $File
        )

    $TextCandidate =
        $TextExtensions -contains $Extension -or
        $Leaf -in @(
            ".env.example",
            ".gitignore",
            ".npmrc",
            ".nvmrc",
            ".node-version"
        )

    if (-not $TextCandidate) {
        continue
    }

    $Info =
        Get-Item $File

    if ($Info.Length -gt 5MB) {
        continue
    }

    $Content =
        [System.IO.File]::ReadAllText(
            $Info.FullName
        )

    if ($SecretRegex.IsMatch($Content)) {
        $SecretFindings.Add($File)
    }
}

if ($SecretFindings.Count -gt 0) {
    $SecretFindings
    throw "Possivel segredo real encontrado em arquivo do workspace."
}

Write-Host "[OK] Secret scan incluindo arquivos novos." -ForegroundColor Green

# ============================================================
# NEXT_PUBLIC SECRET BOUNDARY
# ============================================================

[string[]]$PublicSecretMatches = @(
    & git grep `
        --cached `
        -n `
        -I `
        -E `
        'NEXT_PUBLIC_(META_ACCESS_TOKEN|META_APP_SECRET|META_WEBHOOK_VERIFY_TOKEN|ONESIGNAL_API_KEY|AUTH_ACCESS_TOKEN_SECRET|AUTH_REFRESH_TOKEN_PEPPER)' `
        2>$null
)

$PublicSecretExitCode =
    $LASTEXITCODE

if (
    $PublicSecretExitCode -ne 0 -and
    $PublicSecretExitCode -ne 1
) {
    throw "NEXT_PUBLIC secret boundary scan falhou."
}

if (@($PublicSecretMatches).Count -gt 0) {
    $PublicSecretMatches
    throw "Server-side secret exposto via NEXT_PUBLIC_."
}

Write-Host "[OK] NEXT_PUBLIC secret boundary." -ForegroundColor Green

# ============================================================
# GIT DIFF
# ============================================================

& git diff --check

if ($LASTEXITCODE -ne 0) {
    throw "git diff --check falhou."
}

Write-Host "[OK] git diff --check." -ForegroundColor Green

# ============================================================
# CLEAN BACKUPS
# ============================================================

Remove-Item `
    ".\tmp\stage12-macroblock1-backup" `
    -Recurse `
    -Force `
    -ErrorAction SilentlyContinue

Remove-Item `
    $BackupRoot `
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
Write-Host "[OK] ETAPA 12 COMPLETAMENTE VALIDADA." -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Validado:" -ForegroundColor Cyan
Write-Host "- Helmet API"
Write-Host "- Helmet webhook"
Write-Host "- strict CORS allowlist"
Write-Host "- login rate limit"
Write-Host "- refresh rate limit"
Write-Host "- API global rate limit"
Write-Host "- API payload limit"
Write-Host "- webhook payload limit"
Write-Host "- request timeout"
Write-Host "- headers timeout"
Write-Host "- keep-alive timeout"
Write-Host "- max headers count"
Write-Host "- trusted proxy policy"
Write-Host "- API liveness/readiness"
Write-Host "- webhook liveness/readiness"
Write-Host "- Meta verification challenge"
Write-Host "- invalid HMAC rejection"
Write-Host "- valid Meta HMAC"
Write-Host "- production environment fail-closed"
Write-Host "- production seed fail-closed"
Write-Host "- server-side secret validation"
Write-Host "- NEXT_PUBLIC secret boundary"
Write-Host "- expired SENDING no-resend"
Write-Host "- outbound unknown delivery audit"
Write-Host "- active outbound lease preserved"
Write-Host "- Next security headers"
Write-Host "- production dependency audit"
Write-Host "- complete monorepo build"
Write-Host "- global CI"
Write-Host "- staging/production runbook"
Write-Host "- remote deployment verifier"
Write-Host "- secret scan including new files"
Write-Host "- git checks"
Write-Host ""
Write-Host "[READY] Repositorio pronto para provisionamento remoto de staging." -ForegroundColor Green
Write-Host "Proxima etapa: ETAPA 13 - CUTOVER E RELEASE CONTROLADO." -ForegroundColor Yellow