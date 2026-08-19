export type AdsSchedulerConfig = Readonly<{
  intervalMs: number;
  microbatchSize: number;
  maxInflightPerEmployee: number;
  leaseMs: number;
  backpressureDelayMs: number;
  microbatchYieldMs: number;
  maxClaimsPerTick: number;
  maxQueueAttempts: number;
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

export function parseAdsSchedulerConfig(): AdsSchedulerConfig {
  return {
    intervalMs: readInteger('ADS_SCHEDULER_INTERVAL_MS', 1000, 100, 60_000),

    microbatchSize: readInteger('ADS_MICROBATCH_SIZE', 10, 1, 10_000),

    maxInflightPerEmployee: readInteger('ADS_MAX_INFLIGHT_PER_EMPLOYEE', 100, 1, 1_000_000),

    leaseMs: readInteger('ADS_CLAIM_LEASE_MS', 30_000, 5_000, 900_000),

    backpressureDelayMs: readInteger('ADS_BACKPRESSURE_DELAY_MS', 5_000, 100, 900_000),

    microbatchYieldMs: readInteger('ADS_MICROBATCH_YIELD_MS', 250, 0, 60_000),

    maxClaimsPerTick: readInteger('ADS_MAX_CLAIMS_PER_TICK', 25, 1, 1000),

    maxQueueAttempts: readInteger('ADS_MAX_QUEUE_ATTEMPTS', 25, 1, 1000),
  };
}
