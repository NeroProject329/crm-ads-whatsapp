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

    $Pattern = "(?ms)^$Kind\s+$([regex]::Escape($Name))\s*\{.*?^\}"

    $Match = [regex]::Match(
        $Content,
        $Pattern
    )

    if (-not $Match.Success) {
        throw "Prisma $Kind $Name nao encontrado."
    }

    return $Match
}

function Add-ToPrismaModel {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$Model,

        [Parameter(Mandatory = $true)]
        [string]$Marker,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Members
    )

    $Match = Get-PrismaBlock `
        -Content $Content `
        -Kind "model" `
        -Name $Model

    if ($Match.Value.Contains($Marker)) {
        return $Content
    }

    $Block = $Match.Value
    $ClosingIndex = $Block.LastIndexOf("}")

    if ($ClosingIndex -lt 0) {
        throw "Fechamento do model $Model nao encontrado."
    }

    $NewBlock =
        $Block.Substring(0, $ClosingIndex).TrimEnd() +
        "`r`n`r`n" +
        $Members.TrimEnd() +
        "`r`n" +
        "}"

    return (
        $Content.Substring(0, $Match.Index) +
        $NewBlock +
        $Content.Substring($Match.Index + $Match.Length)
    )
}

function Insert-AfterPrismaBlock {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [ValidateSet("model", "enum")]
        [string]$Kind,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Marker,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$NewContent
    )

    if ($Content.Contains($Marker)) {
        return $Content
    }

    $Match = Get-PrismaBlock `
        -Content $Content `
        -Kind $Kind `
        -Name $Name

    $InsertAt =
        $Match.Index +
        $Match.Length

    return (
        $Content.Substring(0, $InsertAt) +
        "`r`n`r`n" +
        $NewContent.Trim() +
        "`r`n" +
        $Content.Substring($InsertAt).TrimStart("`r", "`n")
    )
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " ETAPA 9 - MACROBLOCO 9.1" -ForegroundColor Cyan
Write-Host " WHATSAPP INBOX CONSTRUCTION" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

# ============================================================
# BACKUP
# ============================================================

$BackupRoot =
    ".\tmp\stage9-macroblock1-backup"

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
    ".\packages\database\prisma\schema.prisma",
    ".\packages\database\prisma\seed.ts",
    ".\packages\database\prisma\verify-seed.ts",
    ".\packages\contracts\src\index.ts",
    ".\packages\validation\src\index.ts",
    ".\packages\meta-cloud-api\src\index.ts",
    ".\apps\api\src\app.module.ts",
    ".\apps\api\src\authorization\authorization.types.ts",
    ".\apps\api\src\authorization\access-token.guard.ts",
    ".\apps\worker\package.json",
    ".\apps\worker\src\main.ts",
    ".\.env.example",
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

Write-Host "[OK] Backup Stage 9 preparado." -ForegroundColor Green

# ============================================================
# PRISMA
# ============================================================

$SchemaPath =
    ".\packages\database\prisma\schema.prisma"

$Schema =
    Read-Text -Path $SchemaPath

$InboxEnums = @'
enum WhatsAppConversationStatus {
  OPEN
  CLOSED
  ARCHIVED
}

enum WhatsAppMessageDirection {
  INBOUND
  OUTBOUND
}

enum WhatsAppMessageType {
  TEXT
  TEMPLATE
  IMAGE
  AUDIO
  VIDEO
  DOCUMENT
  STICKER
  LOCATION
  CONTACTS
  INTERACTIVE
  REACTION
  UNKNOWN
}

enum WhatsAppMessageStatus {
  RECEIVED
  QUEUED
  SENDING
  SENT
  DELIVERED
  READ
  FAILED
  DELETED
}
'@

$Schema = Insert-AfterPrismaBlock `
    -Content $Schema `
    -Kind "enum" `
    -Name "MetaWebhookStatus" `
    -Marker "enum WhatsAppConversationStatus" `
    -NewContent $InboxEnums

$OrganizationRelations = @'
  whatsAppContacts             WhatsAppContact[]
  whatsAppConversations        WhatsAppConversation[]
  whatsAppMessages             WhatsAppMessage[]
  whatsAppMessageStatusEvents  WhatsAppMessageStatusEvent[]
  whatsAppQuickReplies         WhatsAppQuickReply[]
'@

$Schema = Add-ToPrismaModel `
    -Content $Schema `
    -Model "Organization" `
    -Marker "whatsAppContacts" `
    -Members $OrganizationRelations

$EmployeeRelations = @'
  assignedWhatsAppConversations WhatsAppConversation[]
'@

$Schema = Add-ToPrismaModel `
    -Content $Schema `
    -Model "Employee" `
    -Marker "assignedWhatsAppConversations" `
    -Members $EmployeeRelations

$WhatsAppNumberRelations = @'
  inboxConversations       WhatsAppConversation[]
  inboxMessages            WhatsAppMessage[]
  inboxMessageStatusEvents WhatsAppMessageStatusEvent[]
'@

$Schema = Add-ToPrismaModel `
    -Content $Schema `
    -Model "WhatsAppNumber" `
    -Marker "inboxConversations" `
    -Members $WhatsAppNumberRelations

$EnvelopeRelations = @'
  inboxMessages            WhatsAppMessage[]
  inboxMessageStatusEvents WhatsAppMessageStatusEvent[]
'@

$Schema = Add-ToPrismaModel `
    -Content $Schema `
    -Model "MetaWebhookEnvelope" `
    -Marker "inboxMessageStatusEvents" `
    -Members $EnvelopeRelations

$InboxModels = @'
model WhatsAppContact {
  id             String   @id @default(uuid()) @db.Uuid
  organizationId String   @db.Uuid
  waId           String   @db.VarChar(64)
  profileName    String?  @db.VarChar(160)
  lastInboundAt  DateTime? @db.Timestamptz(3)
  lastOutboundAt DateTime? @db.Timestamptz(3)
  createdAt      DateTime @default(now()) @db.Timestamptz(3)
  updatedAt      DateTime @updatedAt @db.Timestamptz(3)

  organization  Organization           @relation(fields: [organizationId], references: [id], onDelete: Restrict)
  conversations WhatsAppConversation[]
  messages      WhatsAppMessage[]

  @@unique([organizationId, id])
  @@unique([organizationId, waId])
  @@index([organizationId, profileName])
  @@index([organizationId, lastInboundAt])
  @@map("whatsapp_contacts")
}

model WhatsAppConversation {
  id                              String                     @id @default(uuid()) @db.Uuid
  organizationId                  String                     @db.Uuid
  whatsAppNumberId                String                     @db.Uuid
  contactId                       String                     @db.Uuid
  assignedEmployeeId              String?                    @db.Uuid
  status                          WhatsAppConversationStatus @default(OPEN)
  customerServiceWindowExpiresAt  DateTime?                  @db.Timestamptz(3)
  lastMessageAt                   DateTime?                  @db.Timestamptz(3)
  lastInboundAt                   DateTime?                  @db.Timestamptz(3)
  lastOutboundAt                  DateTime?                  @db.Timestamptz(3)
  unreadCount                     Int                        @default(0)
  createdAt                       DateTime                   @default(now()) @db.Timestamptz(3)
  updatedAt                       DateTime                   @updatedAt @db.Timestamptz(3)

  organization     Organization    @relation(fields: [organizationId], references: [id], onDelete: Restrict)
  whatsAppNumber   WhatsAppNumber  @relation(fields: [organizationId, whatsAppNumberId], references: [organizationId, id], onDelete: Restrict)
  contact          WhatsAppContact @relation(fields: [organizationId, contactId], references: [organizationId, id], onDelete: Restrict)
  assignedEmployee Employee?       @relation(fields: [organizationId, assignedEmployeeId], references: [organizationId, id], onDelete: Restrict)
  messages         WhatsAppMessage[]

  @@unique([organizationId, id])
  @@unique([organizationId, whatsAppNumberId, contactId])
  @@index([organizationId, assignedEmployeeId, status, lastMessageAt])
  @@index([organizationId, whatsAppNumberId, status, lastMessageAt])
  @@index([organizationId, status, lastMessageAt])
  @@map("whatsapp_conversations")
}

model WhatsAppMessage {
  id                    String                   @id @default(uuid()) @db.Uuid
  organizationId        String                   @db.Uuid
  conversationId        String                   @db.Uuid
  whatsAppNumberId      String                   @db.Uuid
  contactId             String                   @db.Uuid
  sourceEnvelopeId      String?                  @db.Uuid
  direction             WhatsAppMessageDirection
  type                  WhatsAppMessageType
  status                WhatsAppMessageStatus
  metaMessageId         String?                  @unique @db.VarChar(255)
  clientMessageId       String?                  @unique @db.Uuid
  replyToMetaMessageId  String?                  @db.VarChar(255)
  textBody              String?                  @db.Text
  content               Json
  providerTimestamp     DateTime?                @db.Timestamptz(3)
  errorCode             String?                  @db.VarChar(80)
  errorMessage          String?                  @db.VarChar(500)
  queuedAt              DateTime?                @db.Timestamptz(3)
  sentAt                DateTime?                @db.Timestamptz(3)
  deliveredAt           DateTime?                @db.Timestamptz(3)
  readAt                DateTime?                @db.Timestamptz(3)
  failedAt              DateTime?                @db.Timestamptz(3)
  availableAt           DateTime                 @default(now()) @db.Timestamptz(3)
  attempts              Int                      @default(0)
  claimedAt             DateTime?                @db.Timestamptz(3)
  claimedByWorkerId     String?                  @db.VarChar(120)
  leaseExpiresAt        DateTime?                @db.Timestamptz(3)
  lastAttemptAt         DateTime?                @db.Timestamptz(3)
  createdAt             DateTime                 @default(now()) @db.Timestamptz(3)
  updatedAt             DateTime                 @updatedAt @db.Timestamptz(3)

  organization   Organization          @relation(fields: [organizationId], references: [id], onDelete: Restrict)
  conversation   WhatsAppConversation @relation(fields: [organizationId, conversationId], references: [organizationId, id], onDelete: Cascade)
  whatsAppNumber WhatsAppNumber       @relation(fields: [organizationId, whatsAppNumberId], references: [organizationId, id], onDelete: Restrict)
  contact        WhatsAppContact      @relation(fields: [organizationId, contactId], references: [organizationId, id], onDelete: Restrict)
  sourceEnvelope MetaWebhookEnvelope? @relation(fields: [sourceEnvelopeId], references: [id], onDelete: SetNull)

  @@unique([organizationId, id])
  @@index([organizationId, conversationId, createdAt])
  @@index([organizationId, whatsAppNumberId, createdAt])
  @@index([organizationId, direction, status, availableAt])
  @@index([status, leaseExpiresAt])
  @@map("whatsapp_messages")
}

model WhatsAppMessageStatusEvent {
  id                 String                @id @default(uuid()) @db.Uuid
  organizationId     String                @db.Uuid
  whatsAppNumberId   String                @db.Uuid
  sourceEnvelopeId   String?               @db.Uuid
  metaMessageId      String                @db.VarChar(255)
  status             WhatsAppMessageStatus
  recipientWaId      String?               @db.VarChar(64)
  providerTimestamp  DateTime              @db.Timestamptz(3)
  errors             Json?
  payload            Json
  appliedAt          DateTime?             @db.Timestamptz(3)
  createdAt          DateTime              @default(now()) @db.Timestamptz(3)

  organization   Organization          @relation(fields: [organizationId], references: [id], onDelete: Restrict)
  whatsAppNumber WhatsAppNumber       @relation(fields: [organizationId, whatsAppNumberId], references: [organizationId, id], onDelete: Restrict)
  sourceEnvelope MetaWebhookEnvelope? @relation(fields: [sourceEnvelopeId], references: [id], onDelete: SetNull)

  @@unique([organizationId, metaMessageId, status, providerTimestamp])
  @@index([organizationId, metaMessageId, providerTimestamp])
  @@index([organizationId, whatsAppNumberId, providerTimestamp])
  @@index([appliedAt, createdAt])
  @@map("whatsapp_message_status_events")
}

model WhatsAppQuickReply {
  id             String   @id @default(uuid()) @db.Uuid
  organizationId String   @db.Uuid
  title          String   @db.VarChar(120)
  shortcut       String   @db.VarChar(80)
  body           String   @db.Text
  createdAt      DateTime @default(now()) @db.Timestamptz(3)
  updatedAt      DateTime @updatedAt @db.Timestamptz(3)
  deletedAt      DateTime? @db.Timestamptz(3)

  organization Organization @relation(fields: [organizationId], references: [id], onDelete: Restrict)

  @@unique([organizationId, id])
  @@unique([organizationId, shortcut])
  @@index([organizationId, deletedAt, title])
  @@map("whatsapp_quick_replies")
}
'@

$Schema = Insert-AfterPrismaBlock `
    -Content $Schema `
    -Kind "model" `
    -Name "MetaWebhookEnvelope" `
    -Marker "model WhatsAppContact {" `
    -NewContent $InboxModels

Write-Text `
    -Path $SchemaPath `
    -Content $Schema

Write-Host "[OK] Prisma Inbox Stage 9 criado." -ForegroundColor Green

# ============================================================
# CONTRACTS
# ============================================================

$InboxContracts = @'
export type WhatsAppConversationStatus =
  | 'OPEN'
  | 'CLOSED'
  | 'ARCHIVED';

export type WhatsAppMessageDirection =
  | 'INBOUND'
  | 'OUTBOUND';

export type WhatsAppMessageType =
  | 'TEXT'
  | 'TEMPLATE'
  | 'IMAGE'
  | 'AUDIO'
  | 'VIDEO'
  | 'DOCUMENT'
  | 'STICKER'
  | 'LOCATION'
  | 'CONTACTS'
  | 'INTERACTIVE'
  | 'REACTION'
  | 'UNKNOWN';

export type WhatsAppMessageStatus =
  | 'RECEIVED'
  | 'QUEUED'
  | 'SENDING'
  | 'SENT'
  | 'DELIVERED'
  | 'READ'
  | 'FAILED'
  | 'DELETED';

export type InboxContactResponse = Readonly<{
  id: string;
  waId: string;
  profileName: string | null;
}>;

export type InboxNumberResponse = Readonly<{
  id: string;
  displayName: string;
  e164: string;
}>;

export type InboxAssigneeResponse = Readonly<{
  employeeId: string;
  employeeCode: string;
  userId: string;
  displayName: string;
}>;

