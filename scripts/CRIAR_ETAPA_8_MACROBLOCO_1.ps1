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
        New-Item `
            -ItemType Directory `
            -Path $Parent `
            -Force |
            Out-Null
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
        $Content.Substring(
            $Match.Index + $Match.Length
        )
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
Write-Host " ETAPA 8 - MACROBLOCO 8.1" -ForegroundColor Cyan
Write-Host " META CLOUD API FOUNDATION" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

$SchemaPath = ".\packages\database\prisma\schema.prisma"
$ContractsIndexPath = ".\packages\contracts\src\index.ts"
$ValidationIndexPath = ".\packages\validation\src\index.ts"

$WhatsAppServicePath = `
    ".\apps\api\src\whatsapp-numbers\whatsapp-numbers.service.ts"

$WhatsAppControllerPath = `
    ".\apps\api\src\whatsapp-numbers\whatsapp-numbers.controller.ts"

$WebhookPackagePath = `
    ".\apps\webhook-ingress\package.json"

$WebhookMainPath = `
    ".\apps\webhook-ingress\src\main.ts"

$WebhookAppModulePath = `
    ".\apps\webhook-ingress\src\app.module.ts"

$EnvExamplePath = ".\.env.example"

$BackupDirectory = ".\tmp\stage8-macroblock1-backup"

if (-not (Test-Path $BackupDirectory)) {
    New-Item `
        -ItemType Directory `
        -Path $BackupDirectory `
        -Force |
        Out-Null

    foreach ($File in @(
        $SchemaPath,
        $ContractsIndexPath,
        $ValidationIndexPath,
        $WhatsAppServicePath,
        $WhatsAppControllerPath,
        $WebhookPackagePath,
        $WebhookMainPath,
        $WebhookAppModulePath,
        $EnvExamplePath
    )) {
        if (-not (Test-Path $File)) {
            throw "Arquivo obrigatorio nao encontrado: $File"
        }

        $BackupName = $File -replace '^[.][\\/]', ''
        $BackupName = $BackupName -replace '[\\/]', '__'

        Copy-Item `
            -Path $File `
            -Destination (
                Join-Path $BackupDirectory $BackupName
            ) `
            -Force
    }
}

Write-Host "[OK] Backup Stage 8 preparado." -ForegroundColor Green

# ============================================================
# PRISMA ENUM
# ============================================================

$MetaWebhookEnum = @'
enum MetaWebhookStatus {
  RECEIVED
  CLAIMED
  PROCESSED
  UNMATCHED
  IGNORED
  FAILED
}
'@

Insert-AfterPrismaBlock `
    -Path $SchemaPath `
    -Kind "enum" `
    -Name "NotificationDeliveryStatus" `
    -Marker "enum MetaWebhookStatus" `
    -Insertion $MetaWebhookEnum

Write-Host "[OK] MetaWebhookStatus criado." -ForegroundColor Green

# ============================================================
# PRISMA RELATIONS
# ============================================================

Add-ToPrismaModel `
    -Path $SchemaPath `
    -ModelName "Organization" `
    -Marker "metaWebhookEnvelopes" `
    -Insertion @'
  metaWebhookEnvelopes MetaWebhookEnvelope[]
'@

Add-ToPrismaModel `
    -Path $SchemaPath `
    -ModelName "WhatsAppNumber" `
    -Marker "metaPhoneNumberId" `
    -Insertion @'
  metaWabaId            String?   @db.VarChar(64)
  metaPhoneNumberId     String?   @unique @db.VarChar(64)
  metaConnectedAt       DateTime? @db.Timestamptz(3)
  metaWebhookLastSeenAt DateTime? @db.Timestamptz(3)

  metaWebhookEnvelopes MetaWebhookEnvelope[]
'@

Write-Host "[OK] WhatsAppNumber preparado para Meta Cloud API." -ForegroundColor Green

# ============================================================
# PRISMA WEBHOOK MODEL
# ============================================================

$MetaWebhookModel = @'
model MetaWebhookEnvelope {
  id                 String            @id @default(uuid()) @db.Uuid
  organizationId     String?           @db.Uuid
  whatsAppNumberId   String?           @db.Uuid
  object             String?           @db.VarChar(120)
  field              String?           @db.VarChar(120)
  wabaId             String?           @db.VarChar(64)
  metaPhoneNumberId  String?           @db.VarChar(64)
  payloadHash        String            @unique @db.Char(64)
  payload            Json
  status             MetaWebhookStatus @default(RECEIVED)
  receivedAt         DateTime          @default(now()) @db.Timestamptz(3)
  availableAt        DateTime          @default(now()) @db.Timestamptz(3)
  attempts           Int               @default(0)
  claimedAt          DateTime?         @db.Timestamptz(3)
  claimedByWorkerId  String?           @db.VarChar(120)
  leaseExpiresAt     DateTime?         @db.Timestamptz(3)
  processedAt        DateTime?         @db.Timestamptz(3)
  failureReason      String?           @db.VarChar(500)
  createdAt          DateTime          @default(now()) @db.Timestamptz(3)
  updatedAt          DateTime          @updatedAt @db.Timestamptz(3)

  organization   Organization?  @relation(fields: [organizationId], references: [id], onDelete: SetNull)
  whatsAppNumber WhatsAppNumber? @relation(fields: [whatsAppNumberId], references: [id], onDelete: SetNull)

  @@index([organizationId, status, availableAt])
  @@index([organizationId, whatsAppNumberId, receivedAt])
  @@index([metaPhoneNumberId, receivedAt])
  @@index([status, leaseExpiresAt])
  @@index([receivedAt])
  @@map("meta_webhook_envelopes")
}
'@

Insert-AfterPrismaBlock `
    -Path $SchemaPath `
    -Kind "model" `
    -Name "WhatsAppNumber" `
    -Marker "model MetaWebhookEnvelope {" `
    -Insertion $MetaWebhookModel

$Schema = Read-Text -Path $SchemaPath
$Schema = $Schema.TrimStart([char]0xFEFF)

Write-Text `
    -Path $SchemaPath `
    -Content $Schema

Write-Host "[OK] MetaWebhookEnvelope criado." -ForegroundColor Green

# ============================================================
# META CLOUD CONTRACTS
# ============================================================

$MetaContracts = @'
export type ConfigureWhatsAppMetaRequest =
  Readonly<{
    wabaId: string | null;
    phoneNumberId: string | null;
  }>;

