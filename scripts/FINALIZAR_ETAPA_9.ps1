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
        New-Item `
            -ItemType Directory `
            -Path $Parent `
            -Force |
            Out-Null
    }

    [System.IO.File]::WriteAllLines(
        $FullPath,
        $Lines,
        $Utf8NoBom
    )
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " ETAPA 9 - MACROBLOCO 9.2" -ForegroundColor Cyan
Write-Host " WHATSAPP INBOX AUDIT + CLOSURE" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

# ============================================================
# PREFLIGHT
# ============================================================

$RequiredFiles = @(
    ".\packages\database\prisma\schema.prisma",
    ".\packages\database\prisma\seed.ts",
    ".\packages\database\prisma\verify-seed.ts",
    ".\packages\contracts\src\inbox.ts",
    ".\packages\validation\src\inbox.ts",
    ".\packages\meta-cloud-api\src\whatsapp-webhook-events.ts",
    ".\apps\api\src\inbox\inbox.service.ts",
    ".\apps\api\src\inbox\inbox.controller.ts",
    ".\apps\api\src\inbox\inbox.module.ts",
    ".\apps\worker\src\whatsapp-runtime.config.ts",
    ".\apps\worker\src\whatsapp-inbox-processor.service.ts",
    ".\apps\worker\src\whatsapp-outbound-dispatcher.service.ts"
)

foreach ($File in $RequiredFiles) {
    if (-not (Test-Path $File)) {
        throw "Macrobloco 9.1 incompleto: $File"
    }
}

Write-Host "[OK] Preflight 9.1." -ForegroundColor Green

# ============================================================
# HARDEN NULLABLE IDEMPOTENCY KEYS
# Prisma @@unique cannot contain nullable fields.
# ============================================================

$SchemaPath =
    ".\packages\database\prisma\schema.prisma"

$Schema =
    Read-Text -Path $SchemaPath

$Schema =
    $Schema.Replace(
        '  metaMessageId         String?                  @db.VarChar(255)',
        '  metaMessageId         String?                  @unique @db.VarChar(255)'
    )

$Schema =
    $Schema.Replace(
        '  clientMessageId       String?                  @db.Uuid',
        '  clientMessageId       String?                  @unique @db.Uuid'
    )

$Schema =
    $Schema.Replace(
        "  @@unique([organizationId, metaMessageId])`r`n",
        ""
    )

$Schema =
    $Schema.Replace(
        "  @@unique([organizationId, metaMessageId])`n",
        ""
    )

$Schema =
    $Schema.Replace(
        "  @@unique([organizationId, clientMessageId])`r`n",
        ""
    )

$Schema =
    $Schema.Replace(
        "  @@unique([organizationId, clientMessageId])`n",
        ""
    )

Write-Text `
    -Path $SchemaPath `
    -Content $Schema

Write-Host "[OK] Idempotency keys Stage 9 endurecidas." -ForegroundColor Green

# ============================================================
# PATCH API FOR GLOBAL OPTIONAL UNIQUE clientMessageId
# ============================================================

$InboxServicePath =
    ".\apps\api\src\inbox\inbox.service.ts"

$InboxService =
    Read-Text -Path $InboxServicePath

$OldClientLookup = @'
    const existing =
      await this.database.client.whatsAppMessage.findUnique({
        where: {
          organizationId_clientMessageId: {
            organizationId:
              principal.organizationId,

            clientMessageId:
              input.clientMessageId,
          },
        },
      });
'@

$NewClientLookup = @'
    const existing =
      await this.database.client.whatsAppMessage.findUnique({
        where: {
          clientMessageId:
            input.clientMessageId,
        },
      });
'@

if ($InboxService.Contains($OldClientLookup.Trim())) {
    $InboxService =
        $InboxService.Replace(
            $OldClientLookup.Trim(),
            $NewClientLookup.Trim()
        )
}

