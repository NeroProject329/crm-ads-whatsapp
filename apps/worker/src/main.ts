import './load-environment.js';

import { randomUUID } from 'node:crypto';

import { hostname } from 'node:os';

import { createDatabaseClient } from '@crm/database';

import { MetaCloudApiClient, parseMetaCloudApiConfig } from '@crm/meta-cloud-api';

import { AdsSchedulerService } from './ads-scheduler.service.js';

import { NotificationDispatcherService } from './notification-dispatcher.service.js';

import {
  isNotificationDispatcherEnabled,
  parseNotificationDispatcherConfig,
} from './notification-dispatcher.config.js';

import { parseAdsSchedulerConfig } from './scheduler.config.js';

import { WhatsAppInboxProcessorService } from './whatsapp-inbox-processor.service.js';

import { WhatsAppOutboundDispatcherService } from './whatsapp-outbound-dispatcher.service.js';

import { parseWhatsAppRuntimeConfig } from './whatsapp-runtime.config.js';

const service = 'worker' as const;

const heartbeatIntervalMs = 30_000;

const schedulerConfig = parseAdsSchedulerConfig();

const notificationConfig = parseNotificationDispatcherConfig();

const whatsAppConfig = parseWhatsAppRuntimeConfig();

const workerId =
  process.env.ADS_WORKER_ID?.trim() || `${hostname()}-${process.pid}-${randomUUID()}`;

const database = createDatabaseClient();

const scheduler = new AdsSchedulerService(database, workerId, schedulerConfig);

const notificationDispatcher = new NotificationDispatcherService(
  database,
  workerId,
  notificationConfig,
);

const metaConfigured = Boolean(
  process.env.META_GRAPH_API_VERSION?.trim() && process.env.META_ACCESS_TOKEN?.trim(),
);

const metaClient = metaConfigured
  ? new MetaCloudApiClient(parseMetaCloudApiConfig(process.env))
  : null;

const inboxProcessor = new WhatsAppInboxProcessorService(database, workerId, whatsAppConfig);

const outboundDispatcher = new WhatsAppOutboundDispatcherService(
  database,
  workerId,
  whatsAppConfig,
  metaClient,
);

let schedulerRunning = false;

let notificationRunning = false;

let inboxRunning = false;

let outboundRunning = false;

let shuttingDown = false;

function log(event: string, extra: Record<string, unknown> = {}): void {
  console.log(
    JSON.stringify({
      event,
      service,
      workerId,
      timestamp: new Date().toISOString(),
      ...extra,
    }),
  );
}

async function runSchedulerTick(): Promise<void> {
  if (schedulerRunning || shuttingDown) {
    return;
  }

  schedulerRunning = true;

  try {
    const summary = await scheduler.runTick();

    if (summary.claimed > 0 || summary.failed > 0 || summary.lostLease > 0) {
      log('ads.scheduler.tick', summary);
    }
  } catch (error) {
    log('ads.scheduler.error', {
      message: error instanceof Error ? error.message : String(error),
    });
  } finally {
    schedulerRunning = false;
  }
}

async function runNotificationTick(): Promise<void> {
  if (notificationRunning || shuttingDown) {
    return;
  }

  notificationRunning = true;

  try {
    const summary = await notificationDispatcher.runTick();

    if (summary.claimed > 0 || summary.failed > 0) {
      log('notification.dispatch.tick', summary);
    }
  } catch (error) {
    log('notification.dispatch.error', {
      message: error instanceof Error ? error.message : String(error),
    });
  } finally {
    notificationRunning = false;
  }
}

async function runInboxTick(): Promise<void> {
  if (inboxRunning || shuttingDown) {
    return;
  }

  inboxRunning = true;

  try {
    const summary = await inboxProcessor.runTick();

    if (summary.claimed > 0 || summary.failed > 0) {
      log('whatsapp.inbox.tick', summary);
    }
  } catch (error) {
    log('whatsapp.inbox.error', {
      message: error instanceof Error ? error.message : String(error),
    });
  } finally {
    inboxRunning = false;
  }
}

async function runOutboundTick(): Promise<void> {
  if (outboundRunning || shuttingDown) {
    return;
  }

  outboundRunning = true;

  try {
    const summary = await outboundDispatcher.runTick();

    if (summary.claimed > 0 || summary.failed > 0 || summary.retried > 0) {
      log('whatsapp.outbound.tick', summary);
    }
  } catch (error) {
    log('whatsapp.outbound.error', {
      message: error instanceof Error ? error.message : String(error),
    });
  } finally {
    outboundRunning = false;
  }
}

log('service.started', {
  heartbeatIntervalMs,

  schedulerIntervalMs: schedulerConfig.intervalMs,

  microbatchSize: schedulerConfig.microbatchSize,

  notificationDispatcherEnabled: isNotificationDispatcherEnabled(notificationConfig),

  notificationIntervalMs: notificationConfig.intervalMs,

  whatsAppInboxIntervalMs: whatsAppConfig.inboxIntervalMs,

  whatsAppOutboundIntervalMs: whatsAppConfig.outboundIntervalMs,

  metaOutboundConfigured: metaConfigured,
});

await Promise.all([runSchedulerTick(), runNotificationTick(), runInboxTick(), runOutboundTick()]);

const schedulerTimer = setInterval(() => {
  void runSchedulerTick();
}, schedulerConfig.intervalMs);

const notificationTimer = setInterval(() => {
  void runNotificationTick();
}, notificationConfig.intervalMs);

const inboxTimer = setInterval(() => {
  void runInboxTick();
}, whatsAppConfig.inboxIntervalMs);

const outboundTimer = setInterval(() => {
  void runOutboundTick();
}, whatsAppConfig.outboundIntervalMs);

const heartbeatTimer = setInterval(() => {
  log('service.heartbeat', {
    schedulerRunning,
    notificationRunning,
    inboxRunning,
    outboundRunning,
  });
}, heartbeatIntervalMs);

async function shutdown(signal: NodeJS.Signals): Promise<void> {
  if (shuttingDown) {
    return;
  }

  shuttingDown = true;

  clearInterval(schedulerTimer);

  clearInterval(notificationTimer);

  clearInterval(inboxTimer);

  clearInterval(outboundTimer);

  clearInterval(heartbeatTimer);

  log('service.stopping', {
    signal,
  });

  while (schedulerRunning || notificationRunning || inboxRunning || outboundRunning) {
    await new Promise<void>((resolve) => {
      setTimeout(resolve, 50);
    });
  }

  await database.$disconnect();

  log('service.stopped', {
    signal,
  });

  process.exit(0);
}

process.once('SIGINT', () => {
  void shutdown('SIGINT');
});

process.once('SIGTERM', () => {
  void shutdown('SIGTERM');
});
