import '../src/load-environment.js';

import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';

import { createDatabaseClient } from '@crm/database';

import { AdsSchedulerService } from '../../worker/src/ads-scheduler.service.js';

import type { AdsSchedulerConfig } from '../../worker/src/scheduler.config.js';

import { probeHostname, type SiteProbeResult } from '../src/safe-probe.js';

import { SiteMonitorService, type SiteProbe } from '../src/site-monitor.service.js';

import type { SiteMonitorConfig } from '../src/site-monitor.config.js';

const employeeId = process.env.STAGE6_EMPLOYEE_ID?.trim();

if (!employeeId) {
  throw new Error('STAGE6_EMPLOYEE_ID is required.');
}

const database = createDatabaseClient();

const organizationSlug = process.env.SEED_ORGANIZATION_SLUG?.trim() || 'crm-ads-whatsapp';

const unique = randomUUID().replaceAll('-', '').slice(0, 16);

const fixturePrefix = 'stage6-runtime-';

const monitorConfig: SiteMonitorConfig = {
  tickIntervalMs: 100,
  checkIntervalMs: 60_000,
  retryDelayMs: 60_000,
  timeoutMs: 1_000,
  leaseMs: 30_000,
  failureThreshold: 3,
  recoveryThreshold: 2,
  concurrency: 1,
  maxClaimsPerTick: 1,
  stateSyncIntervalMs: 3_600_000,
  checkRetentionDays: 14,
  cleanupIntervalMs: 86_400_000,
};

