import '../src/load-environment.js';

import assert from 'node:assert/strict';

import { createHash, randomUUID } from 'node:crypto';

import { createDatabaseClient } from '@crm/database';

import { MetaCloudApiClient } from '@crm/meta-cloud-api';

import { AdsSchedulerService } from '../src/ads-scheduler.service.js';

import { WhatsAppInboxProcessorService } from '../src/whatsapp-inbox-processor.service.js';

import { WhatsAppNumberHealthSyncService } from '../src/whatsapp-number-health-sync.service.js';

import type { AdsSchedulerConfig } from '../src/scheduler.config.js';

import type { WhatsAppNumberHealthConfig } from '../src/whatsapp-number-health.config.js';

import type { WhatsAppRuntimeConfig } from '../src/whatsapp-runtime.config.js';

const database = createDatabaseClient();

const unique = randomUUID().replaceAll('-', '').slice(0, 12);

const organizationSlug = `stage11-runtime-${unique}`;

const schedulerConfig: AdsSchedulerConfig = {
  intervalMs: 1000,

  microbatchSize: 10,

  maxInflightPerEmployee: 100,

  leaseMs: 30000,

  backpressureDelayMs: 1000,

  microbatchYieldMs: 0,

  maxClaimsPerTick: 25,

  maxQueueAttempts: 25,
};

const inboxConfig: WhatsAppRuntimeConfig = {
  inboxIntervalMs: 1000,

  inboxLeaseMs: 30000,

  inboxMaxClaimsPerTick: 1,

  inboxMaxAttempts: 8,

  inboxRetryBaseMs: 1000,

  outboundIntervalMs: 1000,

  outboundLeaseMs: 30000,

  outboundMaxClaimsPerTick: 25,

  outboundMaxAttempts: 8,

  outboundRetryBaseMs: 2000,

  outboundDisabledRetryMs: 30000,
};

const healthConfig: WhatsAppNumberHealthConfig = {
  intervalMs: 1000,

  pollIntervalMs: 60000,

  failureRetryMs: 1000,

  leaseMs: 30000,

  maxClaimsPerTick: 1,

  recoveryHealthyChecks: 2,
};

function log(
  event: string,

  extra: Record<string, unknown> = {},
): void {
  console.log(
    JSON.stringify({
      event,

      timestamp: new Date().toISOString(),

      ...extra,
    }),
  );
}

function hashPayload(payload: unknown): string {
  return createHash('sha256').update(JSON.stringify(payload)).digest('hex');
}

function qualityPayload(
  input: Readonly<{
    wabaId: string;

    displayPhoneNumber: string;

    event: string;

    currentLimit: string;
  }>,
): Record<string, unknown> {
  return {
    object: 'whatsapp_business_account',

    entry: [
      {
        id: input.wabaId,

        changes: [
          {
            field: 'phone_number_quality_update',

            value: {
              display_phone_number: input.displayPhoneNumber,

              event: input.event,

              current_limit: input.currentLimit,
            },
          },
        ],
      },
    ],
  };
}

async function createQualityEnvelope(
  input: Readonly<{
    organizationId: string;

    whatsAppNumberId: string;

    wabaId: string;

    displayPhoneNumber: string;

    event: string;

    currentLimit: string;

    priorityOffset: number;
  }>,
): Promise<void> {
  const payload = qualityPayload({
    wabaId: input.wabaId,

    displayPhoneNumber: input.displayPhoneNumber,

    event: input.event,

    currentLimit: input.currentLimit,
  });

  await database.metaWebhookEnvelope.create({
    data: {
      organizationId: input.organizationId,

      whatsAppNumberId: input.whatsAppNumberId,

      object: 'whatsapp_business_account',

      field: 'phone_number_quality_update',

      wabaId: input.wabaId,

      payloadHash: hashPayload({
        payload,
        nonce: `${unique}-${input.priorityOffset}`,
      }),

      payload,

      status: 'RECEIVED',

      availableAt: new Date(input.priorityOffset),

      receivedAt: new Date(),
    },
  });
}