$OldExistingCheck = @'
    if (existing) {
      if (
        existing.conversationId !==
        conversation.id
      ) {
'@

$NewExistingCheck = @'
    if (existing) {
      if (
        existing.organizationId !==
          principal.organizationId ||
        existing.conversationId !==
          conversation.id
      ) {
'@

if ($InboxService.Contains($OldExistingCheck.Trim())) {
    $InboxService =
        $InboxService.Replace(
            $OldExistingCheck.Trim(),
            $NewExistingCheck.Trim()
        )
}

Write-Text `
    -Path $InboxServicePath `
    -Content $InboxService

# ============================================================
# PATCH WORKER FOR GLOBAL OPTIONAL UNIQUE metaMessageId
# ============================================================

$InboxProcessorPath =
    ".\apps\worker\src\whatsapp-inbox-processor.service.ts"

$InboxProcessor =
    Read-Text -Path $InboxProcessorPath

$OldMessageLookup = @'
        const existing =
          await transaction.whatsAppMessage.findUnique({
            where: {
              organizationId_metaMessageId: {
                organizationId,
                metaMessageId:
                  event.messageId,
              },
            },

            select: {
              id:
                true,
            },
          });

        if (existing) {
          return false;
        }
'@

$NewMessageLookup = @'
        const existing =
          await transaction.whatsAppMessage.findUnique({
            where: {
              metaMessageId:
                event.messageId,
            },

            select: {
              id:
                true,

              organizationId:
                true,
            },
          });

        if (existing) {
          if (
            existing.organizationId !==
              organizationId
          ) {
            throw new Error(
              'Meta message id collision across organizations.',
            );
          }

          return false;
        }
'@

if ($InboxProcessor.Contains($OldMessageLookup.Trim())) {
    $InboxProcessor =
        $InboxProcessor.Replace(
            $OldMessageLookup.Trim(),
            $NewMessageLookup.Trim()
        )
}

$OldStatusMessageLookup = @'
        const message =
          await transaction.whatsAppMessage.findUnique({
            where: {
              organizationId_metaMessageId: {
                organizationId,

                metaMessageId:
                  event.messageId,
              },
            },
          });
'@

$NewStatusMessageLookup = @'
        const message =
          await transaction.whatsAppMessage.findUnique({
            where: {
              metaMessageId:
                event.messageId,
            },
          });

        if (
          message &&
          message.organizationId !==
            organizationId
        ) {
          throw new Error(
            'Meta status message id collision across organizations.',
          );
        }
'@

if ($InboxProcessor.Contains($OldStatusMessageLookup.Trim())) {
    $InboxProcessor =
        $InboxProcessor.Replace(
            $OldStatusMessageLookup.Trim(),
            $NewStatusMessageLookup.Trim()
        )
}

# JSON input hardening

if (-not $InboxProcessor.Contains("function normalizeJsonObject(")) {
    $NormalizeAnchor = @'
function parseProviderTimestamp(
'@

    if (-not $InboxProcessor.Contains($NormalizeAnchor.Trim())) {
        throw "normalizeJsonValue anchor Stage 9 nao encontrado."
    }

    $JsonHelpers = @'
function normalizeJsonObject(
  value: unknown,
): JsonObject {
  const normalized =
    normalizeJsonValue(
      value,
    );

  if (
    typeof normalized ===
      'object' &&
    normalized !==
      null &&
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

function normalizeJsonArray(
  value:
    readonly unknown[],
): JsonValue[] {
  return value.map(
    normalizeJsonValue,
  );
}

'@

    $InboxProcessor =
        $InboxProcessor.Replace(
            $NormalizeAnchor.Trim(),
            $JsonHelpers +
            $NormalizeAnchor.Trim()
        )
}

$InboxProcessor =
    $InboxProcessor.Replace(
        "content:`r`n              normalizeJsonValue(`r`n                event.payload,`r`n              ),",
        "content:`r`n              normalizeJsonObject(`r`n                event.payload,`r`n              ),"
    )

$InboxProcessor =
    $InboxProcessor.Replace(
        "content:`n              normalizeJsonValue(`n                event.payload,`n              ),",
        "content:`n              normalizeJsonObject(`n                event.payload,`n              ),"
    )

$InboxProcessor =
    $InboxProcessor.Replace(
        "errors:`r`n                      normalizeJsonValue(`r`n                        event.errors,`r`n                      ),",
        "errors:`r`n                      normalizeJsonArray(`r`n                        event.errors,`r`n                      ),"
    )

$InboxProcessor =
    $InboxProcessor.Replace(
        "errors:`n                      normalizeJsonValue(`n                        event.errors,`n                      ),",
        "errors:`n                      normalizeJsonArray(`n                        event.errors,`n                      ),"
    )

$InboxProcessor =
    $InboxProcessor.Replace(
        "payload:`r`n                normalizeJsonValue(`r`n                  event.payload,`r`n                ),",
        "payload:`r`n                normalizeJsonObject(`r`n                  event.payload,`r`n                ),"
    )

$InboxProcessor =
    $InboxProcessor.Replace(
        "payload:`n                normalizeJsonValue(`n                  event.payload,`n                ),",
        "payload:`n                normalizeJsonObject(`n                  event.payload,`n                ),"
    )

Write-Text `
    -Path $InboxProcessorPath `
    -Content $InboxProcessor

Write-Host "[OK] Inbox processor endurecido." -ForegroundColor Green

# ============================================================
# OUTBOUND: RECHECK 24H WINDOW AT DISPATCH TIME
# ============================================================

$OutboundPath =
    ".\apps\worker\src\whatsapp-outbound-dispatcher.service.ts"

$Outbound =
    Read-Text -Path $OutboundPath

if (-not $Outbound.Contains("customerServiceWindowExpiresAt:")) {
    $ContactInclude = @'
          contact: {
            select: {
              waId:
                true,
            },
          },

          whatsAppNumber: {
'@

    $ContactReplacement = @'
          contact: {
            select: {
              waId:
                true,
            },
          },

          conversation: {
            select: {
              customerServiceWindowExpiresAt:
                true,
            },
          },

          whatsAppNumber: {
'@

    if (-not $Outbound.Contains($ContactInclude.Trim())) {
        throw "Outbound conversation include anchor nao encontrado."
    }

    $Outbound =
        $Outbound.Replace(
            $ContactInclude.Trim(),
            $ContactReplacement.Trim()
        )
}

if (-not $Outbound.Contains("'LOCAL_POLICY_WINDOW_CLOSED'")) {
    $BeforeBody = @'
    const body =
      this.buildMetaPayload(
'@

    $WindowCheck = @'
    if (
      message.type ===
        'TEXT' &&
      (
        !message.conversation.customerServiceWindowExpiresAt ||
        message.conversation.customerServiceWindowExpiresAt <=
          new Date()
      )
    ) {
      throw new MetaCloudApiError({
        status:
          400,

        message:
          'The 24-hour customer service window is closed.',

        code:
          null,

        errorSubcode:
          null,

        metaType:
          'LOCAL_POLICY_WINDOW_CLOSED',

        fbtraceId:
          null,

        requestId:
          null,
      });
    }

'@

    if (-not $Outbound.Contains($BeforeBody.Trim())) {
        throw "Outbound body anchor nao encontrado."
    }

    $Outbound =
        $Outbound.Replace(
            $BeforeBody.Trim(),
            $WindowCheck +
            $BeforeBody.Trim()
        )
}

$OldErrorCode = @'
          errorCode:
            uncertainOutcome
              ? 'OUTBOUND_DELIVERY_UNKNOWN'
              : metaError?.code !==
                    null &&
                  metaError?.code !==
                    undefined
                ? `META_${metaError.code}`
                : 'META_SEND_FAILED',
'@

$NewErrorCode = @'
          errorCode:
            uncertainOutcome
              ? 'OUTBOUND_DELIVERY_UNKNOWN'
              : metaError?.metaType ===
                    'LOCAL_POLICY_WINDOW_CLOSED'
                ? 'WHATSAPP_CUSTOMER_SERVICE_WINDOW_CLOSED'
                : metaError?.code !==
                      null &&
                    metaError?.code !==
                      undefined
                  ? `META_${metaError.code}`
                  : 'META_SEND_FAILED',
'@

if ($Outbound.Contains($OldErrorCode.Trim())) {
    $Outbound =
        $Outbound.Replace(
            $OldErrorCode.Trim(),
            $NewErrorCode.Trim()
        )
}

Write-Text `
    -Path $OutboundPath `
    -Content $Outbound

Write-Host "[OK] Outbound 24h dispatch guard criado." -ForegroundColor Green

# ============================================================
# HARDEN 9.1 GENERATOR TOO
# ============================================================

$Stage91Path =
    ".\scripts\CRIAR_ETAPA_9_MACROBLOCO_1.ps1"

if (Test-Path $Stage91Path) {
    $Stage91 =
        Read-Text -Path $Stage91Path

    $Stage91 =
        $Stage91.Replace(
            'metaMessageId         String?                  @db.VarChar(255)',
            'metaMessageId         String?                  @unique @db.VarChar(255)'
        )

    $Stage91 =
        $Stage91.Replace(
            'clientMessageId       String?                  @db.Uuid',
            'clientMessageId       String?                  @unique @db.Uuid'
        )

    $Stage91 =
        $Stage91.Replace(
            "  @@unique([organizationId, metaMessageId])`r`n",
            ""
        )

    $Stage91 =
        $Stage91.Replace(
            "  @@unique([organizationId, clientMessageId])`r`n",
            ""
        )

    $Stage91 =
        $Stage91.Replace(
            "  @@unique([organizationId, metaMessageId])`n",
            ""
        )

    $Stage91 =
        $Stage91.Replace(
            "  @@unique([organizationId, clientMessageId])`n",
            ""
        )

    Write-Text `
        -Path $Stage91Path `
        -Content $Stage91
}

# ============================================================
# TESTS - META WEBHOOK PARSER
# ============================================================

$MetaParserTests = @'
import {
  describe,
  expect,
  it,
} from 'vitest';

import {
  parseWhatsAppWebhookEvents,
} from './whatsapp-webhook-events.js';

describe(
  'parseWhatsAppWebhookEvents',
  () => {
    it(
      'extracts inbound messages',
      () => {
        const events =
          parseWhatsAppWebhookEvents({
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
                          '987654321',
                      },

                      contacts: [
                        {
                          wa_id:
                            '5511999999999',

                          profile: {
                            name:
                              'Cliente Stage 9',
                          },
                        },
                      ],

                      messages: [
                        {
                          id:
                            'wamid.stage9.parser.inbound',

                          from:
                            '5511999999999',

                          timestamp:
                            '1700000000',

                          type:
                            'text',

                          text: {
                            body:
                              'Ola',
                          },
                        },
                      ],
                    },
                  },
                ],
              },
            ],
          });

        expect(
          events,
        ).toHaveLength(
          1,
        );

        expect(
          events[0],
        ).toMatchObject({
          kind:
            'MESSAGE',

          messageId:
            'wamid.stage9.parser.inbound',

          from:
            '5511999999999',

          messageType:
            'text',

          textBody:
            'Ola',

          profileName:
            'Cliente Stage 9',

          phoneNumberId:
            '987654321',

          wabaId:
            '123456789',
        });
      },
    );

    it(
      'extracts delivery statuses',
      () => {
        const events =
          parseWhatsAppWebhookEvents({
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
                          '987654321',
                      },

                      statuses: [
                        {
                          id:
                            'wamid.stage9.parser.outbound',

                          recipient_id:
                            '5511999999999',

                          status:
                            'delivered',

                          timestamp:
                            '1700000001',
                        },
                      ],
                    },
                  },
                ],
              },
            ],
          });

        expect(
          events,
        ).toHaveLength(
          1,
        );

        expect(
          events[0],
        ).toMatchObject({
          kind:
            'STATUS',

          messageId:
            'wamid.stage9.parser.outbound',

          status:
            'delivered',

          recipientId:
            '5511999999999',
        });
      },
    );

    it(
      'ignores malformed events safely',
      () => {
        expect(
          parseWhatsAppWebhookEvents(
            null,
          ),
        ).toEqual(
          [],
        );

        expect(
          parseWhatsAppWebhookEvents({
            entry: [
              null,
              {},
            ],
          }),
        ).toEqual(
          [],
        );
      },
    );
  },
);
'@

Write-Text `
    -Path ".\packages\meta-cloud-api\src\whatsapp-webhook-events.spec.ts" `
    -Content $MetaParserTests

# ============================================================
# TESTS - VALIDATION
# ============================================================

$ValidationTests = @'
import {
  describe,
  expect,
  it,
} from 'vitest';

import {
  createInboxQuickReplySchema,
  sendInboxMessageSchema,
  updateInboxConversationSchema,
} from './inbox.js';

describe(
  'Stage 9 inbox validation',
  () => {
    it(
      'accepts a text message',
      () => {
        expect(
          sendInboxMessageSchema.safeParse({
            clientMessageId:
              '8eaa25de-f318-47c4-b86b-20735f887e00',

            type:
              'TEXT',

            text:
              'Ola',
          }).success,
        ).toBe(
          true,
        );
      },
    );

    it(
      'accepts a template message',
      () => {
        expect(
          sendInboxMessageSchema.safeParse({
            clientMessageId:
              '1b024628-7958-46f3-8be1-658ee446b07d',

            type:
              'TEMPLATE',

            templateName:
              'order_update',

            languageCode:
              'pt_BR',
          }).success,
        ).toBe(
          true,
        );
      },
    );

    it(
      'rejects unknown fields',
      () => {
        expect(
          sendInboxMessageSchema.safeParse({
            clientMessageId:
              '8eaa25de-f318-47c4-b86b-20735f887e00',

            type:
              'TEXT',

            text:
              'Ola',

            organizationId:
              '24a9b07c-ea64-47b9-b0e3-6c4a550c1733',
          }).success,
        ).toBe(
          false,
        );
      },
    );

    it(
      'requires an update field',
      () => {
        expect(
          updateInboxConversationSchema.safeParse(
            {},
          ).success,
        ).toBe(
          false,
        );
      },
    );

    it(
      'normalizes quick reply shortcut',
      () => {
        const parsed =
          createInboxQuickReplySchema.parse({
            title:
              'Boas vindas',

            shortcut:
              '  BOAS_VINDAS  ',

            body:
              'Ola!',
          });

        expect(
          parsed.shortcut,
        ).toBe(
          'boas_vindas',
        );
      },
    );
  },
);
'@

