import { createHash } from 'node:crypto';

import { Inject, Injectable } from '@nestjs/common';

import { extractMetaWebhookSummary } from '@crm/meta-cloud-api';

import { DatabaseService } from './database.service.js';

type JsonPrimitive = string | number | boolean | null;

type JsonValue =
  | JsonPrimitive
  | JsonValue[]
  | {
      [key: string]: JsonValue;
    };

type JsonObject = {
  [key: string]: JsonValue;
};

function normalizeJsonValue(value: unknown): JsonValue {
  if (value === null || typeof value === 'string' || typeof value === 'boolean') {
    return value;
  }

  if (typeof value === 'number') {
    return Number.isFinite(value) ? value : null;
  }

  if (Array.isArray(value)) {
    return value.map((item) => normalizeJsonValue(item));
  }

  if (typeof value === 'object' && value !== null) {
    const result: JsonObject = {};

    for (const [key, item] of Object.entries(value)) {
      result[key] = normalizeJsonValue(item);
    }

    return result;
  }

  return null;
}

function normalizePayload(value: unknown): JsonObject {
  const normalized = normalizeJsonValue(value);

  if (typeof normalized === 'object' && normalized !== null && !Array.isArray(normalized)) {
    return normalized;
  }

  return {
    value: normalized,
  };
}

export type MetaWebhookIngestResult = Readonly<{
  envelopeId: string;
  status: 'RECEIVED' | 'UNMATCHED' | 'IGNORED';
  organizationId: string | null;
  whatsAppNumberId: string | null;
}>;

@Injectable()
export class MetaWebhookService {
  constructor(
    @Inject(DatabaseService)
    private readonly database: DatabaseService,
  ) {}

  async ingest(payload: unknown, rawBody: Buffer): Promise<MetaWebhookIngestResult> {
    const summary = extractMetaWebhookSummary(payload);

    const payloadHash = createHash('sha256').update(rawBody).digest('hex');

    const number = summary.phoneNumberId
      ? await this.database.client.whatsAppNumber.findFirst({
          where: {
            metaPhoneNumberId: summary.phoneNumberId,

            deletedAt: null,

            ...(summary.wabaId
              ? {
                  metaWabaId: summary.wabaId,
                }
              : {}),
          },

          select: {
            id: true,

            organizationId: true,
          },
        })
      : null;

    const status: 'RECEIVED' | 'UNMATCHED' | 'IGNORED' =
      summary.object !== 'whatsapp_business_account'
        ? 'IGNORED'
        : number
          ? 'RECEIVED'
          : 'UNMATCHED';

    const receivedAt = new Date();

    const envelope = await this.database.client.$transaction(async (transaction) => {
      const stored = await transaction.metaWebhookEnvelope.upsert({
        where: {
          payloadHash,
        },

        create: {
          organizationId: number?.organizationId ?? null,

          whatsAppNumberId: number?.id ?? null,

          object: summary.object,

          field: summary.field,

          wabaId: summary.wabaId,

          metaPhoneNumberId: summary.phoneNumberId,

          payloadHash,

          payload: normalizePayload(payload),

          status,

          receivedAt,
        },

        update: {},
      });

      if (number) {
        await transaction.whatsAppNumber.update({
          where: {
            id: number.id,
          },

          data: {
            metaWebhookLastSeenAt: receivedAt,
          },
        });
      }

      return stored;
    });

    return {
      envelopeId: envelope.id,

      status:
        envelope.status === 'RECEIVED'
          ? 'RECEIVED'
          : envelope.status === 'UNMATCHED'
            ? 'UNMATCHED'
            : 'IGNORED',

      organizationId: envelope.organizationId,

      whatsAppNumberId: envelope.whatsAppNumberId,
    };
  }
}