async function cleanup(): Promise<void> {
  const organization = await database.organization.findUnique({
    where: {
      slug: organizationSlug,
    },

    select: {
      id: true,
    },
  });

  if (!organization) {
    return;
  }

  const organizationId = organization.id;

  await database.auditLog.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.whatsAppNumberHealthEvent.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.whatsAppNumberIncident.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.whatsAppNumberHealthState.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.leadAttribution.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.lead.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.whatsAppMessageStatusEvent.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.whatsAppMessage.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.whatsAppConversation.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.whatsAppContact.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.metaWebhookEnvelope.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.adsMicrobatch.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.adsQueueItem.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.adsRequest.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.trafficPoolSchedulerState.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.trafficPoolMember.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.trafficPool.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.whatsAppNumber.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.siteMonitorCheck.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.siteMonitorIncident.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.siteMonitorState.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.siteDomain.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.site.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.session.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.userRole.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.employee.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.rolePermission.deleteMany({
    where: {
      role: {
        organizationId,
      },
    },
  });

  await database.role.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.user.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.team.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.organization.delete({
    where: {
      id: organizationId,
    },
  });
}

async function main(): Promise<void> {
  log('stage11.validation.started');

  await cleanup();

  const organization = await database.organization.create({
    data: {
      name: 'Stage 11 Runtime',

      slug: organizationSlug,

      status: 'ACTIVE',
    },
  });

  const team = await database.team.create({
    data: {
      organizationId: organization.id,

      name: 'Stage 11 Team',

      slug: `stage11-${unique}`,

      status: 'ACTIVE',
    },
  });

  const employeeUser = await database.user.create({
    data: {
      organizationId: organization.id,

      email: `stage11-employee-${unique}@example.com`,

      emailNormalized: `stage11-employee-${unique}@example.com`,

      displayName: 'Stage 11 Employee',

      status: 'ACTIVE',
    },
  });

  const otherUser = await database.user.create({
    data: {
      organizationId: organization.id,

      email: `stage11-other-${unique}@example.com`,

      emailNormalized: `stage11-other-${unique}@example.com`,

      displayName: 'Stage 11 Other Employee',

      status: 'ACTIVE',
    },
  });

  const employee = await database.employee.create({
    data: {
      organizationId: organization.id,

      teamId: team.id,

      userId: employeeUser.id,

      employeeCode: `S11A${unique}`,

      status: 'ACTIVE',
    },
  });

  const otherEmployee = await database.employee.create({
    data: {
      organizationId: organization.id,

      teamId: team.id,

      userId: otherUser.id,

      employeeCode: `S11B${unique}`,

      status: 'ACTIVE',
    },
  });

  const site = await database.site.create({
    data: {
      organizationId: organization.id,

      ownerEmployeeId: employee.id,

      name: 'Stage 11 Site',

      slug: `stage11-site-${unique}`,

      status: 'ACTIVE',
    },
  });

  const pool = await database.trafficPool.create({
    data: {
      organizationId: organization.id,

      siteId: site.id,

      name: 'Stage 11 Pool',

      slug: `stage11-pool-${unique}`,

      status: 'ACTIVE',
    },
  });

  const suffix = Date.now().toString().slice(-6);

  const numberA = await database.whatsAppNumber.create({
    data: {
      organizationId: organization.id,

      assignedEmployeeId: employee.id,

      displayName: 'Stage 11 Number A',

      e164: `+155511${suffix}`,

      status: 'ACTIVE',

      metaWabaId: `811001${suffix}`,

      metaPhoneNumberId: `911001${suffix}`,

      metaConnectedAt: new Date(),
    },
  });

  const numberB = await database.whatsAppNumber.create({
    data: {
      organizationId: organization.id,

      assignedEmployeeId: employee.id,

      displayName: 'Stage 11 Number B',

      e164: `+155512${suffix}`,

      status: 'ACTIVE',

      metaWabaId: `811002${suffix}`,

      metaPhoneNumberId: `911002${suffix}`,

      metaConnectedAt: new Date(),
    },
  });

  const numberOther = await database.whatsAppNumber.create({
    data: {
      organizationId: organization.id,

      assignedEmployeeId: otherEmployee.id,

      displayName: 'Stage 11 Other Number',

      e164: `+155513${suffix}`,

      status: 'ACTIVE',
    },
  });

  const memberA = await database.trafficPoolMember.create({
    data: {
      organizationId: organization.id,

      trafficPoolId: pool.id,

      whatsAppNumberId: numberA.id,

      position: 1,

      status: 'ACTIVE',
    },
  });

  const memberB = await database.trafficPoolMember.create({
    data: {
      organizationId: organization.id,

      trafficPoolId: pool.id,

      whatsAppNumberId: numberB.id,

      position: 2,

      status: 'ACTIVE',
    },
  });

  await database.whatsAppNumberHealthState.createMany({
    data: [
      {
        organizationId: organization.id,

        whatsAppNumberId: numberA.id,

        status: 'HEALTHY',

        schedulerEligible: true,

        metaQualityRating: 'GREEN',

        lastHealthyAt: new Date(),

        consecutiveHealthyChecks: 2,

        nextCheckAt: new Date(Date.now() + 60 * 60 * 1000),
      },

      {
        organizationId: organization.id,

        whatsAppNumberId: numberB.id,

        status: 'HEALTHY',

        schedulerEligible: true,

        metaQualityRating: 'GREEN',

        lastHealthyAt: new Date(),

        consecutiveHealthyChecks: 2,

        nextCheckAt: new Date(Date.now() + 60 * 60 * 1000),
      },

      {
        organizationId: organization.id,

        whatsAppNumberId: numberOther.id,

        status: 'HEALTHY',

        schedulerEligible: true,

        metaQualityRating: 'UNKNOWN',

        nextCheckAt: new Date(Date.now() + 60 * 60 * 1000),
      },
    ],
  });

  const request = await database.adsRequest.create({
    data: {
      organizationId: organization.id,

      employeeId: employee.id,

      siteId: site.id,

      trafficPoolId: pool.id,

      requestedByUserId: employeeUser.id,

      requestedLeadCount: 10,

      scheduledLeadCount: 10,

      fulfilledLeadCount: 3,

      status: 'PARTIALLY_FULFILLED',

      startedAt: new Date(),
    },
  });

  const queue = await database.adsQueueItem.create({
    data: {
      organizationId: organization.id,

      adsRequestId: request.id,

      employeeId: employee.id,

      trafficPoolId: pool.id,

      status: 'COMPLETED',

      completedAt: new Date(),
    },
  });

  const unhealthyBatch = await database.adsMicrobatch.create({
    data: {
      organizationId: organization.id,

      adsRequestId: request.id,

      adsQueueItemId: queue.id,

      employeeId: employee.id,

      trafficPoolId: pool.id,

      trafficPoolMemberId: memberA.id,

      whatsAppNumberId: numberA.id,

      sequence: 1,

      reservedLeadCount: 10,

      deliveredLeadCount: 3,

      status: 'DELIVERING',

      startedAt: new Date(),

      plannedAt: new Date(),
    },
  });

  const inbox = new WhatsAppInboxProcessorService(database, `stage11-inbox-${unique}`, inboxConfig);

  await createQualityEnvelope({
    organizationId: organization.id,

    whatsAppNumberId: numberA.id,

    wabaId: numberA.metaWabaId!,

    displayPhoneNumber: numberA.e164,

    event: 'DOWNGRADE',

    currentLimit: 'TIER_1K',

    priorityOffset: 1,
  });

  const downgradeTick = await inbox.runTick();

  assert.equal(downgradeTick.processed, 1);

  const degradedState = await database.whatsAppNumberHealthState.findUniqueOrThrow({
    where: {
      organizationId_whatsAppNumberId: {
        organizationId: organization.id,

        whatsAppNumberId: numberA.id,
      },
    },
  });

  assert.equal(degradedState.status, 'DEGRADED');

  assert.equal(degradedState.schedulerEligible, false);

  const cancelledBatch = await database.adsMicrobatch.findUniqueOrThrow({
    where: {
      id: unhealthyBatch.id,
    },
  });

  assert.equal(cancelledBatch.status, 'CANCELLED');

  assert.equal(cancelledBatch.deliveredLeadCount, 3);

  const requestAfterRelease = await database.adsRequest.findUniqueOrThrow({
    where: {
      id: request.id,
    },
  });

  assert.equal(requestAfterRelease.fulfilledLeadCount, 3);

  assert.equal(requestAfterRelease.scheduledLeadCount, 3);

  const queueAfterRelease = await database.adsQueueItem.findUniqueOrThrow({
    where: {
      id: queue.id,
    },
  });

  assert.equal(queueAfterRelease.status, 'WAITING');

  log('stage11.degraded_contingency_release.passed');

  const scheduler = new AdsSchedulerService(
    database,
    `stage11-scheduler-${unique}`,
    schedulerConfig,
  );

  const schedulerTick = await scheduler.runTick();

  assert.ok(schedulerTick.claimed >= 1);

  const replacementBatch = await database.adsMicrobatch.findFirstOrThrow({
    where: {
      organizationId: organization.id,

      adsRequestId: request.id,

      status: {
        in: ['PLANNED', 'DELIVERING'],
      },
    },

    orderBy: {
      sequence: 'desc',
    },
  });

  assert.equal(replacementBatch.whatsAppNumberId, numberB.id);

  assert.equal(replacementBatch.reservedLeadCount, 7);

  assert.equal(replacementBatch.deliveredLeadCount, 0);

  assert.equal(
    (
      await database.adsRequest.findUniqueOrThrow({
        where: {
          id: request.id,
        },
      })
    ).scheduledLeadCount,
    10,
  );

  log('stage11.scheduler_reroute.passed');

  await createQualityEnvelope({
    organizationId: organization.id,

    whatsAppNumberId: numberA.id,

    wabaId: numberA.metaWabaId!,

    displayPhoneNumber: numberA.e164,

    event: 'FLAGGED',

    currentLimit: 'TIER_1K',

    priorityOffset: 2,
  });

  await inbox.runTick();

  const criticalState = await database.whatsAppNumberHealthState.findUniqueOrThrow({
    where: {
      organizationId_whatsAppNumberId: {
        organizationId: organization.id,

        whatsAppNumberId: numberA.id,
      },
    },
  });

  assert.equal(criticalState.status, 'CRITICAL');

  assert.equal(criticalState.schedulerEligible, false);

  const openIncident = await database.whatsAppNumberIncident.findFirstOrThrow({
    where: {
      organizationId: organization.id,

      whatsAppNumberId: numberA.id,

      status: 'OPEN',

      type: 'META_QUALITY',
    },
  });

  assert.equal(openIncident.severity, 'CRITICAL');

  log('stage11.flagged_critical_incident.passed');

  await createQualityEnvelope({
    organizationId: organization.id,

    whatsAppNumberId: numberA.id,

    wabaId: numberA.metaWabaId!,

    displayPhoneNumber: numberA.e164,

    event: 'UNFLAGGED',

    currentLimit: 'TIER_1K',

    priorityOffset: 3,
  });

  await inbox.runTick();

  const recoveringAfterUnflagged = await database.whatsAppNumberHealthState.findUniqueOrThrow({
    where: {
      organizationId_whatsAppNumberId: {
        organizationId: organization.id,

        whatsAppNumberId: numberA.id,
      },
    },
  });

  assert.equal(recoveringAfterUnflagged.status, 'RECOVERING');

  assert.equal(recoveringAfterUnflagged.schedulerEligible, false);

  log('stage11.unflagged_recovering.passed');

  let metaFetchCount = 0;

  const metaClient = new MetaCloudApiClient(
    {
      graphBaseUrl: 'https://graph.facebook.com',

      graphApiVersion: 'v99.0',

      accessToken: 'stage11-runtime-token',

      timeoutMs: 5000,
    },

    async (input) => {
      metaFetchCount += 1;

      const url = new URL(String(input));

      assert.equal(url.pathname.endsWith(`/${numberA.metaPhoneNumberId}`), true);

      return new Response(
        JSON.stringify({
          id: numberA.metaPhoneNumberId,

          verified_name: 'Stage 11 Number A',

          display_phone_number: numberA.e164,

          quality_rating: 'GREEN',
        }),

        {
          status: 200,

          headers: {
            'content-type': 'application/json',
          },
        },
      );
    },
  );

  const healthSync = new WhatsAppNumberHealthSyncService(
    database,
    `stage11-health-${unique}`,
    healthConfig,
    metaClient,
  );

  await database.whatsAppNumberHealthState.update({
    where: {
      organizationId_whatsAppNumberId: {
        organizationId: organization.id,

        whatsAppNumberId: numberA.id,
      },
    },

    data: {
      nextCheckAt: new Date(0),
    },
  });

  const firstGreenTick = await healthSync.runTick();

  assert.equal(firstGreenTick.synced, 1);

  const firstGreenState = await database.whatsAppNumberHealthState.findUniqueOrThrow({
    where: {
      organizationId_whatsAppNumberId: {
        organizationId: organization.id,

        whatsAppNumberId: numberA.id,
      },
    },
  });

  assert.equal(firstGreenState.status, 'RECOVERING');

  assert.equal(firstGreenState.schedulerEligible, false);

  assert.equal(firstGreenState.consecutiveHealthyChecks, 1);

  log('stage11.first_green_still_recovering.passed');

  await database.whatsAppNumberHealthState.update({
    where: {
      id: firstGreenState.id,
    },

    data: {
      nextCheckAt: new Date(0),
    },
  });

  const secondGreenTick = await healthSync.runTick();

  assert.equal(secondGreenTick.synced, 1);

  const healthyAgain = await database.whatsAppNumberHealthState.findUniqueOrThrow({
    where: {
      id: firstGreenState.id,
    },
  });

  assert.equal(healthyAgain.status, 'HEALTHY');

  assert.equal(healthyAgain.schedulerEligible, true);

  assert.ok(healthyAgain.consecutiveHealthyChecks >= 2);

  assert.equal(metaFetchCount, 2);

  const resolvedIncident = await database.whatsAppNumberIncident.findFirstOrThrow({
    where: {
      organizationId: organization.id,

      whatsAppNumberId: numberA.id,

      type: 'META_QUALITY',
    },

    orderBy: {
      openedAt: 'desc',
    },
  });

  assert.equal(resolvedIncident.status, 'RESOLVED');

  assert.ok(resolvedIncident.resolvedAt);

  log('stage11.recovery_confirmed.passed');

  const apiModule = await import('../../api/dist/whatsapp-health/whatsapp-health.service.js');

  const api = new apiModule.WhatsAppHealthService({
    client: database,
  } as never);

  const adminPrincipal = {
    organizationId: organization.id,

    userId: employeeUser.id,

    sessionId: randomUUID(),

    roles: ['ADMIN'] as const,
  };

  const employeePrincipal = {
    organizationId: organization.id,

    userId: employeeUser.id,

    sessionId: randomUUID(),

    roles: ['EMPLOYEE'] as const,
  };

  const otherPrincipal = {
    organizationId: organization.id,

    userId: otherUser.id,

    sessionId: randomUUID(),

    roles: ['EMPLOYEE'] as const,
  };

  const healthResponse = await api.getHealth(employeePrincipal, numberA.id);

  assert.equal(healthResponse.status, 'HEALTHY');

  await assert.rejects(() => api.getHealth(otherPrincipal, numberA.id));

  const otherHealth = await api.getHealth(otherPrincipal, numberOther.id);

  assert.equal(otherHealth.whatsAppNumberId, numberOther.id);

  log('stage11.employee_isolation.passed');

  const pauseResponse = await api.pause(adminPrincipal, numberOther.id);

  assert.equal(pauseResponse.status, 'DISABLED');

  assert.equal(pauseResponse.schedulerEligible, false);

  assert.equal(pauseResponse.manualPaused, true);

  const resumeResponse = await api.resume(adminPrincipal, numberOther.id);

  assert.equal(resumeResponse.manualPaused, false);

  assert.equal(resumeResponse.status, 'UNKNOWN');

  assert.equal(resumeResponse.schedulerEligible, true);

  log('stage11.manual_pause_resume.passed');

  const events = await api.listEvents(adminPrincipal, numberA.id, 100);

  assert.ok(events.some((event) => event.currentStatus === 'CRITICAL'));

  assert.ok(events.some((event) => event.currentStatus === 'RECOVERING'));

  assert.ok(events.some((event) => event.currentStatus === 'HEALTHY'));

  const incidents = await api.listIncidents(adminPrincipal, numberA.id, 100);

  assert.ok(
    incidents.some(
      (incident) => incident.type === 'META_QUALITY' && incident.status === 'RESOLVED',
    ),
  );

  log('stage11.history_and_incidents_api.passed');

  const auditContingency = await database.auditLog.count({
    where: {
      organizationId: organization.id,

      action: 'whatsapp_number.contingency_activated',
    },
  });

  const auditRelease = await database.auditLog.count({
    where: {
      organizationId: organization.id,

      action: 'ads_microbatch.contingency_released',
    },
  });

  const auditPause = await database.auditLog.count({
    where: {
      organizationId: organization.id,

      action: 'whatsapp_number.health_paused',
    },
  });

  const auditResume = await database.auditLog.count({
    where: {
      organizationId: organization.id,

      action: 'whatsapp_number.health_resumed',
    },
  });

  assert.ok(auditContingency >= 1);

  assert.ok(auditRelease >= 1);

  assert.ok(auditPause >= 1);

  assert.ok(auditResume >= 1);

  log('stage11.audit.passed', {
    auditContingency,
    auditRelease,
    auditPause,
    auditResume,
  });

  log('stage11.validation.completed');
}

try {
  await main();
} finally {
  try {
    await cleanup();
  } finally {
    await database.$disconnect();
  }
}