Write-Text `
    -Path ".\packages\validation\src\inbox.spec.ts" `
    -Content $ValidationTests

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

$MigrationRoot =
    ".\packages\database\prisma\migrations"

$Migration =
    Get-ChildItem `
        -Path $MigrationRoot `
        -Directory `
        -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -like "*stage_9_whatsapp_inbox*"
    } |
    Select-Object -First 1

if ($null -eq $Migration) {
    Invoke-Native `
        -Description "Create Stage 9 migration" `
        -Command "pnpm" `
        -Arguments @(
            "--filter",
            "@crm/database",
            "exec",
            "prisma",
            "migrate",
            "dev",
            "--name",
            "stage_9_whatsapp_inbox",
            "--create-only"
        )
}

$Migration =
    Get-ChildItem `
        -Path $MigrationRoot `
        -Directory `
        -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -like "*stage_9_whatsapp_inbox*"
    } |
    Select-Object -First 1

if ($null -eq $Migration) {
    throw "Migration Stage 9 nao encontrada."
}

Write-Host "[OK] Migration: $($Migration.Name)" -ForegroundColor Green

Invoke-Native `
    -Description "Deploy Stage 9 migration" `
    -Command "pnpm" `
    -Arguments @("db:migrate:deploy")

Invoke-Native `
    -Description "Prisma generate" `
    -Command "pnpm" `
    -Arguments @("db:generate")

# ============================================================
# SEED + PERMISSIONS
# ============================================================

Invoke-Native `
    -Description "Database seed Stage 9" `
    -Command "pnpm" `
    -Arguments @("db:seed")

Invoke-Native `
    -Description "Verify Stage 9 seed" `
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
    -Description "Format Stage 9" `
    -Command "pnpm" `
    -Arguments @("format")

