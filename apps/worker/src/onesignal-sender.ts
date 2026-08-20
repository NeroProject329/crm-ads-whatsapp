import type { NotificationDispatcherConfig } from './notification-dispatcher.config.js';

export type PushMessage = Readonly<{
  externalId: string;
  title: string;
  body: string;
  url: string | null;
  data: unknown;
}>;

export type PushSendResult = Readonly<{
  providerMessageId: string | null;
}>;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

export async function sendOneSignalPush(
  config: NotificationDispatcherConfig,
  message: PushMessage,
): Promise<PushSendResult> {
  if (!config.oneSignalAppId || !config.oneSignalApiKey) {
    throw new Error('OneSignal is not configured.');
  }

  const payload: Record<string, unknown> = {
    app_id: config.oneSignalAppId,

    include_aliases: {
      external_id: [message.externalId],
    },

    target_channel: 'push',

    headings: {
      en: message.title,
    },

    contents: {
      en: message.body,
    },
  };

  if (message.url) {
    payload.url = message.url;
  }

  if (isRecord(message.data)) {
    payload.data = message.data;
  }

  const response = await fetch('https://api.onesignal.com/notifications?c=push', {
    method: 'POST',

    headers: {
      Authorization: `Key ${config.oneSignalApiKey}`,

      'Content-Type': 'application/json',
    },

    body: JSON.stringify(payload),

    signal: AbortSignal.timeout(10_000),
  });

  const responseText = await response.text();

  if (!response.ok) {
    throw new Error(`OneSignal HTTP ${response.status}: ${responseText.slice(0, 300)}`);
  }

  let parsed: unknown = null;

  try {
    parsed = JSON.parse(responseText);
  } catch {
    parsed = null;
  }

  const providerMessageId = isRecord(parsed) && typeof parsed.id === 'string' ? parsed.id : null;

  return {
    providerMessageId,
  };
}