export type MetaConnectionResponse =
  Readonly<{
    wabaId: string | null;
    phoneNumberId: string | null;
    connectedAt: string | null;
    webhookLastSeenAt: string | null;
  }>;
'@

Write-Text `
    -Path ".\packages\contracts\src\meta-cloud.ts" `
    -Content $MetaContracts

$Contracts = Read-Text -Path $ContractsIndexPath

if (
    -not $Contracts.Contains(
        "export * from './meta-cloud.js';"
    )
) {
    $Contracts = (
        $Contracts.TrimEnd() +
        "`r`nexport * from './meta-cloud.js';`r`n"
    )
}

if (
    -not $Contracts.Contains(
        "metaPhoneNumberId: string | null;"
    )
) {
    $Anchor = "  notes: string | null;"

    $WhatsAppStart = $Contracts.IndexOf(
        "export type WhatsAppNumberResponse"
    )

    $AnchorIndex = $Contracts.IndexOf(
        $Anchor,
        $WhatsAppStart
    )

    if ($AnchorIndex -lt 0) {
        throw "WhatsAppNumberResponse notes anchor nao encontrado."
    }

    $InsertAt = $AnchorIndex + $Anchor.Length

    $Addition = @'

  metaWabaId: string | null;

  metaPhoneNumberId: string | null;

  metaConnectedAt: string | null;

  metaWebhookLastSeenAt: string | null;
'@

    $Contracts = (
        $Contracts.Substring(0, $InsertAt) +
        $Addition +
        $Contracts.Substring($InsertAt)
    )
}

Write-Text `
    -Path $ContractsIndexPath `
    -Content $Contracts

Write-Host "[OK] Contracts Meta Cloud criados." -ForegroundColor Green

# ============================================================
# META CLOUD VALIDATION
# ============================================================

$MetaValidation = @'
import {
  z,
} from 'zod';

const metaNumericIdSchema =
  z
    .string()
    .trim()
    .min(5)
    .max(64)
    .regex(/^\d+$/);

export const configureWhatsAppMetaSchema =
  z
    .object({
      wabaId:
        metaNumericIdSchema.nullable(),

      phoneNumberId:
        metaNumericIdSchema.nullable(),
    })
    .strict()
    .refine(
      (value) =>
        (
          value.wabaId === null &&
          value.phoneNumberId === null
        ) ||
        (
          value.wabaId !== null &&
          value.phoneNumberId !== null
        ),
      {
        message:
          'wabaId and phoneNumberId must both be provided or both be null.',
      },
    );

export type ConfigureWhatsAppMetaInput =
  z.infer<
    typeof configureWhatsAppMetaSchema
  >;
'@

Write-Text `
    -Path ".\packages\validation\src\meta-cloud.ts" `
    -Content $MetaValidation

$Validation = Read-Text -Path $ValidationIndexPath

if (
    -not $Validation.Contains(
        "export * from './meta-cloud.js';"
    )
) {
    $Validation = (
        $Validation.TrimEnd() +
        "`r`nexport * from './meta-cloud.js';`r`n"
    )

    Write-Text `
        -Path $ValidationIndexPath `
        -Content $Validation
}

Write-Host "[OK] Validation Meta Cloud criada." -ForegroundColor Green

# ============================================================
# @crm/meta-cloud-api PACKAGE
# ============================================================

$MetaPackageJson = @'
{
  "name": "@crm/meta-cloud-api",
  "version": "0.2.0",
  "private": true,
  "type": "module",
  "main": "dist/index.js",
  "types": "./src/index.ts",
  "exports": {
    ".": {
      "types": "./src/index.ts",
      "default": "./dist/index.js"
    }
  },
  "files": [
    "dist"
  ],
  "scripts": {
    "build": "tsc -p tsconfig.json",
    "lint": "eslint src",
    "typecheck": "tsc --noEmit -p tsconfig.json",
    "test": "vitest run --config ../../tooling/testing/vitest.config.ts --passWithNoTests",
    "clean": "rimraf dist coverage"
  }
}
'@

Write-Text `
    -Path ".\packages\meta-cloud-api\package.json" `
    -Content $MetaPackageJson

$MetaTsConfig = @'
{
  "extends": "../../tooling/typescript/library.json",
  "compilerOptions": {
    "rootDir": "src",
    "outDir": "dist"
  },
  "include": [
    "src/**/*.ts"
  ],
  "exclude": [
    "node_modules",
    "dist",
    "coverage",
    "src/**/*.spec.ts"
  ]
}
'@

Write-Text `
    -Path ".\packages\meta-cloud-api\tsconfig.json" `
    -Content $MetaTsConfig

$MetaConfig = @'
export type MetaCloudApiConfig =
  Readonly<{
    graphBaseUrl: string;
    graphApiVersion: string;
    accessToken: string;
    timeoutMs: number;
  }>;

function readRequired(
  environment:
    NodeJS.ProcessEnv,
  name: string,
): string {
  const value =
    environment[name]?.trim();

  if (!value) {
    throw new Error(
      `${name} is required.`,
    );
  }

  return value;
}

function readTimeout(
  environment:
    NodeJS.ProcessEnv,
): number {
  const raw =
    environment.META_HTTP_TIMEOUT_MS?.trim();

  if (!raw) {
    return 10_000;
  }

  const value =
    Number(raw);

  if (
    !Number.isInteger(value) ||
    value < 500 ||
    value > 120_000
  ) {
    throw new Error(
      'META_HTTP_TIMEOUT_MS must be an integer between 500 and 120000.',
    );
  }

  return value;
}

export function parseMetaCloudApiConfig(
  environment:
    NodeJS.ProcessEnv =
      process.env,
): MetaCloudApiConfig {
  const graphApiVersion =
    readRequired(
      environment,
      'META_GRAPH_API_VERSION',
    );

  if (
    !/^v\d+\.\d+$/.test(
      graphApiVersion,
    )
  ) {
    throw new Error(
      'META_GRAPH_API_VERSION must look like vXX.X.',
    );
  }

  const accessToken =
    readRequired(
      environment,
      'META_ACCESS_TOKEN',
    );

  const graphBaseUrl =
    (
      environment.META_GRAPH_BASE_URL?.trim() ||
      'https://graph.facebook.com'
    ).replace(/\/+$/, '');

  const parsedBaseUrl =
    new URL(
      graphBaseUrl,
    );

  if (
    parsedBaseUrl.protocol !==
    'https:'
  ) {
    throw new Error(
      'META_GRAPH_BASE_URL must use HTTPS.',
    );
  }

  return {
    graphBaseUrl,
    graphApiVersion,
    accessToken,
    timeoutMs:
      readTimeout(
        environment,
      ),
  };
}
'@

