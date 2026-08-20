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
Write-Host " ETAPA 12 - MACROBLOCO 12.1" -ForegroundColor Cyan
Write-Host " SECURITY HARDENING + PRODUCTION FOUNDATION" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

# ============================================================
# PREFLIGHT
# ============================================================

$RequiredFiles = @(
    ".\package.json",
    ".\.env.example",
    ".\packages\config\src\index.ts",
    ".\packages\config\src\auth.ts",
    ".\apps\api\src\main.ts",
    ".\apps\api\src\app.module.ts",
    ".\apps\api\src\auth\auth.controller.ts",
    ".\apps\api\src\health.controller.ts",
    ".\apps\webhook-ingress\src\main.ts",
    ".\apps\webhook-ingress\src\health.controller.ts",
    ".\apps\webhook-ingress\src\database.service.ts",
    ".\apps\webhook-ingress\src\meta-webhook.controller.ts",
    ".\apps\worker\src\main.ts",
    ".\apps\worker\src\whatsapp-outbound-dispatcher.service.ts",
    ".\apps\site-monitor-worker\src\main.ts",
    ".\apps\web\next.config.ts"
)

foreach ($File in $RequiredFiles) {
    if (-not (Test-Path $File)) {
        throw "Arquivo necessario ausente: $File"
    }
}

Write-Host "[OK] Preflight Stage 12." -ForegroundColor Green

# ============================================================
# BACKUP
# ============================================================

$BackupRoot =
    ".\tmp\stage12-macroblock1-backup"

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
    ".\pnpm-lock.yaml",
    ".\.env.example",
    ".\packages\config\src\index.ts",
    ".\apps\api\package.json",
    ".\apps\api\src\main.ts",
    ".\apps\api\src\app.module.ts",
    ".\apps\api\src\auth\auth.controller.ts",
    ".\apps\webhook-ingress\package.json",
    ".\apps\webhook-ingress\src\main.ts",
    ".\apps\webhook-ingress\src\health.controller.ts",
    ".\apps\webhook-ingress\src\database.service.ts",
    ".\apps\worker\package.json",
    ".\apps\worker\src\main.ts",
    ".\apps\worker\src\whatsapp-outbound-dispatcher.service.ts",
    ".\apps\site-monitor-worker\package.json",
    ".\apps\site-monitor-worker\src\main.ts",
    ".\apps\web\next.config.ts",
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

Write-Host "[OK] Backup Stage 12 preparado." -ForegroundColor Green

# ============================================================
# SECURITY DEPENDENCIES
# ============================================================

Invoke-Native `
    -Description "Install API security dependencies" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/api",
        "add",
        "helmet@8.3.0",
        "@nestjs/throttler@6.5.0"
    )

Invoke-Native `
    -Description "Install webhook security dependencies" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/webhook-ingress",
        "add",
        "helmet@8.3.0",
        "@crm/config@workspace:*"
    )

Invoke-Native `
    -Description "Add config dependency to worker" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/worker",
        "add",
        "@crm/config@workspace:*"
    )

Invoke-Native `
    -Description "Add config dependency to site monitor worker" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/site-monitor-worker",
        "add",
        "@crm/config@workspace:*"
    )

# ============================================================
# SHARED HTTP SECURITY CONFIG
# ============================================================

$HttpSecurity = @'
import {
  z,
} from 'zod';

const rawHttpSecurityEnvironmentSchema =
  z.object({
    APP_ENV:
      z
        .enum([
          'development',
          'test',
          'staging',
          'production',
        ])
        .default(
          'development',
        ),

    API_CORS_ALLOWED_ORIGINS:
      z
        .string()
        .default(
          '',
        ),

    HTTP_TRUST_PROXY_HOPS:
      z.coerce
        .number()
        .int()
        .min(0)
        .max(5)
        .default(0),

    API_BODY_LIMIT_BYTES:
      z.coerce
        .number()
        .int()
        .min(1024)
        .max(
          5 *
            1024 *
            1024,
        )
        .default(
          256 *
            1024,
        ),

    WEBHOOK_BODY_LIMIT_BYTES:
      z.coerce
        .number()
        .int()
        .min(1024)
        .max(
          10 *
            1024 *
            1024,
        )
        .default(
          1024 *
            1024,
        ),

    HTTP_REQUEST_TIMEOUT_MS:
      z.coerce
        .number()
        .int()
        .min(5000)
        .max(120000)
        .default(30000),

    HTTP_HEADERS_TIMEOUT_MS:
      z.coerce
        .number()
        .int()
        .min(5000)
        .max(60000)
        .default(15000),

    HTTP_KEEP_ALIVE_TIMEOUT_MS:
      z.coerce
        .number()
        .int()
        .min(1000)
        .max(120000)
        .default(5000),

    HTTP_MAX_HEADERS_COUNT:
      z.coerce
        .number()
        .int()
        .min(20)
        .max(500)
        .default(100),

    API_RATE_LIMIT_TTL_MS:
      z.coerce
        .number()
        .int()
        .min(1000)
        .max(3600000)
        .default(60000),

    API_RATE_LIMIT_DEFAULT:
      z.coerce
        .number()
        .int()
        .min(10)
        .max(10000)
        .default(300),

    AUTH_LOGIN_RATE_LIMIT:
      z.coerce
        .number()
        .int()
        .min(1)
        .max(100)
        .default(10),

    AUTH_REFRESH_RATE_LIMIT:
      z.coerce
        .number()
        .int()
        .min(1)
        .max(500)
        .default(30),
  });

export type HttpSecurityEnvironment =
  Readonly<{
    appEnvironment:
      'development' |
      'test' |
      'staging' |
      'production';

    corsAllowedOrigins:
      readonly string[];

    trustProxyHops:
      number;

    apiBodyLimitBytes:
      number;

    webhookBodyLimitBytes:
      number;

    requestTimeoutMs:
      number;

    headersTimeoutMs:
      number;

    keepAliveTimeoutMs:
      number;

    maxHeadersCount:
      number;

    apiRateLimitTtlMs:
      number;

    apiRateLimitDefault:
      number;

    authLoginRateLimit:
      number;

    authRefreshRateLimit:
      number;
  }>;

