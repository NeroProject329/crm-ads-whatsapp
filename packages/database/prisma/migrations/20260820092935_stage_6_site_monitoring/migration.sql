-- CreateEnum
CREATE TYPE "SiteMonitorStatus" AS ENUM ('UNKNOWN', 'HEALTHY', 'DEGRADED', 'DOWN');

-- CreateEnum
CREATE TYPE "SiteMonitorCheckOutcome" AS ENUM ('SUCCESS', 'FAILURE');

-- CreateEnum
CREATE TYPE "SiteMonitorIncidentStatus" AS ENUM ('OPEN', 'RESOLVED');

-- AlterTable
ALTER TABLE "site_domains" ADD COLUMN     "monitoringEnabled" BOOLEAN NOT NULL DEFAULT true;

-- CreateTable
CREATE TABLE "site_monitor_states" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "siteId" UUID NOT NULL,
    "siteDomainId" UUID NOT NULL,
    "status" "SiteMonitorStatus" NOT NULL DEFAULT 'UNKNOWN',
    "consecutiveFailures" INTEGER NOT NULL DEFAULT 0,
    "consecutiveSuccesses" INTEGER NOT NULL DEFAULT 0,
    "lastCheckedAt" TIMESTAMPTZ(3),
    "lastSuccessAt" TIMESTAMPTZ(3),
    "lastFailureAt" TIMESTAMPTZ(3),
    "lastHttpStatus" INTEGER,
    "lastLatencyMs" INTEGER,
    "lastResolvedAddress" VARCHAR(80),
    "lastFailureCode" VARCHAR(80),
    "lastFailureMessage" VARCHAR(500),
    "downSince" TIMESTAMPTZ(3),
    "recoveredAt" TIMESTAMPTZ(3),
    "nextCheckAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "claimedAt" TIMESTAMPTZ(3),
    "claimedByWorkerId" VARCHAR(120),
    "leaseExpiresAt" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "site_monitor_states_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "site_monitor_checks" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "siteId" UUID NOT NULL,
    "siteDomainId" UUID NOT NULL,
    "outcome" "SiteMonitorCheckOutcome" NOT NULL,
    "statusBefore" "SiteMonitorStatus" NOT NULL,
    "statusAfter" "SiteMonitorStatus" NOT NULL,
    "httpStatus" INTEGER,
    "latencyMs" INTEGER,
    "resolvedAddress" VARCHAR(80),
    "failureCode" VARCHAR(80),
    "failureMessage" VARCHAR(500),
    "checkedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "site_monitor_checks_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "site_monitor_incidents" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "siteId" UUID NOT NULL,
    "siteDomainId" UUID NOT NULL,
    "status" "SiteMonitorIncidentStatus" NOT NULL DEFAULT 'OPEN',
    "openedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "resolvedAt" TIMESTAMPTZ(3),
    "openedAfterFailures" INTEGER NOT NULL,
    "lastFailureCode" VARCHAR(80),
    "lastFailureMessage" VARCHAR(500),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "site_monitor_incidents_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "site_monitor_states_organizationId_status_nextCheckAt_idx" ON "site_monitor_states"("organizationId", "status", "nextCheckAt");

-- CreateIndex
CREATE INDEX "site_monitor_states_organizationId_leaseExpiresAt_idx" ON "site_monitor_states"("organizationId", "leaseExpiresAt");

-- CreateIndex
CREATE INDEX "site_monitor_states_siteId_status_idx" ON "site_monitor_states"("siteId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "site_monitor_states_organizationId_id_key" ON "site_monitor_states"("organizationId", "id");

-- CreateIndex
CREATE UNIQUE INDEX "site_monitor_states_organizationId_siteDomainId_key" ON "site_monitor_states"("organizationId", "siteDomainId");

-- CreateIndex
CREATE INDEX "site_monitor_checks_organizationId_siteDomainId_checkedAt_idx" ON "site_monitor_checks"("organizationId", "siteDomainId", "checkedAt");

-- CreateIndex
CREATE INDEX "site_monitor_checks_organizationId_siteId_checkedAt_idx" ON "site_monitor_checks"("organizationId", "siteId", "checkedAt");

-- CreateIndex
CREATE INDEX "site_monitor_checks_organizationId_outcome_checkedAt_idx" ON "site_monitor_checks"("organizationId", "outcome", "checkedAt");

-- CreateIndex
CREATE UNIQUE INDEX "site_monitor_checks_organizationId_id_key" ON "site_monitor_checks"("organizationId", "id");

-- CreateIndex
CREATE INDEX "site_monitor_incidents_organizationId_siteDomainId_status_o_idx" ON "site_monitor_incidents"("organizationId", "siteDomainId", "status", "openedAt");

-- CreateIndex
CREATE INDEX "site_monitor_incidents_organizationId_siteId_status_idx" ON "site_monitor_incidents"("organizationId", "siteId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "site_monitor_incidents_organizationId_id_key" ON "site_monitor_incidents"("organizationId", "id");

-- AddForeignKey
ALTER TABLE "site_monitor_states" ADD CONSTRAINT "site_monitor_states_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "site_monitor_states" ADD CONSTRAINT "site_monitor_states_organizationId_siteId_fkey" FOREIGN KEY ("organizationId", "siteId") REFERENCES "sites"("organizationId", "id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "site_monitor_states" ADD CONSTRAINT "site_monitor_states_organizationId_siteDomainId_fkey" FOREIGN KEY ("organizationId", "siteDomainId") REFERENCES "site_domains"("organizationId", "id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "site_monitor_checks" ADD CONSTRAINT "site_monitor_checks_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "site_monitor_checks" ADD CONSTRAINT "site_monitor_checks_organizationId_siteId_fkey" FOREIGN KEY ("organizationId", "siteId") REFERENCES "sites"("organizationId", "id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "site_monitor_checks" ADD CONSTRAINT "site_monitor_checks_organizationId_siteDomainId_fkey" FOREIGN KEY ("organizationId", "siteDomainId") REFERENCES "site_domains"("organizationId", "id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "site_monitor_incidents" ADD CONSTRAINT "site_monitor_incidents_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "site_monitor_incidents" ADD CONSTRAINT "site_monitor_incidents_organizationId_siteId_fkey" FOREIGN KEY ("organizationId", "siteId") REFERENCES "sites"("organizationId", "id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "site_monitor_incidents" ADD CONSTRAINT "site_monitor_incidents_organizationId_siteDomainId_fkey" FOREIGN KEY ("organizationId", "siteDomainId") REFERENCES "site_domains"("organizationId", "id") ON DELETE CASCADE ON UPDATE CASCADE;