const schedulerConfig: AdsSchedulerConfig = {
  intervalMs: 100,
  microbatchSize: 5,
  maxInflightPerEmployee: 1_000_000,
  leaseMs: 30_000,
  backpressureDelayMs: 60_000,
  microbatchYieldMs: 0,
  maxClaimsPerTick: 1,
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

async function cleanupFixtures(): Promise<void> {
  const sites = await database.site.findMany({
    where: {
      ownerEmployeeId: employeeId,

      slug: {
        startsWith: fixturePrefix,
      },
    },

    select: {
      id: true,
    },
  });

  for (const site of sites) {
    const requests = await database.adsRequest.findMany({
      where: {
        siteId: site.id,
      },

      select: {
        id: true,
      },
    });

    const requestIds = requests.map((request) => request.id);

    const pools = await database.trafficPool.findMany({
      where: {
        siteId: site.id,
      },

      select: {
        id: true,
      },
    });

    const poolIds = pools.map((pool) => pool.id);

    const members =
      poolIds.length > 0
        ? await database.trafficPoolMember.findMany({
            where: {
              trafficPoolId: {
                in: poolIds,
              },
            },

            select: {
              whatsAppNumberId: true,
            },
          })
        : [];

    const numberIds = [...new Set(members.map((member) => member.whatsAppNumberId))];

    if (requestIds.length > 0) {
      const microbatches = await database.adsMicrobatch.findMany({
        where: {
          adsRequestId: {
            in: requestIds,
          },
        },

        select: {
          id: true,
        },
      });

      const queueItems = await database.adsQueueItem.findMany({
        where: {
          adsRequestId: {
            in: requestIds,
          },
        },

        select: {
          id: true,
        },
      });

      const auditResourceIds = [
        ...requestIds,
        ...microbatches.map((item) => item.id),
        ...queueItems.map((item) => item.id),
      ];

      if (auditResourceIds.length > 0) {
        await database.auditLog.deleteMany({
          where: {
            resourceId: {
              in: auditResourceIds,
            },
          },
        });
      }

      await database.adsMicrobatch.deleteMany({
        where: {
          adsRequestId: {
            in: requestIds,
          },
        },
      });

      await database.adsQueueItem.deleteMany({
        where: {
          adsRequestId: {
            in: requestIds,
          },
        },
      });

      await database.adsRequest.deleteMany({
        where: {
          id: {
            in: requestIds,
          },
        },
      });
    }

    const domains = await database.siteDomain.findMany({
      where: {
        siteId: site.id,
      },

      select: {
        id: true,
      },
    });

    const domainIds = domains.map((domain) => domain.id);

    if (domainIds.length > 0) {
      await database.auditLog.deleteMany({
        where: {
          resourceId: {
            in: domainIds,
          },
        },
      });

      await database.siteMonitorCheck.deleteMany({
        where: {
          siteDomainId: {
            in: domainIds,
          },
        },
      });

      await database.siteMonitorIncident.deleteMany({
        where: {
          siteDomainId: {
            in: domainIds,
          },
        },
      });

      await database.siteMonitorState.deleteMany({
        where: {
          siteDomainId: {
            in: domainIds,
          },
        },
      });

      await database.siteDomain.deleteMany({
        where: {
          id: {
            in: domainIds,
          },
        },
      });
    }

    if (poolIds.length > 0) {
      await database.trafficPoolMember.deleteMany({
        where: {
          trafficPoolId: {
            in: poolIds,
          },
        },
      });

      await database.trafficPoolSchedulerState.deleteMany({
        where: {
          trafficPoolId: {
            in: poolIds,
          },
        },
      });

      await database.trafficPool.deleteMany({
        where: {
          id: {
            in: poolIds,
          },
        },
      });
    }

    if (numberIds.length > 0) {
      await database.whatsAppNumber.deleteMany({
        where: {
          id: {
            in: numberIds,
          },
        },
      });
    }

    await database.site.delete({
      where: {
        id: site.id,
      },
    });
  }
}

function failureProbe(code: string): SiteProbeResult {
  return {
    success: false,
    httpStatus: null,
    latencyMs: 25,
    resolvedAddress: '8.8.8.8',
    failureCode: code,
    failureMessage: `Simulated ${code}`,
  };
}

function successProbe(): SiteProbeResult {
  return {
    success: true,
    httpStatus: 200,
    latencyMs: 20,
    resolvedAddress: '8.8.8.8',
    failureCode: null,
    failureMessage: null,
  };
}

async function forceDue(siteDomainId: string): Promise<void> {
  await database.siteMonitorState.update({
    where: {
      organizationId_siteDomainId: {
        organizationId: organization.id,

        siteDomainId,
      },
    },

    data: {
      nextCheckAt: new Date(0),

      claimedAt: null,
      claimedByWorkerId: null,
      leaseExpiresAt: null,
    },
  });
}

let organization: Awaited<ReturnType<typeof database.organization.findUniqueOrThrow>>;

try {
  event('stage6.validation.started');

  await cleanupFixtures();

  organization = await database.organization.findUniqueOrThrow({
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

      name: 'Stage 6 Runtime Site',

      slug: `${fixturePrefix}${unique}`,

      status: 'ACTIVE',
    },
  });

  const primaryDomain = await database.siteDomain.create({
    data: {
      organizationId: organization.id,

      siteId: site.id,

      hostname: `stage6-${unique}.example.com`,

      status: 'ACTIVE',
      isPrimary: true,
      monitoringEnabled: true,
    },
  });

  await database.siteMonitorState.create({
    data: {
      organizationId: organization.id,

      siteId: site.id,

      siteDomainId: primaryDomain.id,

      nextCheckAt: new Date(0),
    },
  });

  const probeSequence: SiteProbeResult[] = [
    failureProbe('SIMULATED_1'),
    failureProbe('SIMULATED_2'),
    failureProbe('SIMULATED_3'),
    successProbe(),
    successProbe(),
    successProbe(),
  ];

  const deterministicProbe: SiteProbe = async () => {
    const result = probeSequence.shift();

    if (!result) {
      return successProbe();
    }

    return result;
  };

  const monitor = new SiteMonitorService(
    database,
    `stage6-monitor-${unique}`,
    monitorConfig,
    deterministicProbe,
    primaryDomain.id,
  );

  await monitor.runTick();

  let state = await database.siteMonitorState.findUniqueOrThrow({
    where: {
      organizationId_siteDomainId: {
        organizationId: organization.id,

        siteDomainId: primaryDomain.id,
      },
    },
  });

  assert.equal(state.status, 'DEGRADED');

  assert.equal(state.consecutiveFailures, 1);

  assert.equal(
    await database.siteMonitorIncident.count({
      where: {
        siteDomainId: primaryDomain.id,

        status: 'OPEN',
      },
    }),
    0,
  );

  event('stage6.first_failure.passed');

  await forceDue(primaryDomain.id);

  await monitor.runTick();

  state = await database.siteMonitorState.findUniqueOrThrow({
    where: {
      organizationId_siteDomainId: {
        organizationId: organization.id,

        siteDomainId: primaryDomain.id,
      },
    },
  });

  assert.equal(state.status, 'DEGRADED');

  assert.equal(state.consecutiveFailures, 2);

  await forceDue(primaryDomain.id);

  await monitor.runTick();

  state = await database.siteMonitorState.findUniqueOrThrow({
    where: {
      organizationId_siteDomainId: {
        organizationId: organization.id,

        siteDomainId: primaryDomain.id,
      },
    },
  });

  assert.equal(state.status, 'DOWN');

  assert.equal(state.consecutiveFailures, 3);

  assert.ok(state.downSince);

  const openIncident = await database.siteMonitorIncident.findFirstOrThrow({
    where: {
      siteDomainId: primaryDomain.id,

      status: 'OPEN',
    },
  });

  assert.equal(openIncident.openedAfterFailures, 3);

  event('stage6.down_incident.passed', {
    incidentId: openIncident.id,
  });

  const downAudit = await database.auditLog.count({
    where: {
      action: 'site_monitor.down',

      resourceId: primaryDomain.id,
    },
  });

  assert.ok(downAudit >= 1);

  await forceDue(primaryDomain.id);

  await monitor.runTick();

  state = await database.siteMonitorState.findUniqueOrThrow({
    where: {
      organizationId_siteDomainId: {
        organizationId: organization.id,

        siteDomainId: primaryDomain.id,
      },
    },
  });

  assert.equal(state.status, 'DEGRADED');

  assert.equal(state.consecutiveSuccesses, 1);

  assert.equal(
    await database.siteMonitorIncident.count({
      where: {
        siteDomainId: primaryDomain.id,

        status: 'OPEN',
      },
    }),
    1,
  );

  event('stage6.partial_recovery.passed');

  await forceDue(primaryDomain.id);

  await monitor.runTick();

  state = await database.siteMonitorState.findUniqueOrThrow({
    where: {
      organizationId_siteDomainId: {
        organizationId: organization.id,

        siteDomainId: primaryDomain.id,
      },
    },
  });

  assert.equal(state.status, 'HEALTHY');

  assert.equal(state.consecutiveSuccesses, 2);

  assert.equal(state.downSince, null);

  assert.ok(state.recoveredAt);

  const resolvedIncident = await database.siteMonitorIncident.findUniqueOrThrow({
    where: {
      id: openIncident.id,
    },
  });

  assert.equal(resolvedIncident.status, 'RESOLVED');

  assert.ok(resolvedIncident.resolvedAt);

  const recoveryAudit = await database.auditLog.count({
    where: {
      action: 'site_monitor.recovered',

      resourceId: primaryDomain.id,
    },
  });

  assert.ok(recoveryAudit >= 1);

  event('stage6.recovery.passed');

  const lifecycleChecks = await database.siteMonitorCheck.findMany({
    where: {
      siteDomainId: primaryDomain.id,
    },

    orderBy: {
      checkedAt: 'asc',
    },
  });

  assert.equal(lifecycleChecks.length, 5);

  assert.deepEqual(
    lifecycleChecks.map((check) => check.statusAfter),
    ['DEGRADED', 'DEGRADED', 'DOWN', 'DEGRADED', 'HEALTHY'],
  );

  event('stage6.history.passed', {
    checks: lifecycleChecks.length,
  });

  const ssrfResult = await probeHostname('localhost', 1_000);

  assert.equal(ssrfResult.success, false);

  assert.equal(ssrfResult.failureCode, 'SECURITY_BLOCKED_ADDRESS');

  event('stage6.ssrf.passed');

  await database.siteMonitorState.update({
    where: {
      organizationId_siteDomainId: {
        organizationId: organization.id,

        siteDomainId: primaryDomain.id,
      },
    },

    data: {
      status: 'HEALTHY',

      nextCheckAt: new Date(Date.now() + 3_600_000),

      claimedAt: new Date(Date.now() - 60_000),

      claimedByWorkerId: 'dead-stage6-worker',

      leaseExpiresAt: new Date(Date.now() - 30_000),
    },
  });

  const checksBeforeLeaseRecovery = await database.siteMonitorCheck.count({
    where: {
      siteDomainId: primaryDomain.id,
    },
  });

  await monitor.runTick();

  const checksAfterLeaseRecovery = await database.siteMonitorCheck.count({
    where: {
      siteDomainId: primaryDomain.id,
    },
  });

  assert.equal(checksAfterLeaseRecovery, checksBeforeLeaseRecovery + 1);

  const recoveredLeaseState = await database.siteMonitorState.findUniqueOrThrow({
    where: {
      organizationId_siteDomainId: {
        organizationId: organization.id,

        siteDomainId: primaryDomain.id,
      },
    },
  });

  assert.equal(recoveredLeaseState.claimedByWorkerId, null);

  assert.equal(recoveredLeaseState.leaseExpiresAt, null);

  event('stage6.lease_recovery.passed');

  const secondaryDomain = await database.siteDomain.create({
    data: {
      organizationId: organization.id,

      siteId: site.id,

      hostname: `stage6-concurrency-${unique}.example.com`,

      status: 'ACTIVE',
      isPrimary: false,
      monitoringEnabled: true,
    },
  });

  await database.siteMonitorState.create({
    data: {
      organizationId: organization.id,

      siteId: site.id,

      siteDomainId: secondaryDomain.id,

      nextCheckAt: new Date(0),
    },
  });

  let concurrentProbeCalls = 0;

  const concurrentProbe: SiteProbe = async () => {
    concurrentProbeCalls += 1;

    await new Promise<void>((resolve) => {
      setTimeout(resolve, 150);
    });

    return successProbe();
  };

  const monitorA = new SiteMonitorService(
    database,
    `stage6-a-${unique}`,
    monitorConfig,
    concurrentProbe,
    secondaryDomain.id,
  );

  const monitorB = new SiteMonitorService(
    database,
    `stage6-b-${unique}`,
    monitorConfig,
    concurrentProbe,
    secondaryDomain.id,
  );

  await Promise.all([monitorA.runTick(), monitorB.runTick()]);

  const concurrentChecks = await database.siteMonitorCheck.count({
    where: {
      siteDomainId: secondaryDomain.id,
    },
  });

  assert.equal(concurrentChecks, 1);

  assert.equal(concurrentProbeCalls, 1);

  event('stage6.concurrent_claim.passed');

  const pool = await database.trafficPool.create({
    data: {
      organizationId: organization.id,

      siteId: site.id,

      name: 'Stage 6 Scheduler Pool',

      slug: `stage6-pool-${unique}`,

      status: 'ACTIVE',
    },
  });

  const whatsAppNumber = await database.whatsAppNumber.create({
    data: {
      organizationId: organization.id,

      assignedEmployeeId: employee.id,

      displayName: 'Stage 6 Scheduler Number',

      e164: `+1998${Date.now().toString().slice(-10)}`,

      status: 'ACTIVE',
    },
  });

  await database.trafficPoolMember.create({
    data: {
      organizationId: organization.id,

      trafficPoolId: pool.id,

      whatsAppNumberId: whatsAppNumber.id,

      position: 1,
      status: 'ACTIVE',
    },
  });

  const requestAndQueue = await database.$transaction(async (transaction) => {
    const request = await transaction.adsRequest.create({
      data: {
        organizationId: organization.id,

        employeeId: employee.id,

        siteId: site.id,

        trafficPoolId: pool.id,

        requestedByUserId: employee.userId,

        requestedLeadCount: 5,
      },
    });

    const queue = await transaction.adsQueueItem.create({
      data: {
        organizationId: organization.id,

        adsRequestId: request.id,

        employeeId: employee.id,

        trafficPoolId: pool.id,

        priority: -1_000_000,

        availableAt: new Date(0),
      },
    });

    return {
      request,
      queue,
    };
  });

  await database.siteMonitorState.update({
    where: {
      organizationId_siteDomainId: {
        organizationId: organization.id,

        siteDomainId: primaryDomain.id,
      },
    },

    data: {
      status: 'DOWN',
      downSince: new Date(),
      nextCheckAt: new Date(Date.now() + 3_600_000),
    },
  });

  const scheduler = new AdsSchedulerService(
    database,
    `stage6-scheduler-${unique}`,
    schedulerConfig,
  );

  await scheduler.runTick();

  let schedulerRequest = await database.adsRequest.findUniqueOrThrow({
    where: {
      id: requestAndQueue.request.id,
    },
  });

  let schedulerQueue = await database.adsQueueItem.findUniqueOrThrow({
    where: {
      id: requestAndQueue.queue.id,
    },
  });

  assert.equal(schedulerRequest.scheduledLeadCount, 0);

  assert.equal(schedulerQueue.status, 'WAITING');

  assert.equal(
    await database.adsMicrobatch.count({
      where: {
        adsRequestId: requestAndQueue.request.id,
      },
    }),
    0,
  );

  const siteDownQueueAudit = await database.auditLog.count({
    where: {
      action: 'ads_queue.site_down',

      resourceId: requestAndQueue.queue.id,
    },
  });

  assert.ok(siteDownQueueAudit >= 1);

  event('stage6.scheduler_blocked.passed');

  await database.siteMonitorState.update({
    where: {
      organizationId_siteDomainId: {
        organizationId: organization.id,

        siteDomainId: primaryDomain.id,
      },
    },

    data: {
      status: 'HEALTHY',
      downSince: null,
      recoveredAt: new Date(),
    },
  });

  await database.adsQueueItem.update({
    where: {
      id: requestAndQueue.queue.id,
    },

    data: {
      availableAt: new Date(0),
    },
  });

  await scheduler.runTick();

  schedulerRequest = await database.adsRequest.findUniqueOrThrow({
    where: {
      id: requestAndQueue.request.id,
    },
  });

  schedulerQueue = await database.adsQueueItem.findUniqueOrThrow({
    where: {
      id: requestAndQueue.queue.id,
    },
  });

  assert.equal(schedulerRequest.scheduledLeadCount, 5);

  assert.equal(schedulerRequest.status, 'PROCESSING');

  assert.equal(schedulerQueue.status, 'COMPLETED');

  assert.equal(
    await database.adsMicrobatch.count({
      where: {
        adsRequestId: requestAndQueue.request.id,
      },
    }),
    1,
  );

  event('stage6.scheduler_recovery.passed');

  event('stage6.validation.completed');
} finally {
  try {
    await cleanupFixtures();
  } finally {
    await database.$disconnect();
  }
}