function parseOrigins(
  raw:
    string,

  productionLike:
    boolean,
): readonly string[] {
  const values =
    raw
      .split(',')
      .map(
        (
          item,
        ) =>
          item.trim(),
      )
      .filter(
        Boolean,
      );

  const effective =
    values.length >
    0
      ? values
      : productionLike
        ? []
        : [
            'http://localhost:3000',
            'http://127.0.0.1:3000',
          ];

  if (
    productionLike &&
    effective.length ===
      0
  ) {
    throw new Error(
      'API_CORS_ALLOWED_ORIGINS is required in staging and production.',
    );
  }

  const normalized =
    effective.map(
      (
        value,
      ) => {
        const url =
          new URL(
            value,
          );

        if (
          url.origin !==
          value
        ) {
          throw new Error(
            `CORS origin must not contain path/query/hash: ${value}`,
          );
        }

        if (
          productionLike &&
          url.protocol !==
            'https:'
        ) {
          throw new Error(
            `CORS origin must use HTTPS in staging/production: ${value}`,
          );
        }

        return url.origin;
      },
    );

  return Array.from(
    new Set(
      normalized,
    ),
  );
}

export function parseHttpSecurityEnvironment(
  environment:
    NodeJS.ProcessEnv =
      process.env,
): HttpSecurityEnvironment {
  const fallbackAppEnvironment =
    environment.NODE_ENV ===
    'test'
      ? 'test'
      : environment.NODE_ENV ===
          'production'
        ? 'production'
        : 'development';

  const parsed =
    rawHttpSecurityEnvironmentSchema.parse({
      ...environment,

      APP_ENV:
        environment.APP_ENV?.trim() ||
        fallbackAppEnvironment,
    });

  const productionLike =
    parsed.APP_ENV ===
      'staging' ||
    parsed.APP_ENV ===
      'production';

  if (
    parsed.HTTP_HEADERS_TIMEOUT_MS >
    parsed.HTTP_REQUEST_TIMEOUT_MS
  ) {
    throw new Error(
      'HTTP_HEADERS_TIMEOUT_MS must be <= HTTP_REQUEST_TIMEOUT_MS.',
    );
  }

  return {
    appEnvironment:
      parsed.APP_ENV,

    corsAllowedOrigins:
      parseOrigins(
        parsed.API_CORS_ALLOWED_ORIGINS,
        productionLike,
      ),

    trustProxyHops:
      parsed.HTTP_TRUST_PROXY_HOPS,

    apiBodyLimitBytes:
      parsed.API_BODY_LIMIT_BYTES,

    webhookBodyLimitBytes:
      parsed.WEBHOOK_BODY_LIMIT_BYTES,

    requestTimeoutMs:
      parsed.HTTP_REQUEST_TIMEOUT_MS,

    headersTimeoutMs:
      parsed.HTTP_HEADERS_TIMEOUT_MS,

    keepAliveTimeoutMs:
      parsed.HTTP_KEEP_ALIVE_TIMEOUT_MS,

    maxHeadersCount:
      parsed.HTTP_MAX_HEADERS_COUNT,

    apiRateLimitTtlMs:
      parsed.API_RATE_LIMIT_TTL_MS,

    apiRateLimitDefault:
      parsed.API_RATE_LIMIT_DEFAULT,

    authLoginRateLimit:
      parsed.AUTH_LOGIN_RATE_LIMIT,

    authRefreshRateLimit:
      parsed.AUTH_REFRESH_RATE_LIMIT,
  };
}
'@

Write-Text `
    -Path ".\packages\config\src\http-security.ts" `
    -Content $HttpSecurity

# ============================================================
# PRODUCTION READINESS
# ============================================================

$ProductionReadiness = @'
import {
  parseAuthEnvironment,
} from './auth.js';

import {
  parseHttpSecurityEnvironment,
} from './http-security.js';

export type ProductionService =
  | 'api'
  | 'webhook-ingress'
  | 'worker'
  | 'site-monitor-worker'
  | 'web';

function required(
  environment:
    NodeJS.ProcessEnv,

  name:
    string,

  minimumLength:
    number = 1,
): string {
  const value =
    environment[name]?.trim();

  if (
    !value ||
    value.length <
      minimumLength
  ) {
    throw new Error(
      `${name} is required for staging/production.`,
    );
  }

  const lowered =
    value.toLowerCase();

  if (
    lowered.includes(
      'change_me',
    ) ||
    lowered.includes(
      'placeholder',
    ) ||
    lowered.includes(
      'example-secret',
    ) ||
    lowered ===
      'test'
  ) {
    throw new Error(
      `${name} contains a placeholder value.`,
    );
  }

  return value;
}

function requireDatabaseUrl(
  environment:
    NodeJS.ProcessEnv,
): void {
  const raw =
    required(
      environment,
      'DATABASE_URL',
      10,
    );

  const url =
    new URL(
      raw,
    );

  if (
    url.protocol !==
      'postgresql:' &&
    url.protocol !==
      'postgres:'
  ) {
    throw new Error(
      'DATABASE_URL must use PostgreSQL.',
    );
  }

  if (
    url.hostname ===
      'localhost' ||
    url.hostname ===
      '127.0.0.1'
  ) {
    throw new Error(
      'DATABASE_URL cannot use localhost in staging/production.',
    );
  }
}

function assertGraphVersion(
  environment:
    NodeJS.ProcessEnv,
): void {
  const version =
    required(
      environment,
      'META_GRAPH_API_VERSION',
    );

  if (
    !/^v\d+\.\d+$/.test(
      version,
    )
  ) {
    throw new Error(
      'META_GRAPH_API_VERSION must look like vXX.X.',
    );
  }
}

export function assertServiceProductionReadiness(
  service:
    ProductionService,

  environment:
    NodeJS.ProcessEnv =
      process.env,
): void {
  const http =
    parseHttpSecurityEnvironment(
      environment,
    );

  const productionLike =
    http.appEnvironment ===
      'staging' ||
    http.appEnvironment ===
      'production';

  if (
    !productionLike
  ) {
    return;
  }

  if (
    environment.NODE_ENV !==
      'production'
  ) {
    throw new Error(
      'NODE_ENV must be production when APP_ENV is staging or production.',
    );
  }

  if (
    service !==
    'web'
  ) {
    requireDatabaseUrl(
      environment,
    );
  }

  if (
    service ===
    'api'
  ) {
    const auth =
      parseAuthEnvironment(
        environment,
      );

    if (
      auth.AUTH_ACCESS_TOKEN_SECRET ===
      auth.AUTH_REFRESH_TOKEN_PEPPER
    ) {
      throw new Error(
        'AUTH_ACCESS_TOKEN_SECRET and AUTH_REFRESH_TOKEN_PEPPER must be different.',
      );
    }

    if (
      http.corsAllowedOrigins.length ===
      0
    ) {
      throw new Error(
        'API requires at least one CORS origin.',
      );
    }
  }

  if (
    service ===
    'webhook-ingress'
  ) {
    required(
      environment,
      'META_APP_SECRET',
      32,
    );

    required(
      environment,
      'META_WEBHOOK_VERIFY_TOKEN',
      16,
    );
  }

  if (
    service ===
    'worker'
  ) {
    assertGraphVersion(
      environment,
    );

    required(
      environment,
      'META_ACCESS_TOKEN',
      20,
    );

    required(
      environment,
      'ONESIGNAL_APP_ID',
      8,
    );

    required(
      environment,
      'ONESIGNAL_API_KEY',
      20,
    );
  }

  if (
    service ===
    'web'
  ) {
    required(
      environment,
      'NEXT_PUBLIC_ONESIGNAL_APP_ID',
      8,
    );
  }
}
'@

