export type NotificationDispatcherConfig = Readonly<{
  intervalMs: number;
  leaseMs: number;
  maxAttempts: number;
  retryBaseMs: number;
  maxClaimsPerTick: number;
  oneSignalAppId: string | null;
  oneSignalApiKey: string | null;
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

function readOptional(name: string): string | null {
  const value = process.env[name]?.trim();

  return value ? value : null;
}

export function parseNotificationDispatcherConfig(): NotificationDispatcherConfig {
  return {
    intervalMs: readInteger('NOTIFICATION_DISPATCH_INTERVAL_MS', 1000, 100, 60_000),

    leaseMs: readInteger('NOTIFICATION_DELIVERY_LEASE_MS', 30_000, 5_000, 900_000),

    maxAttempts: readInteger('NOTIFICATION_MAX_ATTEMPTS', 8, 1, 100),

    retryBaseMs: readInteger('NOTIFICATION_RETRY_BASE_MS', 5_000, 100, 3_600_000),

    maxClaimsPerTick: readInteger('NOTIFICATION_MAX_CLAIMS_PER_TICK', 25, 1, 1000),

    oneSignalAppId: readOptional('ONESIGNAL_APP_ID'),

    oneSignalApiKey: readOptional('ONESIGNAL_API_KEY'),
  };
}

export function isNotificationDispatcherEnabled(config: NotificationDispatcherConfig): boolean {
  return Boolean(config.oneSignalAppId && config.oneSignalApiKey);
}
