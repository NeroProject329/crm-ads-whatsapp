-- CreateEnum
CREATE TYPE "AdsMicrobatchStatus" AS ENUM ('PLANNED', 'DELIVERING', 'COMPLETED', 'CANCELLED', 'FAILED');

-- AlterTable
ALTER TABLE "ads_queue_items" ADD COLUMN     "claimedByWorkerId" VARCHAR(120),
ADD COLUMN     "lastAttemptAt" TIMESTAMPTZ(3),
ADD COLUMN     "leaseExpiresAt" TIMESTAMPTZ(3);

-- AlterTable
ALTER TABLE "ads_requests" ADD COLUMN     "scheduledLeadCount" INTEGER NOT NULL DEFAULT 0;

-- CreateTable
CREATE TABLE "traffic_pool_scheduler_states" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "trafficPoolId" UUID NOT NULL,
    "nextPosition" INTEGER NOT NULL DEFAULT 1,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "traffic_pool_scheduler_states_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ads_microbatches" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "adsRequestId" UUID NOT NULL,
    "adsQueueItemId" UUID NOT NULL,
    "employeeId" UUID NOT NULL,
    "trafficPoolId" UUID NOT NULL,
    "trafficPoolMemberId" UUID NOT NULL,
    "whatsAppNumberId" UUID NOT NULL,
    "sequence" INTEGER NOT NULL,
    "reservedLeadCount" INTEGER NOT NULL,
    "deliveredLeadCount" INTEGER NOT NULL DEFAULT 0,
    "status" "AdsMicrobatchStatus" NOT NULL DEFAULT 'PLANNED',
    "plannedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "startedAt" TIMESTAMPTZ(3),
    "completedAt" TIMESTAMPTZ(3),
    "cancelledAt" TIMESTAMPTZ(3),
    "failureReason" VARCHAR(500),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "ads_microbatches_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "traffic_pool_scheduler_states_organizationId_updatedAt_idx" ON "traffic_pool_scheduler_states"("organizationId", "updatedAt");

-- CreateIndex
CREATE UNIQUE INDEX "traffic_pool_scheduler_states_organizationId_id_key" ON "traffic_pool_scheduler_states"("organizationId", "id");

-- CreateIndex
CREATE UNIQUE INDEX "traffic_pool_scheduler_states_organizationId_trafficPoolId_key" ON "traffic_pool_scheduler_states"("organizationId", "trafficPoolId");

-- CreateIndex
CREATE INDEX "ads_microbatches_organizationId_employeeId_status_idx" ON "ads_microbatches"("organizationId", "employeeId", "status");

-- CreateIndex
CREATE INDEX "ads_microbatches_organizationId_trafficPoolId_status_idx" ON "ads_microbatches"("organizationId", "trafficPoolId", "status");

-- CreateIndex
CREATE INDEX "ads_microbatches_organizationId_whatsAppNumberId_status_idx" ON "ads_microbatches"("organizationId", "whatsAppNumberId", "status");

-- CreateIndex
CREATE INDEX "ads_microbatches_organizationId_adsRequestId_status_idx" ON "ads_microbatches"("organizationId", "adsRequestId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "ads_microbatches_organizationId_id_key" ON "ads_microbatches"("organizationId", "id");

-- CreateIndex
CREATE UNIQUE INDEX "ads_microbatches_adsRequestId_sequence_key" ON "ads_microbatches"("adsRequestId", "sequence");

-- CreateIndex
CREATE INDEX "ads_queue_items_organizationId_status_leaseExpiresAt_idx" ON "ads_queue_items"("organizationId", "status", "leaseExpiresAt");

-- CreateIndex
CREATE INDEX "ads_requests_organizationId_employeeId_status_scheduledLead_idx" ON "ads_requests"("organizationId", "employeeId", "status", "scheduledLeadCount");

-- AddForeignKey
ALTER TABLE "traffic_pool_scheduler_states" ADD CONSTRAINT "traffic_pool_scheduler_states_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "traffic_pool_scheduler_states" ADD CONSTRAINT "traffic_pool_scheduler_states_organizationId_trafficPoolId_fkey" FOREIGN KEY ("organizationId", "trafficPoolId") REFERENCES "traffic_pools"("organizationId", "id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ads_microbatches" ADD CONSTRAINT "ads_microbatches_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ads_microbatches" ADD CONSTRAINT "ads_microbatches_organizationId_adsRequestId_fkey" FOREIGN KEY ("organizationId", "adsRequestId") REFERENCES "ads_requests"("organizationId", "id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ads_microbatches" ADD CONSTRAINT "ads_microbatches_organizationId_adsQueueItemId_fkey" FOREIGN KEY ("organizationId", "adsQueueItemId") REFERENCES "ads_queue_items"("organizationId", "id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ads_microbatches" ADD CONSTRAINT "ads_microbatches_organizationId_employeeId_fkey" FOREIGN KEY ("organizationId", "employeeId") REFERENCES "employees"("organizationId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ads_microbatches" ADD CONSTRAINT "ads_microbatches_organizationId_trafficPoolId_fkey" FOREIGN KEY ("organizationId", "trafficPoolId") REFERENCES "traffic_pools"("organizationId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ads_microbatches" ADD CONSTRAINT "ads_microbatches_trafficPoolMemberId_fkey" FOREIGN KEY ("trafficPoolMemberId") REFERENCES "traffic_pool_members"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ads_microbatches" ADD CONSTRAINT "ads_microbatches_organizationId_whatsAppNumberId_fkey" FOREIGN KEY ("organizationId", "whatsAppNumberId") REFERENCES "whatsapp_numbers"("organizationId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;
