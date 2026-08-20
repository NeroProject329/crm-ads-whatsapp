export type SiteMonitorConfig = Readonly<{
  tickIntervalMs: number;
  checkIntervalMs: number;
  retryDelayMs: number;
  timeoutMs: number;
  leaseMs: number;
  failureThreshold: number;
  recoveryThreshold: number;
  concurrency: number;
  maxClaimsPerTick: number;
  stateSyncIntervalMs: number;
  checkRetentionDays: number;
  cleanupIntervalMs: number;
}>;

function readInteger(name: string, fallback: number, minimum: number, maximum: number): number {
  const raw = process.env[name]?.trim();

  if (!raw) {
    return fallback;
  }

  const value = Number(raw);

  if (!Number.isInteger(value) || value < minimum || value > maximum) {
    throw new Error(`${name} must be an integer between ${minimum} and ${maximum}.`);
  }

  return value;
}

export function parseSiteMonitorConfig(): SiteMonitorConfig {
  return {
    tickIntervalMs: readInteger('SITE_MONITOR_TICK_INTERVAL_MS', 1000, 100, 60_000),

    checkIntervalMs: readInteger('SITE_MONITOR_CHECK_INTERVAL_MS', 30_000, 5_000, 3_600_000),

    retryDelayMs: readInteger('SITE_MONITOR_RETRY_DELAY_MS', 5_000, 1_000, 300_000),

    timeoutMs: readInteger('SITE_MONITOR_TIMEOUT_MS', 5_000, 500, 60_000),

    leaseMs: readInteger('SITE_MONITOR_LEASE_MS', 15_000, 2_000, 300_000),

    failureThreshold: readInteger('SITE_MONITOR_FAILURE_THRESHOLD', 3, 1, 20),

    recoveryThreshold: readInteger('SITE_MONITOR_RECOVERY_THRESHOLD', 2, 1, 20),

    concurrency: readInteger('SITE_MONITOR_CONCURRENCY', 5, 1, 50),

    maxClaimsPerTick: readInteger('SITE_MONITOR_MAX_CLAIMS_PER_TICK', 25, 1, 1000),

    stateSyncIntervalMs: readInteger(
      'SITE_MONITOR_STATE_SYNC_INTERVAL_MS',
      60_000,
      1_000,
      3_600_000,
    ),

    checkRetentionDays: readInteger('SITE_MONITOR_CHECK_RETENTION_DAYS', 14, 1, 365),

    cleanupIntervalMs: readInteger(
      'SITE_MONITOR_CLEANUP_INTERVAL_MS',
      21_600_000,
      60_000,
      86_400_000,
    ),
  };
}
