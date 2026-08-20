export type MetaWebhookSummary = Readonly<{
  object: string | null;
  wabaId: string | null;
  field: string | null;
  phoneNumberId: string | null;
}>;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function stringValue(value: unknown): string | null {
  return typeof value === 'string' ? value : null;
}

export function extractMetaWebhookSummary(payload: unknown): MetaWebhookSummary {
  if (!isRecord(payload)) {
    return {
      object: null,
      wabaId: null,
      field: null,
      phoneNumberId: null,
    };
  }

  const entries = Array.isArray(payload.entry) ? payload.entry : [];

  const firstEntry = isRecord(entries[0]) ? entries[0] : null;

  const changes = firstEntry && Array.isArray(firstEntry.changes) ? firstEntry.changes : [];

  const firstChange = isRecord(changes[0]) ? changes[0] : null;

  const value = firstChange && isRecord(firstChange.value) ? firstChange.value : null;

  const metadata = value && isRecord(value.metadata) ? value.metadata : null;

  return {
    object: stringValue(payload.object),

    wabaId: stringValue(firstEntry?.id),

    field: stringValue(firstChange?.field),

    phoneNumberId: stringValue(metadata?.phone_number_id),
  };
}