# ============================================================
# TARGETED TESTS
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
    -Description "Database typecheck" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/database",
        "typecheck"
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
    -Description "API tests" `
    -Command "pnpm" `
    -Arguments @(
        "--filter",
        "@crm/api",
        "test"
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

# ============================================================
# TARGETED BUILDS
# ============================================================

Invoke-Native `
    -Description "Stage 9 dependency builds" `
    -Command "pnpm" `
    -Arguments @(
        "exec",
        "turbo",
        "run",
        "build",
        "--filter=@crm/api",
        "--filter=@crm/worker",
        "--filter=@crm/meta-cloud-api"
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
  WhatsAppInboxProcessorService,
} from '../src/whatsapp-inbox-processor.service.js';

import {
  WhatsAppOutboundDispatcherService,
} from '../src/whatsapp-outbound-dispatcher.service.js';

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
  process.env.SEED_ORGANIZATION_SLUG?.trim() ||
  'crm-ads-whatsapp';

const numberPrefix =
  'Stage 9 Runtime';

const employeeEmailPrefix =
  'stage9.runtime.';

const foreignOrgPrefix =
  'stage9-runtime-tenant-';

const metaPhonePrefix =
  '990900';

const contactPrefix =
  '55990900';

const quickReplyPrefix =
  `stage9_${unique}`;

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
        100,

      outboundIntervalMs:
        1000,

      outboundLeaseMs:
        30000,

      outboundMaxClaimsPerTick:
        25,

      outboundMaxAttempts:
        8,

      outboundRetryBaseMs: 5000,

      outboundDisabledRetryMs:
        1000,
    };

function event(
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

function numericSuffix(
  offset:
    number,
): string {
  return (
    Date.now()
      .toString()
      .slice(
        -8,
      ) +
    offset
      .toString()
      .padStart(
        2,
        '0',
      )
  );
}

function payloadHash(
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

async function cleanupFixtures():
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
    organization
  ) {
    const numbers =
      await database.whatsAppNumber.findMany({
        where: {
          organizationId:
            organization.id,

          displayName: {
            startsWith:
              numberPrefix,
          },
        },

        select: {
          id:
            true,
        },
      });

    const numberIds =
      numbers.map(
        (
          item,
        ) =>
          item.id,
      );

    const quickReplies =
      await database.whatsAppQuickReply.findMany({
        where: {
          organizationId:
            organization.id,

          shortcut: {
            startsWith:
              'stage9_',
          },
        },

        select: {
          id:
            true,
        },
      });

    const conversations =
      numberIds.length >
        0
        ? await database.whatsAppConversation.findMany({
            where: {
              organizationId:
                organization.id,

              whatsAppNumberId: {
                in:
                  numberIds,
              },
            },

            select: {
              id:
                true,
            },
          })
        : [];

    const messages =
      numberIds.length >
        0
        ? await database.whatsAppMessage.findMany({
            where: {
              organizationId:
                organization.id,

              whatsAppNumberId: {
                in:
                  numberIds,
              },
            },

            select: {
              id:
                true,
            },
          })
        : [];

    const resourceIds = [
      ...numberIds,

      ...quickReplies.map(
        (
          item,
        ) =>
          item.id,
      ),

      ...conversations.map(
        (
          item,
        ) =>
          item.id,
      ),

      ...messages.map(
        (
          item,
        ) =>
          item.id,
      ),
    ];

    if (
      resourceIds.length >
        0
    ) {
      await database.auditLog.deleteMany({
        where: {
          organizationId:
            organization.id,

          resourceId: {
            in:
              resourceIds,
          },
        },
      });
    }

    if (
      numberIds.length >
        0
    ) {
      await database.whatsAppMessageStatusEvent.deleteMany({
        where: {
          organizationId:
            organization.id,

          whatsAppNumberId: {
            in:
              numberIds,
          },
        },
      });

      await database.whatsAppMessage.deleteMany({
        where: {
          organizationId:
            organization.id,

          whatsAppNumberId: {
            in:
              numberIds,
          },
        },
      });

      await database.whatsAppConversation.deleteMany({
        where: {
          organizationId:
            organization.id,

          whatsAppNumberId: {
            in:
              numberIds,
          },
        },
      });

      await database.whatsAppContact.deleteMany({
        where: {
          organizationId:
            organization.id,

          waId: {
            startsWith:
              contactPrefix,
          },
        },
      });

      await database.metaWebhookEnvelope.deleteMany({
        where: {
          OR: [
            {
              whatsAppNumberId: {
                in:
                  numberIds,
              },
            },

            {
              metaPhoneNumberId: {
                startsWith:
                  metaPhonePrefix,
              },
            },
          ],
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

    await database.whatsAppQuickReply.deleteMany({
      where: {
        organizationId:
          organization.id,

        shortcut: {
          startsWith:
            'stage9_',
        },
      },
    });

    const users =
      await database.user.findMany({
        where: {
          organizationId:
            organization.id,

          emailNormalized: {
            startsWith:
              employeeEmailPrefix,
          },
        },

        select: {
          id:
            true,
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

      await database.employee.deleteMany({
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

  const foreignOrganizations =
    await database.organization.findMany({
      where: {
        slug: {
          startsWith:
            foreignOrgPrefix,
        },
      },

      select: {
        id:
          true,
      },
    });

  for (
    const organization of foreignOrganizations
  ) {
    await database.whatsAppMessageStatusEvent.deleteMany({
      where: {
        organizationId:
          organization.id,
      },
    });

    await database.whatsAppMessage.deleteMany({
      where: {
        organizationId:
          organization.id,
      },
    });

    await database.whatsAppConversation.deleteMany({
      where: {
        organizationId:
          organization.id,
      },
    });

    await database.whatsAppContact.deleteMany({
      where: {
        organizationId:
          organization.id,
      },
    });

    await database.metaWebhookEnvelope.deleteMany({
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

    await database.whatsAppQuickReply.deleteMany({
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

    await database.employee.deleteMany({
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

    await database.team.deleteMany({
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

async function createEnvelope(
  organizationId:
    string,
  whatsAppNumberId:
    string,
  wabaId:
    string,
  phoneNumberId:
    string,
  payload:
    Record<
      string,
      unknown
    >,
  override:
    Readonly<{
      status?:
        'RECEIVED' |
        'CLAIMED';

      claimedByWorkerId?:
        string | null;

      leaseExpiresAt?:
        Date | null;
    }> = {},
) {
  return database.metaWebhookEnvelope.create({
    data: {
      organizationId,

      whatsAppNumberId,

      object:
        'whatsapp_business_account',

      field:
        'messages',

      wabaId,

      metaPhoneNumberId:
        phoneNumberId,

      payloadHash:
        payloadHash(
          payload,
        ),

      payload,

      status:
        override.status ??
        'RECEIVED',

      ...(override.claimedByWorkerId !==
      undefined
        ? {
            claimedByWorkerId:
              override.claimedByWorkerId,
          }
        : {}),

      ...(override.status ===
      'CLAIMED'
        ? {
            claimedAt:
              new Date(
                Date.now() -
                  60000,
              ),
          }
        : {}),

      ...(override.leaseExpiresAt !==
      undefined
        ? {
            leaseExpiresAt:
              override.leaseExpiresAt,
          }
        : {}),
    },
  });
}

function inboundPayload(
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

      profileName:
        string;

      timestamp:
        number;
    }>,
): Record<
  string,
  unknown
> {
  return {
    stage9RuntimeNonce:
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
                      input.profileName,
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
                      'Mensagem Stage 9',
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

function statusPayload(
  input:
    Readonly<{
      nonce:
        string;

      wabaId:
        string;

      phoneNumberId:
        string;

      messageId:
        string;

      recipientId:
        string;

      statuses:
        readonly Readonly<{
          status:
            string;

          timestamp:
            number;
        }>[];
    }>,
): Record<
  string,
  unknown
> {
  return {
    stage9RuntimeNonce:
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

              statuses:
                input.statuses.map(
                  (
                    status,
                  ) => ({
                    id:
                      input.messageId,

                    recipient_id:
                      input.recipientId,

                    status:
                      status.status,

                    timestamp:
                      String(
                        status.timestamp,
                      ),
                  }),
                ),
            },
          },
        ],
      },
    ],
  };
}

function createMetaClient(
  handler:
    (
      body:
        Record<
          string,
          unknown
        >,
      url:
        string,
    ) =>
      Promise<Response>,
): MetaCloudApiClient {
  return new MetaCloudApiClient(
    {
      graphBaseUrl:
        'https://graph.example.test',

      graphApiVersion:
        'v99.0',

      accessToken:
        'stage9-runtime-token',

      timeoutMs:
        5000,
    },

    async (
      input,
      init,
    ) => {
      const raw =
        typeof init?.body ===
          'string'
          ? init.body
          : '{}';

      return handler(
        JSON.parse(
          raw,
        ) as Record<
          string,
          unknown
        >,

        String(
          input,
        ),
      );
    },
  );
}

async function main():
Promise<void> {
  event(
    'stage9.validation.started',
  );

  await cleanupFixtures();

  const pendingEnvelopeCount =
    await database.metaWebhookEnvelope.count({
      where: {
        status: {
          in: [
            'RECEIVED',
            'CLAIMED',
          ],
        },
      },
    });

  assert.equal(
    pendingEnvelopeCount,
    0,
    'Stage 9 runtime refuses to consume pre-existing pending webhook envelopes.',
  );

  const pendingOutboundCount =
    await database.whatsAppMessage.count({
      where: {
        direction:
          'OUTBOUND',

        status: {
          in: [
            'QUEUED',
            'SENDING',
          ],
        },
      },
    });

  assert.equal(
    pendingOutboundCount,
    0,
    'Stage 9 runtime refuses to touch pre-existing outbound queue items.',
  );

  const organization =
    await database.organization.findUniqueOrThrow({
      where: {
        slug:
          organizationSlug,
      },

      include: {
        teams: {
          where: {
            status:
              'ACTIVE',
          },

          take:
            1,
        },

        users: {
          where: {
            employee: {
              isNot:
                null,
            },
          },

          include: {
            employee:
              true,
          },

          take:
            1,
        },
      },
    });

  const team =
    organization.teams[0];

  const adminUser =
    organization.users[0];

  assert.ok(
    team,
    'Seed team missing.',
  );

  assert.ok(
    adminUser?.employee,
    'Seed employee missing.',
  );

  const primaryEmployee =
    adminUser.employee;

  const secondaryUser =
    await database.user.create({
      data: {
        organizationId:
          organization.id,

        email:
          `${employeeEmailPrefix}${unique}@example.com`,

        emailNormalized:
          `${employeeEmailPrefix}${unique}@example.com`,

        displayName:
          'Stage 9 Secondary Employee',

        status:
          'ACTIVE',
      },
    });

  const secondaryEmployee =
    await database.employee.create({
      data: {
        organizationId:
          organization.id,

        teamId:
          team.id,

        userId:
          secondaryUser.id,

        employeeCode:
          `S9${unique}`,

        status:
          'ACTIVE',
      },
    });

  const phoneA =
    `${metaPhonePrefix}${numericSuffix(1)}`;

  const phoneB =
    `${metaPhonePrefix}${numericSuffix(2)}`;

  const wabaA =
    `${metaPhonePrefix}${numericSuffix(3)}`;

  const wabaB =
    `${metaPhonePrefix}${numericSuffix(4)}`;

  const numberA =
    await database.whatsAppNumber.create({
      data: {
        organizationId:
          organization.id,

        assignedEmployeeId:
          primaryEmployee.id,

        displayName:
          `${numberPrefix} A`,

        e164:
          `+1555${numericSuffix(5)}`,

        status:
          'ACTIVE',

        metaWabaId:
          wabaA,

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
          secondaryEmployee.id,

        displayName:
          `${numberPrefix} B`,

        e164:
          `+1555${numericSuffix(6)}`,

        status:
          'ACTIVE',

        metaWabaId:
          wabaB,

        metaPhoneNumberId:
          phoneB,

        metaConnectedAt:
          new Date(),
      },
    });

  const processorA =
    new WhatsAppInboxProcessorService(
      database,
      `stage9-inbox-a-${unique}`,
      runtimeConfig,
    );

  const processorB =
    new WhatsAppInboxProcessorService(
      database,
      `stage9-inbox-b-${unique}`,
      runtimeConfig,
    );

  const nowSeconds =
    Math.floor(
      Date.now() /
        1000,
    );

  const waIdA =
    `${contactPrefix}${numericSuffix(7)}`;

  const inboundMessageId =
    `wamid.stage9.inbound.${unique}`;

  await createEnvelope(
    organization.id,
    numberA.id,
    wabaA,
    phoneA,
    inboundPayload({
      nonce:
        `first-${unique}`,

      wabaId:
        wabaA,

      phoneNumberId:
        phoneA,

      waId:
        waIdA,

      messageId:
        inboundMessageId,

      profileName:
        'Cliente Runtime A',

      timestamp:
        nowSeconds,
    }),
  );

  const firstTick =
    await processorA.runTick();

  assert.equal(
    firstTick.messages,
    1,
  );

  const inboundMessage =
    await database.whatsAppMessage.findUniqueOrThrow({
      where: {
        metaMessageId:
          inboundMessageId,
      },
    });

  assert.equal(
    inboundMessage.direction,
    'INBOUND',
  );

  assert.equal(
    inboundMessage.status,
    'RECEIVED',
  );

  const conversationA =
    await database.whatsAppConversation.findUniqueOrThrow({
      where: {
        id:
          inboundMessage.conversationId,
      },
    });

  assert.equal(
    conversationA.assignedEmployeeId,
    primaryEmployee.id,
  );

  assert.equal(
    conversationA.unreadCount,
    1,
  );

  assert.ok(
    conversationA.customerServiceWindowExpiresAt,
  );

  const expectedWindow =
    new Date(
      nowSeconds *
        1000 +
        24 *
          60 *
          60 *
          1000,
    );

  assert.equal(
    conversationA.customerServiceWindowExpiresAt?.getTime(),
    expectedWindow.getTime(),
  );

  event(
    'stage9.inbound_message.passed',
  );

  await createEnvelope(
    organization.id,
    numberA.id,
    wabaA,
    phoneA,
    inboundPayload({
      nonce:
        `duplicate-${unique}`,

      wabaId:
        wabaA,

      phoneNumberId:
        phoneA,

      waId:
        waIdA,

      messageId:
        inboundMessageId,

      profileName:
        'Cliente Runtime A',

      timestamp:
        nowSeconds,
    }),
  );

  await processorA.runTick();

  assert.equal(
    await database.whatsAppMessage.count({
      where: {
        metaMessageId:
          inboundMessageId,
      },
    }),
    1,
  );

  const conversationAfterDuplicate =
    await database.whatsAppConversation.findUniqueOrThrow({
      where: {
        id:
          conversationA.id,
      },
    });

  assert.equal(
    conversationAfterDuplicate.unreadCount,
    1,
  );

  event(
    'stage9.wamid_idempotency.passed',
  );

  const concurrentMessageId =
    `wamid.stage9.concurrent.${unique}`;

  const waIdB =
    `${contactPrefix}${numericSuffix(8)}`;

  const concurrentEnvelope =
    await createEnvelope(
      organization.id,
      numberB.id,
      wabaB,
      phoneB,
      inboundPayload({
        nonce:
          `concurrent-${unique}`,

        wabaId:
          wabaB,

        phoneNumberId:
          phoneB,

        waId:
          waIdB,

        messageId:
          concurrentMessageId,

        profileName:
          'Cliente Runtime B',

        timestamp:
          nowSeconds,
      }),
    );

  await Promise.all([
    processorA.runTick(),
    processorB.runTick(),
  ]);

  assert.equal(
    await database.whatsAppMessage.count({
      where: {
        metaMessageId:
          concurrentMessageId,
      },
    }),
    1,
  );

  const concurrentEnvelopeAfter =
    await database.metaWebhookEnvelope.findUniqueOrThrow({
      where: {
        id:
          concurrentEnvelope.id,
      },
    });

  assert.equal(
    concurrentEnvelopeAfter.status,
    'PROCESSED',
  );

  event(
    'stage9.concurrent_inbox_claim.passed',
  );

  const recoveredMessageId =
    `wamid.stage9.recovered.${unique}`;

  const recoveredEnvelope =
    await createEnvelope(
      organization.id,
      numberA.id,
      wabaA,
      phoneA,
      inboundPayload({
        nonce:
          `lease-${unique}`,

        wabaId:
          wabaA,

        phoneNumberId:
          phoneA,

        waId:
          waIdA,

        messageId:
          recoveredMessageId,

        profileName:
          'Cliente Runtime A',

        timestamp:
          nowSeconds,
      }),
      {
        status:
          'CLAIMED',

        claimedByWorkerId:
          'dead-worker',

        leaseExpiresAt:
          new Date(
            Date.now() -
              60000,
          ),
      },
    );

  await processorA.runTick();

  assert.equal(
    (
      await database.metaWebhookEnvelope.findUniqueOrThrow({
        where: {
          id:
            recoveredEnvelope.id,
        },
      })
    ).status,
    'PROCESSED',
  );

  assert.ok(
    await database.whatsAppMessage.findUnique({
      where: {
        metaMessageId:
          recoveredMessageId,
      },
    }),
  );

  event(
    'stage9.inbox_lease_recovery.passed',
  );

  const apiModule =
    await import(
      '../../api/dist/inbox/inbox.service.js'
    );

  const inboxService =
    new apiModule.InboxService(
      {
        client:
          database,
      } as never,
    );

  const adminPrincipal = {
    organizationId:
      organization.id,

    userId:
      adminUser.id,

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
      adminUser.id,

    sessionId:
      randomUUID(),

    roles: [
      'EMPLOYEE',
    ] as const,
  };

  const employeeList =
    await inboxService.listConversations(
      employeePrincipal,
      {
        limit:
          30,

        whatsAppNumberId:
          numberA.id,
      },
    );

  assert.ok(
    employeeList.items.some(
      (
        item,
      ) =>
        item.id ===
        conversationA.id,
    ),
  );

  const conversationB =
    await database.whatsAppConversation.findFirstOrThrow({
      where: {
        organizationId:
          organization.id,

        whatsAppNumberId:
          numberB.id,
      },
    });

  await assert.rejects(
    () =>
      inboxService.getConversation(
        employeePrincipal,
        conversationB.id,
      ),
  );

  event(
    'stage9.employee_isolation.passed',
  );

  const clientTextId =
    randomUUID();

  const queuedText =
    await inboxService.sendMessage(
      adminPrincipal,
      conversationA.id,
      {
        clientMessageId:
          clientTextId,

        type:
          'TEXT',

        text:
          'Resposta Stage 9',
      },
    );

  const sameQueuedText =
    await inboxService.sendMessage(
      adminPrincipal,
      conversationA.id,
      {
        clientMessageId:
          clientTextId,

        type:
          'TEXT',

        text:
          'Resposta Stage 9',
      },
    );

  assert.equal(
    sameQueuedText.id,
    queuedText.id,
  );

  event(
    'stage9.client_idempotency.passed',
  );

  let textRequestCount =
    0;

  const textMetaId =
    `wamid.stage9.outbound.text.${unique}`;

  const textClient =
    createMetaClient(
      async (
        body,
        url,
      ) => {
        textRequestCount +=
          1;

        assert.ok(
          url.includes(
            `/${phoneA}/messages`,
          ),
        );

        assert.equal(
          body.type,
          'text',
        );

        return new Response(
          JSON.stringify({
            messages: [
              {
                id:
                  textMetaId,
              },
            ],
          }),
          {
            status:
              200,
          },
        );
      },
    );

  const textDispatcher =
    new WhatsAppOutboundDispatcherService(
      database,
      `stage9-outbound-text-${unique}`,
      runtimeConfig,
      textClient,
    );

  await textDispatcher.runTick();

  assert.equal(
    textRequestCount,
    1,
  );

  const sentText =
    await database.whatsAppMessage.findUniqueOrThrow({
      where: {
        id:
          queuedText.id,
      },
    });

  assert.equal(
    sentText.status,
    'SENT',
  );

  assert.equal(
    sentText.metaMessageId,
    textMetaId,
  );

  event(
    'stage9.outbound_text.passed',
  );

  await database.whatsAppConversation.update({
    where: {
      id:
        conversationA.id,
    },

    data: {
      customerServiceWindowExpiresAt:
        new Date(
          Date.now() -
            1000,
        ),
    },
  });

  await assert.rejects(
    () =>
      inboxService.sendMessage(
        adminPrincipal,
        conversationA.id,
        {
          clientMessageId:
            randomUUID(),

          type:
            'TEXT',

          text:
            'Janela fechada',
        },
      ),
  );

  event(
    'stage9.window_api_guard.passed',
  );

  const templateQueued =
    await inboxService.sendMessage(
      adminPrincipal,
      conversationA.id,
      {
        clientMessageId:
          randomUUID(),

        type:
          'TEMPLATE',

        templateName:
          'stage9_template',

        languageCode:
          'pt_BR',
      },
    );

  const templateMetaId =
    `wamid.stage9.template.${unique}`;

  const templateClient =
    createMetaClient(
      async (
        body,
      ) => {
        assert.equal(
          body.type,
          'template',
        );

        return new Response(
          JSON.stringify({
            messages: [
              {
                id:
                  templateMetaId,
              },
            ],
          }),
          {
            status:
              200,
          },
        );
      },
    );

  const templateDispatcher =
    new WhatsAppOutboundDispatcherService(
      database,
      `stage9-outbound-template-${unique}`,
      runtimeConfig,
      templateClient,
    );

  await templateDispatcher.runTick();

  assert.equal(
    (
      await database.whatsAppMessage.findUniqueOrThrow({
        where: {
          id:
            templateQueued.id,
        },
      })
    ).status,
    'SENT',
  );

  event(
    'stage9.template_outside_window.passed',
  );

  const blockedText =
    await database.whatsAppMessage.create({
      data: {
        organizationId:
          organization.id,

        conversationId:
          conversationA.id,

        whatsAppNumberId:
          numberA.id,

        contactId:
          inboundMessage.contactId,

        direction:
          'OUTBOUND',

        type:
          'TEXT',

        status:
          'QUEUED',

        clientMessageId:
          randomUUID(),

        textBody:
          'Nao pode sair',

        content: {
          type:
            'text',

          text: {
            body:
              'Nao pode sair',
          },
        },

        queuedAt:
          new Date(),
      },
    });

  let blockedNetworkCalls =
    0;

  const blockedClient =
    createMetaClient(
      async () => {
        blockedNetworkCalls +=
          1;

        return new Response(
          '{}',
          {
            status:
              500,
          },
        );
      },
    );

  const blockedDispatcher =
    new WhatsAppOutboundDispatcherService(
      database,
      `stage9-outbound-blocked-${unique}`,
      runtimeConfig,
      blockedClient,
    );

  await blockedDispatcher.runTick();

  const blockedAfter =
    await database.whatsAppMessage.findUniqueOrThrow({
      where: {
        id:
          blockedText.id,
      },
    });

  assert.equal(
    blockedNetworkCalls,
    0,
  );

  assert.equal(
    blockedAfter.status,
    'FAILED',
  );

  assert.equal(
    blockedAfter.errorCode,
    'WHATSAPP_CUSTOMER_SERVICE_WINDOW_CLOSED',
  );

  event(
    'stage9.window_worker_guard.passed',
  );

  const statusNow =
    Math.floor(
      Date.now() /
        1000,
    );

  await createEnvelope(
    organization.id,
    numberA.id,
    wabaA,
    phoneA,
    statusPayload({
      nonce:
        `read-${unique}`,

      wabaId:
        wabaA,

      phoneNumberId:
        phoneA,

      messageId:
        textMetaId,

      recipientId:
        waIdA,

      statuses: [
        {
          status:
            'delivered',

          timestamp:
            statusNow,
        },

        {
          status:
            'read',

          timestamp:
            statusNow +
            1,
        },
      ],
    }),
  );

  await processorA.runTick();

  const readText =
    await database.whatsAppMessage.findUniqueOrThrow({
      where: {
        id:
          sentText.id,
      },
    });

  assert.equal(
    readText.status,
    'READ',
  );

  assert.ok(
    readText.deliveredAt,
  );

  assert.ok(
    readText.readAt,
  );

  await createEnvelope(
    organization.id,
    numberA.id,
    wabaA,
    phoneA,
    statusPayload({
      nonce:
        `late-sent-${unique}`,

      wabaId:
        wabaA,

      phoneNumberId:
        phoneA,

      messageId:
        textMetaId,

      recipientId:
        waIdA,

      statuses: [
        {
          status:
            'sent',

          timestamp:
            statusNow -
            5,
        },
      ],
    }),
  );

  await processorA.runTick();

  assert.equal(
    (
      await database.whatsAppMessage.findUniqueOrThrow({
        where: {
          id:
            sentText.id,
        },
      })
    ).status,
    'READ',
  );

  event(
    'stage9.status_reconciliation.passed',
  );

  const pendingMetaId =
    `wamid.stage9.pending.${unique}`;

  await createEnvelope(
    organization.id,
    numberA.id,
    wabaA,
    phoneA,
    statusPayload({
      nonce:
        `before-send-${unique}`,

      wabaId:
        wabaA,

      phoneNumberId:
        phoneA,

      messageId:
        pendingMetaId,

      recipientId:
        waIdA,

      statuses: [
        {
          status:
            'delivered',

          timestamp:
            statusNow +
            2,
        },
      ],
    }),
  );

  await processorA.runTick();

  const pendingStatus =
    await database.whatsAppMessageStatusEvent.findFirstOrThrow({
      where: {
        organizationId:
          organization.id,

        metaMessageId:
          pendingMetaId,
      },
    });

  assert.equal(
    pendingStatus.appliedAt,
    null,
  );

  const pendingMessage =
    await inboxService.sendMessage(
      adminPrincipal,
      conversationA.id,
      {
        clientMessageId:
          randomUUID(),

        type:
          'TEMPLATE',

        templateName:
          'stage9_pending',

        languageCode:
          'pt_BR',
      },
    );

  const pendingClient =
    createMetaClient(
      async () =>
        new Response(
          JSON.stringify({
            messages: [
              {
                id:
                  pendingMetaId,
              },
            ],
          }),
          {
            status:
              200,
          },
        ),
    );

  const pendingDispatcher =
    new WhatsAppOutboundDispatcherService(
      database,
      `stage9-outbound-pending-${unique}`,
      runtimeConfig,
      pendingClient,
    );

  await pendingDispatcher.runTick();

  assert.equal(
    (
      await database.whatsAppMessage.findUniqueOrThrow({
        where: {
          id:
            pendingMessage.id,
        },
      })
    ).status,
    'DELIVERED',
  );

  assert.ok(
    (
      await database.whatsAppMessageStatusEvent.findUniqueOrThrow({
        where: {
          id:
            pendingStatus.id,
        },
      })
    ).appliedAt,
  );

  event(
    'stage9.status_before_send.passed',
  );

  const retryMessage =
    await inboxService.sendMessage(
      adminPrincipal,
      conversationA.id,
      {
        clientMessageId:
          randomUUID(),

        type:
          'TEMPLATE',

        templateName:
          'stage9_retry',

        languageCode:
          'pt_BR',
      },
    );

  let retryCalls =
    0;

  const retryMetaId =
    `wamid.stage9.retry.${unique}`;

  const retryClient =
    createMetaClient(
      async () => {
        retryCalls +=
          1;

        if (
          retryCalls ===
            1
        ) {
          return new Response(
            JSON.stringify({
              error: {
                message:
                  'Rate limited',

                type:
                  'OAuthException',

                code:
                  4,
              },
            }),
            {
              status:
                429,
            },
          );
        }

        return new Response(
          JSON.stringify({
            messages: [
              {
                id:
                  retryMetaId,
              },
            ],
          }),
          {
            status:
              200,
          },
        );
      },
    );

  const retryDispatcher =
    new WhatsAppOutboundDispatcherService(
      database,
      `stage9-outbound-retry-${unique}`,
      runtimeConfig,
      retryClient,
    );

  await retryDispatcher.runTick();

  const afterRateLimit =
    await database.whatsAppMessage.findUniqueOrThrow({
      where: {
        id:
          retryMessage.id,
      },
    });

  assert.equal(
    afterRateLimit.status,
    'QUEUED',
  );

  await database.whatsAppMessage.update({
    where: {
      id:
        retryMessage.id,
    },

    data: {
      availableAt:
        new Date(),
    },
  });

  await retryDispatcher.runTick();

  const afterRetry =
    await database.whatsAppMessage.findUniqueOrThrow({
      where: {
        id:
          retryMessage.id,
      },
    });

  assert.equal(
    afterRetry.status,
    'SENT',
  );

  assert.equal(
    afterRetry.attempts,
    2,
  );

  assert.equal(
    retryCalls,
    2,
  );

  event(
    'stage9.retry_backoff.passed',
  );

  const uncertainMessage =
    await inboxService.sendMessage(
      adminPrincipal,
      conversationA.id,
      {
        clientMessageId:
          randomUUID(),

        type:
          'TEMPLATE',

        templateName:
          'stage9_uncertain',

        languageCode:
          'pt_BR',
      },
    );

  const uncertainClient =
    createMetaClient(
      async () => {
        throw new Error(
          'Simulated socket reset',
        );
      },
    );

  const uncertainDispatcher =
    new WhatsAppOutboundDispatcherService(
      database,
      `stage9-outbound-uncertain-${unique}`,
      runtimeConfig,
      uncertainClient,
    );

  await uncertainDispatcher.runTick();

  const uncertainAfter =
    await database.whatsAppMessage.findUniqueOrThrow({
      where: {
        id:
          uncertainMessage.id,
      },
    });

  assert.equal(
    uncertainAfter.status,
    'FAILED',
  );

  assert.equal(
    uncertainAfter.errorCode,
    'OUTBOUND_DELIVERY_UNKNOWN',
  );

  event(
    'stage9.uncertain_outcome_protection.passed',
  );

  const leaseMessage =
    await inboxService.sendMessage(
      adminPrincipal,
      conversationA.id,
      {
        clientMessageId:
          randomUUID(),

        type:
          'TEMPLATE',

        templateName:
          'stage9_lease',

        languageCode:
          'pt_BR',
      },
    );

  await database.whatsAppMessage.update({
    where: {
      id:
        leaseMessage.id,
    },

    data: {
      status:
        'SENDING',

      claimedAt:
        new Date(
          Date.now() -
            60000,
        ),

      claimedByWorkerId:
        'dead-outbound-worker',

      leaseExpiresAt:
        new Date(
          Date.now() -
            30000,
        ),
    },
  });

  const leaseMetaId =
    `wamid.stage9.lease.${unique}`;

  const leaseDispatcher =
    new WhatsAppOutboundDispatcherService(
      database,
      `stage9-outbound-lease-${unique}`,
      runtimeConfig,
      createMetaClient(
        async () =>
          new Response(
            JSON.stringify({
              messages: [
                {
                  id:
                    leaseMetaId,
                },
              ],
            }),
            {
              status:
                200,
            },
          ),
      ),
    );

  await leaseDispatcher.runTick();

  assert.equal(
    (
      await database.whatsAppMessage.findUniqueOrThrow({
        where: {
          id:
            leaseMessage.id,
        },
      })
    ).status,
    'SENT',
  );

  event(
    'stage9.outbound_lease_recovery.passed',
  );

  const concurrentOutbound =
    await inboxService.sendMessage(
      adminPrincipal,
      conversationA.id,
      {
        clientMessageId:
          randomUUID(),

        type:
          'TEMPLATE',

        templateName:
          'stage9_concurrent',

        languageCode:
          'pt_BR',
      },
    );

  let concurrentSendCalls =
    0;

  const concurrentOutboundClient =
    createMetaClient(
      async () => {
        concurrentSendCalls +=
          1;

        return new Response(
          JSON.stringify({
            messages: [
              {
                id:
                  `wamid.stage9.concurrent.out.${unique}`,
              },
            ],
          }),
          {
            status:
              200,
          },
        );
      },
    );

  const outboundA =
    new WhatsAppOutboundDispatcherService(
      database,
      `stage9-out-a-${unique}`,
      runtimeConfig,
      concurrentOutboundClient,
    );

  const outboundB =
    new WhatsAppOutboundDispatcherService(
      database,
      `stage9-out-b-${unique}`,
      runtimeConfig,
      concurrentOutboundClient,
    );

  await Promise.all([
    outboundA.runTick(),
    outboundB.runTick(),
  ]);

  assert.equal(
    concurrentSendCalls,
    1,
  );

  assert.equal(
    (
      await database.whatsAppMessage.findUniqueOrThrow({
        where: {
          id:
            concurrentOutbound.id,
        },
      })
    ).status,
    'SENT',
  );

  event(
    'stage9.concurrent_outbound_claim.passed',
  );

  const quickReply =
    await inboxService.createQuickReply(
      adminPrincipal,
      {
        title:
          'Stage 9 Ola',

        shortcut:
          `${quickReplyPrefix}_ola`,

        body:
          'Ola! Como posso ajudar?',
      },
    );

  const quickReplies =
    await inboxService.listQuickReplies(
      adminPrincipal,
    );

  assert.ok(
    quickReplies.some(
      (
        item,
      ) =>
        item.id ===
        quickReply.id,
    ),
  );

  await assert.rejects(
    () =>
      inboxService.createQuickReply(
        adminPrincipal,
        {
          title:
            'Duplicada',

          shortcut:
            `${quickReplyPrefix}_ola`,

          body:
            'Duplicada',
        },
      ),
  );

  event(
    'stage9.quick_replies.passed',
  );

  const conversationRead =
    await inboxService.markConversationRead(
      adminPrincipal,
      conversationA.id,
    );

  assert.equal(
    conversationRead.unreadCount,
    0,
  );

  await assert.rejects(
    () =>
      inboxService.updateConversation(
        employeePrincipal,
        conversationA.id,
        {
          assignedEmployeeId:
            secondaryEmployee.id,
        },
      ),
  );

  event(
    'stage9.assignment_and_read.passed',
  );

  const foreignOrganization =
    await database.organization.create({
      data: {
        name:
          'Stage 9 Foreign Tenant',

        slug:
          `${foreignOrgPrefix}${unique}`,

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
          `${numberPrefix} Foreign`,

        e164:
          `+1555${numericSuffix(20)}`,

        status:
          'ACTIVE',

        metaWabaId:
          `${metaPhonePrefix}${numericSuffix(21)}`,

        metaPhoneNumberId:
          `${metaPhonePrefix}${numericSuffix(22)}`,

        metaConnectedAt:
          new Date(),
      },
    });

  const foreignContact =
    await database.whatsAppContact.create({
      data: {
        organizationId:
          foreignOrganization.id,

        waId:
          `${contactPrefix}${numericSuffix(23)}`,

        profileName:
          'Foreign Contact',
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

        status:
          'OPEN',
      },
    });

  await assert.rejects(
    () =>
      inboxService.getConversation(
        adminPrincipal,
        foreignConversation.id,
      ),
  );

  event(
    'stage9.tenant_isolation.passed',
  );

  const auditCount =
    await database.auditLog.count({
      where: {
        organizationId:
          organization.id,

        resourceId: {
          in: [
            queuedText.id,
            quickReply.id,
            conversationA.id,
          ],
        },
      },
    });

  assert.ok(
    auditCount >=
      3,
  );

  event(
    'stage9.audit.passed',
    {
      auditCount,
    },
  );

  event(
    'stage9.validation.completed',
  );
}

try {
  await main();
}
finally {
  try {
    await cleanupFixtures();
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
    -Path ".\apps\worker\scripts\stage9-runtime-validation.ts" `
    -Content $RuntimeValidator

Invoke-Native `
    -Description "Format runtime validator" `
    -Command "pnpm" `
    -Arguments @("format")

# Rebuild after formatter/generated runtime is in place.

Invoke-Native `
    -Description "Rebuild API and Worker" `
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
# STAGE 9 DATABASE + API + WORKER RUNTIME
# ============================================================

Write-Host ""
Write-Host "==== Stage 9 runtime validation ====" -ForegroundColor Cyan

& pnpm `
    --filter `
    "@crm/worker" `
    exec `
    tsx `
    "scripts/stage9-runtime-validation.ts"

if ($LASTEXITCODE -ne 0) {
    throw "Stage 9 runtime validation falhou."
}

Write-Host "[OK] Stage 9 runtime validation." -ForegroundColor Green

# ============================================================
# WORKER PROCESS SMOKE
# ============================================================

Write-Host ""
Write-Host "==== Worker process smoke Stage 9 ====" -ForegroundColor Cyan

$WorkerProcess =
    $null

$EnvironmentNames = @(
    "ADS_WORKER_ID",
    "WHATSAPP_INBOX_INTERVAL_MS",
    "WHATSAPP_OUTBOUND_INTERVAL_MS"
)

$PreviousEnvironment =
    @{}

foreach ($Name in $EnvironmentNames) {
    if (Test-Path "Env:$Name") {
        $PreviousEnvironment[$Name] =
            [Environment]::GetEnvironmentVariable(
                $Name,
                "Process"
            )
    }
}

$env:ADS_WORKER_ID =
    "stage9-process-smoke"

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
        throw "Worker encerrou durante process smoke. ExitCode: $($WorkerProcess.ExitCode)"
    }

    Write-Host "[OK] Worker Stage 9 permaneceu online." -ForegroundColor Green
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

    foreach ($Name in $EnvironmentNames) {
        if ($PreviousEnvironment.ContainsKey($Name)) {
            [Environment]::SetEnvironmentVariable(
                $Name,
                [string]$PreviousEnvironment[$Name],
                "Process"
            )
        }
        else {
            Remove-Item `
                "Env:$Name" `
                -ErrorAction SilentlyContinue
        }
    }
}

