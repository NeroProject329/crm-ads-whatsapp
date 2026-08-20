-- CreateEnum
CREATE TYPE "LeadStatus" AS ENUM ('ATTRIBUTED', 'EXCESS');

-- CreateTable
CREATE TABLE "leads" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "contactId" UUID NOT NULL,
    "firstInboundMessageId" UUID NOT NULL,
    "firstWhatsAppNumberId" UUID NOT NULL,
    "ownerEmployeeId" UUID,
    "waIdSnapshot" VARCHAR(64) NOT NULL,
    "profileNameSnapshot" VARCHAR(160),
    "status" "LeadStatus" NOT NULL DEFAULT 'EXCESS',
    "excessReason" VARCHAR(120),
    "firstSeenAt" TIMESTAMPTZ(3) NOT NULL,
    "lastSeenAt" TIMESTAMPTZ(3) NOT NULL,
    "inboundMessageCount" INTEGER NOT NULL DEFAULT 1,
    "attributedAt" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "leads_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "lead_attributions" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "leadId" UUID NOT NULL,
    "adsRequestId" UUID NOT NULL,
    "adsMicrobatchId" UUID NOT NULL,
    "employeeId" UUID NOT NULL,
    "whatsAppNumberId" UUID NOT NULL,
    "inboundMessageId" UUID NOT NULL,
    "attributedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "lead_attributions_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "leads_organizationId_status_firstSeenAt_idx" ON "leads"("organizationId", "status", "firstSeenAt");

-- CreateIndex
CREATE INDEX "leads_organizationId_ownerEmployeeId_status_firstSeenAt_idx" ON "leads"("organizationId", "ownerEmployeeId", "status", "firstSeenAt");

-- CreateIndex
CREATE INDEX "leads_organizationId_firstWhatsAppNumberId_status_firstSeen_idx" ON "leads"("organizationId", "firstWhatsAppNumberId", "status", "firstSeenAt");

-- CreateIndex
CREATE INDEX "leads_organizationId_waIdSnapshot_idx" ON "leads"("organizationId", "waIdSnapshot");

-- CreateIndex
CREATE UNIQUE INDEX "leads_organizationId_id_key" ON "leads"("organizationId", "id");

-- CreateIndex
CREATE UNIQUE INDEX "leads_organizationId_contactId_key" ON "leads"("organizationId", "contactId");

-- CreateIndex
CREATE UNIQUE INDEX "leads_organizationId_firstInboundMessageId_key" ON "leads"("organizationId", "firstInboundMessageId");

-- CreateIndex
CREATE INDEX "lead_attributions_organizationId_adsRequestId_attributedAt_idx" ON "lead_attributions"("organizationId", "adsRequestId", "attributedAt");

-- CreateIndex
CREATE INDEX "lead_attributions_organizationId_adsMicrobatchId_attributed_idx" ON "lead_attributions"("organizationId", "adsMicrobatchId", "attributedAt");

-- CreateIndex
CREATE INDEX "lead_attributions_organizationId_employeeId_attributedAt_idx" ON "lead_attributions"("organizationId", "employeeId", "attributedAt");

-- CreateIndex
CREATE INDEX "lead_attributions_organizationId_whatsAppNumberId_attribute_idx" ON "lead_attributions"("organizationId", "whatsAppNumberId", "attributedAt");

-- CreateIndex
CREATE UNIQUE INDEX "lead_attributions_organizationId_id_key" ON "lead_attributions"("organizationId", "id");

-- CreateIndex
CREATE UNIQUE INDEX "lead_attributions_organizationId_leadId_key" ON "lead_attributions"("organizationId", "leadId");

-- CreateIndex
CREATE UNIQUE INDEX "lead_attributions_organizationId_inboundMessageId_key" ON "lead_attributions"("organizationId", "inboundMessageId");

-- AddForeignKey
ALTER TABLE "leads" ADD CONSTRAINT "leads_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "leads" ADD CONSTRAINT "leads_organizationId_contactId_fkey" FOREIGN KEY ("organizationId", "contactId") REFERENCES "whatsapp_contacts"("organizationId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "leads" ADD CONSTRAINT "leads_organizationId_firstInboundMessageId_fkey" FOREIGN KEY ("organizationId", "firstInboundMessageId") REFERENCES "whatsapp_messages"("organizationId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "leads" ADD CONSTRAINT "leads_organizationId_firstWhatsAppNumberId_fkey" FOREIGN KEY ("organizationId", "firstWhatsAppNumberId") REFERENCES "whatsapp_numbers"("organizationId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "leads" ADD CONSTRAINT "leads_organizationId_ownerEmployeeId_fkey" FOREIGN KEY ("organizationId", "ownerEmployeeId") REFERENCES "employees"("organizationId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "lead_attributions" ADD CONSTRAINT "lead_attributions_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "lead_attributions" ADD CONSTRAINT "lead_attributions_organizationId_leadId_fkey" FOREIGN KEY ("organizationId", "leadId") REFERENCES "leads"("organizationId", "id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "lead_attributions" ADD CONSTRAINT "lead_attributions_organizationId_adsRequestId_fkey" FOREIGN KEY ("organizationId", "adsRequestId") REFERENCES "ads_requests"("organizationId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "lead_attributions" ADD CONSTRAINT "lead_attributions_organizationId_adsMicrobatchId_fkey" FOREIGN KEY ("organizationId", "adsMicrobatchId") REFERENCES "ads_microbatches"("organizationId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "lead_attributions" ADD CONSTRAINT "lead_attributions_organizationId_employeeId_fkey" FOREIGN KEY ("organizationId", "employeeId") REFERENCES "employees"("organizationId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "lead_attributions" ADD CONSTRAINT "lead_attributions_organizationId_whatsAppNumberId_fkey" FOREIGN KEY ("organizationId", "whatsAppNumberId") REFERENCES "whatsapp_numbers"("organizationId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "lead_attributions" ADD CONSTRAINT "lead_attributions_organizationId_inboundMessageId_fkey" FOREIGN KEY ("organizationId", "inboundMessageId") REFERENCES "whatsapp_messages"("organizationId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;
