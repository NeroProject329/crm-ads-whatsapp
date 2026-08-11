const service = 'worker' as const;
const heartbeatIntervalMs = 30 * 1_000;

function log(event: string, extra: Record<string, unknown> = {}): void {
  console.log(
    JSON.stringify({
      event,
      service,
      timestamp: new Date().toISOString(),
      ...extra,
    }),
  );
}

log('service.started', { heartbeatIntervalMs });

const heartbeat = setInterval(() => {
  log('service.heartbeat');
}, heartbeatIntervalMs);

function shutdown(signal: NodeJS.Signals): void {
  clearInterval(heartbeat);
  log('service.stopped', { signal });
  process.exit(0);
}

process.once('SIGINT', shutdown);
process.once('SIGTERM', shutdown);