# ============================================================
# GLOBAL CI
# ============================================================

Invoke-Native `
    -Description "Global CI Stage 9" `
    -Command "pnpm" `
    -Arguments @("ci:check")

# ============================================================
# DOCUMENTATION
# ============================================================

$Stage9Document = @(
    "# Etapa 9 - WhatsApp Inbox",
    "",
    "## Status",
    "",
    "CONCLUIDA.",
    "",
    "## Boundary",
    "",
    "A Etapa 9 transforma os MetaWebhookEnvelope persistidos pela Etapa 8 em dados de dominio da caixa de atendimento.",
    "",
    "## Entidades",
    "",
    "- WhatsAppContact",
    "- WhatsAppConversation",
    "- WhatsAppMessage",
    "- WhatsAppMessageStatusEvent",
    "- WhatsAppQuickReply",
    "",
    "## Inbound",
    "",
    "MetaWebhookEnvelope e a fila persistente de entrada.",
    "",
    "O worker utiliza claim atomico PostgreSQL, FOR UPDATE SKIP LOCKED, lease, recovery e retry.",
    "",
    "A idempotencia HTTP da Etapa 8 continua baseada em payloadHash.",
    "",
    "A idempotencia de negocio da Etapa 9 utiliza Meta message id / wamid.",
    "",
    "Envelopes diferentes contendo o mesmo wamid nao criam uma segunda mensagem.",
    "",
    "## Conversations",
    "",
    "A conversa e unica por Organization + WhatsAppNumber + Contact.",
    "",
    "Mensagens inbound reabrem a conversa e atualizam unreadCount.",
    "",
    "Quando o numero possui Employee atribuido, novas conversas herdam essa atribuicao.",
    "",
    "EMPLOYEE enxerga apenas conversas atribuidas ao proprio Employee.",
    "",
    "ADMIN possui visibilidade organizacional.",
    "",
    "## Customer service window",
    "",
    "Cada mensagem inbound valida estende customerServiceWindowExpiresAt para 24 horas apos o timestamp da mensagem do cliente.",
    "",
    "TEXT outbound e bloqueado fora da janela.",
    "",
    "A regra e validada na API e novamente no dispatcher antes da chamada externa.",
    "",
    "TEMPLATE outbound pode ser enfileirado fora da janela.",
    "",
    "## Outbound",
    "",
    "Mensagens outbound sao persistidas antes da chamada Meta.",
    "",
    "clientMessageId e unique e fornece idempotencia para retries do cliente/API.",
    "",
    "O dispatcher utiliza claim e lease PostgreSQL.",
    "",
    "Envio utiliza Meta Phone Number ID /messages atraves de @crm/meta-cloud-api.",
    "",
    "HTTP 429 e 5xx utilizam retry com exponential backoff.",
    "",
    "Erro de rede com resultado externo incerto nao e reenviado cegamente.",
    "",
    "Nessa situacao a mensagem termina FAILED com OUTBOUND_DELIVERY_UNKNOWN para evitar duplicacao ao cliente.",
    "",
    "## Delivery status",
    "",
    "Estados persistidos:",
    "",
    "- SENT",
    "- DELIVERED",
    "- READ",
    "- FAILED",
    "- DELETED",
    "",
    "Status que chega antes da persistencia do Meta message id fica em WhatsAppMessageStatusEvent e e reconciliado apos o envio.",
    "",
    "Eventos atrasados nao rebaixam READ para DELIVERED ou SENT.",
    "",
    "## Quick replies",
    "",
    "Quick replies sao organizacionais, possuem shortcut unico por Organization e soft delete.",
    "",
    "EMPLOYEE recebe quick_reply.read.",
    "",
    "Gerenciamento de quick replies permanece administrativo.",
    "",
    "## Permissions",
    "",
    "- inbox.read",
    "- inbox.manage",
    "- quick_reply.read",
    "- quick_reply.manage",
    "",
    "ADMIN recebe todas.",
    "",
    "EMPLOYEE recebe inbox.read, inbox.manage e quick_reply.read.",
    "",
    "## Validation",
    "",
    "O fechamento da Etapa 9 valida:",
    "",
    "- migration e Prisma generate",
    "- seed e permission catalog",
    "- inbound webhook",
    "- wamid idempotency",
    "- concurrent inbox claim",
    "- expired lease recovery",
    "- employee isolation",
    "- API clientMessageId idempotency",
    "- 24h window na API",
    "- 24h window no dispatcher",
    "- text outbound mockado",
    "- template outbound mockado",
    "- status reconciliation",
    "- status before send",
    "- 429 retry",
    "- unknown network outcome protection",
    "- outbound lease recovery",
    "- concurrent outbound claim",
    "- quick replies",
    "- tenant isolation",
    "- audit",
    "- worker process smoke",
    "- global CI",
    "- secret scan",
    "",
    "## Proxima etapa",
    "",
    "Etapa 10 - Leads unicos e atribuicao."
)

Write-Lines `
    -Path ".\docs\ETAPA_9_WHATSAPP_INBOX.md" `
    -Lines $Stage9Document

$Stage9Decisions = @(
    "# Decisoes - Etapa 9",
    "",
    "Webhook HTTP e processamento de dominio permanecem desacoplados.",
    "",
    "MetaWebhookEnvelope e a fonte persistente de ingestao.",
    "",
    "wamid e a chave de idempotencia de negocio para mensagens Meta.",
    "",
    "metaMessageId e optional @unique porque outbound ainda nao possui wamid antes da resposta Meta.",
    "",
    "clientMessageId e optional @unique e identifica unicamente uma tentativa logica criada pelo frontend/API.",
    "",
    "A conversa e unica por tenant, numero WhatsApp e contato.",
    "",
    "A janela de 24 horas deriva exclusivamente de mensagem inbound do cliente.",
    "",
    "TEXT exige janela aberta tanto no enqueue quanto imediatamente antes do envio.",
    "",
    "TEMPLATE e a via permitida quando a janela de atendimento esta fechada.",
    "",
    "Claim e lease continuam PostgreSQL-first.",
    "",
    "O worker nao depende de Redis para garantir a integridade da fila da Inbox.",
    "",
    "HTTP 429/5xx da Meta sao retryable com backoff.",
    "",
    "Falha de transporte com outcome desconhecido nao e reenviada automaticamente para evitar mensagem duplicada.",
    "",
    "Status da Meta pode chegar antes da resposta de envio; por isso existe WhatsAppMessageStatusEvent separado.",
    "",
    "EMPLOYEE acessa somente conversas atribuidas ao proprio Employee.",
    "",
    "Mudanca de assignee e restrita a ADMIN.",
    "",
    "Quick reply pode ser lida pelo EMPLOYEE, mas gerenciada somente com quick_reply.manage."
)

Write-Lines `
    -Path ".\docs\DECISOES_ETAPA_9.md" `
    -Lines $Stage9Decisions

$EtapasPath =
    ".\docs\ETAPAS.md"

if (Test-Path $EtapasPath) {
    $Etapas =
        Read-Text -Path $EtapasPath

    for (
        $Stage =
            1;
        $Stage -le
            9;
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

    if ($Etapas.Contains("## Etapa 9 - Inbox")) {
        $Etapas =
            [regex]::Replace(
                $Etapas,
                '(?s)## Etapa 9 - Inbox.*?(?=## Etapa 10|\z)',
                @'
## Etapa 9 - Inbox

Status: CONCLUIDA.

Implementado:

- WhatsAppContact
- WhatsAppConversation
- WhatsAppMessage
- WhatsAppMessageStatusEvent
- WhatsAppQuickReply
- inbound webhook processor
- wamid idempotency
- customer service window 24h
- employee assignment
- persistent outbound queue
- Meta text/template outbound
- status reconciliation
- quick replies
- claim/lease/recovery
- retry protection
- tenant isolation

Documentacao:

- docs/ETAPA_9_WHATSAPP_INBOX.md
- docs/DECISOES_ETAPA_9.md

Proxima: Etapa 10 - Leads unicos e atribuicao.

'@
            )
    }
    else {
        $Etapas =
            $Etapas.TrimEnd() +
            "`r`n`r`n" +
            "## Etapa 9 - Inbox`r`n`r`n" +
            "Status: CONCLUIDA.`r`n`r`n" +
            "Documentacao: docs/ETAPA_9_WHATSAPP_INBOX.md e docs/DECISOES_ETAPA_9.md.`r`n`r`n" +
            "Proxima: Etapa 10 - Leads unicos e atribuicao.`r`n"
    }

    Write-Text `
        -Path $EtapasPath `
        -Content $Etapas
}

Write-Host "[OK] Stage 9 documentation." -ForegroundColor Green

# ============================================================
# FINAL FORMAT + CI SAFETY
# ============================================================

Invoke-Native `
    -Description "Final format Stage 9" `
    -Command "pnpm" `
    -Arguments @("format")