Write-Text `
    -Path ".\packages\meta-cloud-api\src\config.ts" `
    -Content $MetaConfig

# ============================================================
# GRAPH API CLIENT
# ============================================================

$MetaClient = @'
import type {
  MetaCloudApiConfig,
} from './config.js';

type FetchImplementation =
  typeof fetch;

type MetaErrorShape =
  Readonly<{
    message: string | null;
    type: string | null;
    code: number | null;
    errorSubcode: number | null;
    fbtraceId: string | null;
  }>;

function isRecord(
  value: unknown,
): value is Record<string, unknown> {
  return (
    typeof value === 'object' &&
    value !== null &&
    !Array.isArray(value)
  );
}

function readString(
  value: unknown,
): string | null {
  return typeof value === 'string'
    ? value
    : null;
}

function readNumber(
  value: unknown,
): number | null {
  return typeof value === 'number' &&
    Number.isFinite(value)
    ? value
    : null;
}

function parseMetaError(
  payload: unknown,
): MetaErrorShape {
  if (!isRecord(payload)) {
    return {
      message: null,
      type: null,
      code: null,
      errorSubcode: null,
      fbtraceId: null,
    };
  }

  const error =
    isRecord(payload.error)
      ? payload.error
      : null;

  if (!error) {
    return {
      message: null,
      type: null,
      code: null,
      errorSubcode: null,
      fbtraceId: null,
    };
  }

  return {
    message:
      readString(
        error.message,
      ),

    type:
      readString(
        error.type,
      ),

    code:
      readNumber(
        error.code,
      ),

    errorSubcode:
      readNumber(
        error.error_subcode,
      ),

    fbtraceId:
      readString(
        error.fbtrace_id,
      ),
  };
}

export class MetaCloudApiError
  extends Error {
  readonly status:
    number;

  readonly code:
    number | null;

  readonly errorSubcode:
    number | null;

  readonly metaType:
    string | null;

  readonly fbtraceId:
    string | null;

  readonly requestId:
    string | null;

  constructor(
    input: Readonly<{
      status: number;
      message: string;
      code: number | null;
      errorSubcode: number | null;
      metaType: string | null;
      fbtraceId: string | null;
      requestId: string | null;
    }>,
  ) {
    super(
      input.message,
    );

    this.name =
      'MetaCloudApiError';

    this.status =
      input.status;

    this.code =
      input.code;

    this.errorSubcode =
      input.errorSubcode;

    this.metaType =
      input.metaType;

    this.fbtraceId =
      input.fbtraceId;

    this.requestId =
      input.requestId;
  }
}

export class MetaCloudApiClient {
  constructor(
    private readonly config:
      MetaCloudApiConfig,

    private readonly fetchImplementation:
      FetchImplementation =
        fetch,
  ) {}

  async get<T>(
    path: string,
    query:
      Readonly<Record<string, string>> =
        {},
  ): Promise<T> {
    return this.request<T>(
      'GET',
      path,
      query,
      undefined,
    );
  }

  async post<T>(
    path: string,
    body:
      Readonly<Record<string, unknown>>,
  ): Promise<T> {
    return this.request<T>(
      'POST',
      path,
      {},
      body,
    );
  }

  private async request<T>(
    method:
      'GET' |
      'POST',
    path: string,
    query:
      Readonly<Record<string, string>>,
    body:
      Readonly<Record<string, unknown>> |
      undefined,
  ): Promise<T> {
    const normalizedPath =
      path
        .trim()
        .replace(/^\/+/, '');

    if (
      !normalizedPath ||
      normalizedPath.includes('..')
    ) {
      throw new Error(
        'Invalid Meta Graph API path.',
      );
    }

    const url =
      new URL(
        `${this.config.graphBaseUrl}/${this.config.graphApiVersion}/${normalizedPath}`,
      );

    for (
      const [
        key,
        value,
      ] of Object.entries(
        query,
      )
    ) {
      url.searchParams.set(
        key,
        value,
      );
    }

    const response =
      await this.fetchImplementation(
        url,
        {
          method,

          headers: {
            Authorization:
              `Bearer ${this.config.accessToken}`,

            Accept:
              'application/json',

            ...(body
              ? {
                  'Content-Type':
                    'application/json',
                }
              : {}),
          },

          ...(body
            ? {
                body:
                  JSON.stringify(
                    body,
                  ),
              }
            : {}),

          signal:
            AbortSignal.timeout(
              this.config.timeoutMs,
            ),
        },
      );

    const raw =
      await response.text();

    let payload:
      unknown = null;

    if (raw) {
      try {
        payload =
          JSON.parse(
            raw,
          ) as unknown;
      }
      catch {
        payload =
          null;
      }
    }

    if (!response.ok) {
      const metaError =
        parseMetaError(
          payload,
        );

      throw new MetaCloudApiError({
        status:
          response.status,

        message:
          metaError.message ??
          `Meta Graph API HTTP ${response.status}`,

        code:
          metaError.code,

        errorSubcode:
          metaError.errorSubcode,

        metaType:
          metaError.type,

        fbtraceId:
          metaError.fbtraceId,

        requestId:
          response.headers.get(
            'x-fb-request-id',
          ),
      });
    }

    return payload as T;
  }
}
'@

Write-Text `
    -Path ".\packages\meta-cloud-api\src\client.ts" `
    -Content $MetaClient

# ============================================================
# WEBHOOK SECURITY
# ============================================================

$WebhookSecurity = @'
import {
  createHmac,
  timingSafeEqual,
} from 'node:crypto';

function safeEqual(
  left: string,
  right: string,
): boolean {
  const leftBuffer =
    Buffer.from(
      left,
      'utf8',
    );

  const rightBuffer =
    Buffer.from(
      right,
      'utf8',
    );

  if (
    leftBuffer.length !==
    rightBuffer.length
  ) {
    return false;
  }

  return timingSafeEqual(
    leftBuffer,
    rightBuffer,
  );
}

