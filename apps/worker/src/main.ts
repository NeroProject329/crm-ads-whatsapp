import './load-environment.js';

import { randomUUID } from 'node:crypto';
import { hostname } from 'node:os';

import { createDatabaseClient } from '@crm/database';

import { AdsSchedulerService } from './ads-scheduler.service.js';

import { parseAdsSchedulerConfig } from './scheduler.config.js';

const service = 'worker' as const;

const heartbeatIntervalMs = 30_000;

const config = parseAdsSchedulerConfig();

const workerId =
  process.env.ADS_WORKER_ID?.trim() || `${hostname()}-${process.pid}-${randomUUID()}`;

const database = createDatabaseClient();

const scheduler = new AdsSchedulerService(database, workerId, config);

let schedulerRunning = false;
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

log('service.started', {
  heartbeatIntervalMs,
  schedulerIntervalMs: config.intervalMs,
  microbatchSize: config.microbatchSize,
  maxInflightPerEmployee: config.maxInflightPerEmployee,
  leaseMs: config.leaseMs,
});

await runSchedulerTick();

const schedulerTimer = setInterval(() => {
  void runSchedulerTick();
}, config.intervalMs);

const heartbeatTimer = setInterval(() => {
  log('service.heartbeat', {
    schedulerRunning,
  });
}, heartbeatIntervalMs);

async function shutdown(signal: NodeJS.Signals): Promise<void> {
  if (shuttingDown) {
    return;
  }

  shuttingDown = true;

  clearInterval(schedulerTimer);

  clearInterval(heartbeatTimer);

  log('service.stopping', {
    signal,
  });

  while (schedulerRunning) {
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
