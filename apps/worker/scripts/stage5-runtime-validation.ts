import '../src/load-environment.js';

import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';

import { createDatabaseClient } from '@crm/database';

import { AdsSchedulerService } from '../src/ads-scheduler.service.js';

import type { AdsSchedulerConfig } from '../src/scheduler.config.js';

const employeeId = process.env.STAGE5_EMPLOYEE_ID?.trim();

if (!employeeId) {
  throw new Error('STAGE5_EMPLOYEE_ID is required.');
}

const database = createDatabaseClient();

const organizationSlug = process.env.SEED_ORGANIZATION_SLUG?.trim() || 'crm-ads-whatsapp';

const unique = randomUUID().replaceAll('-', '').slice(0, 16);

const config: AdsSchedulerConfig = {
  intervalMs: 100,
  microbatchSize: 5,
  maxInflightPerEmployee: 35,
  leaseMs: 30_000,
  backpressureDelayMs: 60_000,
  microbatchYieldMs: 0,
  maxClaimsPerTick: 25,
  maxQueueAttempts: 25,
};

function event(name: string, extra: Record<string, unknown> = {}): void {
  console.log(
    JSON.stringify({
      event: name,
      timestamp: new Date().toISOString(),
      ...extra,
    }),
  );
}

async function createPool(label: string, memberCount: number) {
  const organization = await database.organization.findUniqueOrThrow({
    where: {
      slug: organizationSlug,
    },
  });

  const employee = await database.employee.findFirstOrThrow({
    where: {
      id: employeeId,
      organizationId: organization.id,
      status: 'ACTIVE',
      deletedAt: null,
    },
  });

  const site = await database.site.create({
    data: {
      organizationId: organization.id,
      ownerEmployeeId: employee.id,
      name: `Stage5 ${label}`,
      slug: `stage5-${label}-${unique}`.toLowerCase(),
      status: 'ACTIVE',
    },
  });

  const pool = await database.trafficPool.create({
    data: {
      organizationId: organization.id,
      siteId: site.id,
      name: `Stage5 ${label} Pool`,
      slug: `stage5-${label}-pool-${unique}`.toLowerCase(),
      status: 'ACTIVE',
    },
  });

  const numberIds: string[] = [];

  for (let index = 0; index < memberCount; index += 1) {
    const number = await database.whatsAppNumber.create({
      data: {
        organizationId: organization.id,
        assignedEmployeeId: employee.id,
        displayName: `Stage5 ${label} Number ${index + 1}`,
        e164: `+1999${Date.now()}${index}${Math.floor(Math.random() * 1000)}`,
        status: 'ACTIVE',
      },
    });

    numberIds.push(number.id);

    await database.trafficPoolMember.create({
      data: {
        organizationId: organization.id,
        trafficPoolId: pool.id,
        whatsAppNumberId: number.id,
        position: index + 1,
        status: 'ACTIVE',
      },
    });
  }

  return {
    organization,
    employee,
    site,
    pool,
    numberIds,
  };
}

async function createRequest(
  organizationId: string,
  employeeIdValue: string,
  userId: string,
  siteId: string,
  poolId: string,
  leadCount: number,
) {
  return database.$transaction(async (transaction) => {
    const request = await transaction.adsRequest.create({
      data: {
        organizationId,
        employeeId: employeeIdValue,
        siteId,
        trafficPoolId: poolId,
        requestedByUserId: userId,
        requestedLeadCount: leadCount,
      },
    });

    const queueItem = await transaction.adsQueueItem.create({
      data: {
        organizationId,
        adsRequestId: request.id,
        employeeId: employeeIdValue,
        trafficPoolId: poolId,
      },
    });

    return {
      request,
      queueItem,
    };
  });
}