export function verifyMetaWebhookChallenge(
  input: Readonly<{
    mode: string | undefined;
    providedToken: string | undefined;
    challenge: string | undefined;
    expectedToken: string;
  }>,
): string | null {
  if (
    input.mode !==
    'subscribe'
  ) {
    return null;
  }

  if (
    !input.providedToken ||
    !safeEqual(
      input.providedToken,
      input.expectedToken,
    )
  ) {
    return null;
  }

  if (
    input.challenge ===
    undefined
  ) {
    return null;
  }

  return input.challenge;
}

export function verifyMetaWebhookSignature(
  appSecret: string,
  rawBody: Buffer,
  signatureHeader:
    string | undefined,
): boolean {
  if (
    !signatureHeader ||
    !signatureHeader.startsWith(
      'sha256=',
    )
  ) {
    return false;
  }

  const received =
    signatureHeader.slice(
      'sha256='.length,
    );

  if (
    !/^[a-fA-F0-9]{64}$/.test(
      received,
    )
  ) {
    return false;
  }

  const expected =
    createHmac(
      'sha256',
      appSecret,
    )
      .update(
        rawBody,
      )
      .digest(
        'hex',
      );

  return safeEqual(
    received.toLowerCase(),
    expected,
  );
}
'@

Write-Text `
    -Path ".\packages\meta-cloud-api\src\webhook-security.ts" `
    -Content $WebhookSecurity

# ============================================================
# WEBHOOK PAYLOAD SUMMARY
# ============================================================

$WebhookPayload = @'
export type MetaWebhookSummary =
  Readonly<{
    object: string | null;
    wabaId: string | null;
    field: string | null;
    phoneNumberId: string | null;
  }>;

function isRecord(
  value: unknown,
): value is Record<string, unknown> {
  return (
    typeof value === 'object' &&
    value !== null &&
    !Array.isArray(value)
  );
}

function stringValue(
  value: unknown,
): string | null {
  return typeof value === 'string'
    ? value
    : null;
}

export function extractMetaWebhookSummary(
  payload: unknown,
): MetaWebhookSummary {
  if (!isRecord(payload)) {
    return {
      object: null,
      wabaId: null,
      field: null,
      phoneNumberId: null,
    };
  }

  const entries =
    Array.isArray(
      payload.entry,
    )
      ? payload.entry
      : [];

  const firstEntry =
    isRecord(
      entries[0],
    )
      ? entries[0]
      : null;

  const changes =
    firstEntry &&
    Array.isArray(
      firstEntry.changes,
    )
      ? firstEntry.changes
      : [];

  const firstChange =
    isRecord(
      changes[0],
    )
      ? changes[0]
      : null;

  const value =
    firstChange &&
    isRecord(
      firstChange.value,
    )
      ? firstChange.value
      : null;

  const metadata =
    value &&
    isRecord(
      value.metadata,
    )
      ? value.metadata
      : null;

  return {
    object:
      stringValue(
        payload.object,
      ),

    wabaId:
      stringValue(
        firstEntry?.id,
      ),

    field:
      stringValue(
        firstChange?.field,
      ),

    phoneNumberId:
      stringValue(
        metadata?.phone_number_id,
      ),
  };
}
'@

Write-Text `
    -Path ".\packages\meta-cloud-api\src\webhook-payload.ts" `
    -Content $WebhookPayload

$MetaIndex = @'
export {
  MetaCloudApiClient,
  MetaCloudApiError,
} from './client.js';

export {
  parseMetaCloudApiConfig,
  type MetaCloudApiConfig,
} from './config.js';

export {
  extractMetaWebhookSummary,
  type MetaWebhookSummary,
} from './webhook-payload.js';

export {
  verifyMetaWebhookChallenge,
  verifyMetaWebhookSignature,
} from './webhook-security.js';
'@

Write-Text `
    -Path ".\packages\meta-cloud-api\src\index.ts" `
    -Content $MetaIndex

# ============================================================
# META PACKAGE TESTS
# ============================================================

$MetaSecurityTests = @'
import {
  createHmac,
} from 'node:crypto';

import {
  describe,
  expect,
  it,
} from 'vitest';

import {
  verifyMetaWebhookChallenge,
  verifyMetaWebhookSignature,
} from './webhook-security.js';

describe('verifyMetaWebhookChallenge', () => {
  it('accepts the expected verification token', () => {
    expect(
      verifyMetaWebhookChallenge({
        mode:
          'subscribe',

        providedToken:
          'expected-token',

        expectedToken:
          'expected-token',

        challenge:
          '123456',
      }),
    ).toBe(
      '123456',
    );
  });

  it('rejects a wrong verification token', () => {
    expect(
      verifyMetaWebhookChallenge({
        mode:
          'subscribe',

        providedToken:
          'wrong',

        expectedToken:
          'expected-token',

        challenge:
          '123456',
      }),
    ).toBeNull();
  });
});

describe('verifyMetaWebhookSignature', () => {
  it('validates HMAC SHA-256 over the raw request body', () => {
    const secret =
      'stage8-secret';

    const rawBody =
      Buffer.from(
        '{"object":"whatsapp_business_account"}',
      );

    const digest =
      createHmac(
        'sha256',
        secret,
      )
        .update(
          rawBody,
        )
        .digest(
          'hex',
        );

    expect(
      verifyMetaWebhookSignature(
        secret,
        rawBody,
        `sha256=${digest}`,
      ),
    ).toBe(true);

    expect(
      verifyMetaWebhookSignature(
        secret,
        rawBody,
        `sha256=${'0'.repeat(64)}`,
      ),
    ).toBe(false);
  });
});
'@

Write-Text `
    -Path ".\packages\meta-cloud-api\src\webhook-security.spec.ts" `
    -Content $MetaSecurityTests

$MetaPayloadTests = @'
import {
  describe,
  expect,
  it,
} from 'vitest';

import {
  extractMetaWebhookSummary,
} from './webhook-payload.js';

describe('extractMetaWebhookSummary', () => {
  it('extracts WABA, field and phone number metadata', () => {
    expect(
      extractMetaWebhookSummary({
        object:
          'whatsapp_business_account',

        entry: [
          {
            id:
              '123456789',

            changes: [
              {
                field:
                  'messages',

                value: {
                  metadata: {
                    phone_number_id:
                      '9988776655',
                  },
                },
              },
            ],
          },
        ],
      }),
    ).toEqual({
      object:
        'whatsapp_business_account',

      wabaId:
        '123456789',

      field:
        'messages',

      phoneNumberId:
        '9988776655',
    });
  });

  it('returns nullable metadata for unknown payloads', () => {
    expect(
      extractMetaWebhookSummary({}),
    ).toEqual({
      object: null,
      wabaId: null,
      field: null,
      phoneNumberId: null,
    });
  });
});
'@

