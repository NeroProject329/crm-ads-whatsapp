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
Write-Host " ETAPA 7 - MACROBLOCO 7.1" -ForegroundColor Cyan
Write-Host " PWA + ONESIGNAL" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

$SchemaPath = ".\packages\database\prisma\schema.prisma"
$ContractsIndexPath = ".\packages\contracts\src\index.ts"
$ValidationIndexPath = ".\packages\validation\src\index.ts"
$AppModulePath = ".\apps\api\src\app.module.ts"
$WorkerMainPath = ".\apps\worker\src\main.ts"
$WebLayoutPath = ".\apps\web\src\app\layout.tsx"
$NextConfigPath = ".\apps\web\next.config.ts"
$EnvExamplePath = ".\.env.example"

$BackupDirectory = ".\tmp\stage7-macroblock1-backup"

if (-not (Test-Path $BackupDirectory)) {
    New-Item `
        -ItemType Directory `
        -Path $BackupDirectory `
        -Force |
        Out-Null

    $BackupFiles = @(
        $SchemaPath,
        $ContractsIndexPath,
        $ValidationIndexPath,
        $AppModulePath,
        $WorkerMainPath,
        $WebLayoutPath,
        $NextConfigPath,
        $EnvExamplePath
    )

    foreach ($File in $BackupFiles) {
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

Write-Host "[OK] Backup Stage 7 preparado." -ForegroundColor Green

# ============================================================
# PRISMA ENUMS
# ============================================================

$NotificationEnums = @'
enum PushProvider {
  ONESIGNAL
}

enum PushDeviceStatus {
  ACTIVE
  INACTIVE
  REVOKED
}

enum NotificationChannel {
  PUSH
}

enum NotificationStatus {
  QUEUED
  PROCESSING
  SENT
  FAILED
  SKIPPED
  CANCELLED
}

enum NotificationDeliveryStatus {
  WAITING
  CLAIMED
  SENT
  FAILED
  SKIPPED
  CANCELLED
}
'@

Insert-AfterPrismaBlock `
    -Path $SchemaPath `
    -Kind "enum" `
    -Name "AdsMicrobatchStatus" `
    -Marker "enum PushProvider" `
    -Insertion $NotificationEnums

Write-Host "[OK] Enums Stage 7 criados." -ForegroundColor Green

# ============================================================
# PRISMA RELATIONS
# ============================================================

Add-ToPrismaModel `
    -Path $SchemaPath `
    -ModelName "Organization" `
    -Marker "pushDevices" `
    -Insertion @'
  pushDevices             PushDevice[]
  notificationPreferences NotificationPreference[]
  notifications           Notification[]
  notificationDeliveries  NotificationDelivery[]
'@

Add-ToPrismaModel `
    -Path $SchemaPath `
    -ModelName "User" `
    -Marker "pushDevices" `
    -Insertion @'
  pushDevices             PushDevice[]
  notificationPreference  NotificationPreference?
  notifications           Notification[]
  notificationDeliveries  NotificationDelivery[]
'@

Write-Host "[OK] Relacoes Stage 7 adicionadas." -ForegroundColor Green

# ============================================================
# PRISMA MODELS
# ============================================================

$NotificationModels = @'
model PushDevice {
  id             String           @id @default(uuid()) @db.Uuid
  organizationId String           @db.Uuid
  userId         String           @db.Uuid
  provider       PushProvider     @default(ONESIGNAL)
  subscriptionId String           @unique @db.VarChar(160)
  oneSignalId    String?          @db.VarChar(160)
  status         PushDeviceStatus @default(ACTIVE)
  optedIn        Boolean          @default(true)
  platform       String?          @db.VarChar(80)
  browser        String?          @db.VarChar(80)
  deviceLabel    String?          @db.VarChar(120)
  userAgent      String?          @db.VarChar(500)
  subscribedAt   DateTime         @default(now()) @db.Timestamptz(3)
  unsubscribedAt DateTime?        @db.Timestamptz(3)
  revokedAt      DateTime?        @db.Timestamptz(3)
  lastSeenAt     DateTime         @default(now()) @db.Timestamptz(3)
  createdAt      DateTime         @default(now()) @db.Timestamptz(3)
  updatedAt      DateTime         @updatedAt @db.Timestamptz(3)

  organization Organization @relation(fields: [organizationId], references: [id], onDelete: Cascade)
  user         User         @relation(fields: [organizationId, userId], references: [organizationId, id], onDelete: Cascade)

  @@unique([organizationId, id])
  @@index([organizationId, userId, status])
  @@index([organizationId, userId, optedIn])
  @@map("push_devices")
}

model NotificationPreference {
  organizationId String   @db.Uuid
  userId         String   @db.Uuid
  pushEnabled    Boolean  @default(true)
  siteMonitoring Boolean  @default(true)
  adsUpdates     Boolean  @default(true)
  whatsappInbox  Boolean  @default(true)
  createdAt      DateTime @default(now()) @db.Timestamptz(3)
  updatedAt      DateTime @updatedAt @db.Timestamptz(3)

  organization Organization @relation(fields: [organizationId], references: [id], onDelete: Cascade)
  user         User         @relation(fields: [organizationId, userId], references: [organizationId, id], onDelete: Cascade)

  @@id([organizationId, userId])
  @@map("notification_preferences")
}

model Notification {
  id             String              @id @default(uuid()) @db.Uuid
  organizationId String              @db.Uuid
  userId         String              @db.Uuid
  channel        NotificationChannel @default(PUSH)
  type           String              @db.VarChar(120)
  title          String              @db.VarChar(160)
  body           String              @db.VarChar(500)
  url            String?             @db.VarChar(500)
  data           Json?
  idempotencyKey String?             @db.VarChar(160)
  status         NotificationStatus  @default(QUEUED)
  processedAt    DateTime?           @db.Timestamptz(3)
  failureReason  String?             @db.VarChar(500)
  createdAt      DateTime            @default(now()) @db.Timestamptz(3)
  updatedAt      DateTime            @updatedAt @db.Timestamptz(3)

  organization Organization           @relation(fields: [organizationId], references: [id], onDelete: Cascade)
  user         User                   @relation(fields: [organizationId, userId], references: [organizationId, id], onDelete: Cascade)
  deliveries   NotificationDelivery[]

  @@unique([organizationId, id])
  @@unique([organizationId, idempotencyKey])
  @@index([organizationId, userId, createdAt])
  @@index([organizationId, status, createdAt])
  @@map("notifications")
}

model NotificationDelivery {
  id                String                     @id @default(uuid()) @db.Uuid
  organizationId    String                     @db.Uuid
  notificationId    String                     @db.Uuid
  userId            String                     @db.Uuid
  provider          PushProvider               @default(ONESIGNAL)
  status            NotificationDeliveryStatus @default(WAITING)
  attempts          Int                        @default(0)
  nextAttemptAt     DateTime                   @default(now()) @db.Timestamptz(3)
  claimedAt         DateTime?                  @db.Timestamptz(3)
  claimedByWorkerId String?                    @db.VarChar(120)
  leaseExpiresAt    DateTime?                  @db.Timestamptz(3)
  providerMessageId String?                    @db.VarChar(160)
  sentAt            DateTime?                  @db.Timestamptz(3)
  failedAt          DateTime?                  @db.Timestamptz(3)
  lastError         String?                    @db.VarChar(500)
  createdAt         DateTime                   @default(now()) @db.Timestamptz(3)
  updatedAt         DateTime                   @updatedAt @db.Timestamptz(3)

  organization Organization @relation(fields: [organizationId], references: [id], onDelete: Cascade)
  notification Notification @relation(fields: [organizationId, notificationId], references: [organizationId, id], onDelete: Cascade)
  user         User         @relation(fields: [organizationId, userId], references: [organizationId, id], onDelete: Cascade)

  @@unique([organizationId, id])
  @@unique([notificationId, provider])
  @@index([organizationId, status, nextAttemptAt])
  @@index([organizationId, userId, status])
  @@index([leaseExpiresAt])
  @@map("notification_deliveries")
}
'@

Insert-AfterPrismaBlock `
    -Path $SchemaPath `
    -Kind "model" `
    -Name "AdsMicrobatch" `
    -Marker "model PushDevice {" `
    -Insertion $NotificationModels

$Schema = Read-Text -Path $SchemaPath
$Schema = $Schema.TrimStart([char]0xFEFF)

Write-Text `
    -Path $SchemaPath `
    -Content $Schema

Write-Host "[OK] Models Stage 7 criados." -ForegroundColor Green

# ============================================================
# CONTRACTS
# ============================================================

$NotificationContracts = @'
export type PushProvider = 'ONESIGNAL';

export type PushDeviceStatus =
  | 'ACTIVE'
  | 'INACTIVE'
  | 'REVOKED';

export type PushDeviceResponse = Readonly<{
  id: string;
  subscriptionId: string;
  oneSignalId: string | null;
  provider: PushProvider;
  status: PushDeviceStatus;
  optedIn: boolean;
  platform: string | null;
  browser: string | null;
  deviceLabel: string | null;
  subscribedAt: string;
  unsubscribedAt: string | null;
  lastSeenAt: string;
  createdAt: string;
  updatedAt: string;
}>;

export type PushDeviceListResponse =
  readonly PushDeviceResponse[];

export type RegisterPushDeviceRequest = Readonly<{
  subscriptionId: string;
  oneSignalId?: string | null;
  optedIn: boolean;
  platform?: string | null;
  browser?: string | null;
  deviceLabel?: string | null;
}>;

export type NotificationPreferenceResponse = Readonly<{
  pushEnabled: boolean;
  siteMonitoring: boolean;
  adsUpdates: boolean;
  whatsappInbox: boolean;
  createdAt: string;
  updatedAt: string;
}>;

export type UpdateNotificationPreferenceRequest = Readonly<{
  pushEnabled?: boolean;
  siteMonitoring?: boolean;
  adsUpdates?: boolean;
  whatsappInbox?: boolean;
}>;

export type NotificationStatus =
  | 'QUEUED'
  | 'PROCESSING'
  | 'SENT'
  | 'FAILED'
  | 'SKIPPED'
  | 'CANCELLED';

export type NotificationResponse = Readonly<{
  id: string;
  type: string;
  title: string;
  body: string;
  url: string | null;
  data: unknown;
  status: NotificationStatus;
  createdAt: string;
  processedAt: string | null;
}>;

export type NotificationListResponse =
  readonly NotificationResponse[];
'@

Write-Text `
    -Path ".\packages\contracts\src\notifications.ts" `
    -Content $NotificationContracts

$ContractsIndex = Read-Text -Path $ContractsIndexPath

if (-not $ContractsIndex.Contains("export * from './notifications.js';")) {
    $ContractsIndex = (
        $ContractsIndex.TrimEnd() +
        "`r`nexport * from './notifications.js';`r`n"
    )

    Write-Text `
        -Path $ContractsIndexPath `
        -Content $ContractsIndex
}

Write-Host "[OK] Contracts Stage 7 criados." -ForegroundColor Green

# ============================================================
# VALIDATION
# ============================================================

$NotificationValidation = @'
import { z } from 'zod';

const optionalLabelSchema =
  z.string().trim().min(1).max(120).nullable();

const optionalClientSchema =
  z.string().trim().min(1).max(80).nullable();

export const registerPushDeviceSchema =
  z
    .object({
      subscriptionId:
        z.string().uuid(),

      oneSignalId:
        z.string().uuid().nullable().optional(),

      optedIn:
        z.boolean(),

      platform:
        optionalClientSchema.optional(),

      browser:
        optionalClientSchema.optional(),

      deviceLabel:
        optionalLabelSchema.optional(),
    })
    .strict();

export const updateNotificationPreferenceSchema =
  z
    .object({
      pushEnabled:
        z.boolean().optional(),

      siteMonitoring:
        z.boolean().optional(),

      adsUpdates:
        z.boolean().optional(),

      whatsappInbox:
        z.boolean().optional(),
    })
    .strict()
    .refine(
      (value) =>
        Object.keys(value).length > 0,
      {
        message:
          'At least one notification preference must be provided.',
      },
    );

export type RegisterPushDeviceInput =
  z.infer<
    typeof registerPushDeviceSchema
  >;

export type UpdateNotificationPreferenceInput =
  z.infer<
    typeof updateNotificationPreferenceSchema
  >;
'@

Write-Text `
    -Path ".\packages\validation\src\notifications.ts" `
    -Content $NotificationValidation

$ValidationIndex = Read-Text -Path $ValidationIndexPath

if (-not $ValidationIndex.Contains("export * from './notifications.js';")) {
    $ValidationIndex = (
        $ValidationIndex.TrimEnd() +
        "`r`nexport * from './notifications.js';`r`n"
    )

    Write-Text `
        -Path $ValidationIndexPath `
        -Content $ValidationIndex
}

Write-Host "[OK] Validation Stage 7 criada." -ForegroundColor Green

# ============================================================
# NOTIFICATIONS API SERVICE
# ============================================================

$NotificationService = @'
import {
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';

import type {
  AuthenticatedPrincipal,
} from '@crm/auth';

import type {
  NotificationListResponse,
  NotificationPreferenceResponse,
  PushDeviceListResponse,
  PushDeviceResponse,
} from '@crm/contracts';

import type {
  RegisterPushDeviceInput,
  UpdateNotificationPreferenceInput,
} from '@crm/validation';

import {
  DatabaseService,
} from '../database/database.service.js';

export type EnqueuePushNotificationInput =
  Readonly<{
    organizationId: string;
    userId: string;
    type: string;
    title: string;
    body: string;
    url?: string | null;
    data?: Readonly<Record<string, string>>;
    idempotencyKey?: string | null;
  }>;

@Injectable()
export class NotificationsService {
  constructor(
    @Inject(DatabaseService)
    private readonly database:
      DatabaseService,
  ) {}

  async listDevices(
    principal: AuthenticatedPrincipal,
  ): Promise<PushDeviceListResponse> {
    const devices =
      await this.database.client.pushDevice.findMany({
        where: {
          organizationId:
            principal.organizationId,

          userId:
            principal.userId,

          status: {
            not: 'REVOKED',
          },
        },

        orderBy: {
          lastSeenAt: 'desc',
        },
      });

    return devices.map(
      (device) =>
        this.mapDevice(device),
    );
  }

  async registerDevice(
    principal: AuthenticatedPrincipal,
    input: RegisterPushDeviceInput,
    userAgent: string | null,
  ): Promise<PushDeviceResponse> {
    const now = new Date();

    const device =
      await this.database.client.$transaction(
        async (transaction) => {
          const existing =
            await transaction.pushDevice.findUnique({
              where: {
                subscriptionId:
                  input.subscriptionId,
              },
            });

          const status =
            input.optedIn
              ? 'ACTIVE'
              : 'INACTIVE';

          const saved = existing
            ? await transaction.pushDevice.update({
                where: {
                  id: existing.id,
                },

                data: {
                  organizationId:
                    principal.organizationId,

                  userId:
                    principal.userId,

                  oneSignalId:
                    input.oneSignalId ??
                    null,

                  status,
                  optedIn:
                    input.optedIn,

                  platform:
                    input.platform ??
                    null,

                  browser:
                    input.browser ??
                    null,

                  deviceLabel:
                    input.deviceLabel ??
                    null,

                  userAgent,

                  lastSeenAt:
                    now,

                  ...(input.optedIn
                    ? {
                        subscribedAt:
                          now,

                        unsubscribedAt:
                          null,

                        revokedAt:
                          null,
                      }
                    : {
                        unsubscribedAt:
                          now,
                      }),
                },
              })
            : await transaction.pushDevice.create({
                data: {
                  organizationId:
                    principal.organizationId,

                  userId:
                    principal.userId,

                  subscriptionId:
                    input.subscriptionId,

                  oneSignalId:
                    input.oneSignalId ??
                    null,

                  status,
                  optedIn:
                    input.optedIn,

                  platform:
                    input.platform ??
                    null,

                  browser:
                    input.browser ??
                    null,

                  deviceLabel:
                    input.deviceLabel ??
                    null,

                  userAgent,

                  subscribedAt:
                    now,

                  ...(input.optedIn
                    ? {}
                    : {
                        unsubscribedAt:
                          now,
                      }),
                },
              });

          await transaction.auditLog.create({
            data: {
              organizationId:
                principal.organizationId,

              actorType: 'USER',

              actorUserId:
                principal.userId,

              action:
                existing
                  ? 'push_device.synced'
                  : 'push_device.registered',

              resourceType:
                'push_device',

              resourceId:
                saved.id,

              outcome:
                'SUCCESS',

              metadata: {
                provider:
                  saved.provider,

                optedIn:
                  saved.optedIn,
              },
            },
          });

          return saved;
        },
      );

    return this.mapDevice(device);
  }

  async unregisterDevice(
    principal: AuthenticatedPrincipal,
    subscriptionId: string,
  ): Promise<void> {
    const device =
      await this.database.client.pushDevice.findFirst({
        where: {
          organizationId:
            principal.organizationId,

          userId:
            principal.userId,

          subscriptionId,
        },
      });

    if (!device) {
      throw new NotFoundException({
        code:
          'PUSH_DEVICE_NOT_FOUND',

        message:
          'Push device not found.',
      });
    }

    if (
      device.status ===
      'REVOKED'
    ) {
      return;
    }

    const now = new Date();

    await this.database.client.$transaction(
      async (transaction) => {
        await transaction.pushDevice.update({
          where: {
            id: device.id,
          },

          data: {
            status:
              'REVOKED',

            optedIn:
              false,

            unsubscribedAt:
              device.unsubscribedAt ??
              now,

            revokedAt:
              now,

            lastSeenAt:
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
              'push_device.revoked',

            resourceType:
              'push_device',

            resourceId:
              device.id,

            outcome:
              'SUCCESS',
          },
        });
      },
    );
  }

  async getPreferences(
    principal: AuthenticatedPrincipal,
  ): Promise<NotificationPreferenceResponse> {
    const preferences =
      await this.database.client.notificationPreference.upsert({
        where: {
          organizationId_userId: {
            organizationId:
              principal.organizationId,

            userId:
              principal.userId,
          },
        },

        create: {
          organizationId:
            principal.organizationId,

          userId:
            principal.userId,
        },

        update: {},
      });

    return {
      pushEnabled:
        preferences.pushEnabled,

      siteMonitoring:
        preferences.siteMonitoring,

      adsUpdates:
        preferences.adsUpdates,

      whatsappInbox:
        preferences.whatsappInbox,

      createdAt:
        preferences.createdAt.toISOString(),

      updatedAt:
        preferences.updatedAt.toISOString(),
    };
  }

  async updatePreferences(
    principal: AuthenticatedPrincipal,
    input: UpdateNotificationPreferenceInput,
  ): Promise<NotificationPreferenceResponse> {
    const preferences =
      await this.database.client.notificationPreference.upsert({
        where: {
          organizationId_userId: {
            organizationId:
              principal.organizationId,

            userId:
              principal.userId,
          },
        },

        create: {
          organizationId:
            principal.organizationId,

          userId:
            principal.userId,

          ...(input.pushEnabled !== undefined
            ? {
                pushEnabled:
                  input.pushEnabled === true,
              }
            : {}),

          ...(input.siteMonitoring !== undefined
            ? {
                siteMonitoring:
                  input.siteMonitoring === true,
              }
            : {}),

          ...(input.adsUpdates !== undefined
            ? {
                adsUpdates:
                  input.adsUpdates === true,
              }
            : {}),

          ...(input.whatsappInbox !== undefined
            ? {
                whatsappInbox:
                  input.whatsappInbox === true,
              }
            : {}),
        },

        update: {
          ...(input.pushEnabled !== undefined
            ? {
                pushEnabled:
                  input.pushEnabled === true,
              }
            : {}),

          ...(input.siteMonitoring !== undefined
            ? {
                siteMonitoring:
                  input.siteMonitoring === true,
              }
            : {}),

          ...(input.adsUpdates !== undefined
            ? {
                adsUpdates:
                  input.adsUpdates === true,
              }
            : {}),

          ...(input.whatsappInbox !== undefined
            ? {
                whatsappInbox:
                  input.whatsappInbox === true,
              }
            : {}),
        },
      });

    return {
      pushEnabled:
        preferences.pushEnabled,

      siteMonitoring:
        preferences.siteMonitoring,

      adsUpdates:
        preferences.adsUpdates,

      whatsappInbox:
        preferences.whatsappInbox,

      createdAt:
        preferences.createdAt.toISOString(),

      updatedAt:
        preferences.updatedAt.toISOString(),
    };
  }

  async listNotifications(
    principal: AuthenticatedPrincipal,
  ): Promise<NotificationListResponse> {
    const notifications =
      await this.database.client.notification.findMany({
        where: {
          organizationId:
            principal.organizationId,

          userId:
            principal.userId,
        },

        orderBy: {
          createdAt: 'desc',
        },

        take: 100,
      });

    return notifications.map(
      (notification) => ({
        id:
          notification.id,

        type:
          notification.type,

        title:
          notification.title,

        body:
          notification.body,

        url:
          notification.url,

        data:
          notification.data,

        status:
          notification.status,

        createdAt:
          notification.createdAt.toISOString(),

        processedAt:
          notification.processedAt?.toISOString() ??
          null,
      }),
    );
  }

  async enqueuePush(
    input: EnqueuePushNotificationInput,
  ): Promise<string> {
    if (input.idempotencyKey) {
      const existing =
        await this.database.client.notification.findFirst({
          where: {
            organizationId:
              input.organizationId,

            idempotencyKey:
              input.idempotencyKey,
          },

          select: {
            id: true,
          },
        });

      if (existing) {
        return existing.id;
      }
    }

    const result =
      await this.database.client.$transaction(
        async (transaction) => {
          const notification =
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

                data:
                  input.data ??
                  undefined,

                idempotencyKey:
                  input.idempotencyKey ??
                  null,
              },
            });

          await transaction.notificationDelivery.create({
            data: {
              organizationId:
                input.organizationId,

              notificationId:
                notification.id,

              userId:
                input.userId,

              provider:
                'ONESIGNAL',
            },
          });

          return notification;
        },
      );

    return result.id;
  }

  private mapDevice(
    device: {
      id: string;
      subscriptionId: string;
      oneSignalId: string | null;
      provider: 'ONESIGNAL';
      status: 'ACTIVE' | 'INACTIVE' | 'REVOKED';
      optedIn: boolean;
      platform: string | null;
      browser: string | null;
      deviceLabel: string | null;
      subscribedAt: Date;
      unsubscribedAt: Date | null;
      lastSeenAt: Date;
      createdAt: Date;
      updatedAt: Date;
    },
  ): PushDeviceResponse {
    return {
      id:
        device.id,

      subscriptionId:
        device.subscriptionId,

      oneSignalId:
        device.oneSignalId,

      provider:
        device.provider,

      status:
        device.status,

      optedIn:
        device.optedIn,

      platform:
        device.platform,

      browser:
        device.browser,

      deviceLabel:
        device.deviceLabel,

      subscribedAt:
        device.subscribedAt.toISOString(),

      unsubscribedAt:
        device.unsubscribedAt?.toISOString() ??
        null,

      lastSeenAt:
        device.lastSeenAt.toISOString(),

      createdAt:
        device.createdAt.toISOString(),

      updatedAt:
        device.updatedAt.toISOString(),
    };
  }
}
'@

Write-Text `
    -Path ".\apps\api\src\notifications\notifications.service.ts" `
    -Content $NotificationService

# ============================================================
# API CONTROLLER
# ============================================================

$NotificationController = @'
import {
  BadRequestException,
  Controller,
  Delete,
  Get,
  Headers,
  Inject,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Body,
  UseGuards,
} from '@nestjs/common';

import type {
  AuthenticatedPrincipal,
} from '@crm/auth';

import type {
  NotificationListResponse,
  NotificationPreferenceResponse,
  PushDeviceListResponse,
  PushDeviceResponse,
} from '@crm/contracts';

import {
  registerPushDeviceSchema,
  updateNotificationPreferenceSchema,
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
  NotificationsService,
} from './notifications.service.js';

@Controller()
@UseGuards(
  AccessTokenGuard,
  AuthorizationGuard,
)
export class NotificationsController {
  constructor(
    @Inject(NotificationsService)
    private readonly notificationsService:
      NotificationsService,
  ) {}

  @Get('push/devices')
  @RequirePermissions('profile.read')
  listDevices(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,
  ): Promise<PushDeviceListResponse> {
    return this.notificationsService.listDevices(
      principal,
    );
  }

  @Post('push/devices')
  @RequirePermissions('profile.update')
  registerDevice(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Body()
    body: unknown,

    @Headers('user-agent')
    userAgent: string | undefined,
  ): Promise<PushDeviceResponse> {
    const parsed =
      registerPushDeviceSchema.safeParse(
        body,
      );

    if (!parsed.success) {
      throw new BadRequestException({
        code:
          'PUSH_DEVICE_VALIDATION_ERROR',

        message:
          'Invalid push device payload.',

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

    return this.notificationsService.registerDevice(
      principal,
      parsed.data,
      userAgent ?? null,
    );
  }

  @Delete('push/devices/:subscriptionId')
  @RequirePermissions('profile.update')
  async unregisterDevice(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param(
      'subscriptionId',
      new ParseUUIDPipe(),
    )
    subscriptionId: string,
  ): Promise<Readonly<{ success: true }>> {
    await this.notificationsService.unregisterDevice(
      principal,
      subscriptionId,
    );

    return {
      success: true,
    };
  }

  @Get('notifications/preferences')
  @RequirePermissions('profile.read')
  getPreferences(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,
  ): Promise<NotificationPreferenceResponse> {
    return this.notificationsService.getPreferences(
      principal,
    );
  }

  @Patch('notifications/preferences')
  @RequirePermissions('profile.update')
  updatePreferences(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Body()
    body: unknown,
  ): Promise<NotificationPreferenceResponse> {
    const parsed =
      updateNotificationPreferenceSchema.safeParse(
        body,
      );

    if (!parsed.success) {
      throw new BadRequestException({
        code:
          'NOTIFICATION_PREFERENCE_VALIDATION_ERROR',

        message:
          'Invalid notification preference payload.',

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

    return this.notificationsService.updatePreferences(
      principal,
      parsed.data,
    );
  }

  @Get('notifications')
  @RequirePermissions('profile.read')
  listNotifications(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,
  ): Promise<NotificationListResponse> {
    return this.notificationsService.listNotifications(
      principal,
    );
  }
}
'@

Write-Text `
    -Path ".\apps\api\src\notifications\notifications.controller.ts" `
    -Content $NotificationController

# ============================================================
# API MODULE
# ============================================================

$NotificationModule = @'
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
  NotificationsController,
} from './notifications.controller.js';

import {
  NotificationsService,
} from './notifications.service.js';

@Module({
  imports: [
    AuthorizationModule,
    DatabaseModule,
  ],

  controllers: [
    NotificationsController,
  ],

  providers: [
    NotificationsService,
  ],

  exports: [
    NotificationsService,
  ],
})
export class NotificationsModule {}
'@

Write-Text `
    -Path ".\apps\api\src\notifications\notifications.module.ts" `
    -Content $NotificationModule

# ============================================================
# APP MODULE REGISTER
# ============================================================

$AppModule = Read-Text -Path $AppModulePath

if (-not $AppModule.Contains("NotificationsModule")) {
    $ImportAnchor = "import { AdsModule } from './ads/ads.module.js';"

    if (-not $AppModule.Contains($ImportAnchor)) {
        throw "AdsModule import anchor nao encontrado."
    }

    $AppModule = $AppModule.Replace(
        $ImportAnchor,
        $ImportAnchor +
        "`r`n`r`nimport { NotificationsModule } from './notifications/notifications.module.js';"
    )

    $ArrayAnchor = "    AdsModule,"

    if (-not $AppModule.Contains($ArrayAnchor)) {
        throw "AdsModule array anchor nao encontrado."
    }

    $AppModule = $AppModule.Replace(
        $ArrayAnchor,
        $ArrayAnchor +
        "`r`n    NotificationsModule,"
    )

    Write-Text `
        -Path $AppModulePath `
        -Content $AppModule
}

Write-Host "[OK] NotificationsModule registrado." -ForegroundColor Green

# ============================================================
# NOTIFICATION DISPATCHER CONFIG
# ============================================================

$DispatcherConfig = @'
export type NotificationDispatcherConfig =
  Readonly<{
    intervalMs: number;
    leaseMs: number;
    maxAttempts: number;
    retryBaseMs: number;
    maxClaimsPerTick: number;
    oneSignalAppId: string | null;
    oneSignalApiKey: string | null;
  }>;

function readInteger(
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
    !Number.isInteger(value) ||
    value < minimum ||
    value > maximum
  ) {
    throw new Error(
      `${name} must be an integer between ${minimum} and ${maximum}.`,
    );
  }

  return value;
}

function readOptional(
  name: string,
): string | null {
  const value =
    process.env[name]?.trim();

  return value
    ? value
    : null;
}

export function parseNotificationDispatcherConfig():
NotificationDispatcherConfig {
  return {
    intervalMs:
      readInteger(
        'NOTIFICATION_DISPATCH_INTERVAL_MS',
        1000,
        100,
        60_000,
      ),

    leaseMs:
      readInteger(
        'NOTIFICATION_DELIVERY_LEASE_MS',
        30_000,
        5_000,
        900_000,
      ),

    maxAttempts:
      readInteger(
        'NOTIFICATION_MAX_ATTEMPTS',
        8,
        1,
        100,
      ),

    retryBaseMs:
      readInteger(
        'NOTIFICATION_RETRY_BASE_MS',
        5_000,
        100,
        3_600_000,
      ),

    maxClaimsPerTick:
      readInteger(
        'NOTIFICATION_MAX_CLAIMS_PER_TICK',
        25,
        1,
        1000,
      ),

    oneSignalAppId:
      readOptional(
        'ONESIGNAL_APP_ID',
      ),

    oneSignalApiKey:
      readOptional(
        'ONESIGNAL_API_KEY',
      ),
  };
}

export function isNotificationDispatcherEnabled(
  config: NotificationDispatcherConfig,
): boolean {
  return Boolean(
    config.oneSignalAppId &&
    config.oneSignalApiKey,
  );
}
'@

Write-Text `
    -Path ".\apps\worker\src\notification-dispatcher.config.ts" `
    -Content $DispatcherConfig

# ============================================================
# ONESIGNAL SENDER
# ============================================================

$OneSignalSender = @'
import type {
  NotificationDispatcherConfig,
} from './notification-dispatcher.config.js';

export type PushMessage = Readonly<{
  externalId: string;
  title: string;
  body: string;
  url: string | null;
  data: unknown;
}>;

export type PushSendResult = Readonly<{
  providerMessageId: string | null;
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

export async function sendOneSignalPush(
  config: NotificationDispatcherConfig,
  message: PushMessage,
): Promise<PushSendResult> {
  if (
    !config.oneSignalAppId ||
    !config.oneSignalApiKey
  ) {
    throw new Error(
      'OneSignal is not configured.',
    );
  }

  const payload: Record<string, unknown> = {
    app_id:
      config.oneSignalAppId,

    include_aliases: {
      external_id: [
        message.externalId,
      ],
    },

    target_channel:
      'push',

    headings: {
      en:
        message.title,
    },

    contents: {
      en:
        message.body,
    },
  };

  if (message.url) {
    payload.url =
      message.url;
  }

  if (
    isRecord(message.data)
  ) {
    payload.data =
      message.data;
  }

  const response =
    await fetch(
      'https://api.onesignal.com/notifications?c=push',
      {
        method:
          'POST',

        headers: {
          Authorization:
            `Key ${config.oneSignalApiKey}`,

          'Content-Type':
            'application/json',
        },

        body:
          JSON.stringify(payload),

        signal:
          AbortSignal.timeout(
            10_000,
          ),
      },
    );

  const responseText =
    await response.text();

  if (!response.ok) {
    throw new Error(
      `OneSignal HTTP ${response.status}: ${responseText.slice(0, 300)}`,
    );
  }

  let parsed:
    unknown = null;

  try {
    parsed =
      JSON.parse(responseText);
  } catch {
    parsed = null;
  }

  const providerMessageId =
    isRecord(parsed) &&
    typeof parsed.id === 'string'
      ? parsed.id
      : null;

  return {
    providerMessageId,
  };
}
'@

Write-Text `
    -Path ".\apps\worker\src\onesignal-sender.ts" `
    -Content $OneSignalSender

# ============================================================
# NOTIFICATION DISPATCHER
# ============================================================

$NotificationDispatcher = @'
import type {
  CrmDatabaseClient,
} from '@crm/database';

import {
  isNotificationDispatcherEnabled,
  type NotificationDispatcherConfig,
} from './notification-dispatcher.config.js';

import {
  sendOneSignalPush,
  type PushMessage,
  type PushSendResult,
} from './onesignal-sender.js';

type ClaimedDelivery = Readonly<{
  id: string;
}>;

export type NotificationSender =
  (
    config: NotificationDispatcherConfig,
    message: PushMessage,
  ) => Promise<PushSendResult>;

export type NotificationTickSummary =
  Readonly<{
    enabled: boolean;
    claimed: number;
    sent: number;
    failed: number;
    deferred: number;
    skipped: number;
  }>;

function addMilliseconds(
  value: Date,
  milliseconds: number,
): Date {
  return new Date(
    value.getTime() +
      milliseconds,
  );
}

function errorMessage(
  error: unknown,
): string {
  return (
    error instanceof Error
      ? error.message
      : String(error)
  ).slice(0, 500);
}

export class NotificationDispatcherService {
  constructor(
    private readonly database:
      CrmDatabaseClient,

    private readonly workerId:
      string,

    private readonly config:
      NotificationDispatcherConfig,

    private readonly sender:
      NotificationSender =
        sendOneSignalPush,
  ) {}

  async runTick():
  Promise<NotificationTickSummary> {
    if (
      !isNotificationDispatcherEnabled(
        this.config,
      )
    ) {
      return {
        enabled: false,
        claimed: 0,
        sent: 0,
        failed: 0,
        deferred: 0,
        skipped: 0,
      };
    }

    let claimed = 0;
    let sent = 0;
    let failed = 0;
    let deferred = 0;
    let skipped = 0;

    for (
      let index = 0;
      index <
      this.config.maxClaimsPerTick;
      index += 1
    ) {
      const delivery =
        await this.claimNext();

      if (!delivery) {
        break;
      }

      claimed += 1;

      const result =
        await this.process(
          delivery.id,
        );

      if (result === 'SENT') {
        sent += 1;
      }

      if (result === 'FAILED') {
        failed += 1;
      }

      if (result === 'DEFERRED') {
        deferred += 1;
      }

      if (result === 'SKIPPED') {
        skipped += 1;
      }
    }

    return {
      enabled: true,
      claimed,
      sent,
      failed,
      deferred,
      skipped,
    };
  }

  private async claimNext():
  Promise<ClaimedDelivery | null> {
    const rows =
      await this.database.$queryRawUnsafe<
        ClaimedDelivery[]
      >(
        `
          WITH candidate AS (
            SELECT
              "id"
            FROM
              "notification_deliveries"
            WHERE
              (
                (
                  "status" = 'WAITING'
                  AND "nextAttemptAt" <= NOW()
                )
                OR
                (
                  "status" = 'CLAIMED'
                  AND "leaseExpiresAt" IS NOT NULL
                  AND "leaseExpiresAt" <= NOW()
                )
              )
            ORDER BY
              "nextAttemptAt" ASC,
              "createdAt" ASC,
              "id" ASC
            FOR UPDATE SKIP LOCKED
            LIMIT 1
          )
          UPDATE
            "notification_deliveries" delivery
          SET
            "status" = 'CLAIMED',
            "claimedAt" = NOW(),
            "claimedByWorkerId" = $1,
            "leaseExpiresAt" =
              NOW() + ($2::int * INTERVAL '1 millisecond'),
            "attempts" =
              delivery."attempts" + 1,
            "updatedAt" = NOW()
          FROM
            candidate
          WHERE
            delivery."id" =
              candidate."id"
          RETURNING
            delivery."id"
        `,
        this.workerId,
        this.config.leaseMs,
      );

    return rows[0] ?? null;
  }

  private async process(
    deliveryId: string,
  ): Promise<
    'SENT' |
    'FAILED' |
    'DEFERRED' |
    'SKIPPED'
  > {
    const delivery =
      await this.database.notificationDelivery.findFirst({
        where: {
          id:
            deliveryId,

          status:
            'CLAIMED',

          claimedByWorkerId:
            this.workerId,

          leaseExpiresAt: {
            gt:
              new Date(),
          },
        },

        include: {
          notification:
            true,
        },
      });

    if (!delivery) {
      return 'DEFERRED';
    }

    const notification =
      delivery.notification;

    if (
      notification.status ===
      'CANCELLED'
    ) {
      await this.skip(
        delivery.id,
        notification.id,
        'Notification cancelled.',
      );

      return 'SKIPPED';
    }

    const preference =
      await this.database.notificationPreference.findUnique({
        where: {
          organizationId_userId: {
            organizationId:
              delivery.organizationId,

            userId:
              delivery.userId,
          },
        },
      });

    if (
      preference &&
      !preference.pushEnabled
    ) {
      await this.skip(
        delivery.id,
        notification.id,
        'Push notifications disabled by user.',
      );

      return 'SKIPPED';
    }

    const activeDeviceCount =
      await this.database.pushDevice.count({
        where: {
          organizationId:
            delivery.organizationId,

          userId:
            delivery.userId,

          status:
            'ACTIVE',

          optedIn:
            true,
        },
      });

    if (
      activeDeviceCount === 0
    ) {
      await this.skip(
        delivery.id,
        notification.id,
        'No active push device.',
      );

      return 'SKIPPED';
    }

    await this.database.notification.update({
      where: {
        id:
          notification.id,
      },

      data: {
        status:
          'PROCESSING',
      },
    });

    try {
      const result =
        await this.sender(
          this.config,
          {
            externalId:
              delivery.userId,

            title:
              notification.title,

            body:
              notification.body,

            url:
              notification.url,

            data:
              notification.data,
          },
        );

      const now =
        new Date();

      await this.database.$transaction(
        async (transaction) => {
          await transaction.notificationDelivery.update({
            where: {
              id:
                delivery.id,
            },

            data: {
              status:
                'SENT',

              providerMessageId:
                result.providerMessageId,

              sentAt:
                now,

              claimedAt:
                null,

              claimedByWorkerId:
                null,

              leaseExpiresAt:
                null,

              lastError:
                null,
            },
          });

          await transaction.notification.update({
            where: {
              id:
                notification.id,
            },

            data: {
              status:
                'SENT',

              processedAt:
                now,

              failureReason:
                null,
            },
          });

          await transaction.auditLog.create({
            data: {
              organizationId:
                delivery.organizationId,

              actorType:
                'SYSTEM',

              action:
                'notification.sent',

              resourceType:
                'notification',

              resourceId:
                notification.id,

              outcome:
                'SUCCESS',

              metadata: {
                provider:
                  delivery.provider,

                providerMessageId:
                  result.providerMessageId,

                attempts:
                  delivery.attempts,
              },
            },
          });
        },
      );

      return 'SENT';
    } catch (error) {
      const message =
        errorMessage(error);

      if (
        delivery.attempts >=
        this.config.maxAttempts
      ) {
        const now =
          new Date();

        await this.database.$transaction(
          async (transaction) => {
            await transaction.notificationDelivery.update({
              where: {
                id:
                  delivery.id,
              },

              data: {
                status:
                  'FAILED',

                failedAt:
                  now,

                lastError:
                  message,

                claimedAt:
                  null,

                claimedByWorkerId:
                  null,

                leaseExpiresAt:
                  null,
              },
            });

            await transaction.notification.update({
              where: {
                id:
                  notification.id,
              },

              data: {
                status:
                  'FAILED',

                processedAt:
                  now,

                failureReason:
                  message,
              },
            });

            await transaction.auditLog.create({
              data: {
                organizationId:
                  delivery.organizationId,

                actorType:
                  'SYSTEM',

                action:
                  'notification.failed',

                resourceType:
                  'notification',

                resourceId:
                  notification.id,

                outcome:
                  'FAILURE',

                metadata: {
                  provider:
                    delivery.provider,

                  attempts:
                    delivery.attempts,
                },
              },
            });
          },
        );

        return 'FAILED';
      }

      const retryDelay =
        this.config.retryBaseMs *
        Math.min(
          2 ** Math.max(
            0,
            delivery.attempts - 1,
          ),
          64,
        );

      await this.database.$transaction(
        async (transaction) => {
          await transaction.notificationDelivery.update({
            where: {
              id:
                delivery.id,
            },

            data: {
              status:
                'WAITING',

              nextAttemptAt:
                addMilliseconds(
                  new Date(),
                  retryDelay,
                ),

              lastError:
                message,

              claimedAt:
                null,

              claimedByWorkerId:
                null,

              leaseExpiresAt:
                null,
            },
          });

          await transaction.notification.update({
            where: {
              id:
                notification.id,
            },

            data: {
              status:
                'QUEUED',

              failureReason:
                null,
            },
          });
        },
      );

      return 'DEFERRED';
    }
  }

  private async skip(
    deliveryId: string,
    notificationId: string,
    reason: string,
  ): Promise<void> {
    const now =
      new Date();

    await this.database.$transaction(
      async (transaction) => {
        await transaction.notificationDelivery.update({
          where: {
            id:
              deliveryId,
          },

          data: {
            status:
              'SKIPPED',

            claimedAt:
              null,

            claimedByWorkerId:
              null,

            leaseExpiresAt:
              null,

            lastError:
              reason,
          },
        });

        await transaction.notification.update({
          where: {
            id:
              notificationId,
          },

          data: {
            status:
              'SKIPPED',

            processedAt:
              now,

            failureReason:
              reason,
          },
        });
      },
    );
  }
}
'@

Write-Text `
    -Path ".\apps\worker\src\notification-dispatcher.service.ts" `
    -Content $NotificationDispatcher

# ============================================================
# WORKER MAIN - ADS + NOTIFICATION DISPATCH
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

const service =
  'worker' as const;

const heartbeatIntervalMs =
  30_000;

const schedulerConfig =
  parseAdsSchedulerConfig();

const notificationConfig =
  parseNotificationDispatcherConfig();

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

let schedulerRunning =
  false;

let notificationRunning =
  false;

let shuttingDown =
  false;

function log(
  event: string,
  extra: Record<string, unknown> = {},
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
      summary.claimed > 0 ||
      summary.failed > 0 ||
      summary.lostLease > 0
    ) {
      log(
        'ads.scheduler.tick',
        summary,
      );
    }
  } catch (error) {
    log(
      'ads.scheduler.error',
      {
        message:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );
  } finally {
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
      summary.claimed > 0 ||
      summary.failed > 0
    ) {
      log(
        'notification.dispatch.tick',
        summary,
      );
    }
  } catch (error) {
    log(
      'notification.dispatch.error',
      {
        message:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );
  } finally {
    notificationRunning =
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
  },
);

await Promise.all([
  runSchedulerTick(),
  runNotificationTick(),
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

const heartbeatTimer =
  setInterval(
    () => {
      log(
        'service.heartbeat',
        {
          schedulerRunning,
          notificationRunning,
        },
      );
    },

    heartbeatIntervalMs,
  );

async function shutdown(
  signal: NodeJS.Signals,
): Promise<void> {
  if (shuttingDown) {
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
    notificationRunning
  ) {
    await new Promise<void>(
      (resolve) => {
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

  process.exit(0);
}

process.once(
  'SIGINT',
  () => {
    void shutdown('SIGINT');
  },
);

process.once(
  'SIGTERM',
  () => {
    void shutdown('SIGTERM');
  },
);
'@

Write-Text `
    -Path $WorkerMainPath `
    -Content $WorkerMain

Write-Host "[OK] Notification dispatcher integrado ao worker." -ForegroundColor Green

# ============================================================
# PWA MANIFEST
# ============================================================

$Manifest = @'
import type {
  MetadataRoute,
} from 'next';

export default function manifest():
MetadataRoute.Manifest {
  return {
    name:
      'CRM ADS WhatsApp',

    short_name:
      'CRM',

    description:
      'CRM para operacao de ADS e WhatsApp.',

    start_url:
      '/',

    display:
      'standalone',

    orientation:
      'any',

    background_color:
      '#0b0b0b',

    theme_color:
      '#0b0b0b',

    icons: [
      {
        src:
          '/icons/pwa-192.svg',

        sizes:
          '192x192',

        type:
          'image/svg+xml',

        purpose:
          'any',
      },

      {
        src:
          '/icons/pwa-512.svg',

        sizes:
          '512x512',

        type:
          'image/svg+xml',

        purpose:
          'any',
      },

      {
        src:
          '/icons/pwa-maskable.svg',

        sizes:
          '512x512',

        type:
          'image/svg+xml',

        purpose:
          'maskable',
      },
    ],
  };
}
'@

Write-Text `
    -Path ".\apps\web\src\app\manifest.ts" `
    -Content $Manifest

# ============================================================
# ROOT PWA SERVICE WORKER - NO CACHE
# ============================================================

$PwaWorker = @'
/* global self */
self.addEventListener(
  'install',
  () => {
    self.skipWaiting();
  },
);

self.addEventListener(
  'activate',
  (event) => {
    event.waitUntil(
      self.clients.claim(),
    );
  },
);

self.addEventListener(
  'message',
  (event) => {
    if (
      event.data ===
      'SKIP_WAITING'
    ) {
      self.skipWaiting();
    }
  },
);

/*
 * IMPORTANT:
 *
 * This CRM is intentionally online-only.
 *
 * There is NO fetch handler and NO Cache API usage here.
 *
 * Authenticated API responses, ADS data, leads,
 * WhatsApp conversations, dashboards, receipts,
 * tokens and financial information must never be
 * cached for offline use by this service worker.
 */
'@

Write-Text `
    -Path ".\apps\web\public\sw.js" `
    -Content $PwaWorker

# ============================================================
# ONESIGNAL SERVICE WORKER
# ============================================================

$OneSignalWorker = @'
/* global importScripts */
importScripts("https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.sw.js");
'@

Write-Text `
    -Path ".\apps\web\public\push\onesignal\OneSignalSDKWorker.js" `
    -Content $OneSignalWorker

# ============================================================
# PWA ICONS
# ============================================================

$Icon192 = @'
<svg xmlns="http://www.w3.org/2000/svg" width="192" height="192" viewBox="0 0 192 192">
  <rect width="192" height="192" rx="38" fill="#0b0b0b"/>
  <text x="96" y="112" text-anchor="middle" font-size="58" font-family="Arial, sans-serif" font-weight="700" fill="#ffffff">CRM</text>
</svg>
'@

$Icon512 = @'
<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">
  <rect width="512" height="512" rx="104" fill="#0b0b0b"/>
  <text x="256" y="300" text-anchor="middle" font-size="154" font-family="Arial, sans-serif" font-weight="700" fill="#ffffff">CRM</text>
</svg>
'@

$Maskable = @'
<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">
  <rect width="512" height="512" fill="#0b0b0b"/>
  <circle cx="256" cy="256" r="180" fill="#171717"/>
  <text x="256" y="300" text-anchor="middle" font-size="132" font-family="Arial, sans-serif" font-weight="700" fill="#ffffff">CRM</text>
</svg>
'@

Write-Text `
    -Path ".\apps\web\public\icons\pwa-192.svg" `
    -Content $Icon192

Write-Text `
    -Path ".\apps\web\public\icons\pwa-512.svg" `
    -Content $Icon512

Write-Text `
    -Path ".\apps\web\public\icons\pwa-maskable.svg" `
    -Content $Maskable

# ============================================================
# PWA BOOTSTRAP
# ============================================================

$PwaBootstrap = @'
'use client';

import {
  useEffect,
} from 'react';

export function PwaBootstrap() {
  useEffect(
    () => {
      if (
        !(
          'serviceWorker' in
          navigator
        )
      ) {
        return;
      }

      void navigator.serviceWorker.register(
        '/sw.js',
        {
          scope:
            '/',
        },
      );
    },
    [],
  );

  return null;
}
'@

Write-Text `
    -Path ".\apps\web\src\components\pwa-bootstrap.tsx" `
    -Content $PwaBootstrap

# ============================================================
# ONESIGNAL CLIENT BRIDGE
# ============================================================

$PushClient = @'
type PushSubscriptionState =
  Readonly<{
    id: string | null;
    token: string | null;
    optedIn: boolean;
  }>;

type PushSubscriptionChangeEvent =
  Readonly<{
    previous: PushSubscriptionState;
    current: PushSubscriptionState;
  }>;

type OneSignalSdk = {
  init(
    options: {
      appId: string;
      serviceWorkerPath: string;
      serviceWorkerParam: {
        scope: string;
      };
      autoResubscribe: boolean;
    },
  ): Promise<void>;

  login(
    externalId: string,
  ): Promise<void>;

  logout():
  Promise<void>;

  User: {
    onesignalId:
      string | null;

    PushSubscription: {
      id:
        string | null;

      token:
        string | null;

      optedIn:
        boolean;

      optIn():
      Promise<void>;

      optOut():
      Promise<void>;

      addEventListener(
        name: 'change',
        listener: (
          event: PushSubscriptionChangeEvent,
        ) => void,
      ): void;

      removeEventListener(
        name: 'change',
        listener: (
          event: PushSubscriptionChangeEvent,
        ) => void,
      ): void;
    };
  };

  Notifications: {
    isPushSupported():
    boolean;

    permission:
      boolean;
  };
};

declare global {
  interface Window {
    OneSignalDeferred?:
      Array<
        (
          oneSignal:
            OneSignalSdk,
        ) => void | Promise<void>
      >;

    __crmOneSignalInitialized?:
      boolean;
  }
}

function withOneSignal(
  callback: (
    oneSignal: OneSignalSdk,
  ) => void | Promise<void>,
): void {
  window.OneSignalDeferred =
    window.OneSignalDeferred ??
    [];

  window.OneSignalDeferred.push(
    callback,
  );
}

export function initializeOneSignal(
  appId: string,
): void {
  if (
    typeof window ===
    'undefined'
  ) {
    return;
  }

  if (
    window.__crmOneSignalInitialized
  ) {
    return;
  }

  window.__crmOneSignalInitialized =
    true;

  withOneSignal(
    async (oneSignal) => {
      await oneSignal.init({
        appId,

        serviceWorkerPath:
          'push/onesignal/OneSignalSDKWorker.js',

        serviceWorkerParam: {
          scope:
            '/push/onesignal/',
        },

        autoResubscribe:
          true,
      });
    },
  );
}

export type IdentifyPushUserInput =
  Readonly<{
    userId: string;
    accessToken: string;
    apiBaseUrl: string;
  }>;

async function registerDevice(
  oneSignal: OneSignalSdk,
  input: IdentifyPushUserInput,
): Promise<void> {
  const subscriptionId =
    oneSignal.User.PushSubscription.id;

  if (!subscriptionId) {
    return;
  }

  await fetch(
    `${input.apiBaseUrl}/api/v1/push/devices`,
    {
      method:
        'POST',

      headers: {
        Authorization:
          `Bearer ${input.accessToken}`,

        'Content-Type':
          'application/json',
      },

      body:
        JSON.stringify({
          subscriptionId,

          oneSignalId:
            oneSignal.User.onesignalId,

          optedIn:
            oneSignal.User.PushSubscription.optedIn,

          platform:
            navigator.platform ||
            null,

          browser:
            navigator.userAgent,

          deviceLabel:
            null,
        }),
    },
  );
}

export function identifyPushUser(
  input: IdentifyPushUserInput,
): () => void {
  let cleanup:
    (() => void) |
    null = null;

  withOneSignal(
    async (oneSignal) => {
      await oneSignal.login(
        input.userId,
      );

      await registerDevice(
        oneSignal,
        input,
      );

      const listener =
        (
          event:
            PushSubscriptionChangeEvent,
        ) => {
          void event;

          void registerDevice(
            oneSignal,
            input,
          );
        };

      oneSignal.User.PushSubscription.addEventListener(
        'change',
        listener,
      );

      cleanup = () => {
        oneSignal.User.PushSubscription.removeEventListener(
          'change',
          listener,
        );
      };
    },
  );

  return () => {
    cleanup?.();
  };
}

export function requestPushPermission():
void {
  withOneSignal(
    async (oneSignal) => {
      if (
        !oneSignal.Notifications.isPushSupported()
      ) {
        return;
      }

      await oneSignal.User.PushSubscription.optIn();
    },
  );
}

export function optOutPush():
void {
  withOneSignal(
    async (oneSignal) => {
      await oneSignal.User.PushSubscription.optOut();
    },
  );
}

export function detachPushUser(
  input: IdentifyPushUserInput,
): void {
  withOneSignal(
    async (oneSignal) => {
      const subscriptionId =
        oneSignal.User.PushSubscription.id;

      if (subscriptionId) {
        await fetch(
          `${input.apiBaseUrl}/api/v1/push/devices/${subscriptionId}`,
          {
            method:
              'DELETE',

            headers: {
              Authorization:
                `Bearer ${input.accessToken}`,
            },
          },
        );
      }

      await oneSignal.logout();
    },
  );
}

export function isStandalonePwa():
boolean {
  if (
    typeof window ===
    'undefined'
  ) {
    return false;
  }

  return (
    window.matchMedia(
      '(display-mode: standalone)',
    ).matches ||
    (
      'standalone' in navigator &&
      Boolean(
        (
          navigator as Navigator & {
            standalone?: boolean;
          }
        ).standalone,
      )
    )
  );
}
'@

Write-Text `
    -Path ".\apps\web\src\lib\push-client.ts" `
    -Content $PushClient

# ============================================================
# ONESIGNAL BOOTSTRAP COMPONENT
# ============================================================

$OneSignalBootstrap = @'
'use client';

import Script from 'next/script';

import {
  initializeOneSignal,
} from '@/lib/push-client';

const appId =
  process.env.NEXT_PUBLIC_ONESIGNAL_APP_ID?.trim() ??
  '';

export function OneSignalBootstrap() {
  if (!appId) {
    return null;
  }

  return (
    <Script
      id="onesignal-web-sdk"
      src="https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.page.js"
      strategy="afterInteractive"
      onLoad={() => {
        initializeOneSignal(
          appId,
        );
      }}
    />
  );
}
'@

Write-Text `
    -Path ".\apps\web\src\components\onesignal-bootstrap.tsx" `
    -Content $OneSignalBootstrap

# ============================================================
# ROOT LAYOUT
# ============================================================

$WebLayout = @'
import type {
  Metadata,
  Viewport,
} from 'next';

import type {
  ReactNode,
} from 'react';

import {
  OneSignalBootstrap,
} from '@/components/onesignal-bootstrap';

import {
  PwaBootstrap,
} from '@/components/pwa-bootstrap';

import './globals.css';

export const metadata:
Metadata = {
  title:
    'CRM ADS/WhatsApp',

  description:
    'CRM greenfield para ADS, numeros, leads e atendimento WhatsApp.',

  applicationName:
    'CRM ADS WhatsApp',

  appleWebApp: {
    capable:
      true,

    title:
      'CRM',

    statusBarStyle:
      'black-translucent',
  },
};

export const viewport:
Viewport = {
  width:
    'device-width',

  initialScale:
    1,

  viewportFit:
    'cover',

  themeColor:
    '#0b0b0b',
};

type RootLayoutProps =
  Readonly<{
    children:
      ReactNode;
  }>;

export default function RootLayout(
  {
    children,
  }: RootLayoutProps,
) {
  return (
    <html lang="pt-BR">
      <body>
        <PwaBootstrap />
        <OneSignalBootstrap />
        {children}
      </body>
    </html>
  );
}
'@

Write-Text `
    -Path $WebLayoutPath `
    -Content $WebLayout

# ============================================================
# NEXT CONFIG SERVICE WORKER HEADERS
# ============================================================

$NextConfig = @'
import type {
  NextConfig,
} from 'next';

const noCacheHeaders = [
  {
    key:
      'Cache-Control',

    value:
      'no-cache, no-store, must-revalidate',
  },
];

const nextConfig:
NextConfig = {
  output:
    process.env.CRM_STANDALONE === 'true'
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
    -Path $NextConfigPath `
    -Content $NextConfig

Write-Host "[OK] PWA + OneSignal frontend criado." -ForegroundColor Green

# ============================================================
# ENVIRONMENT
# ============================================================

$EnvExample = Read-Text -Path $EnvExamplePath

if (-not $EnvExample.Contains("ONESIGNAL_APP_ID=")) {
    $Stage7Environment = @(
        "",
        "# PWA + OneSignal - Etapa 7",
        "NEXT_PUBLIC_ONESIGNAL_APP_ID=",
        "ONESIGNAL_APP_ID=",
        "ONESIGNAL_API_KEY=",
        "NOTIFICATION_DISPATCH_INTERVAL_MS=1000",
        "NOTIFICATION_DELIVERY_LEASE_MS=30000",
        "NOTIFICATION_MAX_ATTEMPTS=8",
        "NOTIFICATION_RETRY_BASE_MS=5000",
        "NOTIFICATION_MAX_CLAIMS_PER_TICK=25"
    )

    $EnvExample = (
        $EnvExample.TrimEnd() +
        "`r`n" +
        ($Stage7Environment -join "`r`n") +
        "`r`n"
    )

    Write-Text `
        -Path $EnvExamplePath `
        -Content $EnvExample
}

Write-Host "[OK] Variaveis Stage 7 adicionadas." -ForegroundColor Green

# ============================================================
# STRUCTURAL VALIDATION
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
    ".\apps\web\public\icons\pwa-192.svg",
    ".\apps\web\public\icons\pwa-512.svg",
    ".\apps\web\public\icons\pwa-maskable.svg"
)

