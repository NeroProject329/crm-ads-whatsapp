import type { MetaCloudApiClient } from './client.js';

export type MetaPhoneNumberQualityRating = 'GREEN' | 'YELLOW' | 'RED' | 'NA' | 'UNKNOWN';

export type MetaPhoneNumberProfile = Readonly<{
  id: string;
  verifiedName: string | null;
  displayPhoneNumber: string | null;
  qualityRating: MetaPhoneNumberQualityRating;
}>;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function readString(value: unknown): string | null {
  return typeof value === 'string' ? value : null;
}

function parseQualityRating(value: unknown): MetaPhoneNumberQualityRating {
  const normalized = typeof value === 'string' ? value.trim().toUpperCase() : '';

  switch (normalized) {
    case 'GREEN':
      return 'GREEN';

    case 'YELLOW':
      return 'YELLOW';

    case 'RED':
      return 'RED';

    case 'NA':
      return 'NA';

    default:
      return 'UNKNOWN';
  }
}

export async function getMetaPhoneNumberProfile(
  client: MetaCloudApiClient,

  phoneNumberId: string,
): Promise<MetaPhoneNumberProfile> {
  const id = phoneNumberId.trim();

  if (!/^\d+$/.test(id)) {
    throw new Error('Invalid Meta phone number id.');
  }

  const payload = await client.get<unknown>(id, {
    fields: 'id,verified_name,display_phone_number,quality_rating',
  });

  if (!isRecord(payload)) {
    throw new Error('Invalid Meta phone number profile response.');
  }

  return {
    id: readString(payload.id) ?? id,

    verifiedName: readString(payload.verified_name),

    displayPhoneNumber: readString(payload.display_phone_number),

    qualityRating: parseQualityRating(payload.quality_rating),
  };
}