Write-Text `
    -Path ".\packages\meta-cloud-api\src\webhook-payload.spec.ts" `
    -Content $MetaPayloadTests

Write-Host "[OK] @crm/meta-cloud-api criado." -ForegroundColor Green

# ============================================================
# WHATSAPP META CONFIGURATION SERVICE
# ============================================================

$WhatsAppService = Read-Text -Path $WhatsAppServicePath

if (
    -not $WhatsAppService.Contains(
        "ConfigureWhatsAppMetaInput"
    )
) {
    $OldImport = @'
import type { CreateWhatsAppNumberInput, UpdateWhatsAppNumberInput } from '@crm/validation';
'@

    $NewImport = @'
import type {
  ConfigureWhatsAppMetaInput,
  CreateWhatsAppNumberInput,
  UpdateWhatsAppNumberInput,
} from '@crm/validation';
'@

    if (
        -not $WhatsAppService.Contains(
            $OldImport
        )
    ) {
        throw "Import validation WhatsApp service nao encontrado."
    }

    $WhatsAppService = $WhatsAppService.Replace(
        $OldImport,
        $NewImport
    )
}

if (
    -not $WhatsAppService.Contains(
        "async configureMetaCloud("
    )
) {
    $Anchor = "  private async getAccessibleNumber("

    $Index = $WhatsAppService.IndexOf(
        $Anchor
    )

    if ($Index -lt 0) {
        throw "getAccessibleNumber anchor nao encontrado."
    }

    $ConfigureMethod = @'
  async configureMetaCloud(
    principal: AuthenticatedPrincipal,
    numberId: string,
    input: ConfigureWhatsAppMetaInput,
  ): Promise<WhatsAppNumberResponse> {
    await this.getOrganizationNumber(
      principal.organizationId,
      numberId,
    );

    const connected =
      input.wabaId !== null &&
      input.phoneNumberId !== null;

    try {
      const number =
        await this.database.client.$transaction(
          async (transaction) => {
            const updated =
              await transaction.whatsAppNumber.update({
                where: {
                  id:
                    numberId,
                },

                data: {
                  metaWabaId:
                    input.wabaId,

                  metaPhoneNumberId:
                    input.phoneNumberId,

                  metaConnectedAt:
                    connected
                      ? new Date()
                      : null,

                  ...(!connected
                    ? {
                        metaWebhookLastSeenAt:
                          null,
                      }
                    : {}),
                },

                include: {
                  assignedEmployee: {
                    include: {
                      user: {
                        select: {
                          displayName:
                            true,
                        },
                      },
                    },
                  },
                },
              });

            await transaction.auditLog.create({
              data: {
                organizationId:
                  principal.organizationId,

                actorType:
                  'USER',

                actorUserId:
                  principal.userId,

                action:
                  connected
                    ? 'whatsapp_number.meta_connected'
                    : 'whatsapp_number.meta_disconnected',

                resourceType:
                  'whatsapp_number',

                resourceId:
                  updated.id,

                outcome:
                  'SUCCESS',

                metadata: {
                  wabaId:
                    updated.metaWabaId,

                  metaPhoneNumberId:
                    updated.metaPhoneNumberId,
                },
              },
            });

            return updated;
          },
        );

      return this.mapNumber(
        number,
      );
    }
    catch (error) {
      if (
        this.isUniqueConstraintError(
          error,
        )
      ) {
        throw new ConflictException({
          code:
            'META_PHONE_NUMBER_ALREADY_CONNECTED',

          message:
            'This Meta phone number ID is already connected to another WhatsApp number.',
        });
      }

      throw error;
    }
  }

'@

    $WhatsAppService = (
        $WhatsAppService.Substring(
            0,
            $Index
        ) +
        $ConfigureMethod +
        $WhatsAppService.Substring(
            $Index
        )
    )
}

if (
    -not $WhatsAppService.Contains(
        "number.metaWebhookLastSeenAt?.toISOString()"
    )
) {
    $MapStart = $WhatsAppService.IndexOf(
        "private mapNumber"
    )

    if ($MapStart -lt 0) {
        throw "mapNumber nao encontrado."
    }

    $Anchor = "      notes: number.notes,"

    $AnchorIndex =
        $WhatsAppService.IndexOf(
            $Anchor,
            $MapStart
        )

    if ($AnchorIndex -lt 0) {
        throw "mapNumber notes anchor nao encontrado."
    }

    $InsertAt =
        $AnchorIndex +
        $Anchor.Length

    $Fields = @'

      metaWabaId:
        number.metaWabaId,

      metaPhoneNumberId:
        number.metaPhoneNumberId,

      metaConnectedAt:
        number.metaConnectedAt?.toISOString() ??
        null,

      metaWebhookLastSeenAt:
        number.metaWebhookLastSeenAt?.toISOString() ??
        null,
'@

    $WhatsAppService = (
        $WhatsAppService.Substring(
            0,
            $InsertAt
        ) +
        $Fields +
        $WhatsAppService.Substring(
            $InsertAt
        )
    )
}

Write-Text `
    -Path $WhatsAppServicePath `
    -Content $WhatsAppService

# ============================================================
# WHATSAPP META CONFIGURATION CONTROLLER
# ============================================================

$WhatsAppController = Read-Text -Path $WhatsAppControllerPath

if (
    -not $WhatsAppController.Contains(
        "configureWhatsAppMetaSchema"
    )
) {
    $OldImport = @'
import { createWhatsAppNumberSchema, updateWhatsAppNumberSchema } from '@crm/validation';
'@

    $NewImport = @'
import {
  configureWhatsAppMetaSchema,
  createWhatsAppNumberSchema,
  updateWhatsAppNumberSchema,
} from '@crm/validation';
'@

    if (
        -not $WhatsAppController.Contains(
            $OldImport
        )
    ) {
        throw "Validation import controller nao encontrado."
    }

    $WhatsAppController = $WhatsAppController.Replace(
        $OldImport,
        $NewImport
    )
}