Invoke-Native `
    -Description "Final format check Stage 9" `
    -Command "pnpm" `
    -Arguments @("format:check")

Invoke-Native `
    -Description "Final global CI Stage 9" `
    -Command "pnpm" `
    -Arguments @("ci:check")

# ============================================================
# STRUCTURAL SECURITY CHECKS
# ============================================================

Write-Host ""
Write-Host "==== Stage 9 structural security checks ====" -ForegroundColor Cyan

$Guard =
    Read-Text -Path ".\apps\api\src\authorization\access-token.guard.ts"

$AuthorizationTypes =
    Read-Text -Path ".\apps\api\src\authorization\authorization.types.ts"

$Seed =
    Read-Text -Path ".\packages\database\prisma\seed.ts"

$VerifySeed =
    Read-Text -Path ".\packages\database\prisma\verify-seed.ts"

foreach ($Permission in @(
    "inbox.read",
    "inbox.manage",
    "quick_reply.read",
    "quick_reply.manage"
)) {
    if (-not $Guard.Contains($Permission)) {
        throw "AccessTokenGuard nao reconhece $Permission"
    }

    if (-not $AuthorizationTypes.Contains($Permission)) {
        throw "PermissionCode nao reconhece $Permission"
    }

    if (-not $Seed.Contains($Permission)) {
        throw "Seed nao possui $Permission"
    }

    if (-not $VerifySeed.Contains($Permission)) {
        throw "verify-seed nao possui $Permission"
    }
}

