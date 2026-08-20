-- CreateEnum
CREATE TYPE "WhatsAppConversationStatus" AS ENUM ('OPEN', 'CLOSED', 'ARCHIVED');

-- CreateEnum
CREATE TYPE "WhatsAppMessageDirection" AS ENUM ('INBOUND', 'OUTBOUND');

-- CreateEnum
CREATE TYPE "WhatsAppMessageType" AS ENUM ('TEXT', 'TEMPLATE', 'IMAGE', 'AUDIO', 'VIDEO', 'DOCUMENT', 'STICKER', 'LOCATION', 'CONTACTS', 'INTERACTIVE', 'REACTION', 'UNKNOWN');

-- CreateEnum
CREATE TYPE "WhatsAppMessageStatus" AS ENUM ('RECEIVED', 'QUEUED', 'SENDING', 'SENT', 'DELIVERED', 'READ', 'FAILED', 'DELETED');

-- CreateTable
CREATE TABLE "whatsapp_contacts" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "waId" VARCHAR(64) NOT NULL,
    "profileName" VARCHAR(160),
    "lastInboundAt" TIMESTAMPTZ(3),
    "lastOutboundAt" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "whatsapp_contacts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "whatsapp_conversations" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "whatsAppNumberId" UUID NOT NULL,
    "contactId" UUID NOT NULL,
    "assignedEmployeeId" UUID,
    "status" "WhatsAppConversationStatus" NOT NULL DEFAULT 'OPEN',
    "customerServiceWindowExpiresAt" TIMESTAMPTZ(3),
    "lastMessageAt" TIMESTAMPTZ(3),
    "lastInboundAt" TIMESTAMPTZ(3),
    "lastOutboundAt" TIMESTAMPTZ(3),
    "unreadCount" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "whatsapp_conversations_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "whatsapp_messages" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "conversationId" UUID NOT NULL,
    "whatsAppNumberId" UUID NOT NULL,
    "contactId" UUID NOT NULL,
    "sourceEnvelopeId" UUID,
    "direction" "WhatsAppMessageDirection" NOT NULL,
    "type" "WhatsAppMessageType" NOT NULL,
    "status" "WhatsAppMessageStatus" NOT NULL,
    "metaMessageId" VARCHAR(255),
    "clientMessageId" UUID,
    "replyToMetaMessageId" VARCHAR(255),
    "textBody" TEXT,
    "content" JSONB NOT NULL,
    "providerTimestamp" TIMESTAMPTZ(3),
    "errorCode" VARCHAR(80),
    "errorMessage" VARCHAR(500),
    "queuedAt" TIMESTAMPTZ(3),
    "sentAt" TIMESTAMPTZ(3),
    "deliveredAt" TIMESTAMPTZ(3),
    "readAt" TIMESTAMPTZ(3),
    "failedAt" TIMESTAMPTZ(3),
    "availableAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "claimedAt" TIMESTAMPTZ(3),
    "claimedByWorkerId" VARCHAR(120),
    "leaseExpiresAt" TIMESTAMPTZ(3),
    "lastAttemptAt" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "whatsapp_messages_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "whatsapp_message_status_events" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "whatsAppNumberId" UUID NOT NULL,
    "sourceEnvelopeId" UUID,
    "metaMessageId" VARCHAR(255) NOT NULL,
    "status" "WhatsAppMessageStatus" NOT NULL,
    "recipientWaId" VARCHAR(64),
    "providerTimestamp" TIMESTAMPTZ(3) NOT NULL,
    "errors" JSONB,
    "payload" JSONB NOT NULL,
    "appliedAt" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "whatsapp_message_status_events_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "whatsapp_quick_replies" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "title" VARCHAR(120) NOT NULL,
    "shortcut" VARCHAR(80) NOT NULL,
    "body" TEXT NOT NULL,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "deletedAt" TIMESTAMPTZ(3),

    CONSTRAINT "whatsapp_quick_replies_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "whatsapp_contacts_organizationId_profileName_idx" ON "whatsapp_contacts"("organizationId", "profileName");

-- CreateIndex
CREATE INDEX "whatsapp_contacts_organizationId_lastInboundAt_idx" ON "whatsapp_contacts"("organizationId", "lastInboundAt");

-- CreateIndex
CREATE UNIQUE INDEX "whatsapp_contacts_organizationId_id_key" ON "whatsapp_contacts"("organizationId", "id");

-- CreateIndex
CREATE UNIQUE INDEX "whatsapp_contacts_organizationId_waId_key" ON "whatsapp_contacts"("organizationId", "waId");

-- CreateIndex
CREATE INDEX "whatsapp_conversations_organizationId_assignedEmployeeId_st_idx" ON "whatsapp_conversations"("organizationId", "assignedEmployeeId", "status", "lastMessageAt");

-- CreateIndex
CREATE INDEX "whatsapp_conversations_organizationId_whatsAppNumberId_stat_idx" ON "whatsapp_conversations"("organizationId", "whatsAppNumberId", "status", "lastMessageAt");

-- CreateIndex
CREATE INDEX "whatsapp_conversations_organizationId_status_lastMessageAt_idx" ON "whatsapp_conversations"("organizationId", "status", "lastMessageAt");

-- CreateIndex
CREATE UNIQUE INDEX "whatsapp_conversations_organizationId_id_key" ON "whatsapp_conversations"("organizationId", "id");