export type InboxMessageResponse = Readonly<{
  id: string;
  organizationId: string;
  conversationId: string;
  whatsAppNumberId: string;
  contactId: string;

  direction: WhatsAppMessageDirection;
  type: WhatsAppMessageType;
  status: WhatsAppMessageStatus;

  metaMessageId: string | null;
  clientMessageId: string | null;
  replyToMetaMessageId: string | null;

  textBody: string | null;
  content: unknown;

  providerTimestamp: string | null;

  errorCode: string | null;
  errorMessage: string | null;

  queuedAt: string | null;
  sentAt: string | null;
  deliveredAt: string | null;
  readAt: string | null;
  failedAt: string | null;

  createdAt: string;
  updatedAt: string;
}>;

export type InboxConversationResponse = Readonly<{
  id: string;
  organizationId: string;

  status: WhatsAppConversationStatus;

  contact: InboxContactResponse;
  whatsAppNumber: InboxNumberResponse;
  assignedEmployee: InboxAssigneeResponse | null;

  customerServiceWindowExpiresAt: string | null;
  isCustomerServiceWindowOpen: boolean;

  lastMessageAt: string | null;
  lastInboundAt: string | null;
  lastOutboundAt: string | null;

  unreadCount: number;

  lastMessage: InboxMessageResponse | null;

  createdAt: string;
  updatedAt: string;
}>;

export type InboxConversationListResponse = Readonly<{
  items: readonly InboxConversationResponse[];
  nextCursor: string | null;
}>;

export type InboxMessageListResponse = Readonly<{
  items: readonly InboxMessageResponse[];
  nextCursor: string | null;
}>;

export type SendInboxTextMessageRequest = Readonly<{
  clientMessageId: string;
  type: 'TEXT';
  text: string;

  replyToMetaMessageId?: string | null;
}>;

export type SendInboxTemplateMessageRequest = Readonly<{
  clientMessageId: string;
  type: 'TEMPLATE';

  templateName: string;
  languageCode: string;

  components?: readonly unknown[];
}>;

export type SendInboxMessageRequest =
  | SendInboxTextMessageRequest
  | SendInboxTemplateMessageRequest;

export type UpdateInboxConversationRequest = Readonly<{
  status?: WhatsAppConversationStatus;
  assignedEmployeeId?: string | null;
}>;

export type InboxQuickReplyResponse = Readonly<{
  id: string;
  organizationId: string;
  title: string;
  shortcut: string;
  body: string;
  createdAt: string;
  updatedAt: string;
}>;

export type InboxQuickReplyListResponse =
  readonly InboxQuickReplyResponse[];

export type CreateInboxQuickReplyRequest = Readonly<{
  title: string;
  shortcut: string;
  body: string;
}>;

export type UpdateInboxQuickReplyRequest = Readonly<{
  title?: string;
  shortcut?: string;
  body?: string;
}>;
'@

Write-Text `
    -Path ".\packages\contracts\src\inbox.ts" `
    -Content $InboxContracts

$ContractsIndexPath =
    ".\packages\contracts\src\index.ts"

$ContractsIndex =
    Read-Text -Path $ContractsIndexPath

if (-not $ContractsIndex.Contains("export * from './inbox.js';")) {
    $ContractsIndex =
        $ContractsIndex.TrimEnd() +
        "`r`n" +
        "export * from './inbox.js';`r`n"
}

Write-Text `
    -Path $ContractsIndexPath `
    -Content $ContractsIndex

Write-Host "[OK] Inbox contracts criados." -ForegroundColor Green

# ============================================================
# VALIDATION
# ============================================================

$InboxValidation = @'
import { z } from 'zod';

const uuidSchema =
  z.string().uuid();

const conversationStatusSchema =
  z.enum([
    'OPEN',
    'CLOSED',
    'ARCHIVED',
  ]);

export const inboxConversationListQuerySchema =
  z
    .object({
      cursor:
        uuidSchema.optional(),

      limit:
        z.coerce
          .number()
          .int()
          .min(1)
          .max(100)
          .default(30),

      status:
        conversationStatusSchema.optional(),

      whatsAppNumberId:
        uuidSchema.optional(),

      search:
        z
          .string()
          .trim()
          .min(1)
          .max(120)
          .optional(),
    })
    .strict();

export const inboxMessageListQuerySchema =
  z
    .object({
      cursor:
        uuidSchema.optional(),

      limit:
        z.coerce
          .number()
          .int()
          .min(1)
          .max(100)
          .default(50),
    })
    .strict();

const clientMessageIdSchema =
  uuidSchema;

const replyToMetaMessageIdSchema =
  z
    .string()
    .trim()
    .min(1)
    .max(255)
    .nullable()
    .optional();

const sendTextMessageSchema =
  z
    .object({
      clientMessageId:
        clientMessageIdSchema,

      type:
        z.literal('TEXT'),

      text:
        z
          .string()
          .trim()
          .min(1)
          .max(4096),

      replyToMetaMessageId:
        replyToMetaMessageIdSchema,
    })
    .strict();

const sendTemplateMessageSchema =
  z
    .object({
      clientMessageId:
        clientMessageIdSchema,

      type:
        z.literal('TEMPLATE'),

      templateName:
        z
          .string()
          .trim()
          .min(1)
          .max(512),

      languageCode:
        z
          .string()
          .trim()
          .min(2)
          .max(20),

      components:
        z
          .array(
            z.unknown(),
          )
          .max(50)
          .optional(),
    })
    .strict();

export const sendInboxMessageSchema =
  z.discriminatedUnion(
    'type',
    [
      sendTextMessageSchema,
      sendTemplateMessageSchema,
    ],
  );

export const updateInboxConversationSchema =
  z
    .object({
      status:
        conversationStatusSchema.optional(),

      assignedEmployeeId:
        uuidSchema
          .nullable()
          .optional(),
    })
    .strict()
    .refine(
      (value) =>
        Object.keys(
          value,
        ).length > 0,
      {
        message:
          'At least one conversation field must be provided.',
      },
    );

const quickReplyTitleSchema =
  z
    .string()
    .trim()
    .min(1)
    .max(120);

const quickReplyShortcutSchema =
  z
    .string()
    .trim()
    .toLowerCase()
    .min(1)
    .max(80)
    .regex(
      /^[a-z0-9_-]+$/,
    );

const quickReplyBodySchema =
  z
    .string()
    .trim()
    .min(1)
    .max(4096);

export const createInboxQuickReplySchema =
  z
    .object({
      title:
        quickReplyTitleSchema,

      shortcut:
        quickReplyShortcutSchema,

      body:
        quickReplyBodySchema,
    })
    .strict();

export const updateInboxQuickReplySchema =
  z
    .object({
      title:
        quickReplyTitleSchema.optional(),

      shortcut:
        quickReplyShortcutSchema.optional(),

      body:
        quickReplyBodySchema.optional(),
    })
    .strict()
    .refine(
      (value) =>
        Object.keys(
          value,
        ).length > 0,
      {
        message:
          'At least one quick reply field must be provided.',
      },
    );

export type InboxConversationListQuery =
  z.infer<
    typeof inboxConversationListQuerySchema
  >;

export type InboxMessageListQuery =
  z.infer<
    typeof inboxMessageListQuerySchema
  >;

export type SendInboxMessageInput =
  z.infer<
    typeof sendInboxMessageSchema
  >;

export type UpdateInboxConversationInput =
  z.infer<
    typeof updateInboxConversationSchema
  >;

export type CreateInboxQuickReplyInput =
  z.infer<
    typeof createInboxQuickReplySchema
  >;

export type UpdateInboxQuickReplyInput =
  z.infer<
    typeof updateInboxQuickReplySchema
  >;
'@

Write-Text `
    -Path ".\packages\validation\src\inbox.ts" `
    -Content $InboxValidation

$ValidationIndexPath =
    ".\packages\validation\src\index.ts"

$ValidationIndex =
    Read-Text -Path $ValidationIndexPath

if (-not $ValidationIndex.Contains("export * from './inbox.js';")) {
    $ValidationIndex =
        $ValidationIndex.TrimEnd() +
        "`r`n" +
        "export * from './inbox.js';`r`n"
}

Write-Text `
    -Path $ValidationIndexPath `
    -Content $ValidationIndex

Write-Host "[OK] Inbox validation criada." -ForegroundColor Green

# ============================================================
# META WEBHOOK EVENT PARSER
# ============================================================

$WebhookEvents = @'
type UnknownRecord =
  Record<
    string,
    unknown
  >;

export type WhatsAppInboundWebhookEvent =
  Readonly<{
    kind:
      'MESSAGE';

    wabaId:
      string | null;

    phoneNumberId:
      string | null;

    messageId:
      string;

    from:
      string;

    timestamp:
      string | null;

    messageType:
      string;

    textBody:
      string | null;

    profileName:
      string | null;

    replyToMessageId:
      string | null;

    payload:
      UnknownRecord;
  }>;

export type WhatsAppStatusWebhookEvent =
  Readonly<{
    kind:
      'STATUS';

    wabaId:
      string | null;

    phoneNumberId:
      string | null;

    messageId:
      string;

    recipientId:
      string | null;

    timestamp:
      string | null;

    status:
      string;

    errors:
      readonly unknown[];

    payload:
      UnknownRecord;
  }>;

export type WhatsAppWebhookEvent =
  | WhatsAppInboundWebhookEvent
  | WhatsAppStatusWebhookEvent;

function isRecord(
  value: unknown,
): value is UnknownRecord {
  return (
    typeof value ===
      'object' &&
    value !== null &&
    !Array.isArray(
      value,
    )
  );
}

function records(
  value: unknown,
): readonly UnknownRecord[] {
  if (
    !Array.isArray(
      value,
    )
  ) {
    return [];
  }

  return value.filter(
    isRecord,
  );
}

function readString(
  value: unknown,
): string | null {
  return typeof value ===
    'string'
    ? value
    : null;
}

function readTextBody(
  message: UnknownRecord,
): string | null {
  const text =
    isRecord(
      message.text,
    )
      ? message.text
      : null;

  return readString(
    text?.body,
  );
}

function readReplyToMessageId(
  message: UnknownRecord,
): string | null {
  const context =
    isRecord(
      message.context,
    )
      ? message.context
      : null;

  return readString(
    context?.id,
  );
}

export function parseWhatsAppWebhookEvents(
  payload: unknown,
): readonly WhatsAppWebhookEvent[] {
  if (
    !isRecord(
      payload,
    )
  ) {
    return [];
  }

  const events:
    WhatsAppWebhookEvent[] =
      [];

  for (
    const entry of records(
      payload.entry,
    )
  ) {
    const wabaId =
      readString(
        entry.id,
      );

    for (
      const change of records(
        entry.changes,
      )
    ) {
      if (
        readString(
          change.field,
        ) !==
        'messages'
      ) {
        continue;
      }

      const value =
        isRecord(
          change.value,
        )
          ? change.value
          : null;

      if (!value) {
        continue;
      }

      const metadata =
        isRecord(
          value.metadata,
        )
          ? value.metadata
          : null;

      const phoneNumberId =
        readString(
          metadata?.phone_number_id,
        );

      const contactNames =
        new Map<
          string,
          string | null
        >();

      for (
        const contact of records(
          value.contacts,
        )
      ) {
        const waId =
          readString(
            contact.wa_id,
          );

        if (!waId) {
          continue;
        }

        const profile =
          isRecord(
            contact.profile,
          )
            ? contact.profile
            : null;

        contactNames.set(
          waId,
          readString(
            profile?.name,
          ),
        );
      }

      for (
        const message of records(
          value.messages,
        )
      ) {
        const messageId =
          readString(
            message.id,
          );

        const from =
          readString(
            message.from,
          );

        if (
          !messageId ||
          !from
        ) {
          continue;
        }

        events.push({
          kind:
            'MESSAGE',

          wabaId,

          phoneNumberId,

          messageId,

          from,

          timestamp:
            readString(
              message.timestamp,
            ),

          messageType:
            readString(
              message.type,
            ) ??
            'unknown',

          textBody:
            readTextBody(
              message,
            ),

          profileName:
            contactNames.get(
              from,
            ) ??
            null,

          replyToMessageId:
            readReplyToMessageId(
              message,
            ),

          payload:
            message,
        });
      }

      for (
        const status of records(
          value.statuses,
        )
      ) {
        const messageId =
          readString(
            status.id,
          );

        const statusName =
          readString(
            status.status,
          );

        if (
          !messageId ||
          !statusName
        ) {
          continue;
        }

        events.push({
          kind:
            'STATUS',

          wabaId,

          phoneNumberId,

          messageId,

          recipientId:
            readString(
              status.recipient_id,
            ),

          timestamp:
            readString(
              status.timestamp,
            ),

          status:
            statusName,

          errors:
            Array.isArray(
              status.errors,
            )
              ? status.errors
              : [],

          payload:
            status,
        });
      }
    }
  }

  return events;
}
'@

Write-Text `
    -Path ".\packages\meta-cloud-api\src\whatsapp-webhook-events.ts" `
    -Content $WebhookEvents

$MetaIndexPath =
    ".\packages\meta-cloud-api\src\index.ts"

$MetaIndex =
    Read-Text -Path $MetaIndexPath

if (-not $MetaIndex.Contains("from './whatsapp-webhook-events.js'")) {
    $MetaIndex =
        $MetaIndex.TrimEnd() +
        "`r`n" +
        "export { parseWhatsAppWebhookEvents, type WhatsAppInboundWebhookEvent, type WhatsAppStatusWebhookEvent, type WhatsAppWebhookEvent } from './whatsapp-webhook-events.js';`r`n"
}

Write-Text `
    -Path $MetaIndexPath `
    -Content $MetaIndex

Write-Host "[OK] Meta webhook event parser criado." -ForegroundColor Green

# ============================================================
# PERMISSIONS
# ============================================================

$SeedPath =
    ".\packages\database\prisma\seed.ts"

$Seed =
    Read-Text -Path $SeedPath

if (-not $Seed.Contains("'inbox.read'")) {
    $SeedAnchor =
        "  ['ads_queue.manage', 'Gerenciar fila de ADS'],"

    if (-not $Seed.Contains($SeedAnchor)) {
        throw "Anchor de permissions no seed nao encontrado."
    }

    $SeedReplacement = @'
  ['ads_queue.manage', 'Gerenciar fila de ADS'],
  ['inbox.read', 'Visualizar caixa de atendimento WhatsApp'],
  ['inbox.manage', 'Responder e gerenciar conversas WhatsApp'],
  ['quick_reply.read', 'Visualizar respostas rapidas'],
  ['quick_reply.manage', 'Gerenciar respostas rapidas'],
'@

    $Seed =
        $Seed.Replace(
            $SeedAnchor,
            $SeedReplacement.TrimEnd()
        )
}