$SchemaFinal =
    Read-Text -Path $SchemaPath

if ($SchemaFinal.Contains("@@unique([organizationId, metaMessageId])")) {
    throw "Nullable metaMessageId ainda participa de @@unique."
}

if ($SchemaFinal.Contains("@@unique([organizationId, clientMessageId])")) {
    throw "Nullable clientMessageId ainda participa de @@unique."
}

if (-not [regex]::IsMatch($SchemaFinal, '(?m)^\s*metaMessageId\s+String\?\s+@unique\s+@db\.VarChar\(255\)\s*$')) {
    throw "metaMessageId @unique ausente."
}

if (-not [regex]::IsMatch($SchemaFinal, '(?m)^\s*clientMessageId\s+String\?\s+@unique\s+@db\.Uuid\s*$')) {
    throw "clientMessageId @unique ausente."
}

$OutboundFinal =
    Read-Text -Path $OutboundPath

if (-not $OutboundFinal.Contains("LOCAL_POLICY_WINDOW_CLOSED")) {
    throw "Dispatcher nao possui second 24h window guard."
}

if (-not $OutboundFinal.Contains("OUTBOUND_DELIVERY_UNKNOWN")) {
    throw "Dispatcher nao possui uncertain-outcome protection."
}

Write-Host "[OK] Stage 9 structural security checks." -ForegroundColor Green

