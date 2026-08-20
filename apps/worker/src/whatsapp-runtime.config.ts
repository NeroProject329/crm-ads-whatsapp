function parseInteger(name: string, fallback: number, minimum: number, maximum: number): number {
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

export type WhatsAppRuntimeConfig = Readonly<{
  inboxIntervalMs: number;

  inboxLeaseMs: number;

  inboxMaxClaimsPerTick: number;

  inboxMaxAttempts: number;

  inboxRetryBaseMs: number;

  outboundIntervalMs: number;

  outboundLeaseMs: number;

  outboundMaxClaimsPerTick: number;

  outboundMaxAttempts: number;

  outboundRetryBaseMs: number;

  outboundDisabledRetryMs: number;
}>;

export function parseWhatsAppRuntimeConfig(): WhatsAppRuntimeConfig {
  return {
    inboxIntervalMs: parseInteger('WHATSAPP_INBOX_INTERVAL_MS', 1000, 250, 60000),

    inboxLeaseMs: parseInteger('WHATSAPP_INBOX_LEASE_MS', 30000, 5000, 300000),

    inboxMaxClaimsPerTick: parseInteger('WHATSAPP_INBOX_MAX_CLAIMS_PER_TICK', 25, 1, 250),

    inboxMaxAttempts: parseInteger('WHATSAPP_INBOX_MAX_ATTEMPTS', 8, 1, 50),

    inboxRetryBaseMs: parseInteger('WHATSAPP_INBOX_RETRY_BASE_MS', 1000, 250, 600000),

    outboundIntervalMs: parseInteger('WHATSAPP_OUTBOUND_INTERVAL_MS', 1000, 250, 60000),

    outboundLeaseMs: parseInteger('WHATSAPP_OUTBOUND_LEASE_MS', 30000, 5000, 300000),

    outboundMaxClaimsPerTick: parseInteger('WHATSAPP_OUTBOUND_MAX_CLAIMS_PER_TICK', 25, 1, 250),

    outboundMaxAttempts: parseInteger('WHATSAPP_OUTBOUND_MAX_ATTEMPTS', 8, 1, 50),

    outboundRetryBaseMs: parseInteger('WHATSAPP_OUTBOUND_RETRY_BASE_MS', 2000, 250, 600000),

    outboundDisabledRetryMs: parseInteger(
      'WHATSAPP_OUTBOUND_DISABLED_RETRY_MS',
      30000,
      1000,
      3600000,
    ),
  };
}
