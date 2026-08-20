type UnknownRecord = Record<string, unknown>;

export type WhatsAppInboundWebhookEvent = Readonly<{
  kind: 'MESSAGE';

  wabaId: string | null;

  phoneNumberId: string | null;

  messageId: string;

  from: string;

  timestamp: string | null;

  messageType: string;

  textBody: string | null;

  profileName: string | null;

  replyToMessageId: string | null;

  payload: UnknownRecord;
}>;

export type WhatsAppStatusWebhookEvent = Readonly<{
  kind: 'STATUS';

  wabaId: string | null;

  phoneNumberId: string | null;

  messageId: string;

  recipientId: string | null;

  timestamp: string | null;

  status: string;

  errors: readonly unknown[];

  payload: UnknownRecord;
}>;

export type WhatsAppWebhookEvent = WhatsAppInboundWebhookEvent | WhatsAppStatusWebhookEvent;

function isRecord(value: unknown): value is UnknownRecord {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function records(value: unknown): readonly UnknownRecord[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.filter(isRecord);
}

function readString(value: unknown): string | null {
  return typeof value === 'string' ? value : null;
}

function readTextBody(message: UnknownRecord): string | null {
  const text = isRecord(message.text) ? message.text : null;

  return readString(text?.body);
}

function readReplyToMessageId(message: UnknownRecord): string | null {
  const context = isRecord(message.context) ? message.context : null;

  return readString(context?.id);
}

export function parseWhatsAppWebhookEvents(payload: unknown): readonly WhatsAppWebhookEvent[] {
  if (!isRecord(payload)) {
    return [];
  }

  const events: WhatsAppWebhookEvent[] = [];

  for (const entry of records(payload.entry)) {
    const wabaId = readString(entry.id);

    for (const change of records(entry.changes)) {
      if (readString(change.field) !== 'messages') {
        continue;
      }

      const value = isRecord(change.value) ? change.value : null;

      if (!value) {
        continue;
      }

      const metadata = isRecord(value.metadata) ? value.metadata : null;

      const phoneNumberId = readString(metadata?.phone_number_id);

      const contactNames = new Map<string, string | null>();

      for (const contact of records(value.contacts)) {
        const waId = readString(contact.wa_id);

        if (!waId) {
          continue;
        }

        const profile = isRecord(contact.profile) ? contact.profile : null;

        contactNames.set(waId, readString(profile?.name));
      }

      for (const message of records(value.messages)) {
        const messageId = readString(message.id);

        const from = readString(message.from);

        if (!messageId || !from) {
          continue;
        }

        events.push({
          kind: 'MESSAGE',

          wabaId,

          phoneNumberId,

          messageId,

          from,

          timestamp: readString(message.timestamp),

          messageType: readString(message.type) ?? 'unknown',

          textBody: readTextBody(message),

          profileName: contactNames.get(from) ?? null,

          replyToMessageId: readReplyToMessageId(message),

          payload: message,
        });
      }

      for (const status of records(value.statuses)) {
        const messageId = readString(status.id);

        const statusName = readString(status.status);

        if (!messageId || !statusName) {
          continue;
        }

        events.push({
          kind: 'STATUS',

          wabaId,

          phoneNumberId,

          messageId,

          recipientId: readString(status.recipient_id),

          timestamp: readString(status.timestamp),

          status: statusName,

          errors: Array.isArray(status.errors) ? status.errors : [],

          payload: status,
        });
      }
    }
  }

  return events;
}