if (-not $Seed.Contains("'inbox.manage',`r`n    'quick_reply.read'")) {
    $EmployeeAnchor =
        "    'ads_queue.read',"

    if (-not $Seed.Contains($EmployeeAnchor)) {
        throw "Anchor EMPLOYEE permissions nao encontrado."
    }

    $EmployeeReplacement = @'
    'ads_queue.read',
    'inbox.read',
    'inbox.manage',
    'quick_reply.read',
'@

    $Seed =
        $Seed.Replace(
            $EmployeeAnchor,
            $EmployeeReplacement.TrimEnd()
        )
}

Write-Text `
    -Path $SeedPath `
    -Content $Seed

# verify-seed

$VerifySeedPath =
    ".\packages\database\prisma\verify-seed.ts"

$VerifySeed =
    Read-Text -Path $VerifySeedPath

$ExpectedPermissions = @'
const expectedPermissionCodes = [
  'ads_queue.manage',
  'ads_queue.read',
  'ads_request.manage',
  'ads_request.read',
  'audit.read',
  'domain.manage',
  'domain.read',
  'employee.manage',
  'employee.read',
  'inbox.manage',
  'inbox.read',
  'organization.manage',
  'organization.read',
  'profile.read',
  'profile.update',
  'quick_reply.manage',
  'quick_reply.read',
  'site.manage',
  'site.read',
  'team.manage',
  'team.read',
  'traffic_pool.manage',
  'traffic_pool.read',
  'user.manage',
  'user.read',
  'whatsapp_number.manage',
  'whatsapp_number.read',
] as const;
'@

$VerifySeed =
    [regex]::Replace(
        $VerifySeed,
        '(?s)const expectedPermissionCodes = \[.*?\] as const;',
        $ExpectedPermissions.TrimEnd(),
        1
    )

$ExpectedEmployeePermissions = @'
const expectedEmployeePermissionCodes = [
  'ads_queue.read',
  'ads_request.manage',
  'ads_request.read',
  'domain.read',
  'inbox.manage',
  'inbox.read',
  'profile.read',
  'profile.update',
  'quick_reply.read',
  'site.read',
  'traffic_pool.read',
  'whatsapp_number.read',
] as const;
'@

$VerifySeed =
    [regex]::Replace(
        $VerifySeed,
        '(?s)const expectedEmployeePermissionCodes = \[.*?\] as const;',
        $ExpectedEmployeePermissions.TrimEnd(),
        1
    )

$VerifySeed =
    $VerifySeed.Replace(
        "Stage 4 seed",
        "Stage 9 seed"
    )

$VerifySeed =
    $VerifySeed.Replace(
        "Stage 4 permission",
        "Stage 9 permission"
    )

$VerifySeed =
    $VerifySeed.Replace(
        "Stage 4.",
        "Stage 9."
    )

Write-Text `
    -Path $VerifySeedPath `
    -Content $VerifySeed

# authorization types

$AuthorizationTypesPath =
    ".\apps\api\src\authorization\authorization.types.ts"

$AuthorizationTypes =
    Read-Text -Path $AuthorizationTypesPath

if (-not $AuthorizationTypes.Contains("'inbox.read'")) {
    $AuthorizationAnchor =
        "  | 'ads_queue.manage';"

    if (-not $AuthorizationTypes.Contains($AuthorizationAnchor)) {
        throw "Authorization PermissionCode anchor nao encontrado."
    }

    $AuthorizationReplacement = @'
  | 'ads_queue.manage'
  | 'inbox.read'
  | 'inbox.manage'
  | 'quick_reply.read'
  | 'quick_reply.manage';
'@

    $AuthorizationTypes =
        $AuthorizationTypes.Replace(
            $AuthorizationAnchor,
            $AuthorizationReplacement.TrimEnd()
        )
}

Write-Text `
    -Path $AuthorizationTypesPath `
    -Content $AuthorizationTypes

# AccessTokenGuard whitelist

$AccessGuardPath =
    ".\apps\api\src\authorization\access-token.guard.ts"

$AccessGuard =
    Read-Text -Path $AccessGuardPath

if (-not $AccessGuard.Contains("value === 'inbox.read'")) {
    $GuardAnchor =
        "      value === 'ads_queue.manage'"

    if (-not $AccessGuard.Contains($GuardAnchor)) {
        throw "AccessTokenGuard permission anchor nao encontrado."
    }

    $GuardReplacement = @'
      value === 'ads_queue.manage' ||
      value === 'inbox.read' ||
      value === 'inbox.manage' ||
      value === 'quick_reply.read' ||
      value === 'quick_reply.manage'
'@

    $AccessGuard =
        $AccessGuard.Replace(
            $GuardAnchor,
            $GuardReplacement.TrimEnd()
        )
}

Write-Text `
    -Path $AccessGuardPath `
    -Content $AccessGuard

Write-Host "[OK] Stage 9 permissions criadas." -ForegroundColor Green

# ============================================================
# API - INBOX SERVICE
# ============================================================

