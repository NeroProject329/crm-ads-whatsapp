import '../src/load-environment.js';

import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';

import type { AuthenticatedPrincipal } from '@crm/auth';

import { DatabaseService } from '../src/database/database.service.js';

import { NotificationsService } from '../src/notifications/notifications.service.js';

import {
  NotificationDispatcherService,
  type NotificationSender,
} from '../../worker/src/notification-dispatcher.service.js';

import type { NotificationDispatcherConfig } from '../../worker/src/notification-dispatcher.config.js';

const databaseService = new DatabaseService();

const database = databaseService.client;

const notificationsService = new NotificationsService(databaseService);

const organizationSlug = process.env.SEED_ORGANIZATION_SLUG?.trim() || 'crm-ads-whatsapp';

const unique = randomUUID().replaceAll('-', '').slice(0, 16);

const fixtureEmailPrefix = 'stage7.runtime.';

const foreignOrganizationPrefix = 'stage7-runtime-tenant-';

const dispatcherConfig: NotificationDispatcherConfig = {
  intervalMs: 100,
  leaseMs: 30_000,
  maxAttempts: 3,
  retryBaseMs: 50,
  maxClaimsPerTick: 1,
  oneSignalAppId: 'stage7-test-app',
  oneSignalApiKey: 'stage7-test-key',
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

async function deleteUserFixture(userId: string, organizationId: string): Promise<void> {
  const notifications = await database.notification.findMany({
    where: {
      organizationId,
      userId,
    },

    select: {
      id: true,
    },
  });

  const devices = await database.pushDevice.findMany({
    where: {
      organizationId,
      userId,
    },

    select: {
      id: true,
    },
  });

  const resourceIds = [...notifications.map((item) => item.id), ...devices.map((item) => item.id)];

  await database.auditLog.deleteMany({
    where: {
      organizationId,

      OR: [
        {
          actorUserId: userId,
        },

        ...(resourceIds.length > 0
          ? [
              {
                resourceId: {
                  in: resourceIds,
                },
              },
            ]
          : []),
      ],
    },
  });

  await database.notificationDelivery.deleteMany({
    where: {
      organizationId,
      userId,
    },
  });

  await database.notification.deleteMany({
    where: {
      organizationId,
      userId,
    },
  });

  await database.notificationPreference.deleteMany({
    where: {
      organizationId,
      userId,
    },
  });

  await database.pushDevice.deleteMany({
    where: {
      organizationId,
      userId,
    },
  });

  await database.session.deleteMany({
    where: {
      organizationId,
      userId,
    },
  });

  await database.userRole.deleteMany({
    where: {
      organizationId,
      userId,
    },
  });

  await database.user.deleteMany({
    where: {
      organizationId,
      id: userId,
    },
  });
}

async function cleanupRuntimeFixtures(): Promise<void> {
  const primaryOrganization = await database.organization.findUnique({
    where: {
      slug: organizationSlug,
    },
  });

  if (primaryOrganization) {
    const fixtureUsers = await database.user.findMany({
      where: {
        organizationId: primaryOrganization.id,

        emailNormalized: {
          startsWith: fixtureEmailPrefix,
        },
      },

      select: {
        id: true,
      },
    });

    for (const user of fixtureUsers) {
      await deleteUserFixture(user.id, primaryOrganization.id);
    }
  }

  const foreignOrganizations = await database.organization.findMany({
    where: {
      slug: {
        startsWith: foreignOrganizationPrefix,
      },
    },

    select: {
      id: true,
    },
  });

  for (const organization of foreignOrganizations) {
    await database.auditLog.deleteMany({
      where: {
        organizationId: organization.id,
      },
    });

    await database.notificationDelivery.deleteMany({
      where: {
        organizationId: organization.id,
      },
    });

    await database.notification.deleteMany({
      where: {
        organizationId: organization.id,
      },
    });

    await database.notificationPreference.deleteMany({
      where: {
        organizationId: organization.id,
      },
    });

    await database.pushDevice.deleteMany({
      where: {
        organizationId: organization.id,
      },
    });

    await database.session.deleteMany({
      where: {
        organizationId: organization.id,
      },
    });

    await database.userRole.deleteMany({
      where: {
        organizationId: organization.id,
      },
    });

    await database.user.deleteMany({
      where: {
        organizationId: organization.id,
      },
    });

    await database.rolePermission.deleteMany({
      where: {
        role: {
          organizationId: organization.id,
        },
      },
    });

    await database.role.deleteMany({
      where: {
        organizationId: organization.id,
      },
    });

    await database.organization.delete({
      where: {
        id: organization.id,
      },
    });
  }
}

async function makeDeliveryDue(notificationId: string): Promise<void> {
  await database.notificationDelivery.update({
    where: {
      notificationId_provider: {
        notificationId,
        provider: 'ONESIGNAL',
      },
    },

    data: {
      status: 'WAITING',

      nextAttemptAt: new Date(0),

      claimedAt: null,

      claimedByWorkerId: null,

      leaseExpiresAt: null,
    },
  });
}

async function createNotification(
  organizationId: string,
  userId: string,
  suffix: string,
): Promise<string> {
  const notificationId = await notificationsService.enqueuePush({
    organizationId,
    userId,

    type: `stage7.runtime.${suffix}`,

    title: `Stage 7 ${suffix}`,

    body: 'Runtime notification',

    url: '/',

    data: {
      source: 'stage7-runtime',
    },

    idempotencyKey: `stage7:${unique}:${suffix}`,
  });

  await makeDeliveryDue(notificationId);

  return notificationId;
}

try {
  event('stage7.validation.started');

  await cleanupRuntimeFixtures();

  const organization = await database.organization.findUniqueOrThrow({
    where: {
      slug: organizationSlug,
    },
  });

  const userA = await database.user.create({
    data: {
      organizationId: organization.id,

      email: `${fixtureEmailPrefix}${unique}@example.com`,

      emailNormalized: `${fixtureEmailPrefix}${unique}@example.com`,

      displayName: 'Stage 7 Runtime User',

      status: 'ACTIVE',
    },
  });

  const noDeviceUser = await database.user.create({
    data: {
      organizationId: organization.id,

      email: `${fixtureEmailPrefix}nodevice.${unique}@example.com`,

      emailNormalized: `${fixtureEmailPrefix}nodevice.${unique}@example.com`,

      displayName: 'Stage 7 No Device',

      status: 'ACTIVE',
    },
  });

  const foreignOrganization = await database.organization.create({
    data: {
      name: 'Stage 7 Foreign Tenant',

      slug: `${foreignOrganizationPrefix}${unique}`,

      status: 'ACTIVE',
    },
  });

  const userB = await database.user.create({
    data: {
      organizationId: foreignOrganization.id,

      email: `stage7.foreign.${unique}@example.com`,

      emailNormalized: `stage7.foreign.${unique}@example.com`,

      displayName: 'Stage 7 Foreign User',

      status: 'ACTIVE',
    },
  });

  const principalA: AuthenticatedPrincipal = {
    organizationId: organization.id,

    userId: userA.id,

    sessionId: randomUUID(),

    roles: ['ADMIN'],
  };

  const principalNoDevice: AuthenticatedPrincipal = {
    organizationId: organization.id,

    userId: noDeviceUser.id,

    sessionId: randomUUID(),

    roles: ['ADMIN'],
  };

  const principalB: AuthenticatedPrincipal = {
    organizationId: foreignOrganization.id,

    userId: userB.id,

    sessionId: randomUUID(),

    roles: ['ADMIN'],
  };

  const subscriptionA1 = randomUUID();

  const subscriptionA2 = randomUUID();

  const subscriptionB = randomUUID();

  await notificationsService.registerDevice(
    principalA,
    {
      subscriptionId: subscriptionA1,

      oneSignalId: randomUUID(),

      optedIn: true,

      platform: 'iPhone',

      browser: 'Safari',

      deviceLabel: 'Stage 7 iPhone',
    },
    'Stage7 Runtime Safari',
  );

  await notificationsService.registerDevice(
    principalA,
    {
      subscriptionId: subscriptionA2,

      oneSignalId: randomUUID(),

      optedIn: true,

      platform: 'Windows',

      browser: 'Chrome',

      deviceLabel: 'Stage 7 Desktop',
    },
    'Stage7 Runtime Chrome',
  );

  await notificationsService.registerDevice(
    principalB,
    {
      subscriptionId: subscriptionB,

      oneSignalId: randomUUID(),

      optedIn: true,

      platform: 'Android',

      browser: 'Chrome',

      deviceLabel: 'Foreign Android',
    },
    'Stage7 Foreign Chrome',
  );

  const devicesA = await notificationsService.listDevices(principalA);

  const devicesB = await notificationsService.listDevices(principalB);

  assert.equal(devicesA.length, 2);

  assert.equal(devicesB.length, 1);

  assert.ok(devicesA.every((device) => device.subscriptionId !== subscriptionB));

  event('stage7.device_registration.passed');

  await assert.rejects(() => notificationsService.unregisterDevice(principalB, subscriptionA1));

  event('stage7.device_tenant_isolation.passed');

  const switchSubscription = randomUUID();

  await notificationsService.registerDevice(
    principalA,
    {
      subscriptionId: switchSubscription,

      optedIn: true,

      platform: 'Windows',

      browser: 'Chrome',

      deviceLabel: 'Account Switch',
    },
    'Stage7 Switch',
  );

  await notificationsService.registerDevice(
    principalB,
    {
      subscriptionId: switchSubscription,

      optedIn: true,

      platform: 'Windows',

      browser: 'Chrome',

      deviceLabel: 'Account Switch',
    },
    'Stage7 Switch',
  );

  const transferredDevice = await database.pushDevice.findUniqueOrThrow({
    where: {
      subscriptionId: switchSubscription,
    },
  });

  assert.equal(transferredDevice.organizationId, foreignOrganization.id);

  assert.equal(transferredDevice.userId, userB.id);

  event('stage7.account_switch.passed');

  await notificationsService.unregisterDevice(principalA, subscriptionA2);

  await notificationsService.unregisterDevice(principalA, subscriptionA2);

  const revokedDevice = await database.pushDevice.findUniqueOrThrow({
    where: {
      subscriptionId: subscriptionA2,
    },
  });

  assert.equal(revokedDevice.status, 'REVOKED');

  assert.equal(revokedDevice.optedIn, false);

  const activeDevicesA = await notificationsService.listDevices(principalA);

  assert.equal(activeDevicesA.length, 1);

  event('stage7.device_unregister.passed');

  const defaultPreferences = await notificationsService.getPreferences(principalA);

  assert.equal(defaultPreferences.pushEnabled, true);

  assert.equal(defaultPreferences.siteMonitoring, true);

  const disabledPreferences = await notificationsService.updatePreferences(principalA, {
    pushEnabled: false,

    siteMonitoring: false,
  });

  assert.equal(disabledPreferences.pushEnabled, false);

  assert.equal(disabledPreferences.siteMonitoring, false);

  await notificationsService.updatePreferences(principalA, {
    pushEnabled: true,

    siteMonitoring: true,
  });

  event('stage7.preferences.passed');

  const idempotencyKey = `stage7:${unique}:idempotency`;

  const idempotentResults = await Promise.all([
    notificationsService.enqueuePush({
      organizationId: organization.id,

      userId: userA.id,

      type: 'stage7.runtime.idempotency',

      title: 'Idempotency',

      body: 'First concurrent enqueue',

      idempotencyKey,
    }),

    notificationsService.enqueuePush({
      organizationId: organization.id,

      userId: userA.id,

      type: 'stage7.runtime.idempotency',

      title: 'Idempotency duplicate',

      body: 'Second concurrent enqueue',

      idempotencyKey,
    }),
  ]);

  assert.equal(idempotentResults[0], idempotentResults[1]);

  const idempotentNotificationId = idempotentResults[0];

  assert.ok(idempotentNotificationId);

  assert.equal(
    await database.notification.count({
      where: {
        organizationId: organization.id,

        idempotencyKey,
      },
    }),
    1,
  );

  assert.equal(
    await database.notificationDelivery.count({
      where: {
        notificationId: idempotentNotificationId,
      },
    }),
    1,
  );

  await database.notificationDelivery.update({
    where: {
      notificationId_provider: {
        notificationId: idempotentNotificationId,

        provider: 'ONESIGNAL',
      },
    },

    data: {
      nextAttemptAt: new Date(Date.now() + 86_400_000),
    },
  });

  event('stage7.idempotency.passed');

  const notificationsA = await notificationsService.listNotifications(principalA);

  const notificationsB = await notificationsService.listNotifications(principalB);

  assert.ok(notificationsA.some((item) => item.id === idempotentNotificationId));

  assert.ok(notificationsB.every((item) => item.id !== idempotentNotificationId));

  event('stage7.notification_tenant_isolation.passed');

  let noDeviceSenderCalls = 0;

  const noDeviceSender: NotificationSender = async () => {
    noDeviceSenderCalls += 1;

    return {
      providerMessageId: randomUUID(),
    };
  };

  const noDeviceNotification = await createNotification(
    organization.id,
    noDeviceUser.id,
    'no-device',
  );

  const noDeviceDispatcher = new NotificationDispatcherService(
    database,
    `stage7-no-device-${unique}`,
    dispatcherConfig,
    noDeviceSender,
  );

  const noDeviceSummary = await noDeviceDispatcher.runTick();

  assert.equal(noDeviceSummary.skipped, 1);

  assert.equal(noDeviceSenderCalls, 0);

  const noDeviceState = await database.notification.findUniqueOrThrow({
    where: {
      id: noDeviceNotification,
    },
  });

  assert.equal(noDeviceState.status, 'SKIPPED');

  event('stage7.no_device_skip.passed');

  await notificationsService.updatePreferences(principalA, {
    pushEnabled: false,
  });

  let disabledSenderCalls = 0;

  const disabledSender: NotificationSender = async () => {
    disabledSenderCalls += 1;

    return {
      providerMessageId: randomUUID(),
    };
  };

  const disabledNotification = await createNotification(organization.id, userA.id, 'push-disabled');

  const disabledDispatcher = new NotificationDispatcherService(
    database,
    `stage7-disabled-${unique}`,
    dispatcherConfig,
    disabledSender,
  );

  const disabledSummary = await disabledDispatcher.runTick();

  assert.equal(disabledSummary.skipped, 1);

  assert.equal(disabledSenderCalls, 0);

  assert.equal(
    (
      await database.notification.findUniqueOrThrow({
        where: {
          id: disabledNotification,
        },
      })
    ).status,
    'SKIPPED',
  );

  await notificationsService.updatePreferences(principalA, {
    pushEnabled: true,
  });

  event('stage7.preference_skip.passed');

  let sentExternalId: string | null = null;

  const sentSender: NotificationSender = async (_config, message) => {
    sentExternalId = message.externalId;

    return {
      providerMessageId: 'stage7-provider-message',
    };
  };

  const sentNotification = await createNotification(organization.id, userA.id, 'sent');

  const sentDispatcher = new NotificationDispatcherService(
    database,
    `stage7-sent-${unique}`,
    dispatcherConfig,
    sentSender,
  );

  const sentSummary = await sentDispatcher.runTick();

  assert.equal(sentSummary.sent, 1);

  assert.equal(sentExternalId, userA.id);

  const sentState = await database.notification.findUniqueOrThrow({
    where: {
      id: sentNotification,
    },
  });

  const sentDelivery = await database.notificationDelivery.findUniqueOrThrow({
    where: {
      notificationId_provider: {
        notificationId: sentNotification,

        provider: 'ONESIGNAL',
      },
    },
  });

  assert.equal(sentState.status, 'SENT');

  assert.equal(sentDelivery.status, 'SENT');

  assert.equal(sentDelivery.providerMessageId, 'stage7-provider-message');

  event('stage7.mock_onesignal_sent.passed');

  let retryCalls = 0;

  const retryFailureSender: NotificationSender = async () => {
    retryCalls += 1;

    throw new Error('Simulated temporary provider error.');
  };

  const retryNotification = await createNotification(organization.id, userA.id, 'retry');

  const retryDispatcher = new NotificationDispatcherService(
    database,
    `stage7-retry-${unique}`,
    dispatcherConfig,
    retryFailureSender,
  );

  const retrySummary = await retryDispatcher.runTick();

  assert.equal(retrySummary.deferred, 1);

  let retryDelivery = await database.notificationDelivery.findUniqueOrThrow({
    where: {
      notificationId_provider: {
        notificationId: retryNotification,

        provider: 'ONESIGNAL',
      },
    },
  });

  assert.equal(retryDelivery.status, 'WAITING');

  assert.equal(retryDelivery.attempts, 1);

  await makeDeliveryDue(retryNotification);

  const retrySuccessSender: NotificationSender = async () => ({
    providerMessageId: 'retry-recovered',
  });

  const recoveryDispatcher = new NotificationDispatcherService(
    database,
    `stage7-retry-recovery-${unique}`,
    dispatcherConfig,
    retrySuccessSender,
  );

  await recoveryDispatcher.runTick();

  retryDelivery = await database.notificationDelivery.findUniqueOrThrow({
    where: {
      notificationId_provider: {
        notificationId: retryNotification,

        provider: 'ONESIGNAL',
      },
    },
  });

  assert.equal(retryDelivery.status, 'SENT');

  assert.equal(retryDelivery.attempts, 2);

  assert.equal(retryCalls, 1);

  event('stage7.retry_recovery.passed');

  const failedNotification = await createNotification(
    organization.id,
    userA.id,
    'permanent-failure',
  );

  await database.notificationDelivery.update({
    where: {
      notificationId_provider: {
        notificationId: failedNotification,

        provider: 'ONESIGNAL',
      },
    },

    data: {
      attempts: dispatcherConfig.maxAttempts - 1,

      nextAttemptAt: new Date(0),
    },
  });

  const permanentFailureSender: NotificationSender = async () => {
    throw new Error('Simulated permanent provider failure.');
  };

  const failedDispatcher = new NotificationDispatcherService(
    database,
    `stage7-failed-${unique}`,
    dispatcherConfig,
    permanentFailureSender,
  );

  const failedSummary = await failedDispatcher.runTick();

  assert.equal(failedSummary.failed, 1);

  const failedDelivery = await database.notificationDelivery.findUniqueOrThrow({
    where: {
      notificationId_provider: {
        notificationId: failedNotification,

        provider: 'ONESIGNAL',
      },
    },
  });

  const failedState = await database.notification.findUniqueOrThrow({
    where: {
      id: failedNotification,
    },
  });

  assert.equal(failedDelivery.status, 'FAILED');

  assert.equal(failedDelivery.attempts, dispatcherConfig.maxAttempts);

  assert.equal(failedState.status, 'FAILED');

  event('stage7.mock_onesignal_failed.passed');

  const leaseNotification = await createNotification(organization.id, userA.id, 'lease-recovery');

  await database.notificationDelivery.update({
    where: {
      notificationId_provider: {
        notificationId: leaseNotification,

        provider: 'ONESIGNAL',
      },
    },

    data: {
      status: 'CLAIMED',

      attempts: 1,

      claimedAt: new Date(Date.now() - 60_000),

      claimedByWorkerId: 'dead-stage7-worker',

      leaseExpiresAt: new Date(Date.now() - 30_000),

      nextAttemptAt: new Date(Date.now() + 3_600_000),
    },
  });

  const leaseSender: NotificationSender = async () => ({
    providerMessageId: 'lease-recovered',
  });

  const leaseDispatcher = new NotificationDispatcherService(
    database,
    `stage7-lease-${unique}`,
    dispatcherConfig,
    leaseSender,
  );

  await leaseDispatcher.runTick();

  const leaseDelivery = await database.notificationDelivery.findUniqueOrThrow({
    where: {
      notificationId_provider: {
        notificationId: leaseNotification,

        provider: 'ONESIGNAL',
      },
    },
  });

  assert.equal(leaseDelivery.status, 'SENT');

  assert.equal(leaseDelivery.attempts, 2);

  assert.equal(leaseDelivery.claimedByWorkerId, null);

  event('stage7.lease_recovery.passed');

  const concurrentNotification = await createNotification(organization.id, userA.id, 'concurrency');

  let concurrentSenderCalls = 0;

  const concurrentSender: NotificationSender = async () => {
    concurrentSenderCalls += 1;

    await new Promise<void>((resolve) => {
      setTimeout(resolve, 150);
    });

    return {
      providerMessageId: 'concurrent-message',
    };
  };

  const concurrentA = new NotificationDispatcherService(
    database,
    `stage7-worker-a-${unique}`,
    dispatcherConfig,
    concurrentSender,
  );

  const concurrentB = new NotificationDispatcherService(
    database,
    `stage7-worker-b-${unique}`,
    dispatcherConfig,
    concurrentSender,
  );

  await Promise.all([concurrentA.runTick(), concurrentB.runTick()]);

  const concurrentDelivery = await database.notificationDelivery.findUniqueOrThrow({
    where: {
      notificationId_provider: {
        notificationId: concurrentNotification,

        provider: 'ONESIGNAL',
      },
    },
  });

  assert.equal(concurrentDelivery.status, 'SENT');

  assert.equal(concurrentSenderCalls, 1);

  assert.equal(concurrentDelivery.attempts, 1);

  event('stage7.concurrent_claim.passed');

  const sentAudit = await database.auditLog.count({
    where: {
      organizationId: organization.id,

      action: 'notification.sent',
    },
  });

  const failedAudit = await database.auditLog.count({
    where: {
      organizationId: organization.id,

      action: 'notification.failed',
    },
  });

  assert.ok(sentAudit >= 1);

  assert.ok(failedAudit >= 1);

  event('stage7.audit.passed', {
    sentAudit,
    failedAudit,
  });

  event('stage7.validation.completed');
} finally {
  try {
    await cleanupRuntimeFixtures();
  } finally {
    await database.$disconnect();
  }
}
