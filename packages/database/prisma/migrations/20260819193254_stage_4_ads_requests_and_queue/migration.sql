-- CreateEnum
CREATE TYPE "AdsRequestStatus" AS ENUM ('QUEUED', 'PROCESSING', 'PARTIALLY_FULFILLED', 'FULFILLED', 'CANCELLED', 'FAILED');

-- CreateEnum
CREATE TYPE "AdsQueueItemStatus" AS ENUM ('WAITING', 'CLAIMED', 'COMPLETED', 'CANCELLED', 'FAILED');

-- CreateTable
CREATE TABLE "ads_requests" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "employeeId" UUID NOT NULL,
    "siteId" UUID NOT NULL,
    "trafficPoolId" UUID NOT NULL,
    "requestedByUserId" UUID NOT NULL,
    "requestedLeadCount" INTEGER NOT NULL,
    "fulfilledLeadCount" INTEGER NOT NULL DEFAULT 0,
    "status" "AdsRequestStatus" NOT NULL DEFAULT 'QUEUED',
    "notes" VARCHAR(500),
    "queuedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "startedAt" TIMESTAMPTZ(3),
    "completedAt" TIMESTAMPTZ(3),
    "cancelledAt" TIMESTAMPTZ(3),
    "failureReason" VARCHAR(500),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "whatsAppNumberId" UUID,

    CONSTRAINT "ads_requests_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ads_queue_items" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "adsRequestId" UUID NOT NULL,
    "employeeId" UUID NOT NULL,
    "trafficPoolId" UUID NOT NULL,
    "status" "AdsQueueItemStatus" NOT NULL DEFAULT 'WAITING',
    "priority" INTEGER NOT NULL DEFAULT 100,
    "enqueuedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "availableAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "claimedAt" TIMESTAMPTZ(3),
    "completedAt" TIMESTAMPTZ(3),
    "cancelledAt" TIMESTAMPTZ(3),
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "whatsAppNumberId" UUID,

    CONSTRAINT "ads_queue_items_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "ads_requests_organizationId_employeeId_status_idx" ON "ads_requests"("organizationId", "employeeId", "status");

-- CreateIndex
CREATE INDEX "ads_requests_organizationId_siteId_status_idx" ON "ads_requests"("organizationId", "siteId", "status");

-- CreateIndex
CREATE INDEX "ads_requests_organizationId_trafficPoolId_status_idx" ON "ads_requests"("organizationId", "trafficPoolId", "status");

-- CreateIndex
CREATE INDEX "ads_requests_organizationId_status_queuedAt_idx" ON "ads_requests"("organizationId", "status", "queuedAt");

-- CreateIndex
CREATE UNIQUE INDEX "ads_requests_organizationId_id_key" ON "ads_requests"("organizationId", "id");

-- CreateIndex
CREATE INDEX "ads_queue_items_organizationId_status_priority_availableAt__idx" ON "ads_queue_items"("organizationId", "status", "priority", "availableAt", "enqueuedAt");

-- CreateIndex
CREATE INDEX "ads_queue_items_organizationId_employeeId_status_idx" ON "ads_queue_items"("organizationId", "employeeId", "status");

-- CreateIndex
CREATE INDEX "ads_queue_items_organizationId_trafficPoolId_status_idx" ON "ads_queue_items"("organizationId", "trafficPoolId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "ads_queue_items_organizationId_id_key" ON "ads_queue_items"("organizationId", "id");

-- CreateIndex
CREATE UNIQUE INDEX "ads_queue_items_organizationId_adsRequestId_key" ON "ads_queue_items"("organizationId", "adsRequestId");

-- AddForeignKey
ALTER TABLE "ads_requests" ADD CONSTRAINT "ads_requests_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ads_requests" ADD CONSTRAINT "ads_requests_organizationId_employeeId_fkey" FOREIGN KEY ("organizationId", "employeeId") REFERENCES "employees"("organizationId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ads_requests" ADD CONSTRAINT "ads_requests_organizationId_siteId_fkey" FOREIGN KEY ("organizationId", "siteId") REFERENCES "sites"("organizationId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ads_requests" ADD CONSTRAINT "ads_requests_organizationId_trafficPoolId_fkey" FOREIGN KEY ("organizationId", "trafficPoolId") REFERENCES "traffic_pools"("organizationId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ads_requests" ADD CONSTRAINT "ads_requests_organizationId_requestedByUserId_fkey" FOREIGN KEY ("organizationId", "requestedByUserId") REFERENCES "users"("organizationId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ads_requests" ADD CONSTRAINT "ads_requests_whatsAppNumberId_fkey" FOREIGN KEY ("whatsAppNumberId") REFERENCES "whatsapp_numbers"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ads_queue_items" ADD CONSTRAINT "ads_queue_items_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ads_queue_items" ADD CONSTRAINT "ads_queue_items_organizationId_adsRequestId_fkey" FOREIGN KEY ("organizationId", "adsRequestId") REFERENCES "ads_requests"("organizationId", "id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ads_queue_items" ADD CONSTRAINT "ads_queue_items_organizationId_employeeId_fkey" FOREIGN KEY ("organizationId", "employeeId") REFERENCES "employees"("organizationId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ads_queue_items" ADD CONSTRAINT "ads_queue_items_organizationId_trafficPoolId_fkey" FOREIGN KEY ("organizationId", "trafficPoolId") REFERENCES "traffic_pools"("organizationId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ads_queue_items" ADD CONSTRAINT "ads_queue_items_whatsAppNumberId_fkey" FOREIGN KEY ("whatsAppNumberId") REFERENCES "whatsapp_numbers"("id") ON DELETE SET NULL ON UPDATE CASCADE;
