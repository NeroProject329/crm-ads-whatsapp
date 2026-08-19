/*
  Warnings:

  - A unique constraint covering the columns `[organizationId,id]` on the table `employees` will be added. If there are existing duplicate values, this will fail.

*/
-- CreateEnum
CREATE TYPE "SiteStatus" AS ENUM ('ACTIVE', 'PAUSED', 'ARCHIVED');

-- CreateEnum
CREATE TYPE "SiteDomainStatus" AS ENUM ('ACTIVE', 'PAUSED', 'ARCHIVED');

-- CreateEnum
CREATE TYPE "WhatsAppNumberStatus" AS ENUM ('ACTIVE', 'PAUSED', 'DISABLED', 'ARCHIVED');

-- CreateEnum
CREATE TYPE "TrafficPoolStatus" AS ENUM ('ACTIVE', 'PAUSED', 'ARCHIVED');

-- CreateEnum
CREATE TYPE "TrafficPoolMemberStatus" AS ENUM ('ACTIVE', 'PAUSED');

-- CreateTable
CREATE TABLE "sites" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "ownerEmployeeId" UUID NOT NULL,
    "name" VARCHAR(160) NOT NULL,
    "slug" VARCHAR(100) NOT NULL,
    "description" VARCHAR(500),
    "status" "SiteStatus" NOT NULL DEFAULT 'ACTIVE',
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "deletedAt" TIMESTAMPTZ(3),

    CONSTRAINT "sites_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "site_domains" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "siteId" UUID NOT NULL,
    "hostname" VARCHAR(253) NOT NULL,
    "status" "SiteDomainStatus" NOT NULL DEFAULT 'ACTIVE',
    "isPrimary" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "deletedAt" TIMESTAMPTZ(3),

    CONSTRAINT "site_domains_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "whatsapp_numbers" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "assignedEmployeeId" UUID,
    "displayName" VARCHAR(120) NOT NULL,
    "e164" VARCHAR(32) NOT NULL,
    "status" "WhatsAppNumberStatus" NOT NULL DEFAULT 'ACTIVE',
    "notes" VARCHAR(500),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "deletedAt" TIMESTAMPTZ(3),

    CONSTRAINT "whatsapp_numbers_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "traffic_pools" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "siteId" UUID NOT NULL,
    "name" VARCHAR(160) NOT NULL,
    "slug" VARCHAR(100) NOT NULL,
    "description" VARCHAR(500),
    "status" "TrafficPoolStatus" NOT NULL DEFAULT 'ACTIVE',
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "deletedAt" TIMESTAMPTZ(3),

    CONSTRAINT "traffic_pools_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "traffic_pool_members" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "trafficPoolId" UUID NOT NULL,
    "whatsAppNumberId" UUID NOT NULL,
    "position" INTEGER NOT NULL,
    "status" "TrafficPoolMemberStatus" NOT NULL DEFAULT 'ACTIVE',
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "traffic_pool_members_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "sites_organizationId_ownerEmployeeId_status_idx" ON "sites"("organizationId", "ownerEmployeeId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "sites_organizationId_id_key" ON "sites"("organizationId", "id");

-- CreateIndex
CREATE UNIQUE INDEX "sites_organizationId_slug_key" ON "sites"("organizationId", "slug");

-- CreateIndex
CREATE UNIQUE INDEX "site_domains_hostname_key" ON "site_domains"("hostname");

-- CreateIndex
CREATE INDEX "site_domains_organizationId_siteId_status_idx" ON "site_domains"("organizationId", "siteId", "status");

-- CreateIndex
CREATE INDEX "site_domains_organizationId_isPrimary_idx" ON "site_domains"("organizationId", "isPrimary");

-- CreateIndex
CREATE UNIQUE INDEX "site_domains_organizationId_id_key" ON "site_domains"("organizationId", "id");

-- CreateIndex
CREATE UNIQUE INDEX "whatsapp_numbers_e164_key" ON "whatsapp_numbers"("e164");

-- CreateIndex
CREATE INDEX "whatsapp_numbers_organizationId_assignedEmployeeId_status_idx" ON "whatsapp_numbers"("organizationId", "assignedEmployeeId", "status");

-- CreateIndex
CREATE INDEX "whatsapp_numbers_organizationId_status_idx" ON "whatsapp_numbers"("organizationId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "whatsapp_numbers_organizationId_id_key" ON "whatsapp_numbers"("organizationId", "id");

-- CreateIndex
CREATE INDEX "traffic_pools_organizationId_siteId_status_idx" ON "traffic_pools"("organizationId", "siteId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "traffic_pools_organizationId_id_key" ON "traffic_pools"("organizationId", "id");

-- CreateIndex
CREATE UNIQUE INDEX "traffic_pools_organizationId_slug_key" ON "traffic_pools"("organizationId", "slug");

-- CreateIndex
CREATE INDEX "traffic_pool_members_organizationId_whatsAppNumberId_status_idx" ON "traffic_pool_members"("organizationId", "whatsAppNumberId", "status");

-- CreateIndex
CREATE INDEX "traffic_pool_members_organizationId_trafficPoolId_status_idx" ON "traffic_pool_members"("organizationId", "trafficPoolId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "traffic_pool_members_trafficPoolId_whatsAppNumberId_key" ON "traffic_pool_members"("trafficPoolId", "whatsAppNumberId");

-- CreateIndex
CREATE UNIQUE INDEX "traffic_pool_members_trafficPoolId_position_key" ON "traffic_pool_members"("trafficPoolId", "position");

-- CreateIndex
CREATE UNIQUE INDEX "employees_organizationId_id_key" ON "employees"("organizationId", "id");

-- AddForeignKey
ALTER TABLE "sites" ADD CONSTRAINT "sites_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sites" ADD CONSTRAINT "sites_organizationId_ownerEmployeeId_fkey" FOREIGN KEY ("organizationId", "ownerEmployeeId") REFERENCES "employees"("organizationId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "site_domains" ADD CONSTRAINT "site_domains_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "site_domains" ADD CONSTRAINT "site_domains_organizationId_siteId_fkey" FOREIGN KEY ("organizationId", "siteId") REFERENCES "sites"("organizationId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "whatsapp_numbers" ADD CONSTRAINT "whatsapp_numbers_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "whatsapp_numbers" ADD CONSTRAINT "whatsapp_numbers_organizationId_assignedEmployeeId_fkey" FOREIGN KEY ("organizationId", "assignedEmployeeId") REFERENCES "employees"("organizationId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "traffic_pools" ADD CONSTRAINT "traffic_pools_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "traffic_pools" ADD CONSTRAINT "traffic_pools_organizationId_siteId_fkey" FOREIGN KEY ("organizationId", "siteId") REFERENCES "sites"("organizationId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "traffic_pool_members" ADD CONSTRAINT "traffic_pool_members_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "traffic_pool_members" ADD CONSTRAINT "traffic_pool_members_organizationId_trafficPoolId_fkey" FOREIGN KEY ("organizationId", "trafficPoolId") REFERENCES "traffic_pools"("organizationId", "id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "traffic_pool_members" ADD CONSTRAINT "traffic_pool_members_organizationId_whatsAppNumberId_fkey" FOREIGN KEY ("organizationId", "whatsAppNumberId") REFERENCES "whatsapp_numbers"("organizationId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;