if (
    -not $WhatsAppController.Contains(
        "configureMetaCloud("
    )
) {
    $LastBrace =
        $WhatsAppController.LastIndexOf(
            "}"
        )

    if ($LastBrace -lt 0) {
        throw "Controller closing brace nao encontrado."
    }

    $Method = @'

  @Patch(':numberId/meta-cloud')
  @RequirePermissions('whatsapp_number.manage')
  configureMetaCloud(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param(
      'numberId',
      new ParseUUIDPipe(),
    )
    numberId: string,

    @Body()
    body: unknown,
  ): Promise<WhatsAppNumberResponse> {
    const parsed =
      configureWhatsAppMetaSchema.safeParse(
        body,
      );

    if (!parsed.success) {
      throw new BadRequestException({
        code:
          'WHATSAPP_META_VALIDATION_ERROR',

        message:
          'Invalid Meta Cloud API connection payload.',

        issues:
          parsed.error.issues.map(
            (issue) => ({
              code:
                issue.code,

              path:
                issue.path.join('.'),
            }),
          ),
      });
    }

    return this.whatsAppNumbersService.configureMetaCloud(
      principal,
      numberId,
      parsed.data,
    );
  }
'@

    $WhatsAppController = (
        $WhatsAppController.Substring(
            0,
            $LastBrace
        ).TrimEnd() +
        "`r`n" +
        $Method +
        "`r`n}" +
        "`r`n"
    )
}

Write-Text `
    -Path $WhatsAppControllerPath `
    -Content $WhatsAppController

Write-Host "[OK] WhatsAppNumber Meta connection API criada." -ForegroundColor Green

# ============================================================
# WEBHOOK INGRESS PACKAGE
# ============================================================

$WebhookPackage = @'
{
  "name": "@crm/webhook-ingress",
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
    "@crm/meta-cloud-api": "workspace:*",
    "@nestjs/common": "11.1.28",
    "@nestjs/core": "11.1.28",
    "@nestjs/platform-express": "11.1.28",
    "dotenv": "17.4.2",
    "reflect-metadata": "0.2.2",
    "rxjs": "7.8.2"
  }
}
'@

Write-Text `
    -Path $WebhookPackagePath `
    -Content $WebhookPackage

# ============================================================
# WEBHOOK LOAD ENV
# ============================================================

$WebhookLoadEnvironment = @'
import {
  config,
} from 'dotenv';

import {
  dirname,
  resolve,
} from 'node:path';

import {
  fileURLToPath,
} from 'node:url';

const appDirectory =
  resolve(
    dirname(
      fileURLToPath(
        import.meta.url,
      ),
    ),
    '..',
  );

config({
  path:
    resolve(
      appDirectory,
      '../../.env',
    ),

  quiet:
    true,
});
'@

Write-Text `
    -Path ".\apps\webhook-ingress\src\load-environment.ts" `
    -Content $WebhookLoadEnvironment

# ============================================================
# WEBHOOK DATABASE SERVICE
# ============================================================

$WebhookDatabaseService = @'
import {
  Injectable,
  type OnApplicationShutdown,
} from '@nestjs/common';

import {
  createDatabaseClient,
  type CrmDatabaseClient,
} from '@crm/database';

@Injectable()
export class DatabaseService
  implements OnApplicationShutdown {
  readonly client:
    CrmDatabaseClient =
      createDatabaseClient();

  async onApplicationShutdown():
  Promise<void> {
    await this.client.$disconnect();
  }
}
'@

Write-Text `
    -Path ".\apps\webhook-ingress\src\database.service.ts" `
    -Content $WebhookDatabaseService

# ============================================================
# WEBHOOK CONFIG
# ============================================================

$WebhookConfig = @'
export type MetaWebhookConfig =
  Readonly<{
    verifyToken: string | null;
    appSecret: string | null;
  }>;

function optionalEnvironment(
  name: string,
): string | null {
  const value =
    process.env[name]?.trim();

  return value
    ? value
    : null;
}

export function parseMetaWebhookConfig():
MetaWebhookConfig {
  return {
    verifyToken:
      optionalEnvironment(
        'META_WEBHOOK_VERIFY_TOKEN',
      ),

    appSecret:
      optionalEnvironment(
        'META_APP_SECRET',
      ),
  };
}
'@

Write-Text `
    -Path ".\apps\webhook-ingress\src\meta-webhook.config.ts" `
    -Content $WebhookConfig

# ============================================================
# WEBHOOK SERVICE
# ============================================================

$WebhookService = @'
import {
  createHash,
} from 'node:crypto';

import {
  Inject,
  Injectable,
} from '@nestjs/common';

import {
  extractMetaWebhookSummary,
} from '@crm/meta-cloud-api';

import {
  DatabaseService,
} from './database.service.js';

type JsonPrimitive =
  | string
  | number
  | boolean
  | null;

type JsonValue =
  | JsonPrimitive
  | JsonValue[]
  | {
      [key: string]:
        JsonValue;
    };

type JsonObject = {
  [key: string]:
    JsonValue;
};

function normalizeJsonValue(
  value: unknown,
): JsonValue {
  if (
    value === null ||
    typeof value === 'string' ||
    typeof value === 'boolean'
  ) {
    return value;
  }

  if (
    typeof value === 'number'
  ) {
    return Number.isFinite(
      value,
    )
      ? value
      : null;
  }

  if (
    Array.isArray(
      value,
    )
  ) {
    return value.map(
      (item) =>
        normalizeJsonValue(
          item,
        ),
    );
  }

  if (
    typeof value === 'object' &&
    value !== null
  ) {
    const result:
      JsonObject = {};

    for (
      const [
        key,
        item,
      ] of Object.entries(
        value,
      )
    ) {
      result[key] =
        normalizeJsonValue(
          item,
        );
    }

    return result;
  }

  return null;
}

function normalizePayload(
  value: unknown,
): JsonObject {
  const normalized =
    normalizeJsonValue(
      value,
    );

  if (
    typeof normalized === 'object' &&
    normalized !== null &&
    !Array.isArray(
      normalized,
    )
  ) {
    return normalized;
  }

  return {
    value:
      normalized,
  };
}

export type MetaWebhookIngestResult =
  Readonly<{
    envelopeId: string;
    status:
      | 'RECEIVED'
      | 'UNMATCHED'
      | 'IGNORED';
    organizationId: string | null;
    whatsAppNumberId: string | null;
  }>;

@Injectable()
export class MetaWebhookService {
  constructor(
    @Inject(DatabaseService)
    private readonly database:
      DatabaseService,
  ) {}