try {
  event('stage5.validation.started');

  const staleValidationRequests = await database.adsRequest.findMany({
    where: {
      employeeId,
      site: {
        slug: {
          startsWith: 'stage5-',
        },
      },
    },
    select: {
      id: true,
    },
  });

  const staleValidationRequestIds = staleValidationRequests.map((request) => request.id);

  if (staleValidationRequestIds.length > 0) {
    const cleanupAt = new Date();

    await database.adsMicrobatch.updateMany({
      where: {
        adsRequestId: {
          in: staleValidationRequestIds,
        },
        status: {
          in: ['PLANNED', 'DELIVERING'],
        },
      },
      data: {
        status: 'CANCELLED',
        cancelledAt: cleanupAt,
      },
    });

    await database.adsQueueItem.updateMany({
      where: {
        adsRequestId: {
          in: staleValidationRequestIds,
        },
        status: {
          in: ['WAITING', 'CLAIMED'],
        },
      },
      data: {
        status: 'CANCELLED',
        cancelledAt: cleanupAt,
        claimedAt: null,
        claimedByWorkerId: null,
        leaseExpiresAt: null,
      },
    });

    await database.adsRequest.updateMany({
      where: {
        id: {
          in: staleValidationRequestIds,
        },
        status: {
          in: ['QUEUED', 'PROCESSING', 'PARTIALLY_FULFILLED'],
        },
      },
      data: {
        status: 'CANCELLED',
        cancelledAt: cleanupAt,
      },
    });

    event('stage5.validation.cleanup', {
      requests: staleValidationRequestIds.length,
    });
  }

  const roundRobinPool = await createPool('round-robin', 3);

  const roundRobinRequest = await createRequest(
    roundRobinPool.organization.id,
    roundRobinPool.employee.id,
    roundRobinPool.employee.userId,
    roundRobinPool.site.id,
    roundRobinPool.pool.id,
    30,
  );

  const scheduler = new AdsSchedulerService(database, `stage5-validator-${unique}`, config);

  const firstSummary = await scheduler.runTick();

  const roundRobinState = await database.adsRequest.findUniqueOrThrow({
    where: {
      id: roundRobinRequest.request.id,
    },
  });

  const roundRobinQueue = await database.adsQueueItem.findUniqueOrThrow({
    where: {
      id: roundRobinRequest.queueItem.id,
    },
  });

  const roundRobinBatches = await database.adsMicrobatch.findMany({
    where: {
      adsRequestId: roundRobinRequest.request.id,
    },

    orderBy: {
      sequence: 'asc',
    },
  });

  assert.equal(roundRobinState.scheduledLeadCount, 30);

  assert.equal(roundRobinState.status, 'PROCESSING');

  assert.equal(roundRobinQueue.status, 'COMPLETED');

  assert.equal(roundRobinBatches.length, 6);

  const expectedRoundRobin = [
    roundRobinPool.numberIds[0],
    roundRobinPool.numberIds[1],
    roundRobinPool.numberIds[2],
    roundRobinPool.numberIds[0],
    roundRobinPool.numberIds[1],
    roundRobinPool.numberIds[2],
  ];

  assert.deepEqual(
    roundRobinBatches.map((batch) => batch.whatsAppNumberId),
    expectedRoundRobin,
  );

  assert.deepEqual(
    roundRobinBatches.map((batch) => batch.reservedLeadCount),
    [5, 5, 5, 5, 5, 5],
  );

  event('stage5.round_robin.passed', {
    firstSummary,
    batches: roundRobinBatches.length,
  });

  const backpressureRequest = await createRequest(
    roundRobinPool.organization.id,
    roundRobinPool.employee.id,
    roundRobinPool.employee.userId,
    roundRobinPool.site.id,
    roundRobinPool.pool.id,
    20,
  );

  await scheduler.runTick();

  const backpressureState = await database.adsRequest.findUniqueOrThrow({
    where: {
      id: backpressureRequest.request.id,
    },
  });

  const backpressureQueue = await database.adsQueueItem.findUniqueOrThrow({
    where: {
      id: backpressureRequest.queueItem.id,
    },
  });

  assert.equal(backpressureState.scheduledLeadCount, 5);

  assert.equal(backpressureQueue.status, 'WAITING');

  event('stage5.backpressure.passed', {
    scheduledLeadCount: backpressureState.scheduledLeadCount,
  });

  await database.adsMicrobatch.updateMany({
    where: {
      adsRequestId: roundRobinRequest.request.id,
    },

    data: {
      status: 'COMPLETED',
      deliveredLeadCount: 5,
      completedAt: new Date(),
    },
  });

  await database.adsQueueItem.update({
    where: {
      id: backpressureRequest.queueItem.id,
    },

    data: {
      availableAt: new Date(0),
    },
  });

  await scheduler.runTick();

  const backpressureCompleted = await database.adsRequest.findUniqueOrThrow({
    where: {
      id: backpressureRequest.request.id,
    },
  });

  const backpressureQueueCompleted = await database.adsQueueItem.findUniqueOrThrow({
    where: {
      id: backpressureRequest.queueItem.id,
    },
  });

  assert.equal(backpressureCompleted.scheduledLeadCount, 20);

  assert.equal(backpressureQueueCompleted.status, 'COMPLETED');

  event('stage5.backpressure_recovery.passed');

  await database.adsMicrobatch.updateMany({
    where: {
      adsRequestId: backpressureRequest.request.id,
    },

    data: {
      status: 'COMPLETED',
      deliveredLeadCount: 5,
      completedAt: new Date(),
    },
  });

  const concurrencyPool = await createPool('concurrency', 2);

  const concurrencyRequest = await createRequest(
    concurrencyPool.organization.id,
    concurrencyPool.employee.id,
    concurrencyPool.employee.userId,
    concurrencyPool.site.id,
    concurrencyPool.pool.id,
    10,
  );

  const concurrencyConfig: AdsSchedulerConfig = {
    ...config,
    microbatchSize: 10,
    maxInflightPerEmployee: 1000,
  };

  const workerA = new AdsSchedulerService(database, `stage5-worker-a-${unique}`, concurrencyConfig);

  const workerB = new AdsSchedulerService(database, `stage5-worker-b-${unique}`, concurrencyConfig);

  await Promise.all([workerA.runTick(), workerB.runTick()]);

  const concurrencyState = await database.adsRequest.findUniqueOrThrow({
    where: {
      id: concurrencyRequest.request.id,
    },
  });

  const concurrencyBatches = await database.adsMicrobatch.findMany({
    where: {
      adsRequestId: concurrencyRequest.request.id,
    },
  });

  assert.equal(concurrencyState.scheduledLeadCount, 10);

  assert.equal(concurrencyBatches.length, 1);

  event('stage5.concurrent_claim.passed', {
    microbatches: concurrencyBatches.length,
  });

  await database.adsMicrobatch.updateMany({
    where: {
      adsRequestId: concurrencyRequest.request.id,
    },

    data: {
      status: 'COMPLETED',
      deliveredLeadCount: 10,
      completedAt: new Date(),
    },
  });

  const leasePool = await createPool('lease', 1);

  const leaseRequest = await createRequest(
    leasePool.organization.id,
    leasePool.employee.id,
    leasePool.employee.userId,
    leasePool.site.id,
    leasePool.pool.id,
    5,
  );

  await database.adsQueueItem.update({
    where: {
      id: leaseRequest.queueItem.id,
    },

    data: {
      status: 'CLAIMED',
      claimedAt: new Date(Date.now() - 60_000),
      claimedByWorkerId: 'dead-stage5-worker',
      leaseExpiresAt: new Date(Date.now() - 30_000),
      attempts: 1,
    },
  });

  const leaseScheduler = new AdsSchedulerService(database, `stage5-lease-worker-${unique}`, {
    ...config,
    maxInflightPerEmployee: 1000,
  });

  await leaseScheduler.runTick();

  const recoveredRequest = await database.adsRequest.findUniqueOrThrow({
    where: {
      id: leaseRequest.request.id,
    },
  });

  const recoveredQueue = await database.adsQueueItem.findUniqueOrThrow({
    where: {
      id: leaseRequest.queueItem.id,
    },
  });

  assert.equal(recoveredRequest.scheduledLeadCount, 5);

  assert.equal(recoveredQueue.status, 'COMPLETED');

  assert.ok(recoveredQueue.attempts >= 2);

  event('stage5.lease_recovery.passed', {
    attempts: recoveredQueue.attempts,
  });

  const plannedAuditCount = await database.auditLog.count({
    where: {
      organizationId: roundRobinPool.organization.id,
      action: 'ads_microbatch.planned',
    },
  });

  assert.ok(plannedAuditCount >= 1);

  event('stage5.audit.passed', {
    plannedAuditCount,
  });

  event('stage5.validation.completed');
} finally {
  await database.$disconnect();
}
