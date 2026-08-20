/*
  Warnings:

  - A unique constraint covering the columns `[metaPhoneNumberId]` on the table `whatsapp_numbers` will be added. If there are existing duplicate values, this will fail.

*/
-- CreateEnum
CREATE TYPE "MetaWebhookStatus" AS ENUM ('RECEIVED', 'CLAIMED', 'PROCESSED', 'UNMATCHED', 'IGNORED', 'FAILED');

-- AlterTable
ALTER TABLE "whatsapp_numbers" ADD COLUMN     "metaConnectedAt" TIMESTAMPTZ(3),
ADD COLUMN     "metaPhoneNumberId" VARCHAR(64),
ADD COLUMN     "metaWabaId" VARCHAR(64),
ADD COLUMN     "metaWebhookLastSeenAt" TIMESTAMPTZ(3);

-- CreateTable
CREATE TABLE "meta_webhook_envelopes" (
    "id" UUID NOT NULL,
    "organizationId" UUID,
    "whatsAppNumberId" UUID,
    "object" VARCHAR(120),
    "field" VARCHAR(120),
    "wabaId" VARCHAR(64),
    "metaPhoneNumberId" VARCHAR(64),
    "payloadHash" CHAR(64) NOT NULL,
    "payload" JSONB NOT NULL,
    "status" "MetaWebhookStatus" NOT NULL DEFAULT 'RECEIVED',
    "receivedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "availableAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "claimedAt" TIMESTAMPTZ(3),
    "claimedByWorkerId" VARCHAR(120),
    "leaseExpiresAt" TIMESTAMPTZ(3),
    "processedAt" TIMESTAMPTZ(3),
    "failureReason" VARCHAR(500),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "meta_webhook_envelopes_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "meta_webhook_envelopes_payloadHash_key" ON "meta_webhook_envelopes"("payloadHash");

-- CreateIndex
CREATE INDEX "meta_webhook_envelopes_organizationId_status_availableAt_idx" ON "meta_webhook_envelopes"("organizationId", "status", "availableAt");

-- CreateIndex
CREATE INDEX "meta_webhook_envelopes_organizationId_whatsAppNumberId_rece_idx" ON "meta_webhook_envelopes"("organizationId", "whatsAppNumberId", "receivedAt");

-- CreateIndex
CREATE INDEX "meta_webhook_envelopes_metaPhoneNumberId_receivedAt_idx" ON "meta_webhook_envelopes"("metaPhoneNumberId", "receivedAt");

-- CreateIndex
CREATE INDEX "meta_webhook_envelopes_status_leaseExpiresAt_idx" ON "meta_webhook_envelopes"("status", "leaseExpiresAt");

-- CreateIndex
CREATE INDEX "meta_webhook_envelopes_receivedAt_idx" ON "meta_webhook_envelopes"("receivedAt");

-- CreateIndex
CREATE UNIQUE INDEX "whatsapp_numbers_metaPhoneNumberId_key" ON "whatsapp_numbers"("metaPhoneNumberId");

-- AddForeignKey
ALTER TABLE "meta_webhook_envelopes" ADD CONSTRAINT "meta_webhook_envelopes_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "organizations"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "meta_webhook_envelopes" ADD CONSTRAINT "meta_webhook_envelopes_whatsAppNumberId_fkey" FOREIGN KEY ("whatsAppNumberId") REFERENCES "whatsapp_numbers"("id") ON DELETE SET NULL ON UPDATE CASCADE;