# ============================================================
# NO TRACKED ENV
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

$SecretExitCode =
    $LASTEXITCODE

if (
    $SecretExitCode -ne 0 -and
    $SecretExitCode -ne 1
) {
    throw "Secret scan falhou."
}

if (@($TrackedSecretMatches).Count -gt 0) {
    $TrackedSecretMatches
    throw "Possivel segredo encontrado."
}

Write-Host "[OK] Secret scan." -ForegroundColor Green

# ============================================================
# GIT DIFF
# ============================================================

& git diff --check

if ($LASTEXITCODE -ne 0) {
    throw "git diff --check falhou."
}

Write-Host "[OK] git diff --check." -ForegroundColor Green

# ============================================================
# CLEAN BACKUP
# ============================================================

Remove-Item `
    ".\tmp\stage9-macroblock1-backup" `
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
Write-Host "[OK] ETAPA 9 COMPLETAMENTE VALIDADA." -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Validado:" -ForegroundColor Cyan
Write-Host "- Prisma Stage 9 schema"
Write-Host "- migration"
Write-Host "- Prisma generate"
Write-Host "- seed + permission catalog"
Write-Host "- inbox.read / inbox.manage"
Write-Host "- quick_reply.read / quick_reply.manage"
Write-Host "- inbound webhook parsing"
Write-Host "- Meta wamid idempotency"
Write-Host "- persistent contact creation"
Write-Host "- conversation creation/reopen"
Write-Host "- Employee assignment"
Write-Host "- unread lifecycle"
Write-Host "- customer service window 24h"
Write-Host "- API text window guard"
Write-Host "- worker text window guard"
Write-Host "- clientMessageId idempotency"
Write-Host "- outbound TEXT"
Write-Host "- outbound TEMPLATE"
Write-Host "- Meta message ID persistence"
Write-Host "- SENT / DELIVERED / READ reconciliation"
Write-Host "- status-before-send reconciliation"
Write-Host "- 429 retry/backoff"
Write-Host "- unknown network outcome protection"
Write-Host "- inbox lease recovery"
Write-Host "- outbound lease recovery"
Write-Host "- concurrent inbox claim"
Write-Host "- concurrent outbound claim"
Write-Host "- quick replies"
Write-Host "- employee isolation"
Write-Host "- tenant isolation"
Write-Host "- audit"
Write-Host "- worker process smoke"
Write-Host "- global CI"
Write-Host "- documentation"
Write-Host "- git checks"
Write-Host "- secret scan"
Write-Host ""
Write-Host "Proxima etapa: ETAPA 10 - LEADS UNICOS E ATRIBUICAO." -ForegroundColor Yellow