foreach ($RequiredFile in $RequiredFiles) {
    if (-not (Test-Path $RequiredFile)) {
        throw "Arquivo Stage 7 ausente: $RequiredFile"
    }
}

$SchemaFinal = Read-Text -Path $SchemaPath

$SchemaMarkers = @(
    "model PushDevice",
    "model NotificationPreference",
    "model Notification {",
    "model NotificationDelivery",
    "enum PushProvider",
    "enum NotificationDeliveryStatus"
)

foreach ($Marker in $SchemaMarkers) {
    if (-not $SchemaFinal.Contains($Marker)) {
        throw "Marker Stage 7 ausente: $Marker"
    }
}

$PwaWorkerFinal = Read-Text `
    -Path ".\apps\web\public\sw.js"

if ($PwaWorkerFinal.Contains("caches.open")) {
    throw "PWA Stage 7 nao pode criar cache offline."
}

if ($PwaWorkerFinal.Contains("addEventListener(`r`n  'fetch'")) {
    throw "PWA Stage 7 nao deve interceptar fetch."
}

$OneSignalWorkerFinal = Read-Text `
    -Path ".\apps\web\public\push\onesignal\OneSignalSDKWorker.js"

if (-not $OneSignalWorkerFinal.Contains("OneSignalSDK.sw.js")) {
    throw "OneSignal worker invalido."
}

