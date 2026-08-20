export type WhatsAppNumberHealthConfig = Readonly<{
  intervalMs: number;

  pollIntervalMs: number;

  failureRetryMs: number;

  leaseMs: number;

  maxClaimsPerTick: number;

  recoveryHealthyChecks: number;
}>;

function parsePositiveInteger(
  name: string,

  fallback: number,
): number {
  const raw = process.env[name]?.trim();

  if (!raw) {
    return fallback;
  }

  const value = Number(raw);

  if (!Number.isInteger(value) || value <= 0) {
    throw new Error(`${name} must be a positive integer.`);
  }

  return value;
}

export function parseWhatsAppNumberHealthConfig(): WhatsAppNumberHealthConfig {
  return {
    intervalMs: parsePositiveInteger('WHATSAPP_HEALTH_INTERVAL_MS', 5000),

    pollIntervalMs: parsePositiveInteger('WHATSAPP_HEALTH_POLL_INTERVAL_MS', 15 * 60 * 1000),

    failureRetryMs: parsePositiveInteger('WHATSAPP_HEALTH_FAILURE_RETRY_MS', 60 * 1000),

    leaseMs: parsePositiveInteger('WHATSAPP_HEALTH_LEASE_MS', 30000),

    maxClaimsPerTick: parsePositiveInteger('WHATSAPP_HEALTH_MAX_CLAIMS_PER_TICK', 10),

    recoveryHealthyChecks: parsePositiveInteger('WHATSAPP_HEALTH_RECOVERY_GREEN_CHECKS', 2),
  };
}
