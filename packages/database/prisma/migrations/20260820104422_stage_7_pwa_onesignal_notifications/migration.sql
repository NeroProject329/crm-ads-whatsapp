-- CreateEnum
CREATE TYPE "PushProvider" AS ENUM ('ONESIGNAL');

-- CreateEnum
CREATE TYPE "PushDeviceStatus" AS ENUM ('ACTIVE', 'INACTIVE', 'REVOKED');

-- CreateEnum
CREATE TYPE "NotificationChannel" AS ENUM ('PUSH');

-- CreateEnum
CREATE TYPE "NotificationStatus" AS ENUM ('QUEUED', 'PROCESSING', 'SENT', 'FAILED', 'SKIPPED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "NotificationDeliveryStatus" AS ENUM ('WAITING', 'CLAIMED', 'SENT', 'FAILED', 'SKIPPED', 'CANCELLED');

-- CreateTable
CREATE TABLE "push_devices" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "provider" "PushProvider" NOT NULL DEFAULT 'ONESIGNAL',
    "subscriptionId" VARCHAR(160) NOT NULL,
    "oneSignalId" VARCHAR(160),
    "status" "PushDeviceStatus" NOT NULL DEFAULT 'ACTIVE',
    "optedIn" BOOLEAN NOT NULL DEFAULT true,
    "platform" VARCHAR(80),
    "browser" VARCHAR(80),
    "deviceLabel" VARCHAR(120),
    "userAgent" VARCHAR(500),
    "subscribedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "unsubscribedAt" TIMESTAMPTZ(3),
    "revokedAt" TIMESTAMPTZ(3),
    "lastSeenAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "push_devices_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "notification_preferences" (
    "organizationId" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "pushEnabled" BOOLEAN NOT NULL DEFAULT true,
    "siteMonitoring" BOOLEAN NOT NULL DEFAULT true,
    "adsUpdates" BOOLEAN NOT NULL DEFAULT true,
    "whatsappInbox" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "notification_preferences_pkey" PRIMARY KEY ("organizationId","userId")
);

-- CreateTable
CREATE TABLE "notifications" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "channel" "NotificationChannel" NOT NULL DEFAULT 'PUSH',
    "type" VARCHAR(120) NOT NULL,
    "title" VARCHAR(160) NOT NULL,
    "body" VARCHAR(500) NOT NULL,
    "url" VARCHAR(500),
    "data" JSONB,
    "idempotencyKey" VARCHAR(160),
    "status" "NotificationStatus" NOT NULL DEFAULT 'QUEUED',
    "processedAt" TIMESTAMPTZ(3),
    "failureReason" VARCHAR(500),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "notifications_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "notification_deliveries" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "notificationId" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "provider" "PushProvider" NOT NULL DEFAULT 'ONESIGNAL',
    "status" "NotificationDeliveryStatus" NOT NULL DEFAULT 'WAITING',
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "nextAttemptAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "claimedAt" TIMESTAMPTZ(3),
    "claimedByWorkerId" VARCHAR(120),
    "leaseExpiresAt" TIMESTAMPTZ(3),
    "providerMessageId" VARCHAR(160),
    "sentAt" TIMESTAMPTZ(3),
    "failedAt" TIMESTAMPTZ(3),
    "lastError" VARCHAR(500),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "notification_deliveries_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "push_devices_subscriptionId_key" ON "push_devices"("subscriptionId");

-- CreateIndex
CREATE INDEX "push_devices_organizationId_userId_status_idx" ON "push_devices"("organizationId", "userId", "status");

-- CreateIndex
CREATE INDEX "push_devices_organizationId_userId_optedIn_idx" ON "push_devices"("organizationId", "userId", "optedIn");

-- CreateIndex
CREATE UNIQUE INDEX "push_devices_organizationId_id_key" ON "push_devices"("organizationId", "id");

-- CreateIndex
CREATE INDEX "notifications_organizationId_userId_createdAt_idx" ON "notifications"("organizationId", "userId", "createdAt");

-- CreateIndex
CREATE INDEX "notifications_organizationId_status_createdAt_idx" ON "notifications"("organizationId", "status", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "notifications_organizationId_id_key" ON "notifications"("organizationId", "id");

-- CreateIndex
CREATE UNIQUE INDEX "notifications_organizationId_idempotencyKey_key" ON "notifications"("organizationId", "idempotencyKey");

-- CreateIndex
CREATE INDEX "notification_deliveries_organizationId_status_nextAttemptAt_idx" ON "notification_deliveries"("organizationId", "status", "nextAttemptAt");

-- CreateIndex
CREATE INDEX "notification_deliveries_organizationId_userId_status_idx" ON "notification_deliveries"("organizationId", "userId", "status");

-- CreateIndex
CREATE INDEX "notification_deliveries_leaseExpiresAt_idx" ON "notification_deliveries"("leaseExpiresAt");

-- CreateIndex
CREATE UNIQUE INDEX "notification_deliveries_organizationId_id_key" ON "notification_deliveries"("organizationId", "id");

-- CreateIndex
CREATE UNIQUE INDEX "notification_deliveries_notificationId_provider_key" ON "notification_deliveries"("notificationId", "provider");

-- AddForeignKey
ALTER TABLE "push_devices" ADD CONSTRAINT "push_devices_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "organizations"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "push_devices" ADD CONSTRAINT "push_devices_organizationId_userId_fkey" FOREIGN KEY ("organizationId", "userId") REFERENCES "users"("organizationId", "id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notification_preferences" ADD CONSTRAINT "notification_preferences_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "organizations"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notification_preferences" ADD CONSTRAINT "notification_preferences_organizationId_userId_fkey" FOREIGN KEY ("organizationId", "userId") REFERENCES "users"("organizationId", "id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "organizations"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_organizationId_userId_fkey" FOREIGN KEY ("organizationId", "userId") REFERENCES "users"("organizationId", "id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notification_deliveries" ADD CONSTRAINT "notification_deliveries_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "organizations"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notification_deliveries" ADD CONSTRAINT "notification_deliveries_organizationId_notificationId_fkey" FOREIGN KEY ("organizationId", "notificationId") REFERENCES "notifications"("organizationId", "id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notification_deliveries" ADD CONSTRAINT "notification_deliveries_organizationId_userId_fkey" FOREIGN KEY ("organizationId", "userId") REFERENCES "users"("organizationId", "id") ON DELETE CASCADE ON UPDATE CASCADE;