-- CreateIndex
CREATE UNIQUE INDEX "whatsapp_conversations_organizationId_whatsAppNumberId_cont_key" ON "whatsapp_conversations"("organizationId", "whatsAppNumberId", "contactId");

-- CreateIndex
CREATE UNIQUE INDEX "whatsapp_messages_metaMessageId_key" ON "whatsapp_messages"("metaMessageId");

-- CreateIndex
CREATE UNIQUE INDEX "whatsapp_messages_clientMessageId_key" ON "whatsapp_messages"("clientMessageId");

-- CreateIndex
CREATE INDEX "whatsapp_messages_organizationId_conversationId_createdAt_idx" ON "whatsapp_messages"("organizationId", "conversationId", "createdAt");

-- CreateIndex
CREATE INDEX "whatsapp_messages_organizationId_whatsAppNumberId_createdAt_idx" ON "whatsapp_messages"("organizationId", "whatsAppNumberId", "createdAt");

-- CreateIndex
CREATE INDEX "whatsapp_messages_organizationId_direction_status_available_idx" ON "whatsapp_messages"("organizationId", "direction", "status", "availableAt");

-- CreateIndex
CREATE INDEX "whatsapp_messages_status_leaseExpiresAt_idx" ON "whatsapp_messages"("status", "leaseExpiresAt");

-- CreateIndex
CREATE UNIQUE INDEX "whatsapp_messages_organizationId_id_key" ON "whatsapp_messages"("organizationId", "id");

-- CreateIndex
CREATE INDEX "whatsapp_message_status_events_organizationId_metaMessageId_idx" ON "whatsapp_message_status_events"("organizationId", "metaMessageId", "providerTimestamp");

-- CreateIndex
CREATE INDEX "whatsapp_message_status_events_organizationId_whatsAppNumbe_idx" ON "whatsapp_message_status_events"("organizationId", "whatsAppNumberId", "providerTimestamp");

-- CreateIndex
CREATE INDEX "whatsapp_message_status_events_appliedAt_createdAt_idx" ON "whatsapp_message_status_events"("appliedAt", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "whatsapp_message_status_events_organizationId_metaMessageId_key" ON "whatsapp_message_status_events"("organizationId", "metaMessageId", "status", "providerTimestamp");

-- CreateIndex
CREATE INDEX "whatsapp_quick_replies_organizationId_deletedAt_title_idx" ON "whatsapp_quick_replies"("organizationId", "deletedAt", "title");

-- CreateIndex
CREATE UNIQUE INDEX "whatsapp_quick_replies_organizationId_id_key" ON "whatsapp_quick_replies"("organizationId", "id");

-- CreateIndex
CREATE UNIQUE INDEX "whatsapp_quick_replies_organizationId_shortcut_key" ON "whatsapp_quick_replies"("organizationId", "shortcut");

-- AddForeignKey
ALTER TABLE "whatsapp_contacts" ADD CONSTRAINT "whatsapp_contacts_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "whatsapp_conversations" ADD CONSTRAINT "whatsapp_conversations_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "whatsapp_conversations" ADD CONSTRAINT "whatsapp_conversations_organizationId_whatsAppNumberId_fkey" FOREIGN KEY ("organizationId", "whatsAppNumberId") REFERENCES "whatsapp_numbers"("organizationId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "whatsapp_conversations" ADD CONSTRAINT "whatsapp_conversations_organizationId_contactId_fkey" FOREIGN KEY ("organizationId", "contactId") REFERENCES "whatsapp_contacts"("organizationId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "whatsapp_conversations" ADD CONSTRAINT "whatsapp_conversations_organizationId_assignedEmployeeId_fkey" FOREIGN KEY ("organizationId", "assignedEmployeeId") REFERENCES "employees"("organizationId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "whatsapp_messages" ADD CONSTRAINT "whatsapp_messages_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "whatsapp_messages" ADD CONSTRAINT "whatsapp_messages_organizationId_conversationId_fkey" FOREIGN KEY ("organizationId", "conversationId") REFERENCES "whatsapp_conversations"("organizationId", "id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "whatsapp_messages" ADD CONSTRAINT "whatsapp_messages_organizationId_whatsAppNumberId_fkey" FOREIGN KEY ("organizationId", "whatsAppNumberId") REFERENCES "whatsapp_numbers"("organizationId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "whatsapp_messages" ADD CONSTRAINT "whatsapp_messages_organizationId_contactId_fkey" FOREIGN KEY ("organizationId", "contactId") REFERENCES "whatsapp_contacts"("organizationId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "whatsapp_messages" ADD CONSTRAINT "whatsapp_messages_sourceEnvelopeId_fkey" FOREIGN KEY ("sourceEnvelopeId") REFERENCES "meta_webhook_envelopes"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "whatsapp_message_status_events" ADD CONSTRAINT "whatsapp_message_status_events_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "whatsapp_message_status_events" ADD CONSTRAINT "whatsapp_message_status_events_organizationId_whatsAppNumb_fkey" FOREIGN KEY ("organizationId", "whatsAppNumberId") REFERENCES "whatsapp_numbers"("organizationId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "whatsapp_message_status_events" ADD CONSTRAINT "whatsapp_message_status_events_sourceEnvelopeId_fkey" FOREIGN KEY ("sourceEnvelopeId") REFERENCES "meta_webhook_envelopes"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "whatsapp_quick_replies" ADD CONSTRAINT "whatsapp_quick_replies_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