$WorkerMainFinal = Read-Text `
    -Path $WorkerMainPath

if (-not $WorkerMainFinal.Contains("NotificationDispatcherService")) {
    throw "Notification dispatcher nao registrado no worker."
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host "[OK] MACROBLOCO 7.1 CRIADO." -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Implementado:" -ForegroundColor Cyan
Write-Host "- PWA manifest"
Write-Host "- standalone mode"
Write-Host "- PWA root service worker"
Write-Host "- zero offline API cache"
Write-Host "- OneSignal Web SDK v16"
Write-Host "- OneSignal dedicated service worker"
Write-Host "- OneSignal login external_id"
Write-Host "- multi-device subscription sync"
Write-Host "- push opt-in / opt-out"
Write-Host "- PushDevice"
Write-Host "- NotificationPreference"
Write-Host "- Notification"
Write-Host "- NotificationDelivery"
Write-Host "- register/unregister device API"
Write-Host "- notification preferences API"
Write-Host "- notification list API"
Write-Host "- enqueuePush internal service"
Write-Host "- persistent notification dispatcher"
Write-Host "- PostgreSQL claim + lease"
Write-Host "- OneSignal REST sender"
Write-Host "- exponential retry"
Write-Host "- idempotency key"
Write-Host "- secret key server-side only"
Write-Host ""
Write-Host "Migration ainda NAO executada." -ForegroundColor Yellow
Write-Host "OneSignal real ainda NAO precisa estar configurado." -ForegroundColor Yellow
Write-Host "Proximo: Macrobloco 7.2." -ForegroundColor Yellow