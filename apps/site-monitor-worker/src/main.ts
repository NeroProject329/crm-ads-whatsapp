import './load-environment.js';

import { randomUUID } from 'node:crypto';

import { hostname } from 'node:os';

import { createDatabaseClient } from '@crm/database';

import { assertServiceProductionReadiness } from '@crm/config';

import { parseSiteMonitorConfig } from './site-monitor.config.js';

import { SiteMonitorService } from './site-monitor.service.js';

const service = 'site-monitor-worker' as const;

assertServiceProductionReadiness('site-monitor-worker');

const heartbeatIntervalMs = 60_000;

const config = parseSiteMonitorConfig();

const workerId =
  process.env.SITE_MONITOR_WORKER_ID?.trim() || `${hostname()}-${process.pid}-${randomUUID()}`;

const database = createDatabaseClient();

const monitor = new SiteMonitorService(database, workerId, config);

let tickRunning = false;
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

async function runTick(): Promise<void> {
  if (tickRunning || shuttingDown) {
    return;
  }

  tickRunning = true;

  try {
    const summary = await monitor.runTick();

    if (
      summary.claimed > 0 ||
      summary.openedIncidents > 0 ||
      summary.resolvedIncidents > 0 ||
      summary.lostLeases > 0
    ) {
      log('site_monitor.tick', summary);
    }
  } catch (error) {
    log('site_monitor.error', {
      message: error instanceof Error ? error.message : String(error),
    });
  } finally {
    tickRunning = false;
  }
}

log('service.started', {
  heartbeatIntervalMs,

  tickIntervalMs: config.tickIntervalMs,

  checkIntervalMs: config.checkIntervalMs,

  timeoutMs: config.timeoutMs,

  failureThreshold: config.failureThreshold,

  recoveryThreshold: config.recoveryThreshold,

  concurrency: config.concurrency,
});

await runTick();

const tickTimer = setInterval(
  () => {
    void runTick();
  },

  config.tickIntervalMs,
);

const heartbeatTimer = setInterval(
  () => {
    log('service.heartbeat', {
      tickRunning,
    });
  },

  heartbeatIntervalMs,
);

async function shutdown(signal: NodeJS.Signals): Promise<void> {
  if (shuttingDown) {
    return;
  }

  shuttingDown = true;

  clearInterval(tickTimer);

  clearInterval(heartbeatTimer);

  log('service.stopping', {
    signal,
  });

  while (tickRunning) {
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