$InboxService = @'
import {
  ConflictException,
  ForbiddenException,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';

import type {
  AuthenticatedPrincipal,
} from '@crm/auth';

import type {
  EmployeeModel,
  UserModel,
  WhatsAppContactModel,
  WhatsAppConversationModel,
  WhatsAppMessageModel,
  WhatsAppNumberModel,
  WhatsAppQuickReplyModel,
} from '@crm/database';

import type {
  InboxConversationListResponse,
  InboxConversationResponse,
  InboxMessageListResponse,
  InboxMessageResponse,
  InboxQuickReplyListResponse,
  InboxQuickReplyResponse,
} from '@crm/contracts';

import type {
  CreateInboxQuickReplyInput,
  InboxConversationListQuery,
  InboxMessageListQuery,
  SendInboxMessageInput,
  UpdateInboxConversationInput,
  UpdateInboxQuickReplyInput,
} from '@crm/validation';

import {
  DatabaseService,
} from '../database/database.service.js';

type JsonPrimitive =
  string |
  number |
  boolean |
  null;

type JsonValue =
  JsonPrimitive |
  JsonValue[] |
  {
    [key: string]:
      JsonValue;
  };

type JsonObject = {
  [key: string]:
    JsonValue;
};

type LoadedAssignee =
  Pick<
    EmployeeModel,
    'id' |
    'employeeCode' |
    'userId'
  > & {
    user:
      Pick<
        UserModel,
        'displayName'
      >;
  };

type LoadedConversation =
  WhatsAppConversationModel & {
    contact:
      Pick<
        WhatsAppContactModel,
        'id' |
        'waId' |
        'profileName'
      >;

    whatsAppNumber:
      Pick<
        WhatsAppNumberModel,
        'id' |
        'displayName' |
        'e164' |
        'metaPhoneNumberId' |
        'status'
      >;

    assignedEmployee:
      LoadedAssignee |
      null;

    messages:
      WhatsAppMessageModel[];
  };

function normalizeJsonValue(
  value: unknown,
): JsonValue {
  if (
    value === null ||
    typeof value ===
      'string' ||
    typeof value ===
      'boolean'
  ) {
    return value;
  }

  if (
    typeof value ===
      'number'
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
      normalizeJsonValue,
    );
  }

  if (
    typeof value ===
      'object' &&
    value !== null
  ) {
    const result:
      JsonObject =
        {};

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

@Injectable()
export class InboxService {
  constructor(
    @Inject(
      DatabaseService,
    )
    private readonly database:
      DatabaseService,
  ) {}

  async listConversations(
    principal:
      AuthenticatedPrincipal,
    query:
      InboxConversationListQuery,
  ): Promise<
    InboxConversationListResponse
  > {
    const employeeId =
      this.isAdmin(
        principal,
      )
        ? null
        : await this.getCurrentEmployeeId(
            principal,
          );

    const conversations =
      await this.database.client.whatsAppConversation.findMany({
        where: {
          organizationId:
            principal.organizationId,

          ...(employeeId
            ? {
                assignedEmployeeId:
                  employeeId,
              }
            : {}),

          ...(query.status
            ? {
                status:
                  query.status,
              }
            : {}),

          ...(query.whatsAppNumberId
            ? {
                whatsAppNumberId:
                  query.whatsAppNumberId,
              }
            : {}),

          ...(query.search
            ? {
                OR: [
                  {
                    contact: {
                      profileName: {
                        contains:
                          query.search,

                        mode:
                          'insensitive',
                      },
                    },
                  },

                  {
                    contact: {
                      waId: {
                        contains:
                          query.search,
                      },
                    },
                  },

                  {
                    whatsAppNumber: {
                      displayName: {
                        contains:
                          query.search,

                        mode:
                          'insensitive',
                      },
                    },
                  },
                ],
              }
            : {}),
        },

        include: {
          contact: {
            select: {
              id: true,
              waId: true,
              profileName: true,
            },
          },

          whatsAppNumber: {
            select: {
              id: true,
              displayName: true,
              e164: true,
              metaPhoneNumberId: true,
              status: true,
            },
          },

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

          messages: {
            orderBy: {
              createdAt:
                'desc',
            },

            take:
              1,
          },
        },

        orderBy: [
          {
            lastMessageAt:
              'desc',
          },

          {
            id:
              'desc',
          },
        ],

        take:
          query.limit +
          1,

        ...(query.cursor
          ? {
              cursor: {
                id:
                  query.cursor,
              },

              skip:
                1,
            }
          : {}),
      });

    const hasMore =
      conversations.length >
      query.limit;

    const page =
      hasMore
        ? conversations.slice(
            0,
            query.limit,
          )
        : conversations;

    return {
      items:
        page.map(
          (conversation) =>
            this.mapConversation(
              conversation,
            ),
        ),

      nextCursor:
        hasMore
          ? page.at(
              -1,
            )?.id ??
            null
          : null,
    };
  }

  async getConversation(
    principal:
      AuthenticatedPrincipal,
    conversationId:
      string,
  ): Promise<
    InboxConversationResponse
  > {
    const conversation =
      await this.getAccessibleConversation(
        principal,
        conversationId,
      );

    return this.mapConversation(
      conversation,
    );
  }

  async listMessages(
    principal:
      AuthenticatedPrincipal,
    conversationId:
      string,
    query:
      InboxMessageListQuery,
  ): Promise<
    InboxMessageListResponse
  > {
    const conversation =
      await this.getAccessibleConversation(
        principal,
        conversationId,
      );

    const messages =
      await this.database.client.whatsAppMessage.findMany({
        where: {
          organizationId:
            principal.organizationId,

          conversationId:
            conversation.id,
        },

        orderBy: [
          {
            createdAt:
              'desc',
          },

          {
            id:
              'desc',
          },
        ],

        take:
          query.limit +
          1,

        ...(query.cursor
          ? {
              cursor: {
                id:
                  query.cursor,
              },

              skip:
                1,
            }
          : {}),
      });

    const hasMore =
      messages.length >
      query.limit;

    const page =
      hasMore
        ? messages.slice(
            0,
            query.limit,
          )
        : messages;

    return {
      items:
        page.map(
          (message) =>
            this.mapMessage(
              message,
            ),
        ),

      nextCursor:
        hasMore
          ? page.at(
              -1,
            )?.id ??
            null
          : null,
    };
  }

  async sendMessage(
    principal:
      AuthenticatedPrincipal,
    conversationId:
      string,
    input:
      SendInboxMessageInput,
  ): Promise<
    InboxMessageResponse
  > {
    const conversation =
      await this.getAccessibleConversation(
        principal,
        conversationId,
      );

    if (
      conversation.whatsAppNumber.status !==
        'ACTIVE' ||
      !conversation.whatsAppNumber.metaPhoneNumberId
    ) {
      throw new ConflictException({
        code:
          'WHATSAPP_NUMBER_NOT_CONNECTED',

        message:
          'The WhatsApp number is not active and connected to Meta Cloud API.',
      });
    }

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

    if (existing) {
      if (
        existing.conversationId !==
        conversation.id
      ) {
        throw new ConflictException({
          code:
            'WHATSAPP_CLIENT_MESSAGE_ID_CONFLICT',

          message:
            'This client message id is already used by another conversation.',
        });
      }

      return this.mapMessage(
        existing,
      );
    }

    const now =
      new Date();

    const windowOpen =
      Boolean(
        conversation.customerServiceWindowExpiresAt &&
        conversation.customerServiceWindowExpiresAt >
          now,
      );

    if (
      input.type ===
        'TEXT' &&
      !windowOpen
    ) {
      throw new ConflictException({
        code:
          'WHATSAPP_CUSTOMER_SERVICE_WINDOW_CLOSED',

        message:
          'The 24-hour customer service window is closed. Use an approved template message.',
      });
    }

    const content:
      JsonObject =
        input.type ===
          'TEXT'
          ? {
              type:
                'text',

              text: {
                body:
                  input.text,
              },

              ...(input.replyToMetaMessageId
                ? {
                    context: {
                      messageId:
                        input.replyToMetaMessageId,
                    },
                  }
                : {}),
            }
          : {
              type:
                'template',

              template: {
                name:
                  input.templateName,

                languageCode:
                  input.languageCode,

                ...(input.components !==
                undefined
                  ? {
                      components:
                        normalizeJsonValue(
                          input.components,
                        ),
                    }
                  : {}),
              },
            };

    const message =
      await this.database.client.$transaction(
        async (
          transaction,
        ) => {
          const created =
            await transaction.whatsAppMessage.create({
              data: {
                organizationId:
                  principal.organizationId,

                conversationId:
                  conversation.id,

                whatsAppNumberId:
                  conversation.whatsAppNumberId,

                contactId:
                  conversation.contactId,

                direction:
                  'OUTBOUND',

                type:
                  input.type,

                status:
                  'QUEUED',

                clientMessageId:
                  input.clientMessageId,

                replyToMetaMessageId:
                  input.type ===
                    'TEXT'
                    ? input.replyToMetaMessageId ??
                      null
                    : null,

                textBody:
                  input.type ===
                    'TEXT'
                    ? input.text
                    : null,

                content,

                queuedAt:
                  now,

                availableAt:
                  now,
              },
            });

          await transaction.whatsAppConversation.update({
            where: {
              id:
                conversation.id,
            },

            data: {
              lastMessageAt:
                now,
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
                'whatsapp_message.queued',

              resourceType:
                'whatsapp_message',

              resourceId:
                created.id,

              outcome:
                'SUCCESS',

              metadata: {
                conversationId:
                  conversation.id,

                direction:
                  'OUTBOUND',

                type:
                  created.type,

                clientMessageId:
                  created.clientMessageId,
              },
            },
          });

          return created;
        },
      );

    return this.mapMessage(
      message,
    );
  }

  async updateConversation(
    principal:
      AuthenticatedPrincipal,
    conversationId:
      string,
    input:
      UpdateInboxConversationInput,
  ): Promise<
    InboxConversationResponse
  > {
    const conversation =
      await this.getAccessibleConversation(
        principal,
        conversationId,
      );

    if (
      input.assignedEmployeeId !==
        undefined &&
      !this.isAdmin(
        principal,
      )
    ) {
      throw new ForbiddenException({
        code:
          'INBOX_ASSIGNMENT_ADMIN_REQUIRED',

        message:
          'Only ADMIN can change conversation assignment.',
      });
    }

    if (
      input.assignedEmployeeId
    ) {
      await this.assertActiveEmployee(
        principal.organizationId,
        input.assignedEmployeeId,
      );
    }

    await this.database.client.$transaction(
      async (
        transaction,
      ) => {
        await transaction.whatsAppConversation.update({
          where: {
            id:
              conversation.id,
          },

          data: {
            ...(input.status !==
            undefined
              ? {
                  status:
                    input.status,
                }
              : {}),

            ...(input.assignedEmployeeId !==
            undefined
              ? {
                  assignedEmployeeId:
                    input.assignedEmployeeId,
                }
              : {}),
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
              'whatsapp_conversation.updated',

            resourceType:
              'whatsapp_conversation',

            resourceId:
              conversation.id,

            outcome:
              'SUCCESS',

            metadata: {
              ...(input.status !==
              undefined
                ? {
                    status:
                      input.status,
                  }
                : {}),

              ...(input.assignedEmployeeId !==
              undefined
                ? {
                    assignedEmployeeId:
                      input.assignedEmployeeId,
                  }
                : {}),
            },
          },
        });
      },
    );

    return this.getConversation(
      principal,
      conversation.id,
    );
  }

  async markConversationRead(
    principal:
      AuthenticatedPrincipal,
    conversationId:
      string,
  ): Promise<
    InboxConversationResponse
  > {
    const conversation =
      await this.getAccessibleConversation(
        principal,
        conversationId,
      );

    await this.database.client.$transaction(
      async (
        transaction,
      ) => {
        await transaction.whatsAppConversation.update({
          where: {
            id:
              conversation.id,
          },

          data: {
            unreadCount:
              0,
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
              'whatsapp_conversation.read',

            resourceType:
              'whatsapp_conversation',

            resourceId:
              conversation.id,

            outcome:
              'SUCCESS',
          },
        });
      },
    );

    return this.getConversation(
      principal,
      conversation.id,
    );
  }

  async listQuickReplies(
    principal:
      AuthenticatedPrincipal,
  ): Promise<
    InboxQuickReplyListResponse
  > {
    const replies =
      await this.database.client.whatsAppQuickReply.findMany({
        where: {
          organizationId:
            principal.organizationId,

          deletedAt:
            null,
        },

        orderBy: [
          {
            title:
              'asc',
          },

          {
            shortcut:
              'asc',
          },
        ],
      });

    return replies.map(
      (
        reply,
      ) =>
        this.mapQuickReply(
          reply,
        ),
    );
  }

  async createQuickReply(
    principal:
      AuthenticatedPrincipal,
    input:
      CreateInboxQuickReplyInput,
  ): Promise<
    InboxQuickReplyResponse
  > {
    try {
      const reply =
        await this.database.client.$transaction(
          async (
            transaction,
          ) => {
            const created =
              await transaction.whatsAppQuickReply.create({
                data: {
                  organizationId:
                    principal.organizationId,

                  title:
                    input.title,

                  shortcut:
                    input.shortcut,

                  body:
                    input.body,
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
                  'whatsapp_quick_reply.created',

                resourceType:
                  'whatsapp_quick_reply',

                resourceId:
                  created.id,

                outcome:
                  'SUCCESS',

                metadata: {
                  shortcut:
                    created.shortcut,
                },
              },
            });

            return created;
          },
        );

      return this.mapQuickReply(
        reply,
      );
    }
    catch (
      error
    ) {
      if (
        this.isUniqueConstraintError(
          error,
        )
      ) {
        throw new ConflictException({
          code:
            'QUICK_REPLY_SHORTCUT_EXISTS',

          message:
            'This quick reply shortcut already exists.',
        });
      }

      throw error;
    }
  }

  async updateQuickReply(
    principal:
      AuthenticatedPrincipal,
    quickReplyId:
      string,
    input:
      UpdateInboxQuickReplyInput,
  ): Promise<
    InboxQuickReplyResponse
  > {
    await this.getOrganizationQuickReply(
      principal.organizationId,
      quickReplyId,
    );

    try {
      const reply =
        await this.database.client.whatsAppQuickReply.update({
          where: {
            id:
              quickReplyId,
          },

          data: {
            ...(input.title !==
            undefined
              ? {
                  title:
                    input.title,
                }
              : {}),

            ...(input.shortcut !==
            undefined
              ? {
                  shortcut:
                    input.shortcut,
                }
              : {}),

            ...(input.body !==
            undefined
              ? {
                  body:
                    input.body,
                }
              : {}),
          },
        });

      return this.mapQuickReply(
        reply,
      );
    }
    catch (
      error
    ) {
      if (
        this.isUniqueConstraintError(
          error,
        )
      ) {
        throw new ConflictException({
          code:
            'QUICK_REPLY_SHORTCUT_EXISTS',

          message:
            'This quick reply shortcut already exists.',
        });
      }

      throw error;
    }
  }

  async deleteQuickReply(
    principal:
      AuthenticatedPrincipal,
    quickReplyId:
      string,
  ): Promise<
    InboxQuickReplyResponse
  > {
    const existing =
      await this.getOrganizationQuickReply(
        principal.organizationId,
        quickReplyId,
      );

    if (
      existing.deletedAt
    ) {
      throw new NotFoundException({
        code:
          'QUICK_REPLY_NOT_FOUND',

        message:
          'Quick reply not found.',
      });
    }

    const reply =
      await this.database.client.whatsAppQuickReply.update({
        where: {
          id:
            quickReplyId,
        },

        data: {
          deletedAt:
            new Date(),
        },
      });

    return this.mapQuickReply(
      reply,
    );
  }

  private async getAccessibleConversation(
    principal:
      AuthenticatedPrincipal,
    conversationId:
      string,
  ): Promise<
    LoadedConversation
  > {
    const employeeId =
      this.isAdmin(
        principal,
      )
        ? null
        : await this.getCurrentEmployeeId(
            principal,
          );

    const conversation =
      await this.database.client.whatsAppConversation.findFirst({
        where: {
          id:
            conversationId,

          organizationId:
            principal.organizationId,

          ...(employeeId
            ? {
                assignedEmployeeId:
                  employeeId,
              }
            : {}),
        },

        include: {
          contact: {
            select: {
              id: true,
              waId: true,
              profileName: true,
            },
          },

          whatsAppNumber: {
            select: {
              id: true,
              displayName: true,
              e164: true,
              metaPhoneNumberId: true,
              status: true,
            },
          },

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

          messages: {
            orderBy: {
              createdAt:
                'desc',
            },

            take:
              1,
          },
        },
      });

    if (!conversation) {
      throw new NotFoundException({
        code:
          'INBOX_CONVERSATION_NOT_FOUND',

        message:
          'Conversation not found.',
      });
    }

    return conversation;
  }

  private async getOrganizationQuickReply(
    organizationId:
      string,
    quickReplyId:
      string,
  ): Promise<
    WhatsAppQuickReplyModel
  > {
    const reply =
      await this.database.client.whatsAppQuickReply.findFirst({
        where: {
          id:
            quickReplyId,

          organizationId,
        },
      });

    if (!reply) {
      throw new NotFoundException({
        code:
          'QUICK_REPLY_NOT_FOUND',

        message:
          'Quick reply not found.',
      });
    }

    return reply;
  }

  private async getCurrentEmployeeId(
    principal:
      AuthenticatedPrincipal,
  ): Promise<
    string
  > {
    const employee =
      await this.database.client.employee.findFirst({
        where: {
          organizationId:
            principal.organizationId,

          userId:
            principal.userId,

          status:
            'ACTIVE',

          deletedAt:
            null,
        },

        select: {
          id:
            true,
        },
      });

    if (!employee) {
      throw new ForbiddenException({
        code:
          'EMPLOYEE_PROFILE_REQUIRED',

        message:
          'An active employee profile is required.',
      });
    }

    return employee.id;
  }

  private async assertActiveEmployee(
    organizationId:
      string,
    employeeId:
      string,
  ): Promise<
    void
  > {
    const employee =
      await this.database.client.employee.findFirst({
        where: {
          id:
            employeeId,

          organizationId,

          status:
            'ACTIVE',

          deletedAt:
            null,
        },

        select: {
          id:
            true,
        },
      });

    if (!employee) {
      throw new NotFoundException({
        code:
          'INBOX_EMPLOYEE_NOT_FOUND',

        message:
          'Active employee not found.',
      });
    }
  }

  private mapConversation(
    conversation:
      LoadedConversation,
  ): InboxConversationResponse {
    const now =
      new Date();

    return {
      id:
        conversation.id,

      organizationId:
        conversation.organizationId,

      status:
        conversation.status,

      contact: {
        id:
          conversation.contact.id,

        waId:
          conversation.contact.waId,

        profileName:
          conversation.contact.profileName,
      },

      whatsAppNumber: {
        id:
          conversation.whatsAppNumber.id,

        displayName:
          conversation.whatsAppNumber.displayName,

        e164:
          conversation.whatsAppNumber.e164,
      },

      assignedEmployee:
        conversation.assignedEmployee
          ? {
              employeeId:
                conversation.assignedEmployee.id,

              employeeCode:
                conversation.assignedEmployee.employeeCode,

              userId:
                conversation.assignedEmployee.userId,

              displayName:
                conversation.assignedEmployee.user.displayName,
            }
          : null,

      customerServiceWindowExpiresAt:
        conversation.customerServiceWindowExpiresAt?.toISOString() ??
        null,

      isCustomerServiceWindowOpen:
        Boolean(
          conversation.customerServiceWindowExpiresAt &&
          conversation.customerServiceWindowExpiresAt >
            now,
        ),

      lastMessageAt:
        conversation.lastMessageAt?.toISOString() ??
        null,

      lastInboundAt:
        conversation.lastInboundAt?.toISOString() ??
        null,

      lastOutboundAt:
        conversation.lastOutboundAt?.toISOString() ??
        null,

      unreadCount:
        conversation.unreadCount,

      lastMessage:
        conversation.messages[0]
          ? this.mapMessage(
              conversation.messages[0],
            )
          : null,

      createdAt:
        conversation.createdAt.toISOString(),

      updatedAt:
        conversation.updatedAt.toISOString(),
    };
  }

  private mapMessage(
    message:
      WhatsAppMessageModel,
  ): InboxMessageResponse {
    return {
      id:
        message.id,

      organizationId:
        message.organizationId,

      conversationId:
        message.conversationId,

      whatsAppNumberId:
        message.whatsAppNumberId,

      contactId:
        message.contactId,

      direction:
        message.direction,

      type:
        message.type,

      status:
        message.status,

      metaMessageId:
        message.metaMessageId,

      clientMessageId:
        message.clientMessageId,

      replyToMetaMessageId:
        message.replyToMetaMessageId,

      textBody:
        message.textBody,

      content:
        message.content,

      providerTimestamp:
        message.providerTimestamp?.toISOString() ??
        null,

      errorCode:
        message.errorCode,

      errorMessage:
        message.errorMessage,

      queuedAt:
        message.queuedAt?.toISOString() ??
        null,

      sentAt:
        message.sentAt?.toISOString() ??
        null,

      deliveredAt:
        message.deliveredAt?.toISOString() ??
        null,

      readAt:
        message.readAt?.toISOString() ??
        null,

      failedAt:
        message.failedAt?.toISOString() ??
        null,

      createdAt:
        message.createdAt.toISOString(),

      updatedAt:
        message.updatedAt.toISOString(),
    };
  }

  private mapQuickReply(
    reply:
      WhatsAppQuickReplyModel,
  ): InboxQuickReplyResponse {
    return {
      id:
        reply.id,

      organizationId:
        reply.organizationId,

      title:
        reply.title,

      shortcut:
        reply.shortcut,

      body:
        reply.body,

      createdAt:
        reply.createdAt.toISOString(),

      updatedAt:
        reply.updatedAt.toISOString(),
    };
  }

  private isAdmin(
    principal:
      AuthenticatedPrincipal,
  ): boolean {
    return principal.roles.includes(
      'ADMIN',
    );
  }

  private isUniqueConstraintError(
    error:
      unknown,
  ): boolean {
    if (
      typeof error !==
        'object' ||
      error ===
        null
    ) {
      return false;
    }

    return (
      'code' in
        error &&
      (
        error as {
          code?:
            unknown;
        }
      ).code ===
        'P2002'
    );
  }
}
'@

New-Item `
    -ItemType Directory `
    -Path ".\apps\api\src\inbox" `
    -Force |
    Out-Null

Write-Text `
    -Path ".\apps\api\src\inbox\inbox.service.ts" `
    -Content $InboxService

# ============================================================
# API CONTROLLER
# ============================================================

$InboxController = @'
import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  Inject,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';

import type {
  AuthenticatedPrincipal,
} from '@crm/auth';

import type {
  InboxConversationListResponse,
  InboxConversationResponse,
  InboxMessageListResponse,
  InboxMessageResponse,
  InboxQuickReplyListResponse,
  InboxQuickReplyResponse,
} from '@crm/contracts';

import {
  createInboxQuickReplySchema,
  inboxConversationListQuerySchema,
  inboxMessageListQuerySchema,
  sendInboxMessageSchema,
  updateInboxConversationSchema,
  updateInboxQuickReplySchema,
} from '@crm/validation';

import {
  AccessTokenGuard,
} from '../authorization/access-token.guard.js';

import {
  AuthorizationGuard,
} from '../authorization/authorization.guard.js';

import {
  CurrentPrincipal,
} from '../authorization/current-principal.decorator.js';

import {
  RequirePermissions,
} from '../authorization/require-permissions.decorator.js';

import {
  InboxService,
} from './inbox.service.js';

@Controller('inbox')
@UseGuards(
  AccessTokenGuard,
  AuthorizationGuard,
)
export class InboxController {
  constructor(
    @Inject(
      InboxService,
    )
    private readonly inboxService:
      InboxService,
  ) {}

  @Get('conversations')
  @RequirePermissions(
    'inbox.read',
  )
  listConversations(
    @CurrentPrincipal()
    principal:
      AuthenticatedPrincipal,

    @Query()
    query:
      unknown,
  ): Promise<
    InboxConversationListResponse
  > {
    const parsed =
      inboxConversationListQuerySchema.safeParse(
        query,
      );

    if (
      !parsed.success
    ) {
      throw this.validationError(
        'INBOX_QUERY_VALIDATION_ERROR',
        parsed.error.issues,
      );
    }

    return this.inboxService.listConversations(
      principal,
      parsed.data,
    );
  }

  @Get(
    'conversations/:conversationId',
  )
  @RequirePermissions(
    'inbox.read',
  )
  getConversation(
    @CurrentPrincipal()
    principal:
      AuthenticatedPrincipal,

    @Param(
      'conversationId',
      new ParseUUIDPipe(),
    )
    conversationId:
      string,
  ): Promise<
    InboxConversationResponse
  > {
    return this.inboxService.getConversation(
      principal,
      conversationId,
    );
  }

  @Get(
    'conversations/:conversationId/messages',
  )
  @RequirePermissions(
    'inbox.read',
  )
  listMessages(
    @CurrentPrincipal()
    principal:
      AuthenticatedPrincipal,

    @Param(
      'conversationId',
      new ParseUUIDPipe(),
    )
    conversationId:
      string,

    @Query()
    query:
      unknown,
  ): Promise<
    InboxMessageListResponse
  > {
    const parsed =
      inboxMessageListQuerySchema.safeParse(
        query,
      );

    if (
      !parsed.success
    ) {
      throw this.validationError(
        'INBOX_MESSAGE_QUERY_VALIDATION_ERROR',
        parsed.error.issues,
      );
    }

    return this.inboxService.listMessages(
      principal,
      conversationId,
      parsed.data,
    );
  }

  @Post(
    'conversations/:conversationId/messages',
  )
  @RequirePermissions(
    'inbox.manage',
  )
  sendMessage(
    @CurrentPrincipal()
    principal:
      AuthenticatedPrincipal,

    @Param(
      'conversationId',
      new ParseUUIDPipe(),
    )
    conversationId:
      string,

    @Body()
    body:
      unknown,
  ): Promise<
    InboxMessageResponse
  > {
    const parsed =
      sendInboxMessageSchema.safeParse(
        body,
      );

    if (
      !parsed.success
    ) {
      throw this.validationError(
        'INBOX_MESSAGE_VALIDATION_ERROR',
        parsed.error.issues,
      );
    }

    return this.inboxService.sendMessage(
      principal,
      conversationId,
      parsed.data,
    );
  }

  @Patch(
    'conversations/:conversationId',
  )
  @RequirePermissions(
    'inbox.manage',
  )
  updateConversation(
    @CurrentPrincipal()
    principal:
      AuthenticatedPrincipal,

    @Param(
      'conversationId',
      new ParseUUIDPipe(),
    )
    conversationId:
      string,

    @Body()
    body:
      unknown,
  ): Promise<
    InboxConversationResponse
  > {
    const parsed =
      updateInboxConversationSchema.safeParse(
        body,
      );

    if (
      !parsed.success
    ) {
      throw this.validationError(
        'INBOX_CONVERSATION_VALIDATION_ERROR',
        parsed.error.issues,
      );
    }

    return this.inboxService.updateConversation(
      principal,
      conversationId,
      parsed.data,
    );
  }

  @Post(
    'conversations/:conversationId/read',
  )
  @RequirePermissions(
    'inbox.manage',
  )
  markRead(
    @CurrentPrincipal()
    principal:
      AuthenticatedPrincipal,

    @Param(
      'conversationId',
      new ParseUUIDPipe(),
    )
    conversationId:
      string,
  ): Promise<
    InboxConversationResponse
  > {
    return this.inboxService.markConversationRead(
      principal,
      conversationId,
    );
  }

  @Get(
    'quick-replies',
  )
  @RequirePermissions(
    'quick_reply.read',
  )
  listQuickReplies(
    @CurrentPrincipal()
    principal:
      AuthenticatedPrincipal,
  ): Promise<
    InboxQuickReplyListResponse
  > {
    return this.inboxService.listQuickReplies(
      principal,
    );
  }

  @Post(
    'quick-replies',
  )
  @RequirePermissions(
    'quick_reply.manage',
  )
  createQuickReply(
    @CurrentPrincipal()
    principal:
      AuthenticatedPrincipal,

    @Body()
    body:
      unknown,
  ): Promise<
    InboxQuickReplyResponse
  > {
    const parsed =
      createInboxQuickReplySchema.safeParse(
        body,
      );

    if (
      !parsed.success
    ) {
      throw this.validationError(
        'QUICK_REPLY_VALIDATION_ERROR',
        parsed.error.issues,
      );
    }

    return this.inboxService.createQuickReply(
      principal,
      parsed.data,
    );
  }

  @Patch(
    'quick-replies/:quickReplyId',
  )
  @RequirePermissions(
    'quick_reply.manage',
  )
  updateQuickReply(
    @CurrentPrincipal()
    principal:
      AuthenticatedPrincipal,

    @Param(
      'quickReplyId',
      new ParseUUIDPipe(),
    )
    quickReplyId:
      string,

    @Body()
    body:
      unknown,
  ): Promise<
    InboxQuickReplyResponse
  > {
    const parsed =
      updateInboxQuickReplySchema.safeParse(
        body,
      );

    if (
      !parsed.success
    ) {
      throw this.validationError(
        'QUICK_REPLY_VALIDATION_ERROR',
        parsed.error.issues,
      );
    }

    return this.inboxService.updateQuickReply(
      principal,
      quickReplyId,
      parsed.data,
    );
  }

  @Delete(
    'quick-replies/:quickReplyId',
  )
  @RequirePermissions(
    'quick_reply.manage',
  )
  deleteQuickReply(
    @CurrentPrincipal()
    principal:
      AuthenticatedPrincipal,

    @Param(
      'quickReplyId',
      new ParseUUIDPipe(),
    )
    quickReplyId:
      string,
  ): Promise<
    InboxQuickReplyResponse
  > {
    return this.inboxService.deleteQuickReply(
      principal,
      quickReplyId,
    );
  }

  private validationError(
    code:
      string,
    issues:
      readonly {
        code:
          string;

        path:
          PropertyKey[];
      }[],
  ): BadRequestException {
    return new BadRequestException({
      code,

      message:
        'Invalid inbox request.',

      issues:
        issues.map(
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
}
'@

Write-Text `
    -Path ".\apps\api\src\inbox\inbox.controller.ts" `
    -Content $InboxController

$InboxModule = @'
import {
  Module,
} from '@nestjs/common';

import {
  AuthorizationModule,
} from '../authorization/authorization.module.js';

import {
  DatabaseModule,
} from '../database/database.module.js';

import {
  InboxController,
} from './inbox.controller.js';

import {
  InboxService,
} from './inbox.service.js';

@Module({
  imports: [
    AuthorizationModule,
    DatabaseModule,
  ],

  controllers: [
    InboxController,
  ],

  providers: [
    InboxService,
  ],

  exports: [
    InboxService,
  ],
})
export class InboxModule {}
'@

Write-Text `
    -Path ".\apps\api\src\inbox\inbox.module.ts" `
    -Content $InboxModule

$AppModulePath =
    ".\apps\api\src\app.module.ts"

$AppModule =
    Read-Text -Path $AppModulePath

if (-not $AppModule.Contains("InboxModule")) {
    $ImportAnchor =
        "import { NotificationsModule } from './notifications/notifications.module.js';"

    if (-not $AppModule.Contains($ImportAnchor)) {
        throw "AppModule NotificationsModule anchor nao encontrado."
    }

    $AppModule =
        $AppModule.Replace(
            $ImportAnchor,
            $ImportAnchor +
            "`r`n`r`n" +
            "import { InboxModule } from './inbox/inbox.module.js';"
        )

    $ArrayAnchor =
        "    NotificationsModule,"

    if (-not $AppModule.Contains($ArrayAnchor)) {
        throw "AppModule imports array anchor nao encontrado."
    }

    $AppModule =
        $AppModule.Replace(
            $ArrayAnchor,
            $ArrayAnchor +
            "`r`n" +
            "    InboxModule,"
        )
}

Write-Text `
    -Path $AppModulePath `
    -Content $AppModule

Write-Host "[OK] Inbox API criada." -ForegroundColor Green

# ============================================================
# WORKER CONFIG
# ============================================================

$WhatsAppRuntimeConfig = @'
function parseInteger(
  name: string,
  fallback: number,
  minimum: number,
  maximum: number,
): number {
  const raw =
    process.env[name]?.trim();

  if (!raw) {
    return fallback;
  }

  const value =
    Number(raw);

  if (
    !Number.isInteger(
      value,
    ) ||
    value <
      minimum ||
    value >
      maximum
  ) {
    throw new Error(
      `${name} must be an integer between ${minimum} and ${maximum}.`,
    );
  }

  return value;
}

export type WhatsAppRuntimeConfig =
  Readonly<{
    inboxIntervalMs:
      number;

    inboxLeaseMs:
      number;

    inboxMaxClaimsPerTick:
      number;

    inboxMaxAttempts:
      number;

    inboxRetryBaseMs:
      number;

    outboundIntervalMs:
      number;

    outboundLeaseMs:
      number;

    outboundMaxClaimsPerTick:
      number;

    outboundMaxAttempts:
      number;

    outboundRetryBaseMs:
      number;

    outboundDisabledRetryMs:
      number;
  }>;

export function parseWhatsAppRuntimeConfig():
WhatsAppRuntimeConfig {
  return {
    inboxIntervalMs:
      parseInteger(
        'WHATSAPP_INBOX_INTERVAL_MS',
        1000,
        250,
        60000,
      ),

    inboxLeaseMs:
      parseInteger(
        'WHATSAPP_INBOX_LEASE_MS',
        30000,
        5000,
        300000,
      ),

    inboxMaxClaimsPerTick:
      parseInteger(
        'WHATSAPP_INBOX_MAX_CLAIMS_PER_TICK',
        25,
        1,
        250,
      ),

    inboxMaxAttempts:
      parseInteger(
        'WHATSAPP_INBOX_MAX_ATTEMPTS',
        8,
        1,
        50,
      ),

    inboxRetryBaseMs:
      parseInteger(
        'WHATSAPP_INBOX_RETRY_BASE_MS',
        1000,
        250,
        600000,
      ),

    outboundIntervalMs:
      parseInteger(
        'WHATSAPP_OUTBOUND_INTERVAL_MS',
        1000,
        250,
        60000,
      ),

    outboundLeaseMs:
      parseInteger(
        'WHATSAPP_OUTBOUND_LEASE_MS',
        30000,
        5000,
        300000,
      ),

    outboundMaxClaimsPerTick:
      parseInteger(
        'WHATSAPP_OUTBOUND_MAX_CLAIMS_PER_TICK',
        25,
        1,
        250,
      ),

    outboundMaxAttempts:
      parseInteger(
        'WHATSAPP_OUTBOUND_MAX_ATTEMPTS',
        8,
        1,
        50,
      ),

    outboundRetryBaseMs:
      parseInteger(
        'WHATSAPP_OUTBOUND_RETRY_BASE_MS',
        2000,
        250,
        600000,
      ),

    outboundDisabledRetryMs:
      parseInteger(
        'WHATSAPP_OUTBOUND_DISABLED_RETRY_MS',
        30000,
        1000,
        3600000,
      ),
  };
}
'@

Write-Text `
    -Path ".\apps\worker\src\whatsapp-runtime.config.ts" `
    -Content $WhatsAppRuntimeConfig

# ============================================================
# WORKER INBOX PROCESSOR
# ============================================================

$InboxProcessor = @'
import type {
  CrmDatabaseClient,
  WhatsAppMessageStatus,
  WhatsAppMessageType,
} from '@crm/database';

import {
  parseWhatsAppWebhookEvents,
} from '@crm/meta-cloud-api';

import type {
  WhatsAppInboundWebhookEvent,
  WhatsAppStatusWebhookEvent,
} from '@crm/meta-cloud-api';

import type {
  WhatsAppRuntimeConfig,
} from './whatsapp-runtime.config.js';

type JsonPrimitive =
  string |
  number |
  boolean |
  null;

type JsonValue =
  JsonPrimitive |
  JsonValue[] |
  {
    [key: string]:
      JsonValue;
  };

type JsonObject = {
  [key: string]:
    JsonValue;
};

type ClaimedEnvelope =
  Readonly<{
    id:
      string;

    organizationId:
      string | null;

    whatsAppNumberId:
      string | null;

    metaPhoneNumberId:
      string | null;
  }>;

export type WhatsAppInboxTickSummary =
  Readonly<{
    claimed:
      number;

    processed:
      number;

    failed:
      number;

    messages:
      number;

    statuses:
      number;
  }>;

function normalizeJsonValue(
  value: unknown,
): JsonValue {
  if (
    value === null ||
    typeof value ===
      'string' ||
    typeof value ===
      'boolean'
  ) {
    return value;
  }

  if (
    typeof value ===
      'number'
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
      normalizeJsonValue,
    );
  }

  if (
    typeof value ===
      'object' &&
    value !== null
  ) {
    const result:
      JsonObject =
        {};

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

function parseProviderTimestamp(
  value:
    string | null,
  fallback:
    Date,
): Date {
  if (!value) {
    return fallback;
  }

  const seconds =
    Number(value);

  if (
    !Number.isFinite(
      seconds,
    ) ||
    seconds <=
      0
  ) {
    return fallback;
  }

  const timestamp =
    new Date(
      seconds *
        1000,
    );

  return Number.isNaN(
    timestamp.getTime(),
  )
    ? fallback
    : timestamp;
}

function addHours(
  date:
    Date,
  hours:
    number,
): Date {
  return new Date(
    date.getTime() +
      hours *
        60 *
        60 *
        1000,
  );
}

function addMilliseconds(
  date:
    Date,
  milliseconds:
    number,
): Date {
  return new Date(
    date.getTime() +
      milliseconds,
  );
}

function getErrorMessage(
  error:
    unknown,
): string {
  return (
    error instanceof
      Error
      ? error.message
      : String(
          error,
        )
  ).slice(
    0,
    500,
  );
}

function mapMessageType(
  type:
    string,
): WhatsAppMessageType {
  switch (
    type
  ) {
    case 'text':
      return 'TEXT';

    case 'image':
      return 'IMAGE';

    case 'audio':
      return 'AUDIO';

    case 'video':
      return 'VIDEO';

    case 'document':
      return 'DOCUMENT';

    case 'sticker':
      return 'STICKER';

    case 'location':
      return 'LOCATION';

    case 'contacts':
      return 'CONTACTS';

    case 'interactive':
      return 'INTERACTIVE';

    case 'reaction':
      return 'REACTION';

    default:
      return 'UNKNOWN';
  }
}

function mapStatus(
  status:
    string,
): WhatsAppMessageStatus | null {
  switch (
    status
  ) {
    case 'sent':
      return 'SENT';

    case 'delivered':
      return 'DELIVERED';

    case 'read':
      return 'READ';

    case 'failed':
      return 'FAILED';

    case 'deleted':
      return 'DELETED';

    default:
      return null;
  }
}

export class WhatsAppInboxProcessorService {
  constructor(
    private readonly database:
      CrmDatabaseClient,

    private readonly workerId:
      string,

    private readonly config:
      WhatsAppRuntimeConfig,
  ) {}

  async runTick():
  Promise<
    WhatsAppInboxTickSummary
  > {
    let claimed =
      0;

    let processed =
      0;

    let failed =
      0;

    let messages =
      0;

    let statuses =
      0;

    for (
      let index =
        0;
      index <
      this.config.inboxMaxClaimsPerTick;
      index +=
        1
    ) {
      const envelope =
        await this.claimNextEnvelope();

      if (!envelope) {
        break;
      }

      claimed +=
        1;

      try {
        const result =
          await this.processEnvelope(
            envelope,
          );

        processed +=
          1;

        messages +=
          result.messages;

        statuses +=
          result.statuses;
      }
      catch (
        error
      ) {
        await this.handleEnvelopeFailure(
          envelope,
          error,
        );

        failed +=
          1;
      }
    }

    return {
      claimed,
      processed,
      failed,
      messages,
      statuses,
    };
  }

  private async claimNextEnvelope():
  Promise<
    ClaimedEnvelope | null
  > {
    const rows =
      await this.database.$queryRawUnsafe<
        ClaimedEnvelope[]
      >(
        `
        WITH candidate AS (
          SELECT
            "id"
          FROM
            "meta_webhook_envelopes"
          WHERE
            (
              (
                "status" = 'RECEIVED'
                AND "availableAt" <= NOW()
              )
              OR
              (
                "status" = 'CLAIMED'
                AND "leaseExpiresAt" IS NOT NULL
                AND "leaseExpiresAt" <= NOW()
              )
            )
          ORDER BY
            "availableAt" ASC,
            "receivedAt" ASC,
            "id" ASC
          FOR UPDATE SKIP LOCKED
          LIMIT 1
        )
        UPDATE
          "meta_webhook_envelopes" AS envelope
        SET
          "status" = 'CLAIMED',
          "claimedAt" = NOW(),
          "claimedByWorkerId" = $1,
          "leaseExpiresAt" =
            NOW() + ($2::int * INTERVAL '1 millisecond'),
          "attempts" =
            envelope."attempts" + 1,
          "failureReason" = NULL,
          "updatedAt" = NOW()
        FROM
          candidate
        WHERE
          envelope."id" = candidate."id"
        RETURNING
          envelope."id",
          envelope."organizationId",
          envelope."whatsAppNumberId",
          envelope."metaPhoneNumberId"
        `,
        this.workerId,
        this.config.inboxLeaseMs,
      );

    return rows[0] ??
      null;
  }

  private async processEnvelope(
    claimed:
      ClaimedEnvelope,
  ): Promise<
    Readonly<{
      messages:
        number;

      statuses:
        number;
    }>
  > {
    const envelope =
      await this.database.metaWebhookEnvelope.findFirst({
        where: {
          id:
            claimed.id,

          status:
            'CLAIMED',

          claimedByWorkerId:
            this.workerId,

          leaseExpiresAt: {
            gt:
              new Date(),
          },
        },
      });

    if (!envelope) {
      return {
        messages:
          0,

        statuses:
          0,
      };
    }

    if (
      !envelope.organizationId ||
      !envelope.whatsAppNumberId
    ) {
      throw new Error(
        'Claimed webhook envelope has no tenant/number mapping.',
      );
    }

    const events =
      parseWhatsAppWebhookEvents(
        envelope.payload,
      );

    let messageCount =
      0;

    let statusCount =
      0;

    for (
      const event of events
    ) {
      if (
        envelope.metaPhoneNumberId &&
        event.phoneNumberId &&
        envelope.metaPhoneNumberId !==
          event.phoneNumberId
      ) {
        throw new Error(
          'Webhook event phone number does not match the persisted envelope mapping.',
        );
      }

      if (
        event.kind ===
          'MESSAGE'
      ) {
        const created =
          await this.processInboundMessage(
            envelope.organizationId,
            envelope.whatsAppNumberId,
            envelope.id,
            envelope.receivedAt,
            event,
          );

        if (created) {
          messageCount +=
            1;
        }
      }
      else {
        const created =
          await this.processStatusEvent(
            envelope.organizationId,
            envelope.whatsAppNumberId,
            envelope.id,
            envelope.receivedAt,
            event,
          );

        if (created) {
          statusCount +=
            1;
        }
      }
    }

    await this.database.metaWebhookEnvelope.updateMany({
      where: {
        id:
          envelope.id,

        status:
          'CLAIMED',

        claimedByWorkerId:
          this.workerId,
      },

      data: {
        status:
          'PROCESSED',

        processedAt:
          new Date(),

        claimedAt:
          null,

        claimedByWorkerId:
          null,

        leaseExpiresAt:
          null,

        failureReason:
          null,
      },
    });

    return {
      messages:
        messageCount,

      statuses:
        statusCount,
    };
  }

  private async processInboundMessage(
    organizationId:
      string,
    whatsAppNumberId:
      string,
    sourceEnvelopeId:
      string,
    receivedAt:
      Date,
    event:
      WhatsAppInboundWebhookEvent,
  ): Promise<
    boolean
  > {
    return this.database.$transaction(
      async (
        transaction,
      ) => {
        await transaction.$queryRawUnsafe(
          'WITH lock_guard AS MATERIALIZED (SELECT pg_advisory_xact_lock(hashtextextended($1, 0))) SELECT TRUE AS locked FROM lock_guard',
          `wa-message:${organizationId}:${event.messageId}`,
        );

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

        const providerTimestamp =
          parseProviderTimestamp(
            event.timestamp,
            receivedAt,
          );

        const windowExpiresAt =
          addHours(
            providerTimestamp,
            24,
          );

        let contact =
          await transaction.whatsAppContact.upsert({
            where: {
              organizationId_waId: {
                organizationId,
                waId:
                  event.from,
              },
            },

            create: {
              organizationId,
              waId:
                event.from,

              profileName:
                event.profileName,

              lastInboundAt:
                providerTimestamp,
            },

            update: {
              ...(event.profileName
                ? {
                    profileName:
                      event.profileName,
                  }
                : {}),
            },
          });

        if (
          !contact.lastInboundAt ||
          contact.lastInboundAt <
            providerTimestamp
        ) {
          contact =
            await transaction.whatsAppContact.update({
              where: {
                id:
                  contact.id,
              },

              data: {
                lastInboundAt:
                  providerTimestamp,
              },
            });
        }

        const number =
          await transaction.whatsAppNumber.findFirst({
            where: {
              id:
                whatsAppNumberId,

              organizationId,

              deletedAt:
                null,
            },

            select: {
              id:
                true,

              assignedEmployeeId:
                true,
            },
          });

        if (!number) {
          throw new Error(
            'WhatsApp number disappeared while processing an inbound event.',
          );
        }

        let conversation =
          await transaction.whatsAppConversation.upsert({
            where: {
              organizationId_whatsAppNumberId_contactId: {
                organizationId,
                whatsAppNumberId:
                  number.id,

                contactId:
                  contact.id,
              },
            },

            create: {
              organizationId,

              whatsAppNumberId:
                number.id,

              contactId:
                contact.id,

              assignedEmployeeId:
                number.assignedEmployeeId,

              status:
                'OPEN',

              customerServiceWindowExpiresAt:
                windowExpiresAt,

              lastMessageAt:
                providerTimestamp,

              lastInboundAt:
                providerTimestamp,

              unreadCount:
                0,
            },

            update: {},
          });

        const nextWindowExpiresAt =
          !conversation.customerServiceWindowExpiresAt ||
          conversation.customerServiceWindowExpiresAt <
            windowExpiresAt
            ? windowExpiresAt
            : conversation.customerServiceWindowExpiresAt;

        const nextLastInboundAt =
          !conversation.lastInboundAt ||
          conversation.lastInboundAt <
            providerTimestamp
            ? providerTimestamp
            : conversation.lastInboundAt;

        const nextLastMessageAt =
          !conversation.lastMessageAt ||
          conversation.lastMessageAt <
            providerTimestamp
            ? providerTimestamp
            : conversation.lastMessageAt;

        conversation =
          await transaction.whatsAppConversation.update({
            where: {
              id:
                conversation.id,
            },

            data: {
              status:
                'OPEN',

              customerServiceWindowExpiresAt:
                nextWindowExpiresAt,

              lastInboundAt:
                nextLastInboundAt,

              lastMessageAt:
                nextLastMessageAt,

              unreadCount: {
                increment:
                  1,
              },

              ...(!conversation.assignedEmployeeId &&
              number.assignedEmployeeId
                ? {
                    assignedEmployeeId:
                      number.assignedEmployeeId,
                  }
                : {}),
            },
          });

        await transaction.whatsAppMessage.create({
          data: {
            organizationId,

            conversationId:
              conversation.id,

            whatsAppNumberId:
              number.id,

            contactId:
              contact.id,

            sourceEnvelopeId,

            direction:
              'INBOUND',

            type:
              mapMessageType(
                event.messageType,
              ),

            status:
              'RECEIVED',

            metaMessageId:
              event.messageId,

            replyToMetaMessageId:
              event.replyToMessageId,

            textBody:
              event.textBody,

            content:
              normalizeJsonValue(
                event.payload,
              ),

            providerTimestamp,

            availableAt:
              providerTimestamp,
          },
        });

        return true;
      },
    );
  }

  private async processStatusEvent(
    organizationId:
      string,
    whatsAppNumberId:
      string,
    sourceEnvelopeId:
      string,
    receivedAt:
      Date,
    event:
      WhatsAppStatusWebhookEvent,
  ): Promise<
    boolean
  > {
    const status =
      mapStatus(
        event.status,
      );

    if (!status) {
      return false;
    }

    const providerTimestamp =
      parseProviderTimestamp(
        event.timestamp,
        receivedAt,
      );

    return this.database.$transaction(
      async (
        transaction,
      ) => {
        await transaction.$queryRawUnsafe(
          'WITH lock_guard AS MATERIALIZED (SELECT pg_advisory_xact_lock(hashtextextended($1, 0))) SELECT TRUE AS locked FROM lock_guard',
          `wa-status:${organizationId}:${event.messageId}:${status}:${providerTimestamp.toISOString()}`,
        );

        const existingEvent =
          await transaction.whatsAppMessageStatusEvent.findUnique({
            where: {
              organizationId_metaMessageId_status_providerTimestamp: {
                organizationId,

                metaMessageId:
                  event.messageId,

                status,

                providerTimestamp,
              },
            },

            select: {
              id:
                true,
            },
          });

        if (existingEvent) {
          return false;
        }

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

        const statusEvent =
          await transaction.whatsAppMessageStatusEvent.create({
            data: {
              organizationId,

              whatsAppNumberId,

              sourceEnvelopeId,

              metaMessageId:
                event.messageId,

              status,

              recipientWaId:
                event.recipientId,

              providerTimestamp,

              ...(event.errors.length >
              0
                ? {
                    errors:
                      normalizeJsonValue(
                        event.errors,
                      ),
                  }
                : {}),

              payload:
                normalizeJsonValue(
                  event.payload,
                ),

              appliedAt:
                message
                  ? new Date()
                  : null,
            },
          });

        if (!message) {
          void statusEvent;

          return true;
        }

        if (
          status ===
            'SENT' &&
          (
            message.status ===
              'QUEUED' ||
            message.status ===
              'SENDING' ||
            message.status ===
              'SENT'
          )
        ) {
          await transaction.whatsAppMessage.update({
            where: {
              id:
                message.id,
            },

            data: {
              status:
                'SENT',

              sentAt:
                message.sentAt ??
                providerTimestamp,
            },
          });
        }

        if (
          status ===
            'DELIVERED' &&
          message.status !==
            'READ' &&
          message.status !==
            'DELETED'
        ) {
          await transaction.whatsAppMessage.update({
            where: {
              id:
                message.id,
            },

            data: {
              status:
                'DELIVERED',

              sentAt:
                message.sentAt ??
                providerTimestamp,

              deliveredAt:
                providerTimestamp,
            },
          });
        }

        if (
          status ===
            'READ' &&
          message.status !==
            'DELETED'
        ) {
          await transaction.whatsAppMessage.update({
            where: {
              id:
                message.id,
            },

            data: {
              status:
                'READ',

              sentAt:
                message.sentAt ??
                providerTimestamp,

              deliveredAt:
                message.deliveredAt ??
                providerTimestamp,

              readAt:
                providerTimestamp,
            },
          });
        }

        if (
          status ===
            'FAILED' &&
          message.status !==
            'DELIVERED' &&
          message.status !==
            'READ' &&
          message.status !==
            'DELETED'
        ) {
          await transaction.whatsAppMessage.update({
            where: {
              id:
                message.id,
            },

            data: {
              status:
                'FAILED',

              failedAt:
                providerTimestamp,

              errorCode:
                'META_DELIVERY_FAILED',

              errorMessage:
                'Meta reported message delivery failure.',
            },
          });
        }

        if (
          status ===
            'DELETED'
        ) {
          await transaction.whatsAppMessage.update({
            where: {
              id:
                message.id,
            },

            data: {
              status:
                'DELETED',
            },
          });
        }

        return true;
      },
    );
  }

  private async handleEnvelopeFailure(
    envelope:
      ClaimedEnvelope,
    error:
      unknown,
  ): Promise<
    void
  > {
    const current =
      await this.database.metaWebhookEnvelope.findUnique({
        where: {
          id:
            envelope.id,
        },

        select: {
          attempts:
            true,
        },
      });

    if (!current) {
      return;
    }

    const terminal =
      current.attempts >=
      this.config.inboxMaxAttempts;

    const multiplier =
      Math.max(
        0,
        current.attempts -
          1,
      );

    const retryDelay =
      Math.min(
        this.config.inboxRetryBaseMs *
          2 **
            multiplier,
        15 *
          60 *
          1000,
      );

    await this.database.metaWebhookEnvelope.updateMany({
      where: {
        id:
          envelope.id,

        status:
          'CLAIMED',

        claimedByWorkerId:
          this.workerId,
      },

      data: {
        status:
          terminal
            ? 'FAILED'
            : 'RECEIVED',

        availableAt:
          terminal
            ? new Date()
            : addMilliseconds(
                new Date(),
                retryDelay,
              ),

        claimedAt:
          null,

        claimedByWorkerId:
          null,

        leaseExpiresAt:
          null,

        failureReason:
          getErrorMessage(
            error,
          ),
      },
    });
  }
}
'@

Write-Text `
    -Path ".\apps\worker\src\whatsapp-inbox-processor.service.ts" `
    -Content $InboxProcessor

# ============================================================
# OUTBOUND DISPATCHER
# ============================================================

$OutboundDispatcher = @'
import type {
  CrmDatabaseClient,
} from '@crm/database';

import {
  MetaCloudApiError,
} from '@crm/meta-cloud-api';

import type {
  MetaCloudApiClient,
} from '@crm/meta-cloud-api';

import type {
  WhatsAppRuntimeConfig,
} from './whatsapp-runtime.config.js';

type ClaimedMessage =
  Readonly<{
    id:
      string;
  }>;

type UnknownRecord =
  Record<
    string,
    unknown
  >;

type MetaSendResponse =
  Readonly<{
    messages?:
      readonly Readonly<{
        id?:
          string;
      }>[];
  }>;

export type WhatsAppOutboundTickSummary =
  Readonly<{
    claimed:
      number;

    sent:
      number;

    retried:
      number;

    failed:
      number;

    disabled:
      number;
  }>;

function addMilliseconds(
  date:
    Date,
  milliseconds:
    number,
): Date {
  return new Date(
    date.getTime() +
      milliseconds,
  );
}

function isRecord(
  value:
    unknown,
): value is UnknownRecord {
  return (
    typeof value ===
      'object' &&
    value !==
      null &&
    !Array.isArray(
      value,
    )
  );
}

function readString(
  value:
    unknown,
): string | null {
  return typeof value ===
    'string'
    ? value
    : null;
}

function getErrorMessage(
  error:
    unknown,
): string {
  return (
    error instanceof
      Error
      ? error.message
      : String(
          error,
        )
  ).slice(
    0,
    500,
  );
}

export class WhatsAppOutboundDispatcherService {
  constructor(
    private readonly database:
      CrmDatabaseClient,

    private readonly workerId:
      string,

    private readonly config:
      WhatsAppRuntimeConfig,

    private readonly metaClient:
      MetaCloudApiClient | null,
  ) {}

  async runTick():
  Promise<
    WhatsAppOutboundTickSummary
  > {
    let claimed =
      0;

    let sent =
      0;

    let retried =
      0;

    let failed =
      0;

    let disabled =
      0;

    for (
      let index =
        0;
      index <
      this.config.outboundMaxClaimsPerTick;
      index +=
        1
    ) {
      const message =
        await this.claimNextMessage();

      if (!message) {
        break;
      }

      claimed +=
        1;

      if (!this.metaClient) {
        await this.releaseDisabled(
          message,
        );

        disabled +=
          1;

        continue;
      }

      try {
        await this.sendClaimedMessage(
          message,
        );

        sent +=
          1;
      }
      catch (
        error
      ) {
        const result =
          await this.handleSendFailure(
            message,
            error,
          );

        if (
          result ===
            'RETRY'
        ) {
          retried +=
            1;
        }
        else {
          failed +=
            1;
        }
      }
    }

    return {
      claimed,
      sent,
      retried,
      failed,
      disabled,
    };
  }

  private async claimNextMessage():
  Promise<
    ClaimedMessage | null
  > {
    const rows =
      await this.database.$queryRawUnsafe<
        ClaimedMessage[]
      >(
        `
        WITH candidate AS (
          SELECT
            "id"
          FROM
            "whatsapp_messages"
          WHERE
            "direction" = 'OUTBOUND'
            AND (
              (
                "status" = 'QUEUED'
                AND "availableAt" <= NOW()
              )
              OR
              (
                "status" = 'SENDING'
                AND "leaseExpiresAt" IS NOT NULL
                AND "leaseExpiresAt" <= NOW()
                AND "metaMessageId" IS NULL
              )
            )
          ORDER BY
            "availableAt" ASC,
            "createdAt" ASC,
            "id" ASC
          FOR UPDATE SKIP LOCKED
          LIMIT 1
        )
        UPDATE
          "whatsapp_messages" AS message
        SET
          "status" = 'SENDING',
          "claimedAt" = NOW(),
          "claimedByWorkerId" = $1,
          "leaseExpiresAt" =
            NOW() + ($2::int * INTERVAL '1 millisecond'),
          "lastAttemptAt" = NOW(),
          "attempts" =
            message."attempts" + 1,
          "updatedAt" = NOW()
        FROM
          candidate
        WHERE
          message."id" = candidate."id"
        RETURNING
          message."id"
        `,
        this.workerId,
        this.config.outboundLeaseMs,
      );

    return rows[0] ??
      null;
  }

  private async sendClaimedMessage(
    claimed:
      ClaimedMessage,
  ): Promise<
    void
  > {
    if (!this.metaClient) {
      throw new Error(
        'Meta Cloud API is not configured.',
      );
    }

    const message =
      await this.database.whatsAppMessage.findFirst({
        where: {
          id:
            claimed.id,

          direction:
            'OUTBOUND',

          status:
            'SENDING',

          claimedByWorkerId:
            this.workerId,

          leaseExpiresAt: {
            gt:
              new Date(),
          },
        },

        include: {
          contact: {
            select: {
              waId:
                true,
            },
          },

          whatsAppNumber: {
            select: {
              metaPhoneNumberId:
                true,

              status:
                true,
            },
          },
        },
      });

    if (!message) {
      return;
    }

    if (
      message.whatsAppNumber.status !==
        'ACTIVE' ||
      !message.whatsAppNumber.metaPhoneNumberId
    ) {
      throw new MetaCloudApiError({
        status:
          400,

        message:
          'WhatsApp number is not connected to Meta.',

        code:
          null,

        errorSubcode:
          null,

        metaType:
          'LOCAL_CONFIGURATION',

        fbtraceId:
          null,

        requestId:
          null,
      });
    }

    const body =
      this.buildMetaPayload(
        message.type,
        message.textBody,
        message.replyToMetaMessageId,
        message.content,
        message.contact.waId,
      );

    const response =
      await this.metaClient.post<
        MetaSendResponse
      >(
        `${message.whatsAppNumber.metaPhoneNumberId}/messages`,
        body,
      );

    const metaMessageId =
      response.messages?.[0]?.id?.trim();

    if (!metaMessageId) {
      throw new Error(
        'Meta accepted the request without returning a WhatsApp message id.',
      );
    }

    const sentAt =
      new Date();

    const updated =
      await this.database.whatsAppMessage.updateMany({
        where: {
          id:
            message.id,

          status:
            'SENDING',

          claimedByWorkerId:
            this.workerId,
        },

        data: {
          status:
            'SENT',

          metaMessageId,

          sentAt,

          claimedAt:
            null,

          claimedByWorkerId:
            null,

          leaseExpiresAt:
            null,

          errorCode:
            null,

          errorMessage:
            null,
        },
      });

    if (
      updated.count ===
        0
    ) {
      throw new Error(
        'Outbound send succeeded but the local worker lease was lost before persistence.',
      );
    }

    await this.database.whatsAppConversation.update({
      where: {
        id:
          message.conversationId,
      },

      data: {
        lastOutboundAt:
          sentAt,

        lastMessageAt:
          sentAt,
      },
    });

    await this.database.whatsAppContact.update({
      where: {
        id:
          message.contactId,
      },

      data: {
        lastOutboundAt:
          sentAt,
      },
    });

    await this.reconcilePendingStatuses(
      message.organizationId,
      message.id,
      metaMessageId,
    );
  }

  private buildMetaPayload(
    type:
      string,
    textBody:
      string | null,
    replyToMetaMessageId:
      string | null,
    content:
      unknown,
    recipientWaId:
      string,
  ): Readonly<
    Record<
      string,
      unknown
    >
  > {
    if (
      type ===
        'TEXT'
    ) {
      if (!textBody) {
        throw new Error(
          'TEXT outbound message has no text body.',
        );
      }

      return {
        messaging_product:
          'whatsapp',

        recipient_type:
          'individual',

        to:
          recipientWaId,

        type:
          'text',

        text: {
          body:
            textBody,
        },

        ...(replyToMetaMessageId
          ? {
              context: {
                message_id:
                  replyToMetaMessageId,
              },
            }
          : {}),
      };
    }

    if (
      type ===
        'TEMPLATE'
    ) {
      const root =
        isRecord(
          content,
        )
          ? content
          : null;

      const template =
        root &&
        isRecord(
          root.template,
        )
          ? root.template
          : null;

      const name =
        readString(
          template?.name,
        );

      const languageCode =
        readString(
          template?.languageCode,
        );

      if (
        !name ||
        !languageCode
      ) {
        throw new Error(
          'TEMPLATE outbound message is missing template metadata.',
        );
      }

      return {
        messaging_product:
          'whatsapp',

        recipient_type:
          'individual',

        to:
          recipientWaId,

        type:
          'template',

        template: {
          name,

          language: {
            code:
              languageCode,
          },

          ...(Array.isArray(
            template?.components,
          )
            ? {
                components:
                  template.components,
              }
            : {}),
        },
      };
    }

    throw new Error(
      `Outbound message type ${type} is not supported in Stage 9.`,
    );
  }

  private async reconcilePendingStatuses(
    organizationId:
      string,
    messageId:
      string,
    metaMessageId:
      string,
  ): Promise<
    void
  > {
    const events =
      await this.database.whatsAppMessageStatusEvent.findMany({
        where: {
          organizationId,

          metaMessageId,
        },

        orderBy: [
          {
            providerTimestamp:
              'asc',
          },

          {
            createdAt:
              'asc',
          },
        ],
      });

    if (
      events.length ===
        0
    ) {
      return;
    }

    let status:
      'SENT' |
      'DELIVERED' |
      'READ' |
      'FAILED' |
      'DELETED' =
        'SENT';

    let sentAt:
      Date | null =
        null;

    let deliveredAt:
      Date | null =
        null;

    let readAt:
      Date | null =
        null;

    let failedAt:
      Date | null =
        null;

    for (
      const event of events
    ) {
      if (
        event.status ===
          'SENT'
      ) {
        sentAt =
          sentAt ??
          event.providerTimestamp;
      }

      if (
        event.status ===
          'DELIVERED'
      ) {
        status =
          'DELIVERED';

        sentAt =
          sentAt ??
          event.providerTimestamp;

        deliveredAt =
          event.providerTimestamp;
      }

      if (
        event.status ===
          'READ'
      ) {
        status =
          'READ';

        sentAt =
          sentAt ??
          event.providerTimestamp;

        deliveredAt =
          deliveredAt ??
          event.providerTimestamp;

        readAt =
          event.providerTimestamp;
      }

      if (
        event.status ===
          'FAILED' &&
        status !==
          'DELIVERED' &&
        status !==
          'READ'
      ) {
        status =
          'FAILED';

        failedAt =
          event.providerTimestamp;
      }

      if (
        event.status ===
          'DELETED'
      ) {
        status =
          'DELETED';
      }
    }

    await this.database.whatsAppMessage.update({
      where: {
        id:
          messageId,
      },

      data: {
        status,

        ...(sentAt
          ? {
              sentAt,
            }
          : {}),

        ...(deliveredAt
          ? {
              deliveredAt,
            }
          : {}),

        ...(readAt
          ? {
              readAt,
            }
          : {}),

        ...(failedAt
          ? {
              failedAt,
            }
          : {}),
      },
    });

    await this.database.whatsAppMessageStatusEvent.updateMany({
      where: {
        organizationId,

        metaMessageId,

        appliedAt:
          null,
      },

      data: {
        appliedAt:
          new Date(),
      },
    });
  }

  private async releaseDisabled(
    claimed:
      ClaimedMessage,
  ): Promise<
    void
  > {
    await this.database.whatsAppMessage.updateMany({
      where: {
        id:
          claimed.id,

        status:
          'SENDING',

        claimedByWorkerId:
          this.workerId,
      },

      data: {
        status:
          'QUEUED',

        availableAt:
          addMilliseconds(
            new Date(),
            this.config.outboundDisabledRetryMs,
          ),

        claimedAt:
          null,

        claimedByWorkerId:
          null,

        leaseExpiresAt:
          null,
      },
    });
  }

  private async handleSendFailure(
    claimed:
      ClaimedMessage,
    error:
      unknown,
  ): Promise<
    'RETRY' |
    'FAILED'
  > {
    const message =
      await this.database.whatsAppMessage.findUnique({
        where: {
          id:
            claimed.id,
        },

        select: {
          attempts:
            true,

          status:
            true,

          claimedByWorkerId:
            true,
        },
      });

    if (
      !message ||
      message.status !==
        'SENDING' ||
      message.claimedByWorkerId !==
        this.workerId
    ) {
      return 'FAILED';
    }

    /*
     * A generic network/timeout error has uncertain provider outcome.
     * We do NOT blindly resend it because that could duplicate a
     * customer-facing WhatsApp message.
     */
    const uncertainOutcome =
      !(error instanceof
        MetaCloudApiError);

    const metaError =
      error instanceof
        MetaCloudApiError
        ? error
        : null;

    const retryableMetaError =
      Boolean(
        metaError &&
        (
          metaError.status ===
            429 ||
          metaError.status >=
            500
        ),
      );

    const terminal =
      uncertainOutcome ||
      !retryableMetaError ||
      message.attempts >=
        this.config.outboundMaxAttempts;

    if (
      terminal
    ) {
      await this.database.whatsAppMessage.update({
        where: {
          id:
            claimed.id,
        },

        data: {
          status:
            'FAILED',

          failedAt:
            new Date(),

          errorCode:
            uncertainOutcome
              ? 'OUTBOUND_DELIVERY_UNKNOWN'
              : metaError?.code !==
                    null &&
                  metaError?.code !==
                    undefined
                ? `META_${metaError.code}`
                : 'META_SEND_FAILED',

          errorMessage:
            getErrorMessage(
              error,
            ),

          claimedAt:
            null,

          claimedByWorkerId:
            null,

          leaseExpiresAt:
            null,
        },
      });

      return 'FAILED';
    }

    const retryDelay =
      Math.min(
        this.config.outboundRetryBaseMs *
          2 **
            Math.max(
              0,
              message.attempts -
                1,
            ),
        15 *
          60 *
          1000,
      );

    await this.database.whatsAppMessage.update({
      where: {
        id:
          claimed.id,
      },

      data: {
        status:
          'QUEUED',

        availableAt:
          addMilliseconds(
            new Date(),
            retryDelay,
          ),

        errorCode:
          metaError?.code !==
              null &&
            metaError?.code !==
              undefined
            ? `META_${metaError.code}`
            : 'META_RETRYABLE_ERROR',

        errorMessage:
          getErrorMessage(
            error,
          ),

        claimedAt:
          null,

        claimedByWorkerId:
          null,

        leaseExpiresAt:
          null,
      },
    });

    return 'RETRY';
  }
}
'@

Write-Text `
    -Path ".\apps\worker\src\whatsapp-outbound-dispatcher.service.ts" `
    -Content $OutboundDispatcher

Write-Host "[OK] WhatsApp inbox/outbound workers criados." -ForegroundColor Green

# ============================================================
# WORKER PACKAGE
# ============================================================

$WorkerPackagePath =
    ".\apps\worker\package.json"

$WorkerPackage =
    Read-Text -Path $WorkerPackagePath

if (-not $WorkerPackage.Contains('"@crm/meta-cloud-api": "workspace:*"')) {
    $DatabaseDependency =
        '"@crm/database": "workspace:*",'

    if (-not $WorkerPackage.Contains($DatabaseDependency)) {
        throw "Worker @crm/database dependency anchor nao encontrado."
    }

    $WorkerPackage =
        $WorkerPackage.Replace(
            $DatabaseDependency,
            $DatabaseDependency +
            "`r`n    " +
            '"@crm/meta-cloud-api": "workspace:*",'
        )
}

Write-Text `
    -Path $WorkerPackagePath `
    -Content $WorkerPackage

# ============================================================
# WORKER MAIN
# ============================================================

$WorkerMain = @'
import './load-environment.js';

import {
  randomUUID,
} from 'node:crypto';

import {
  hostname,
} from 'node:os';

import {
  createDatabaseClient,
} from '@crm/database';

import {
  MetaCloudApiClient,
  parseMetaCloudApiConfig,
} from '@crm/meta-cloud-api';

import {
  AdsSchedulerService,
} from './ads-scheduler.service.js';

import {
  NotificationDispatcherService,
} from './notification-dispatcher.service.js';

import {
  isNotificationDispatcherEnabled,
  parseNotificationDispatcherConfig,
} from './notification-dispatcher.config.js';

import {
  parseAdsSchedulerConfig,
} from './scheduler.config.js';

import {
  WhatsAppInboxProcessorService,
} from './whatsapp-inbox-processor.service.js';

import {
  WhatsAppOutboundDispatcherService,
} from './whatsapp-outbound-dispatcher.service.js';

import {
  parseWhatsAppRuntimeConfig,
} from './whatsapp-runtime.config.js';

const service =
  'worker' as const;

const heartbeatIntervalMs =
  30_000;

const schedulerConfig =
  parseAdsSchedulerConfig();

const notificationConfig =
  parseNotificationDispatcherConfig();

const whatsAppConfig =
  parseWhatsAppRuntimeConfig();

const workerId =
  process.env.ADS_WORKER_ID?.trim() ||
  `${hostname()}-${process.pid}-${randomUUID()}`;

const database =
  createDatabaseClient();

const scheduler =
  new AdsSchedulerService(
    database,
    workerId,
    schedulerConfig,
  );

const notificationDispatcher =
  new NotificationDispatcherService(
    database,
    workerId,
    notificationConfig,
  );

const metaConfigured =
  Boolean(
    process.env.META_GRAPH_API_VERSION?.trim() &&
    process.env.META_ACCESS_TOKEN?.trim(),
  );

const metaClient =
  metaConfigured
    ? new MetaCloudApiClient(
        parseMetaCloudApiConfig(
          process.env,
        ),
      )
    : null;

const inboxProcessor =
  new WhatsAppInboxProcessorService(
    database,
    workerId,
    whatsAppConfig,
  );

const outboundDispatcher =
  new WhatsAppOutboundDispatcherService(
    database,
    workerId,
    whatsAppConfig,
    metaClient,
  );

let schedulerRunning =
  false;

let notificationRunning =
  false;

let inboxRunning =
  false;

let outboundRunning =
  false;

let shuttingDown =
  false;

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
      service,
      workerId,
      timestamp:
        new Date().toISOString(),
      ...extra,
    }),
  );
}

async function runSchedulerTick():
Promise<void> {
  if (
    schedulerRunning ||
    shuttingDown
  ) {
    return;
  }

  schedulerRunning =
    true;

  try {
    const summary =
      await scheduler.runTick();

    if (
      summary.claimed >
        0 ||
      summary.failed >
        0 ||
      summary.lostLease >
        0
    ) {
      log(
        'ads.scheduler.tick',
        summary,
      );
    }
  }
  catch (
    error
  ) {
    log(
      'ads.scheduler.error',
      {
        message:
          error instanceof
            Error
            ? error.message
            : String(
                error,
              ),
      },
    );
  }
  finally {
    schedulerRunning =
      false;
  }
}

async function runNotificationTick():
Promise<void> {
  if (
    notificationRunning ||
    shuttingDown
  ) {
    return;
  }

  notificationRunning =
    true;

  try {
    const summary =
      await notificationDispatcher.runTick();

    if (
      summary.claimed >
        0 ||
      summary.failed >
        0
    ) {
      log(
        'notification.dispatch.tick',
        summary,
      );
    }
  }
  catch (
    error
  ) {
    log(
      'notification.dispatch.error',
      {
        message:
          error instanceof
            Error
            ? error.message
            : String(
                error,
              ),
      },
    );
  }
  finally {
    notificationRunning =
      false;
  }
}

async function runInboxTick():
Promise<void> {
  if (
    inboxRunning ||
    shuttingDown
  ) {
    return;
  }

  inboxRunning =
    true;

  try {
    const summary =
      await inboxProcessor.runTick();

    if (
      summary.claimed >
        0 ||
      summary.failed >
        0
    ) {
      log(
        'whatsapp.inbox.tick',
        summary,
      );
    }
  }
  catch (
    error
  ) {
    log(
      'whatsapp.inbox.error',
      {
        message:
          error instanceof
            Error
            ? error.message
            : String(
                error,
              ),
      },
    );
  }
  finally {
    inboxRunning =
      false;
  }
}

async function runOutboundTick():
Promise<void> {
  if (
    outboundRunning ||
    shuttingDown
  ) {
    return;
  }

  outboundRunning =
    true;

  try {
    const summary =
      await outboundDispatcher.runTick();

    if (
      summary.claimed >
        0 ||
      summary.failed >
        0 ||
      summary.retried >
        0
    ) {
      log(
        'whatsapp.outbound.tick',
        summary,
      );
    }
  }
  catch (
    error
  ) {
    log(
      'whatsapp.outbound.error',
      {
        message:
          error instanceof
            Error
            ? error.message
            : String(
                error,
              ),
      },
    );
  }
  finally {
    outboundRunning =
      false;
  }
}

log(
  'service.started',
  {
    heartbeatIntervalMs,

    schedulerIntervalMs:
      schedulerConfig.intervalMs,

    microbatchSize:
      schedulerConfig.microbatchSize,

    notificationDispatcherEnabled:
      isNotificationDispatcherEnabled(
        notificationConfig,
      ),

    notificationIntervalMs:
      notificationConfig.intervalMs,

    whatsAppInboxIntervalMs:
      whatsAppConfig.inboxIntervalMs,

    whatsAppOutboundIntervalMs:
      whatsAppConfig.outboundIntervalMs,

    metaOutboundConfigured:
      metaConfigured,
  },
);

await Promise.all([
  runSchedulerTick(),
  runNotificationTick(),
  runInboxTick(),
  runOutboundTick(),
]);

const schedulerTimer =
  setInterval(
    () => {
      void runSchedulerTick();
    },
    schedulerConfig.intervalMs,
  );

const notificationTimer =
  setInterval(
    () => {
      void runNotificationTick();
    },
    notificationConfig.intervalMs,
  );

const inboxTimer =
  setInterval(
    () => {
      void runInboxTick();
    },
    whatsAppConfig.inboxIntervalMs,
  );

const outboundTimer =
  setInterval(
    () => {
      void runOutboundTick();
    },
    whatsAppConfig.outboundIntervalMs,
  );

const heartbeatTimer =
  setInterval(
    () => {
      log(
        'service.heartbeat',
        {
          schedulerRunning,
          notificationRunning,
          inboxRunning,
          outboundRunning,
        },
      );
    },
    heartbeatIntervalMs,
  );

async function shutdown(
  signal:
    NodeJS.Signals,
): Promise<void> {
  if (
    shuttingDown
  ) {
    return;
  }

  shuttingDown =
    true;

  clearInterval(
    schedulerTimer,
  );

  clearInterval(
    notificationTimer,
  );

  clearInterval(
    inboxTimer,
  );

  clearInterval(
    outboundTimer,
  );

  clearInterval(
    heartbeatTimer,
  );

  log(
    'service.stopping',
    {
      signal,
    },
  );

  while (
    schedulerRunning ||
    notificationRunning ||
    inboxRunning ||
    outboundRunning
  ) {
    await new Promise<void>(
      (
        resolve,
      ) => {
        setTimeout(
          resolve,
          50,
        );
      },
    );
  }

  await database.$disconnect();

  log(
    'service.stopped',
    {
      signal,
    },
  );

  process.exit(
    0,
  );
}

process.once(
  'SIGINT',
  () => {
    void shutdown(
      'SIGINT',
    );
  },
);

process.once(
  'SIGTERM',
  () => {
    void shutdown(
      'SIGTERM',
    );
  },
);
'@

Write-Text `
    -Path ".\apps\worker\src\main.ts" `
    -Content $WorkerMain

Write-Host "[OK] Worker principal integrado com Inbox." -ForegroundColor Green

# ============================================================
# ENV EXAMPLE
# ============================================================

$EnvPath =
    ".\.env.example"

$Env =
    Read-Text -Path $EnvPath

if (-not $Env.Contains("WHATSAPP_INBOX_INTERVAL_MS=")) {
    $EnvAppend = @'

# WhatsApp Inbox - Etapa 9
WHATSAPP_INBOX_INTERVAL_MS=1000
WHATSAPP_INBOX_LEASE_MS=30000
WHATSAPP_INBOX_MAX_CLAIMS_PER_TICK=25
WHATSAPP_INBOX_MAX_ATTEMPTS=8
WHATSAPP_INBOX_RETRY_BASE_MS=1000

WHATSAPP_OUTBOUND_INTERVAL_MS=1000
WHATSAPP_OUTBOUND_LEASE_MS=30000
WHATSAPP_OUTBOUND_MAX_CLAIMS_PER_TICK=25
WHATSAPP_OUTBOUND_MAX_ATTEMPTS=8
WHATSAPP_OUTBOUND_RETRY_BASE_MS=2000
WHATSAPP_OUTBOUND_DISABLED_RETRY_MS=30000
'@

    $Env =
        $Env.TrimEnd() +
        "`r`n" +
        $EnvAppend.TrimStart() +
        "`r`n"
}

Write-Text `
    -Path $EnvPath `
    -Content $Env

# ============================================================
# ETAPAS DOC - FIX CURRENT STATUS
# ============================================================

$EtapasPath =
    ".\docs\ETAPAS.md"

if (Test-Path $EtapasPath) {
    $Etapas =
        Read-Text -Path $EtapasPath

    for (
        $Stage =
            1;
        $Stage -le
            8;
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

    $Etapas =
        [regex]::Replace(
            $Etapas,
            "(?m)^\|\s*9\s*\|([^|]+)\|([^|]+)\|$",
            {
                param($Match)

                return (
                    "|     9 |" +
                    $Match.Groups[1].Value +
                    "| EM ANDAMENTO                 |"
                )
            },
            1
        )

    if (-not $Etapas.Contains("## Etapa 9 - Inbox")) {
        $Etapas =
            $Etapas.TrimEnd() +
            "`r`n`r`n" +
            "## Etapa 9 - Inbox`r`n`r`n" +
            "Status: EM ANDAMENTO - Macrobloco 9.1 em construcao.`r`n"
    }

    Write-Text `
        -Path $EtapasPath `
        -Content $Etapas
}

# ============================================================
# STRUCTURAL VALIDATION
# ============================================================

$SchemaCheck =
    Read-Text -Path $SchemaPath

$RequiredSchemaMarkers = @(
    "enum WhatsAppConversationStatus",
    "enum WhatsAppMessageDirection",
    "enum WhatsAppMessageType",
    "enum WhatsAppMessageStatus",
    "model WhatsAppContact",
    "model WhatsAppConversation",
    "model WhatsAppMessage",
    "model WhatsAppMessageStatusEvent",
    "model WhatsAppQuickReply",
    "customerServiceWindowExpiresAt",
    "clientMessageId",
    "sourceEnvelopeId"
)

foreach ($Marker in $RequiredSchemaMarkers) {
    if (-not $SchemaCheck.Contains($Marker)) {
        throw "Schema Stage 9 marker ausente: $Marker"
    }
}

$RequiredFiles = @(
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
        throw "Stage 9 arquivo ausente: $File"
    }
}

$GuardCheck =
    Read-Text -Path $AccessGuardPath

foreach ($Permission in @(
    "inbox.read",
    "inbox.manage",
    "quick_reply.read",
    "quick_reply.manage"
)) {
    if (-not $GuardCheck.Contains($Permission)) {
        throw "AccessTokenGuard permission ausente: $Permission"
    }
}

$WorkerMainCheck =
    Read-Text -Path ".\apps\worker\src\main.ts"

foreach ($Marker in @(
    "WhatsAppInboxProcessorService",
    "WhatsAppOutboundDispatcherService",
    "whatsapp.inbox.tick",
    "whatsapp.outbound.tick"
)) {
    if (-not $WorkerMainCheck.Contains($Marker)) {
        throw "Worker Stage 9 marker ausente: $Marker"
    }
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host "[OK] MACROBLOCO 9.1 CRIADO." -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Construido:" -ForegroundColor Cyan
Write-Host "- WhatsAppContact"
Write-Host "- WhatsAppConversation"
Write-Host "- WhatsAppMessage"
Write-Host "- WhatsAppMessageStatusEvent"
Write-Host "- WhatsAppQuickReply"
Write-Host "- customer service window 24h"
Write-Host "- inbound message parser"
Write-Host "- wamid business idempotency"
Write-Host "- persistent webhook processor"
Write-Host "- claim + lease + retry"
Write-Host "- contact/conversation creation"
Write-Host "- employee assignment"
Write-Host "- unread counter"
Write-Host "- conversation reopen on inbound"
Write-Host "- status sent/delivered/read/failed/deleted"
Write-Host "- status reconciliation foundation"
Write-Host "- persistent outbound queue"
Write-Host "- local clientMessageId idempotency"
Write-Host "- TEXT outbound"
Write-Host "- TEMPLATE outbound"
Write-Host "- 24h TEXT enforcement"
Write-Host "- Meta Graph outbound dispatcher"
Write-Host "- uncertain network outcome duplicate protection"
Write-Host "- quick replies"
Write-Host "- Inbox API"
Write-Host "- cursor pagination"
Write-Host "- tenant + employee isolation"
Write-Host "- Stage 9 permissions"
Write-Host ""
Write-Host "Migration ainda NAO executada." -ForegroundColor Yellow
Write-Host "Prisma generate ainda NAO executado." -ForegroundColor Yellow
Write-Host "Nao rode CI ainda." -ForegroundColor Yellow
Write-Host ""
Write-Host "Proximo: Macrobloco 9.2 - migration, auditoria, runtime e fechamento." -ForegroundColor Yellow