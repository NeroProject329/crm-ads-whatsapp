import './load-environment.js';

import { randomUUID } from 'node:crypto';

import { hostname } from 'node:os';

import { createDatabaseClient } from '@crm/database';

import { AdsSchedulerService } from './ads-scheduler.service.js';

import { NotificationDispatcherService } from './notification-dispatcher.service.js';

import {
  isNotificationDispatcherEnabled,
  parseNotificationDispatcherConfig,
} from './notification-dispatcher.config.js';

import { parseAdsSchedulerConfig } from './scheduler.config.js';

const service = 'worker' as const;

const heartbeatIntervalMs = 30_000;

const schedulerConfig = parseAdsSchedulerConfig();

const notificationConfig = parseNotificationDispatcherConfig();

const workerId =
  process.env.ADS_WORKER_ID?.trim() || `${hostname()}-${process.pid}-${randomUUID()}`;

const database = createDatabaseClient();

const scheduler = new AdsSchedulerService(database, workerId, schedulerConfig);

const notificationDispatcher = new NotificationDispatcherService(
  database,
  workerId,
  notificationConfig,
);

let schedulerRunning = false;

let notificationRunning = false;

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

log('service.started', {
  heartbeatIntervalMs,

  schedulerIntervalMs: schedulerConfig.intervalMs,

  microbatchSize: schedulerConfig.microbatchSize,

  notificationDispatcherEnabled: isNotificationDispatcherEnabled(notificationConfig),

  notificationIntervalMs: notificationConfig.intervalMs,
});

await Promise.all([runSchedulerTick(), runNotificationTick()]);

const schedulerTimer = setInterval(
  () => {
    void runSchedulerTick();
  },

  schedulerConfig.intervalMs,
);

const notificationTimer = setInterval(
  () => {
    void runNotificationTick();
  },

  notificationConfig.intervalMs,
);

const heartbeatTimer = setInterval(
  () => {
    log('service.heartbeat', {
      schedulerRunning,
      notificationRunning,
    });
  },

  heartbeatIntervalMs,
);

async function shutdown(signal: NodeJS.Signals): Promise<void> {
  if (shuttingDown) {
    return;
  }

  shuttingDown = true;

  clearInterval(schedulerTimer);

  clearInterval(notificationTimer);

  clearInterval(heartbeatTimer);

  log('service.stopping', {
    signal,
  });

  while (schedulerRunning || notificationRunning) {
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