  async ingest(
    payload: unknown,
    rawBody: Buffer,
  ): Promise<MetaWebhookIngestResult> {
    const summary =
      extractMetaWebhookSummary(
        payload,
      );

    const payloadHash =
      createHash(
        'sha256',
      )
        .update(
          rawBody,
        )
        .digest(
          'hex',
        );

    const number =
      summary.phoneNumberId
        ? await this.database.client.whatsAppNumber.findFirst({
            where: {
              metaPhoneNumberId:
                summary.phoneNumberId,

              deletedAt:
                null,

              ...(summary.wabaId
                ? {
                    metaWabaId:
                      summary.wabaId,
                  }
                : {}),
            },

            select: {
              id:
                true,

              organizationId:
                true,
            },
          })
        : null;

    const status:
      'RECEIVED' |
      'UNMATCHED' |
      'IGNORED' =
      summary.object !==
      'whatsapp_business_account'
        ? 'IGNORED'
        : number
          ? 'RECEIVED'
          : 'UNMATCHED';

    const receivedAt =
      new Date();

    const envelope =
      await this.database.client.$transaction(
        async (transaction) => {
          const stored =
            await transaction.metaWebhookEnvelope.upsert({
              where: {
                payloadHash,
              },

              create: {
                organizationId:
                  number?.organizationId ??
                  null,

                whatsAppNumberId:
                  number?.id ??
                  null,

                object:
                  summary.object,

                field:
                  summary.field,

                wabaId:
                  summary.wabaId,

                metaPhoneNumberId:
                  summary.phoneNumberId,

                payloadHash,

                payload:
                  normalizePayload(
                    payload,
                  ),

                status,

                receivedAt,
              },

              update: {},
            });

          if (number) {
            await transaction.whatsAppNumber.update({
              where: {
                id:
                  number.id,
              },

              data: {
                metaWebhookLastSeenAt:
                  receivedAt,
              },
            });
          }

          return stored;
        },
      );

    return {
      envelopeId:
        envelope.id,

      status:
        envelope.status ===
        'RECEIVED'
          ? 'RECEIVED'
          : envelope.status ===
              'UNMATCHED'
            ? 'UNMATCHED'
            : 'IGNORED',

      organizationId:
        envelope.organizationId,

      whatsAppNumberId:
        envelope.whatsAppNumberId,
    };
  }
}
'@

Write-Text `
    -Path ".\apps\webhook-ingress\src\meta-webhook.service.ts" `
    -Content $WebhookService

# ============================================================
# WEBHOOK CONTROLLER
# ============================================================