Write-Text `
    -Path ".\packages\config\src\production-readiness.ts" `
    -Content $ProductionReadiness

$ConfigIndexPath =
    ".\packages\config\src\index.ts"

$ConfigIndex =
    Read-Text -Path $ConfigIndexPath

foreach ($Export in @(
    "export { parseHttpSecurityEnvironment, type HttpSecurityEnvironment } from './http-security.js';",
    "export { assertServiceProductionReadiness, type ProductionService } from './production-readiness.js';"
)) {
    if (-not $ConfigIndex.Contains($Export)) {
        $ConfigIndex =
            $ConfigIndex.TrimEnd() +
            "`r`n" +
            $Export +
            "`r`n"
    }
}

Write-Text `
    -Path $ConfigIndexPath `
    -Content $ConfigIndex

# ============================================================
# CONFIG TESTS
# ============================================================

$ConfigTest = @'
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

describe(
  'Stage 12 HTTP security configuration',
  () => {
    it(
      'uses safe local origins in development',
      () => {
        const config =
          parseHttpSecurityEnvironment({
            NODE_ENV:
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
      'rejects HTTP CORS in production',
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
      'does not require production secrets in development',
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
    -Content $ConfigTest

Write-Host "[OK] Shared security configuration criada." -ForegroundColor Green

# ============================================================
# API SECURITY MODULE
# ============================================================

$ApiSecurityModule = @'
import {
  Module,
} from '@nestjs/common';

import {
  APP_GUARD,
} from '@nestjs/core';

import {
  ThrottlerGuard,
  ThrottlerModule,
} from '@nestjs/throttler';

import {
  parseHttpSecurityEnvironment,
} from '@crm/config';

const security =
  parseHttpSecurityEnvironment();

@Module({
  imports: [
    ThrottlerModule.forRoot([
      {
        name:
          'default',

        ttl:
          security.apiRateLimitTtlMs,

        limit:
          security.apiRateLimitDefault,
      },
    ]),
  ],

  providers: [
    {
      provide:
        APP_GUARD,

      useClass:
        ThrottlerGuard,
    },
  ],
})
export class SecurityModule {}
'@

Write-Text `
    -Path ".\apps\api\src\security\security.module.ts" `
    -Content $ApiSecurityModule

# ============================================================
# API MAIN HARDENING
# ============================================================

$ApiMain = @'
import './load-environment.js';
import 'reflect-metadata';

import type {
  Server,
} from 'node:http';

import helmet from 'helmet';

import {
  NestFactory,
} from '@nestjs/core';

import type {
  NestExpressApplication,
} from '@nestjs/platform-express';

import {
  assertServiceProductionReadiness,
  parseHttpSecurityEnvironment,
} from '@crm/config';

import {
  AppModule,
} from './app.module.js';

type HeaderResponse =
  Readonly<{
    setHeader(
      name:
        string,

      value:
        string,
    ): void;
  }>;

async function bootstrap():
Promise<void> {
  assertServiceProductionReadiness(
    'api',
  );

  const security =
    parseHttpSecurityEnvironment();

  const productionLike =
    security.appEnvironment ===
      'staging' ||
    security.appEnvironment ===
      'production';

  const app =
    await NestFactory.create<NestExpressApplication>(
      AppModule,
      {
        abortOnError:
          true,
      },
    );

  app.set(
    'trust proxy',
    security.trustProxyHops,
  );

  app.use(
    helmet({
      contentSecurityPolicy:
        false,

      crossOriginEmbedderPolicy:
        false,

      strictTransportSecurity:
        productionLike
          ? {
              maxAge:
                31536000,

              includeSubDomains:
                true,
            }
          : false,
    }),
  );

  app.use(
    (
      _request:
        unknown,

      response:
        HeaderResponse,

      next:
        () => void,
    ) => {
      response.setHeader(
        'Cache-Control',
        'no-store',
      );

      response.setHeader(
        'X-Robots-Tag',
        'noindex, nofollow',
      );

      next();
    },
  );

  app.enableCors({
    origin:
      [...security.corsAllowedOrigins],

    credentials:
      false,

    methods: [
      'GET',
      'POST',
      'PUT',
      'PATCH',
      'DELETE',
      'OPTIONS',
    ],

    allowedHeaders: [
      'Authorization',
      'Content-Type',
      'Idempotency-Key',
    ],

    maxAge:
      600,
  });

  app.useBodyParser(
    'json',
    {
      limit:
        `${security.apiBodyLimitBytes}b`,
    },
  );

  app.useBodyParser(
    'urlencoded',
    {
      limit:
        `${security.apiBodyLimitBytes}b`,

      extended:
        false,
    },
  );

  app.enableShutdownHooks();

  app.setGlobalPrefix(
    'api/v1',
  );

  const server =
    app.getHttpServer() as Server;

  server.requestTimeout =
    security.requestTimeoutMs;

  server.headersTimeout =
    security.headersTimeoutMs;

  server.keepAliveTimeout =
    security.keepAliveTimeoutMs;

  server.maxHeadersCount =
    security.maxHeadersCount;

  const port =
    Number(
      process.env.PORT ??
        3001,
    );

  await app.listen(
    port,
    '0.0.0.0',
  );

  console.log(
    JSON.stringify({
      event:
        'service.started',

      port,

      service:
        'api',

      appEnvironment:
        security.appEnvironment,

      trustProxyHops:
        security.trustProxyHops,

      corsOriginCount:
        security.corsAllowedOrigins.length,

      timestamp:
        new Date().toISOString(),
    }),
  );
}

void bootstrap();
'@

Write-Text `
    -Path ".\apps\api\src\main.ts" `
    -Content $ApiMain

# ============================================================
# API APP MODULE
# ============================================================

$AppModulePath =
    ".\apps\api\src\app.module.ts"

$AppModule =
    Read-Text -Path $AppModulePath

if (-not $AppModule.Contains("SecurityModule")) {
    $Anchor =
        "import { HealthController } from './health.controller.js';"

    if (-not $AppModule.Contains($Anchor)) {
        throw "API AppModule HealthController anchor nao encontrado."
    }

    $AppModule =
        $AppModule.Replace(
            $Anchor,
            $Anchor +
            "`r`n`r`n" +
            "import { SecurityModule } from './security/security.module.js';"
        )

    $ImportsAnchor =
        "  imports: ["

    if (-not $AppModule.Contains($ImportsAnchor)) {
        throw "API AppModule imports anchor nao encontrado."
    }

    $AppModule =
        $AppModule.Replace(
            $ImportsAnchor,
            $ImportsAnchor +
            "`r`n" +
            "    SecurityModule,"
        )
}

Write-Text `
    -Path $AppModulePath `
    -Content $AppModule

# ============================================================
# STRICT AUTH RATE LIMITS
# ============================================================

$AuthController = @'
import {
  BadRequestException,
  Body,
  Controller,
  Headers,
  Inject,
  Post,
} from '@nestjs/common';

import {
  Throttle,
} from '@nestjs/throttler';

import type {
  AuthLoginResponse,
  AuthLogoutResponse,
  AuthRefreshResponse,
} from '@crm/contracts';

import {
  parseHttpSecurityEnvironment,
} from '@crm/config';

import {
  loginSchema,
  refreshTokenSchema,
} from '@crm/validation';

import {
  AuthService,
} from './auth.service.js';

import {
  SessionService,
} from './session.service.js';

const security =
  parseHttpSecurityEnvironment();

@Controller('auth')
export class AuthController {
  constructor(
    @Inject(
      AuthService,
    )
    private readonly authService:
      AuthService,

    @Inject(
      SessionService,
    )
    private readonly sessionService:
      SessionService,
  ) {}

  @Post('login')
  @Throttle({
    default: {
      limit:
        security.authLoginRateLimit,

      ttl:
        security.apiRateLimitTtlMs,
    },
  })
  async login(
    @Body()
    body:
      unknown,

    @Headers(
      'user-agent',
    )
    userAgent?:
      string,
  ): Promise<
    AuthLoginResponse
  > {
    const parsed =
      loginSchema.safeParse(
        body,
      );

    if (
      !parsed.success
    ) {
      throw new BadRequestException({
        code:
          'AUTH_LOGIN_VALIDATION_ERROR',

        message:
          'Invalid login payload.',

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

    return this.authService.login(
      parsed.data,
      {
        userAgent:
          userAgent?.slice(
            0,
            500,
          ) ??
          null,
      },
    );
  }

  @Post('refresh')
  @Throttle({
    default: {
      limit:
        security.authRefreshRateLimit,

      ttl:
        security.apiRateLimitTtlMs,
    },
  })
  async refresh(
    @Body()
    body:
      unknown,

    @Headers(
      'user-agent',
    )
    userAgent?:
      string,
  ): Promise<
    AuthRefreshResponse
  > {
    const parsed =
      refreshTokenSchema.safeParse(
        body,
      );

    if (
      !parsed.success
    ) {
      throw new BadRequestException({
        code:
          'AUTH_REFRESH_VALIDATION_ERROR',

        message:
          'Invalid refresh payload.',

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

    return this.sessionService.refresh(
      parsed.data.refreshToken,
      {
        userAgent:
          userAgent?.slice(
            0,
            500,
          ) ??
          null,
      },
    );
  }

  @Post('logout')
  async logout(
    @Body()
    body:
      unknown,

    @Headers(
      'user-agent',
    )
    userAgent?:
      string,
  ): Promise<
    AuthLogoutResponse
  > {
    const parsed =
      refreshTokenSchema.safeParse(
        body,
      );

    if (
      !parsed.success
    ) {
      throw new BadRequestException({
        code:
          'AUTH_LOGOUT_VALIDATION_ERROR',

        message:
          'Invalid logout payload.',

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

    return this.sessionService.logout(
      parsed.data.refreshToken,
      {
        userAgent:
          userAgent?.slice(
            0,
            500,
          ) ??
          null,
      },
    );
  }

  @Post('logout-all')
  async logoutAll(
    @Body()
    body:
      unknown,

    @Headers(
      'user-agent',
    )
    userAgent?:
      string,
  ): Promise<
    AuthLogoutResponse
  > {
    const parsed =
      refreshTokenSchema.safeParse(
        body,
      );

    if (
      !parsed.success
    ) {
      throw new BadRequestException({
        code:
          'AUTH_LOGOUT_ALL_VALIDATION_ERROR',

        message:
          'Invalid logout-all payload.',

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

    return this.sessionService.logoutAll(
      parsed.data.refreshToken,
      {
        userAgent:
          userAgent?.slice(
            0,
            500,
          ) ??
          null,
      },
    );
  }
}
'@

Write-Text `
    -Path ".\apps\api\src\auth\auth.controller.ts" `
    -Content $AuthController

Write-Host "[OK] API HTTP/auth hardening criado." -ForegroundColor Green

# ============================================================
# WEBHOOK DATABASE READINESS
# ============================================================

$WebhookDatabaseService = @'
import {
  Injectable,
  type OnApplicationShutdown,
} from '@nestjs/common';

import {
  checkDatabaseConnection,
  createDatabaseClient,
  type CrmDatabaseClient,
} from '@crm/database';

@Injectable()
export class DatabaseService
  implements OnApplicationShutdown
{
  readonly client:
    CrmDatabaseClient =
      createDatabaseClient();

  async isReady():
  Promise<boolean> {
    return checkDatabaseConnection(
      this.client,
    );
  }

  async onApplicationShutdown():
  Promise<void> {
    await this.client.$disconnect();
  }
}
'@

Write-Text `
    -Path ".\apps\webhook-ingress\src\database.service.ts" `
    -Content $WebhookDatabaseService

$WebhookHealth = @'
import {
  Controller,
  Get,
  Inject,
  ServiceUnavailableException,
} from '@nestjs/common';

import {
  DatabaseService,
} from './database.service.js';

type LivenessResponse =
  Readonly<{
    service:
      'webhook-ingress';

    status:
      'ok';

    timestamp:
      string;

    version:
      '0.2.0';
  }>;

type ReadinessResponse =
  LivenessResponse &
  Readonly<{
    database:
      'connected';
  }>;

@Controller('health')
export class HealthController {
  constructor(
    @Inject(
      DatabaseService,
    )
    private readonly database:
      DatabaseService,
  ) {}

  @Get('live')
  getLiveness():
  LivenessResponse {
    return this.createLiveness();
  }

  @Get()
  async getHealth():
  Promise<
    ReadinessResponse
  > {
    return this.getReadiness();
  }

  @Get('ready')
  async getReadiness():
  Promise<
    ReadinessResponse
  > {
    try {
      const ready =
        await this.database.isReady();

      if (
        !ready
      ) {
        throw new Error(
          'Database readiness failed.',
        );
      }

      return {
        ...this.createLiveness(),

        database:
          'connected',
      };
    }
    catch {
      throw new ServiceUnavailableException({
        service:
          'webhook-ingress',

        status:
          'degraded',

        database:
          'unavailable',

        timestamp:
          new Date().toISOString(),

        version:
          '0.2.0',
      });
    }
  }

  private createLiveness():
  LivenessResponse {
    return {
      service:
        'webhook-ingress',

      status:
        'ok',

      timestamp:
        new Date().toISOString(),

      version:
        '0.2.0',
    };
  }
}
'@

Write-Text `
    -Path ".\apps\webhook-ingress\src\health.controller.ts" `
    -Content $WebhookHealth

# ============================================================
# WEBHOOK HTTP HARDENING
# ============================================================

$WebhookMain = @'
import './load-environment.js';
import 'reflect-metadata';

import type {
  Server,
} from 'node:http';

import helmet from 'helmet';

import {
  NestFactory,
} from '@nestjs/core';

import type {
  NestExpressApplication,
} from '@nestjs/platform-express';

import {
  assertServiceProductionReadiness,
  parseHttpSecurityEnvironment,
} from '@crm/config';

import {
  AppModule,
} from './app.module.js';

type HeaderResponse =
  Readonly<{
    setHeader(
      name:
        string,

      value:
        string,
    ): void;
  }>;

async function bootstrap():
Promise<void> {
  assertServiceProductionReadiness(
    'webhook-ingress',
  );

  const security =
    parseHttpSecurityEnvironment();

  const productionLike =
    security.appEnvironment ===
      'staging' ||
    security.appEnvironment ===
      'production';

  const app =
    await NestFactory.create<NestExpressApplication>(
      AppModule,
      {
        abortOnError:
          true,

        rawBody:
          true,
      },
    );

  app.set(
    'trust proxy',
    security.trustProxyHops,
  );

  app.use(
    helmet({
      contentSecurityPolicy:
        false,

      crossOriginEmbedderPolicy:
        false,

      strictTransportSecurity:
        productionLike
          ? {
              maxAge:
                31536000,

              includeSubDomains:
                true,
            }
          : false,
    }),
  );

  app.use(
    (
      _request:
        unknown,

      response:
        HeaderResponse,

      next:
        () => void,
    ) => {
      response.setHeader(
        'Cache-Control',
        'no-store',
      );

      response.setHeader(
        'X-Robots-Tag',
        'noindex, nofollow',
      );

      next();
    },
  );

  /*
   * Keep Nest's built-in parser enabled because rawBody is
   * required for Meta HMAC verification. useBodyParser()
   * preserves rawBody while applying an explicit size limit.
   */
  app.useBodyParser(
    'json',
    {
      limit:
        `${security.webhookBodyLimitBytes}b`,
    },
  );

  app.enableShutdownHooks();

  const server =
    app.getHttpServer() as Server;

  server.requestTimeout =
    security.requestTimeoutMs;

  server.headersTimeout =
    security.headersTimeoutMs;

  server.keepAliveTimeout =
    security.keepAliveTimeoutMs;

  server.maxHeadersCount =
    security.maxHeadersCount;

  const port =
    Number(
      process.env.PORT ??
        3002,
    );

  await app.listen(
    port,
    '0.0.0.0',
  );

  console.log(
    JSON.stringify({
      event:
        'service.started',

      port,

      service:
        'webhook-ingress',

      appEnvironment:
        security.appEnvironment,

      metaWebhookConfigured:
        Boolean(
          process.env.META_APP_SECRET?.trim() &&
          process.env.META_WEBHOOK_VERIFY_TOKEN?.trim(),
        ),

      timestamp:
        new Date().toISOString(),
    }),
  );
}

void bootstrap();
'@

Write-Text `
    -Path ".\apps\webhook-ingress\src\main.ts" `
    -Content $WebhookMain

Write-Host "[OK] Webhook ingress hardening criado." -ForegroundColor Green

# ============================================================
# OUTBOUND UNKNOWN-OUTCOME RECOVERY
# ============================================================

$OutboundPath =
    ".\apps\worker\src\whatsapp-outbound-dispatcher.service.ts"

$Outbound =
    Read-Text -Path $OutboundPath

if (-not $Outbound.Contains("failExpiredSendingMessages")) {
    $RunTickAnchor =
        "  async runTick(): Promise<WhatsAppOutboundTickSummary> {"

    if (-not $Outbound.Contains($RunTickAnchor)) {
        throw "Outbound runTick anchor nao encontrado."
    }

    $Outbound =
        $Outbound.Replace(
            $RunTickAnchor,
            $RunTickAnchor +
            "`r`n" +
            "    await this.failExpiredSendingMessages();"
        )

    $ClaimAnchor =
        "  private async claimNextMessage(): Promise<ClaimedMessage | null> {"

    if (-not $Outbound.Contains($ClaimAnchor)) {
        throw "Outbound claimNextMessage anchor nao encontrado."
    }

    $RecoveryMethod = @'
  private async failExpiredSendingMessages(): Promise<void> {
    const now = new Date();

    const expired = await this.database.whatsAppMessage.findMany({
      where: {
        direction: 'OUTBOUND',

        status: 'SENDING',

        metaMessageId: null,

        leaseExpiresAt: {
          lte: now,
        },
      },

      select: {
        id: true,

        organizationId: true,

        attempts: true,
      },

      take: 100,
    });

    for (const message of expired) {
      const updated = await this.database.whatsAppMessage.updateMany({
        where: {
          id: message.id,

          direction: 'OUTBOUND',

          status: 'SENDING',

          metaMessageId: null,

          leaseExpiresAt: {
            lte: now,
          },
        },

        data: {
          status: 'FAILED',

          failedAt: now,

          errorCode: 'OUTBOUND_DELIVERY_UNKNOWN_AFTER_LEASE',

          errorMessage:
            'Worker lease expired while provider delivery outcome was unknown. Automatic resend was blocked to prevent duplicate customer messages.',

          claimedAt: null,

          claimedByWorkerId: null,

          leaseExpiresAt: null,
        },
      });

      if (updated.count !== 1) {
        continue;
      }

      await this.database.auditLog.create({
        data: {
          organizationId: message.organizationId,

          actorType: 'SYSTEM',

          action: 'whatsapp.outbound.delivery_unknown_after_lease',

          resourceType: 'whatsapp_message',

          resourceId: message.id,

          outcome: 'FAILURE',

          metadata: {
            attempts: message.attempts,

            automaticResendBlocked: true,
          },
        },
      });
    }
  }

'@

    $Outbound =
        $Outbound.Replace(
            $ClaimAnchor,
            $RecoveryMethod +
            $ClaimAnchor
        )
}

$UnsafeClaimPattern =
    'AND\s*\(\s*\(\s*"status"\s*=\s*''QUEUED''\s*AND\s*"availableAt"\s*<=\s*NOW\(\)\s*\)\s*OR\s*\(\s*"status"\s*=\s*''SENDING''\s*AND\s*"leaseExpiresAt"\s*IS\s*NOT\s*NULL\s*AND\s*"leaseExpiresAt"\s*<=\s*NOW\(\)\s*AND\s*"metaMessageId"\s*IS\s*NULL\s*\)\s*\)'

if ([regex]::IsMatch($Outbound, $UnsafeClaimPattern)) {
    $Outbound =
        [regex]::Replace(
            $Outbound,
            $UnsafeClaimPattern,
            'AND "status" = ''QUEUED''`r`n            AND "availableAt" <= NOW()',
            1
        )
}
Write-Text `
    -Path $OutboundPath `
    -Content $Outbound

Write-Host "[OK] Expired SENDING no longer auto-resends." -ForegroundColor Green

# ============================================================
# WORKER PRODUCTION READINESS
# ============================================================

$WorkerMainPath =
    ".\apps\worker\src\main.ts"

$WorkerMain =
    Read-Text -Path $WorkerMainPath

if (-not $WorkerMain.Contains("assertServiceProductionReadiness")) {
    $Anchor =
        "import { createDatabaseClient } from '@crm/database';"

    if (-not $WorkerMain.Contains($Anchor)) {
        throw "Worker database import anchor nao encontrado."
    }

    $WorkerMain =
        $WorkerMain.Replace(
            $Anchor,
            $Anchor +
            "`r`n`r`n" +
            "import { assertServiceProductionReadiness } from '@crm/config';"
        )
}

if (-not $WorkerMain.Contains("assertServiceProductionReadiness('worker');")) {
    $Anchor =
        "const service = 'worker' as const;"

    if (-not $WorkerMain.Contains($Anchor)) {
        throw "Worker service anchor nao encontrado."
    }

    $WorkerMain =
        $WorkerMain.Replace(
            $Anchor,
            $Anchor +
            "`r`n`r`n" +
            "assertServiceProductionReadiness('worker');"
        )
}

Write-Text `
    -Path $WorkerMainPath `
    -Content $WorkerMain

# ============================================================
# SITE MONITOR PRODUCTION READINESS
# ============================================================

$SiteMonitorMainPath =
    ".\apps\site-monitor-worker\src\main.ts"

$SiteMonitorMain =
    Read-Text -Path $SiteMonitorMainPath

if (-not $SiteMonitorMain.Contains("assertServiceProductionReadiness")) {
    $Anchor =
        "import { createDatabaseClient } from '@crm/database';"

    if (-not $SiteMonitorMain.Contains($Anchor)) {
        throw "Site monitor database import anchor nao encontrado."
    }

    $SiteMonitorMain =
        $SiteMonitorMain.Replace(
            $Anchor,
            $Anchor +
            "`r`n`r`n" +
            "import { assertServiceProductionReadiness } from '@crm/config';"
        )
}

if (-not $SiteMonitorMain.Contains("assertServiceProductionReadiness('site-monitor-worker');")) {
    $Anchor =
        "const service = 'site-monitor-worker' as const;"

    if (-not $SiteMonitorMain.Contains($Anchor)) {
        throw "Site monitor service anchor nao encontrado."
    }

    $SiteMonitorMain =
        $SiteMonitorMain.Replace(
            $Anchor,
            $Anchor +
            "`r`n`r`n" +
            "assertServiceProductionReadiness('site-monitor-worker');"
        )
}

Write-Text `
    -Path $SiteMonitorMainPath `
    -Content $SiteMonitorMain

Write-Host "[OK] Worker fail-closed production readiness criada." -ForegroundColor Green

# ============================================================
# NEXT.JS SECURITY HEADERS
# ============================================================

$NextConfig = @'
import type {
  NextConfig,
} from 'next';

const production =
  process.env.NODE_ENV ===
  'production';

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

  ...(production
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

Write-Host "[OK] Next.js baseline security headers criados." -ForegroundColor Green

# ============================================================
# ENVIRONMENT TEMPLATE
# ============================================================

$EnvPath =
    ".\.env.example"

$Env =
    Read-Text -Path $EnvPath

if (-not $Env.Contains("APP_ENV=")) {
    $Env =
        $Env.Replace(
            "NODE_ENV=development",
            "NODE_ENV=development`r`nAPP_ENV=development"
        )
}

if (-not $Env.Contains("API_CORS_ALLOWED_ORIGINS")) {
    $Env =
        $Env.TrimEnd() +
        "`r`n`r`n" +
        "# Security / production readiness - Etapa 12`r`n" +
        "# Em staging/producao: NODE_ENV=production e APP_ENV=staging|production.`r`n" +
        "# Use somente origins HTTPS reais em staging/producao.`r`n" +
        "API_CORS_ALLOWED_ORIGINS=http://localhost:3000`r`n" +
        "# Railway/reverse proxy: ajuste para a quantidade REAL de proxies confiaveis.`r`n" +
        "HTTP_TRUST_PROXY_HOPS=0`r`n" +
        "API_BODY_LIMIT_BYTES=262144`r`n" +
        "WEBHOOK_BODY_LIMIT_BYTES=1048576`r`n" +
        "HTTP_REQUEST_TIMEOUT_MS=30000`r`n" +
        "HTTP_HEADERS_TIMEOUT_MS=15000`r`n" +
        "HTTP_KEEP_ALIVE_TIMEOUT_MS=5000`r`n" +
        "HTTP_MAX_HEADERS_COUNT=100`r`n" +
        "API_RATE_LIMIT_TTL_MS=60000`r`n" +
        "API_RATE_LIMIT_DEFAULT=300`r`n" +
        "AUTH_LOGIN_RATE_LIMIT=10`r`n" +
        "AUTH_REFRESH_RATE_LIMIT=30`r`n"
}

Write-Text `
    -Path $EnvPath `
    -Content $Env

# ============================================================
# ENVIRONMENT VALIDATOR CLI
# ============================================================

$EnvValidator = @'
const service =
  process.argv[2];

const services =
  new Set([
    'api',
    'webhook-ingress',
    'worker',
    'site-monitor-worker',
    'web',
  ]);

if (
  !service ||
  !services.has(
    service,
  )
) {
  console.error(
    'Usage: node scripts/validate-production-environment.mjs <api|webhook-ingress|worker|site-monitor-worker|web>',
  );

  process.exit(2);
}

const appEnvironment =
  process.env.APP_ENV?.trim();

if (
  appEnvironment !==
    'staging' &&
  appEnvironment !==
    'production'
) {
  console.error(
    'APP_ENV must be staging or production for this validator.',
  );

  process.exit(1);
}

if (
  process.env.NODE_ENV !==
  'production'
) {
  console.error(
    'NODE_ENV must be production.',
  );

  process.exit(1);
}

const errors =
  [];

function required(
  name,
  minimumLength =
    1,
) {
  const value =
    process.env[name]?.trim();

  if (
    !value ||
    value.length <
      minimumLength
  ) {
    errors.push(
      `${name}: missing or too short`,
    );

    return null;
  }

  const lower =
    value.toLowerCase();

  if (
    lower.includes(
      'change_me',
    ) ||
    lower.includes(
      'placeholder',
    )
  ) {
    errors.push(
      `${name}: placeholder value`,
    );
  }

  return value;
}

function database() {
  const raw =
    required(
      'DATABASE_URL',
      10,
    );

  if (
    !raw
  ) {
    return;
  }

  try {
    const url =
      new URL(
        raw,
      );

    if (
      url.protocol !==
        'postgresql:' &&
      url.protocol !==
        'postgres:'
    ) {
      errors.push(
        'DATABASE_URL: must use PostgreSQL',
      );
    }

    if (
      url.hostname ===
        'localhost' ||
      url.hostname ===
        '127.0.0.1'
    ) {
      errors.push(
        'DATABASE_URL: localhost is forbidden',
      );
    }
  }
  catch {
    errors.push(
      'DATABASE_URL: invalid URL',
    );
  }
}

if (
  service !==
  'web'
) {
  database();
}

if (
  service ===
  'api'
) {
  const access =
    required(
      'AUTH_ACCESS_TOKEN_SECRET',
      32,
    );

  const pepper =
    required(
      'AUTH_REFRESH_TOKEN_PEPPER',
      32,
    );

  if (
    access &&
    pepper &&
    access ===
      pepper
  ) {
    errors.push(
      'AUTH secrets must be different',
    );
  }

  const origins =
    required(
      'API_CORS_ALLOWED_ORIGINS',
      8,
    );

  if (
    origins
  ) {
    for (
      const raw of
      origins
        .split(',')
        .map(
          (
            value,
          ) =>
            value.trim(),
        )
        .filter(
          Boolean,
        )
    ) {
      try {
        const url =
          new URL(
            raw,
          );

        if (
          url.protocol !==
          'https:'
        ) {
          errors.push(
            `CORS origin must use HTTPS: ${raw}`,
          );
        }
      }
      catch {
        errors.push(
          `Invalid CORS origin: ${raw}`,
        );
      }
    }
  }
}

if (
  service ===
  'webhook-ingress'
) {
  required(
    'META_APP_SECRET',
    32,
  );

  required(
    'META_WEBHOOK_VERIFY_TOKEN',
    16,
  );
}

if (
  service ===
  'worker'
) {
  const graph =
    required(
      'META_GRAPH_API_VERSION',
      4,
    );

  if (
    graph &&
    !/^v\d+\.\d+$/.test(
      graph,
    )
  ) {
    errors.push(
      'META_GRAPH_API_VERSION: invalid format',
    );
  }

  required(
    'META_ACCESS_TOKEN',
    20,
  );

  required(
    'ONESIGNAL_APP_ID',
    8,
  );

  required(
    'ONESIGNAL_API_KEY',
    20,
  );
}

if (
  service ===
  'web'
) {
  required(
    'NEXT_PUBLIC_ONESIGNAL_APP_ID',
    8,
  );
}

if (
  errors.length >
  0
) {
  for (
    const error of
      errors
  ) {
    console.error(
      `[ERROR] ${error}`,
    );
  }

  process.exit(1);
}

console.log(
  `[OK] ${service} production environment validated for ${appEnvironment}.`,
);
'@

Write-Text `
    -Path ".\scripts\validate-production-environment.mjs" `
    -Content $EnvValidator

# ============================================================
# SECURITY DOCUMENTATION
# ============================================================

$SecurityDoc = @(
    "# Etapa 12 - Security Hardening, Staging e Production Readiness",
    "",
    "## Status",
    "",
    "EM ANDAMENTO - Macrobloco 12.1 construido.",
    "",
    "## Security layers",
    "",
    "A Etapa 12 separa:",
    "",
    "1. HTTP/application security.",
    "2. Authentication/session security.",
    "3. Provider/webhook security.",
    "4. Worker failure safety.",
    "5. Environment/secrets validation.",
    "6. Infrastructure controls.",
    "",
    "## API",
    "",
    "- Helmet.",
    "- explicit CORS allowlist.",
    "- no credentials CORS because authentication uses bearer tokens.",
    "- global defense-in-depth rate limit.",
    "- stricter login rate limit.",
    "- stricter refresh rate limit.",
    "- explicit request body limit.",
    "- explicit request/header/keepalive timeouts.",
    "- trusted proxy hop count configured by environment.",
    "- Cache-Control no-store.",
    "- X-Robots-Tag noindex/nofollow.",
    "- fail-closed production environment validation.",
    "",
    "The application throttler is process-local defense in depth.",
    "",
    "A global distributed rate limit must also be configured at the edge/WAF in staging and production.",
    "",
    "## Meta webhook ingress",
    "",
    "- raw body remains enabled.",
    "- X-Hub-Signature-256 validation remains mandatory.",
    "- explicit webhook payload limit.",
    "- Helmet.",
    "- HTTP timeouts.",
    "- database readiness endpoint.",
    "- production boot requires Meta app secret and verify token.",
    "",
    "The Meta callback is NOT protected by the same human API rate limiter.",
    "",
    "Provider authenticity is based on HMAC verification and payload limits.",
    "",
    "## Outbound uncertainty",
    "",
    "Expired SENDING messages without metaMessageId are no longer automatically retried.",
    "",
    "They become FAILED with OUTBOUND_DELIVERY_UNKNOWN_AFTER_LEASE.",
    "",
    "This prevents blind customer-message duplication after crash or lost lease.",
    "",
    "An audit event is persisted for manual reconciliation.",
    "",
    "## Workers",
    "",
    "Production-like worker boot requires:",
    "",
    "- PostgreSQL.",
    "- Meta Graph API version.",
    "- Meta access token.",
    "- OneSignal app id.",
    "- OneSignal API key.",
    "",
    "Site monitor worker requires a valid production PostgreSQL URL.",
    "",
    "## Web",
    "",
    "Baseline security response headers are configured in Next.js.",
    "",
    "CSP is intentionally not finalized before the real frontend is built because Next runtime, OneSignal and future frontend assets must be represented accurately.",
    "",
    "## Environment",
    "",
    "APP_ENV distinguishes development, test, staging and production.",
    "",
    "For staging and production:",
    "",
    "- NODE_ENV must be production.",
    "- server database URLs cannot point to localhost.",
    "- CORS must be explicit HTTPS.",
    "- auth secrets must be strong and distinct.",
    "- provider credentials required by each service must exist.",
    "",
    "## Macrobloco 12.2",
    "",
    "The next macroblock will validate these controls with runtime HTTP tests, security tests, failure injection, builds and staging/production deployment checklist."
)

Write-Lines `
    -Path ".\docs\ETAPA_12_SECURITY_HARDENING.md" `
    -Lines $SecurityDoc

$EtapasPath =
    ".\docs\ETAPAS.md"

if (Test-Path $EtapasPath) {
    $Etapas =
        Read-Text -Path $EtapasPath

    $Etapas =
        [regex]::Replace(
            $Etapas,
            "(?m)^\|\s*12\s*\|([^|]+)\|([^|]+)\|$",
            {
                param($Match)

                return (
                    "|    12 |" +
                    $Match.Groups[1].Value +
                    "| EM ANDAMENTO                 |"
                )
            },
            1
        )

    if (-not $Etapas.Contains("## Etapa 12 - Security")) {
        $Etapas =
            $Etapas.TrimEnd() +
            "`r`n`r`n" +
            "## Etapa 12 - Security Hardening, Staging e Production Readiness`r`n`r`n" +
            "Status: EM ANDAMENTO - Macrobloco 12.1 construido.`r`n"
    }

    Write-Text `
        -Path $EtapasPath `
        -Content $Etapas
}

# ============================================================
# STRUCTURAL CHECKS
# ============================================================

$ApiMainCheck =
    Read-Text -Path ".\apps\api\src\main.ts"

$WebhookMainCheck =
    Read-Text -Path ".\apps\webhook-ingress\src\main.ts"

$OutboundCheck =
    Read-Text -Path $OutboundPath

$WorkerCheck =
    Read-Text -Path $WorkerMainPath

$SiteMonitorCheck =
    Read-Text -Path $SiteMonitorMainPath

$NextCheck =
    Read-Text -Path ".\apps\web\next.config.ts"

foreach ($Marker in @(
    "helmet(",
    "enableCors",
    "trust proxy",
    "requestTimeout",
    "headersTimeout",
    "maxHeadersCount",
    "assertServiceProductionReadiness"
)) {
    if (-not $ApiMainCheck.Contains($Marker)) {
        throw "API security marker ausente: $Marker"
    }
}

foreach ($Marker in @(
    "helmet(",
    "rawBody:",
    "webhookBodyLimitBytes",
    "requestTimeout",
    "assertServiceProductionReadiness"
)) {
    if (-not $WebhookMainCheck.Contains($Marker)) {
        throw "Webhook security marker ausente: $Marker"
    }
}

foreach ($Marker in @(
    "failExpiredSendingMessages",
    "OUTBOUND_DELIVERY_UNKNOWN_AFTER_LEASE",
    "automaticResendBlocked",
    "whatsapp.outbound.delivery_unknown_after_lease"
)) {
    if (-not $OutboundCheck.Contains($Marker)) {
        throw "Outbound safety marker ausente: $Marker"
    }
}


if (-not $WorkerCheck.Contains("assertServiceProductionReadiness('worker');")) {
    throw "Worker production readiness ausente."
}

if (-not $SiteMonitorCheck.Contains("assertServiceProductionReadiness('site-monitor-worker');")) {
    throw "Site monitor production readiness ausente."
}

foreach ($Marker in @(
    "X-Content-Type-Options",
    "X-Frame-Options",
    "Referrer-Policy",
    "Permissions-Policy",
    "Strict-Transport-Security"
)) {
    if (-not $NextCheck.Contains($Marker)) {
        throw "Next security header ausente: $Marker"
    }
}

$SecurityModuleCheck =
    Read-Text -Path ".\apps\api\src\security\security.module.ts"

foreach ($Marker in @(
    "ThrottlerModule",
    "ThrottlerGuard",
    "APP_GUARD"
)) {
    if (-not $SecurityModuleCheck.Contains($Marker)) {
        throw "Rate limiter marker ausente: $Marker"
    }
}

Write-Host "[OK] Stage 12 structural checks." -ForegroundColor Green

# ============================================================
# FINAL STATUS
# ============================================================

Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host "[OK] MACROBLOCO 12.1 CRIADO." -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Construido:" -ForegroundColor Cyan
Write-Host "- Helmet API"
Write-Host "- Helmet webhook ingress"
Write-Host "- explicit API CORS allowlist"
Write-Host "- process-local API rate limiting"
Write-Host "- stricter login rate limit"
Write-Host "- stricter refresh rate limit"
Write-Host "- explicit API body limit"
Write-Host "- explicit webhook body limit"
Write-Host "- HTTP request timeout"
Write-Host "- HTTP headers timeout"
Write-Host "- HTTP keep-alive timeout"
Write-Host "- HTTP max headers count"
Write-Host "- trusted proxy configuration"
Write-Host "- API no-store/noindex"
Write-Host "- webhook no-store/noindex"
Write-Host "- webhook database readiness"
Write-Host "- production environment fail-closed"
Write-Host "- service-specific secret validation"
Write-Host "- outbound expired SENDING duplicate protection"
Write-Host "- outbound unknown-delivery audit"
Write-Host "- worker production readiness"
Write-Host "- site-monitor production readiness"
Write-Host "- Next.js security headers"
Write-Host "- production environment CLI validator"
Write-Host "- Stage 12 documentation foundation"
Write-Host ""
Write-Host "Nenhuma migration nova e necessaria no 12.1." -ForegroundColor Yellow
Write-Host "Nao rode CI manualmente ainda." -ForegroundColor Yellow
Write-Host ""
Write-Host "Proximo: Macrobloco 12.2 - runtime security audit, failure injection, staging e fechamento." -ForegroundColor Yellow