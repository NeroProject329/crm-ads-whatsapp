-- CreateEnum
CREATE TYPE "MetaPhoneQualityRating" AS ENUM ('UNKNOWN', 'GREEN', 'YELLOW', 'RED', 'NA');

-- CreateEnum
CREATE TYPE "WhatsAppNumberHealthStatus" AS ENUM ('UNKNOWN', 'HEALTHY', 'DEGRADED', 'CRITICAL', 'RECOVERING', 'DISABLED');

-- CreateEnum
CREATE TYPE "WhatsAppNumberHealthSource" AS ENUM ('META_API', 'META_WEBHOOK', 'CRM_SIGNAL', 'MANUAL', 'SYSTEM');

-- CreateEnum
CREATE TYPE "WhatsAppNumberIncidentStatus" AS ENUM ('OPEN', 'RESOLVED');

-- CreateTable
CREATE TABLE "whatsapp_number_health_states" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "whatsAppNumberId" UUID NOT NULL,
    "status" "WhatsAppNumberHealthStatus" NOT NULL DEFAULT 'UNKNOWN',
    "schedulerEligible" BOOLEAN NOT NULL DEFAULT true,
    "manualPaused" BOOLEAN NOT NULL DEFAULT false,
    "metaQualityRating" "MetaPhoneQualityRating" NOT NULL DEFAULT 'UNKNOWN',
    "metaQualityEvent" VARCHAR(80),
    "messagingLimitTier" VARCHAR(80),
    "lastReasonCode" VARCHAR(120),
    "lastReasonMessage" VARCHAR(500),
    "lastMetaSyncAt" TIMESTAMPTZ(3),
    "lastMetaWebhookAt" TIMESTAMPTZ(3),
    "lastHealthyAt" TIMESTAMPTZ(3),
    "degradedSinceAt" TIMESTAMPTZ(3),
    "criticalSinceAt" TIMESTAMPTZ(3),
    "recoveringSinceAt" TIMESTAMPTZ(3),
    "consecutiveHealthyChecks" INTEGER NOT NULL DEFAULT 0,
    "consecutiveSyncFailures" INTEGER NOT NULL DEFAULT 0,
    "nextCheckAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "claimedAt" TIMESTAMPTZ(3),
    "claimedByWorkerId" VARCHAR(120),
    "leaseExpiresAt" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "whatsapp_number_health_states_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "whatsapp_number_health_events" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "whatsAppNumberId" UUID NOT NULL,
    "sourceEnvelopeId" UUID,
    "source" "WhatsAppNumberHealthSource" NOT NULL,
    "previousStatus" "WhatsAppNumberHealthStatus" NOT NULL,
    "currentStatus" "WhatsAppNumberHealthStatus" NOT NULL,
    "metaQualityRating" "MetaPhoneQualityRating" NOT NULL,
    "metaQualityEvent" VARCHAR(80),
    "messagingLimitTier" VARCHAR(80),
    "schedulerEligible" BOOLEAN NOT NULL,
    "reasonCode" VARCHAR(120),
    "reasonMessage" VARCHAR(500),
    "occurredAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "whatsapp_number_health_events_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "whatsapp_number_incidents" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "whatsAppNumberId" UUID NOT NULL,
    "status" "WhatsAppNumberIncidentStatus" NOT NULL DEFAULT 'OPEN',
    "type" VARCHAR(120) NOT NULL,
    "severity" "WhatsAppNumberHealthStatus" NOT NULL,
    "openedReasonCode" VARCHAR(120),
    "openedReason" VARCHAR(500),
    "openedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "resolvedReason" VARCHAR(500),
    "resolvedAt" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "whatsapp_number_incidents_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "whatsapp_number_health_states_organizationId_status_schedul_idx" ON "whatsapp_number_health_states"("organizationId", "status", "schedulerEligible");

-- CreateIndex
CREATE INDEX "whatsapp_number_health_states_nextCheckAt_leaseExpiresAt_idx" ON "whatsapp_number_health_states"("nextCheckAt", "leaseExpiresAt");

-- CreateIndex
CREATE INDEX "whatsapp_number_health_states_organizationId_manualPaused_idx" ON "whatsapp_number_health_states"("organizationId", "manualPaused");

-- CreateIndex
CREATE UNIQUE INDEX "whatsapp_number_health_states_organizationId_id_key" ON "whatsapp_number_health_states"("organizationId", "id");

-- CreateIndex
CREATE UNIQUE INDEX "whatsapp_number_health_states_organizationId_whatsAppNumber_key" ON "whatsapp_number_health_states"("organizationId", "whatsAppNumberId");

-- CreateIndex
CREATE INDEX "whatsapp_number_health_events_organizationId_whatsAppNumber_idx" ON "whatsapp_number_health_events"("organizationId", "whatsAppNumberId", "occurredAt");

-- CreateIndex
CREATE INDEX "whatsapp_number_health_events_organizationId_currentStatus__idx" ON "whatsapp_number_health_events"("organizationId", "currentStatus", "occurredAt");

-- CreateIndex
CREATE INDEX "whatsapp_number_health_events_sourceEnvelopeId_idx" ON "whatsapp_number_health_events"("sourceEnvelopeId");

-- CreateIndex
CREATE UNIQUE INDEX "whatsapp_number_health_events_organizationId_id_key" ON "whatsapp_number_health_events"("organizationId", "id");

-- CreateIndex
CREATE INDEX "whatsapp_number_incidents_organizationId_whatsAppNumberId_s_idx" ON "whatsapp_number_incidents"("organizationId", "whatsAppNumberId", "status", "openedAt");

-- CreateIndex
CREATE INDEX "whatsapp_number_incidents_organizationId_status_severity_idx" ON "whatsapp_number_incidents"("organizationId", "status", "severity");

-- CreateIndex
CREATE UNIQUE INDEX "whatsapp_number_incidents_organizationId_id_key" ON "whatsapp_number_incidents"("organizationId", "id");

-- AddForeignKey
ALTER TABLE "whatsapp_number_health_states" ADD CONSTRAINT "whatsapp_number_health_states_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "whatsapp_number_health_states" ADD CONSTRAINT "whatsapp_number_health_states_organizationId_whatsAppNumbe_fkey" FOREIGN KEY ("organizationId", "whatsAppNumberId") REFERENCES "whatsapp_numbers"("organizationId", "id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "whatsapp_number_health_events" ADD CONSTRAINT "whatsapp_number_health_events_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "whatsapp_number_health_events" ADD CONSTRAINT "whatsapp_number_health_events_organizationId_whatsAppNumbe_fkey" FOREIGN KEY ("organizationId", "whatsAppNumberId") REFERENCES "whatsapp_numbers"("organizationId", "id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "whatsapp_number_health_events" ADD CONSTRAINT "whatsapp_number_health_events_sourceEnvelopeId_fkey" FOREIGN KEY ("sourceEnvelopeId") REFERENCES "meta_webhook_envelopes"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "whatsapp_number_incidents" ADD CONSTRAINT "whatsapp_number_incidents_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "whatsapp_number_incidents" ADD CONSTRAINT "whatsapp_number_incidents_organizationId_whatsAppNumberId_fkey" FOREIGN KEY ("organizationId", "whatsAppNumberId") REFERENCES "whatsapp_numbers"("organizationId", "id") ON DELETE CASCADE ON UPDATE CASCADE;