$WebhookController = @'
import {
  BadRequestException,
  Body,
  Controller,
  ForbiddenException,
  Get,
  Header,
  Headers,
  HttpCode,
  HttpStatus,
  Inject,
  Post,
  Query,
  Req,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';

import {
  verifyMetaWebhookChallenge,
  verifyMetaWebhookSignature,
} from '@crm/meta-cloud-api';

import {
  parseMetaWebhookConfig,
} from './meta-webhook.config.js';

import {
  MetaWebhookService,
} from './meta-webhook.service.js';

type RequestWithRawBody =
  Readonly<{
    rawBody?: Buffer;
  }>;

@Controller('webhooks/meta/whatsapp')
export class MetaWebhookController {
  private readonly config =
    parseMetaWebhookConfig();

  constructor(
    @Inject(MetaWebhookService)
    private readonly webhookService:
      MetaWebhookService,
  ) {}

  @Get()
  @Header(
    'Content-Type',
    'text/plain',
  )
  verify(
    @Query('hub.mode')
    mode: string | undefined,

    @Query('hub.verify_token')
    verifyToken: string | undefined,

    @Query('hub.challenge')
    challenge: string | undefined,
  ): string {
    if (!this.config.verifyToken) {
      throw new ServiceUnavailableException({
        code:
          'META_WEBHOOK_NOT_CONFIGURED',

        message:
          'Meta webhook verification is not configured.',
      });
    }

    const result =
      verifyMetaWebhookChallenge({
        mode,

        providedToken:
          verifyToken,

        challenge,

        expectedToken:
          this.config.verifyToken,
      });

    if (result === null) {
      throw new ForbiddenException({
        code:
          'META_WEBHOOK_VERIFICATION_DENIED',

        message:
          'Meta webhook verification failed.',
      });
    }

    return result;
  }

  @Post()
  @HttpCode(
    HttpStatus.OK,
  )
  @Header(
    'Content-Type',
    'text/plain',
  )
  async receive(
    @Req()
    request:
      RequestWithRawBody,

    @Headers(
      'x-hub-signature-256',
    )
    signature:
      string | undefined,

    @Body()
    payload:
      unknown,
  ): Promise<string> {
    if (!this.config.appSecret) {
      throw new ServiceUnavailableException({
        code:
          'META_WEBHOOK_NOT_CONFIGURED',

        message:
          'Meta webhook signature validation is not configured.',
      });
    }

    const rawBody =
      request.rawBody;

    if (
      !rawBody ||
      rawBody.length === 0
    ) {
      throw new BadRequestException({
        code:
          'META_WEBHOOK_RAW_BODY_REQUIRED',

        message:
          'Raw webhook body is required.',
      });
    }

    if (
      !verifyMetaWebhookSignature(
        this.config.appSecret,
        rawBody,
        signature,
      )
    ) {
      throw new UnauthorizedException({
        code:
          'META_WEBHOOK_SIGNATURE_INVALID',

        message:
          'Invalid Meta webhook signature.',
      });
    }

    const result =
      await this.webhookService.ingest(
        payload,
        rawBody,
      );

    console.log(
      JSON.stringify({
        event:
          'meta.webhook.received',

        envelopeId:
          result.envelopeId,

        status:
          result.status,

        matched:
          result.whatsAppNumberId !==
          null,

        timestamp:
          new Date().toISOString(),
      }),
    );

    return 'EVENT_RECEIVED';
  }
}
'@

Write-Text `
    -Path ".\apps\webhook-ingress\src\meta-webhook.controller.ts" `
    -Content $WebhookController

# ============================================================
# WEBHOOK APP MODULE
# ============================================================

$WebhookAppModule = @'
import {
  Module,
} from '@nestjs/common';

import {
  DatabaseService,
} from './database.service.js';

import {
  HealthController,
} from './health.controller.js';

import {
  MetaWebhookController,
} from './meta-webhook.controller.js';

import {
  MetaWebhookService,
} from './meta-webhook.service.js';

@Module({
  controllers: [
    HealthController,
    MetaWebhookController,
  ],

  providers: [
    DatabaseService,
    MetaWebhookService,
  ],
})
export class AppModule {}
'@

Write-Text `
    -Path $WebhookAppModulePath `
    -Content $WebhookAppModule

# ============================================================
# WEBHOOK MAIN WITH RAW BODY
# ============================================================

$WebhookMain = @'
import './load-environment.js';
import 'reflect-metadata';

import {
  NestFactory,
} from '@nestjs/core';

import {
  AppModule,
} from './app.module.js';

async function bootstrap():
Promise<void> {
  const app =
    await NestFactory.create(
      AppModule,
      {
        abortOnError:
          true,

        rawBody:
          true,
      },
    );

  app.enableShutdownHooks();

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
    -Path $WebhookMainPath `
    -Content $WebhookMain

Write-Host "[OK] Meta webhook ingress criado." -ForegroundColor Green

# ============================================================
# ENVIRONMENT
# ============================================================

$EnvExample = Read-Text -Path $EnvExamplePath

if (
    -not $EnvExample.Contains(
        "META_GRAPH_API_VERSION="
    )
) {
    $MetaEnvironment = @(
        "",
        "# Meta Cloud API - Etapa 8",
        "# Set the Graph API version explicitly for each environment.",
        "META_GRAPH_API_VERSION=",
        "META_GRAPH_BASE_URL=https://graph.facebook.com",
        "META_HTTP_TIMEOUT_MS=10000",
        "",
        "# Server-side secrets. Never expose these with NEXT_PUBLIC_.",
        "META_ACCESS_TOKEN=",
        "META_APP_SECRET=",
        "META_WEBHOOK_VERIFY_TOKEN="
    )

    $EnvExample = (
        $EnvExample.TrimEnd() +
        "`r`n" +
        ($MetaEnvironment -join "`r`n") +
        "`r`n"
    )

    Write-Text `
        -Path $EnvExamplePath `
        -Content $EnvExample
}

Write-Host "[OK] Meta environment configurado." -ForegroundColor Green

# ============================================================
# STRUCTURAL VALIDATION
# ============================================================

$RequiredFiles = @(
    ".\packages\meta-cloud-api\package.json",
    ".\packages\meta-cloud-api\tsconfig.json",
    ".\packages\meta-cloud-api\src\index.ts",
    ".\packages\meta-cloud-api\src\config.ts",
    ".\packages\meta-cloud-api\src\client.ts",
    ".\packages\meta-cloud-api\src\webhook-security.ts",
    ".\packages\meta-cloud-api\src\webhook-payload.ts",
    ".\packages\meta-cloud-api\src\webhook-security.spec.ts",
    ".\packages\meta-cloud-api\src\webhook-payload.spec.ts",
    ".\packages\contracts\src\meta-cloud.ts",
    ".\packages\validation\src\meta-cloud.ts",
    ".\apps\webhook-ingress\src\load-environment.ts",
    ".\apps\webhook-ingress\src\database.service.ts",
    ".\apps\webhook-ingress\src\meta-webhook.config.ts",
    ".\apps\webhook-ingress\src\meta-webhook.service.ts",
    ".\apps\webhook-ingress\src\meta-webhook.controller.ts"
)

foreach ($RequiredFile in $RequiredFiles) {
    if (-not (Test-Path $RequiredFile)) {
        throw "Arquivo Stage 8 ausente: $RequiredFile"
    }
}

$SchemaFinal = Read-Text -Path $SchemaPath

foreach ($Marker in @(
    "enum MetaWebhookStatus",
    "model MetaWebhookEnvelope",
    "metaWabaId",
    "metaPhoneNumberId",
    "metaWebhookLastSeenAt"
)) {
    if (-not $SchemaFinal.Contains($Marker)) {
        throw "Marker Stage 8 ausente no Prisma: $Marker"
    }
}

$WebhookControllerFinal = Read-Text `
    -Path ".\apps\webhook-ingress\src\meta-webhook.controller.ts"

foreach ($Marker in @(
    "x-hub-signature-256",
    "verifyMetaWebhookSignature",
    "config.verifyToken",
    "EVENT_RECEIVED"
)) {
    if (-not $WebhookControllerFinal.Contains($Marker)) {
        throw "Webhook ingress marker ausente: $Marker"
    }
}

$WebhookMainFinal = Read-Text `
    -Path $WebhookMainPath

if (-not $WebhookMainFinal.Contains("rawBody:")) {
    throw "Webhook ingress nao preserva raw body."
}

$MetaClientFinal = Read-Text `
    -Path ".\packages\meta-cloud-api\src\client.ts"

if (
    -not $MetaClientFinal.Contains(
        "Authorization:"
    )
) {
    throw "Meta Graph client nao possui Bearer Authorization."
}

if (
    $MetaClientFinal.Contains(
        "v23."
    ) -or
    $MetaClientFinal.Contains(
        "v24."
    ) -or
    $MetaClientFinal.Contains(
        "v25."
    )
) {
    throw "Graph API version nao deve ser hardcoded."
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host "[OK] MACROBLOCO 8.1 CRIADO." -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Implementado:" -ForegroundColor Cyan
Write-Host "- @crm/meta-cloud-api"
Write-Host "- Graph API client"
Write-Host "- explicit Graph API version config"
Write-Host "- Bearer access token"
Write-Host "- HTTP timeout"
Write-Host "- normalized Meta errors"
Write-Host "- webhook verification challenge"
Write-Host "- HMAC SHA-256 signature validation"
Write-Host "- raw webhook body"
Write-Host "- WABA ID extraction"
Write-Host "- Meta Phone Number ID extraction"
Write-Host "- MetaWebhookEnvelope"
Write-Host "- payload SHA-256 deduplication"
Write-Host "- tenant/number webhook resolution"
Write-Host "- RECEIVED / UNMATCHED / IGNORED"
Write-Host "- claim/lease fields ready for Stage 9"
Write-Host "- WhatsAppNumber WABA mapping"
Write-Host "- WhatsAppNumber Phone Number ID mapping"
Write-Host "- webhook last-seen tracking"
Write-Host "- connect/disconnect Meta API endpoint"
Write-Host "- no Meta secrets persisted in database"
Write-Host ""
Write-Host "Migration ainda NAO executada." -ForegroundColor Yellow
Write-Host "Credenciais reais da Meta ainda NAO sao necessarias." -ForegroundColor Yellow
Write-Host "Proximo: Macrobloco 8.2." -ForegroundColor Yellow