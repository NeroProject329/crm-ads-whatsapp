export type MetaPhoneNumberQualityUpdate = Readonly<{
  wabaId: string | null;
  displayPhoneNumber: string;
  event: string | null;
  currentLimit: string | null;
}>;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function readString(value: unknown): string | null {
  return typeof value === 'string' ? value : null;
}

export function parseMetaPhoneNumberQualityUpdates(
  payload: unknown,
): readonly MetaPhoneNumberQualityUpdate[] {
  if (!isRecord(payload)) {
    return [];
  }

  const entries = Array.isArray(payload.entry) ? payload.entry : [];

  const result: MetaPhoneNumberQualityUpdate[] = [];

  for (const rawEntry of entries) {
    if (!isRecord(rawEntry)) {
      continue;
    }

    const wabaId = readString(rawEntry.id);

    const changes = Array.isArray(rawEntry.changes) ? rawEntry.changes : [];

    for (const rawChange of changes) {
      if (!isRecord(rawChange) || rawChange.field !== 'phone_number_quality_update') {
        continue;
      }

      const value = isRecord(rawChange.value) ? rawChange.value : null;

      if (!value) {
        continue;
      }

      const displayPhoneNumber = readString(value.display_phone_number);

      if (!displayPhoneNumber) {
        continue;
      }

      result.push({
        wabaId,

        displayPhoneNumber,

        event: readString(value.event),

        currentLimit: readString(value.current_limit),
      });
    }
  }

  return result;
}
