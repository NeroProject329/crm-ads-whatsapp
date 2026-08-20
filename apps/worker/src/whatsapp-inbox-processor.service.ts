import type { CrmDatabaseClient, WhatsAppMessageStatus, WhatsAppMessageType } from '@crm/database';

import { parseWhatsAppWebhookEvents } from '@crm/meta-cloud-api';

import type { WhatsAppInboundWebhookEvent, WhatsAppStatusWebhookEvent } from '@crm/meta-cloud-api';

import { LeadAttributionService } from './lead-attribution.service.js';

import type { WhatsAppRuntimeConfig } from './whatsapp-runtime.config.js';

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

type ClaimedEnvelope = Readonly<{
  id: string;

  organizationId: string | null;

  whatsAppNumberId: string | null;

  metaPhoneNumberId: string | null;
}>;

export type WhatsAppInboxTickSummary = Readonly<{
  claimed: number;

  processed: number;

  failed: number;

  messages: number;

  statuses: number;
}>;

function normalizeJsonValue(value: unknown): JsonValue {
  if (value === null || typeof value === 'string' || typeof value === 'boolean') {
    return value;
  }

  if (typeof value === 'number') {
    return Number.isFinite(value) ? value : null;
  }

  if (Array.isArray(value)) {
    return value.map(normalizeJsonValue);
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

function normalizeJsonObject(value: unknown): JsonObject {
  const normalized = normalizeJsonValue(value);

  if (typeof normalized === 'object' && normalized !== null && !Array.isArray(normalized)) {
    return normalized;
  }

  return {
    value: normalized,
  };
}

function normalizeJsonArray(value: readonly unknown[]): JsonValue[] {
  return value.map(normalizeJsonValue);
}
function parseProviderTimestamp(value: string | null, fallback: Date): Date {
  if (!value) {
    return fallback;
  }

  const seconds = Number(value);

  if (!Number.isFinite(seconds) || seconds <= 0) {
    return fallback;
  }

  const timestamp = new Date(seconds * 1000);

  return Number.isNaN(timestamp.getTime()) ? fallback : timestamp;
}

function addHours(date: Date, hours: number): Date {
  return new Date(date.getTime() + hours * 60 * 60 * 1000);
}

function addMilliseconds(date: Date, milliseconds: number): Date {
  return new Date(date.getTime() + milliseconds);
}

function getErrorMessage(error: unknown): string {
  return (error instanceof Error ? error.message : String(error)).slice(0, 500);
}

function mapMessageType(type: string): WhatsAppMessageType {
  switch (type) {
    case 'text':
      return 'TEXT';

    case 'image':
      return 'IMAGE';

    case 'audio':
      return 'AUDIO';

    case 'video':
      return 'VIDEO';

    case 'document':
      return 'DOCUMENT';

    case 'sticker':
      return 'STICKER';

    case 'location':
      return 'LOCATION';

    case 'contacts':
      return 'CONTACTS';

    case 'interactive':
      return 'INTERACTIVE';

    case 'reaction':
      return 'REACTION';

    default:
      return 'UNKNOWN';
  }
}

function mapStatus(status: string): WhatsAppMessageStatus | null {
  switch (status) {
    case 'sent':
      return 'SENT';

    case 'delivered':
      return 'DELIVERED';

    case 'read':
      return 'READ';

    case 'failed':
      return 'FAILED';

    case 'deleted':
      return 'DELETED';

    default:
      return null;
  }
}

export class WhatsAppInboxProcessorService {
  private readonly leadAttributionService = new LeadAttributionService();
  constructor(
    private readonly database: CrmDatabaseClient,

    private readonly workerId: string,

    private readonly config: WhatsAppRuntimeConfig,
  ) {}

  async runTick(): Promise<WhatsAppInboxTickSummary> {
    let claimed = 0;

    let processed = 0;

    let failed = 0;

    let messages = 0;

    let statuses = 0;

    for (let index = 0; index < this.config.inboxMaxClaimsPerTick; index += 1) {
      const envelope = await this.claimNextEnvelope();

      if (!envelope) {
        break;
      }

      claimed += 1;

      try {
        const result = await this.processEnvelope(envelope);

        processed += 1;

        messages += result.messages;

        statuses += result.statuses;
      } catch (error) {
        await this.handleEnvelopeFailure(envelope, error);

        failed += 1;
      }
    }

    return {
      claimed,
      processed,
      failed,
      messages,
      statuses,
    };
  }

  private async claimNextEnvelope(): Promise<ClaimedEnvelope | null> {
    const rows = await this.database.$queryRawUnsafe<ClaimedEnvelope[]>(
      `
        WITH candidate AS (
          SELECT
            "id"
          FROM
            "meta_webhook_envelopes"
          WHERE
            (
              (
                "status" = 'RECEIVED'
                AND "availableAt" <= NOW()
              )
              OR
              (
                "status" = 'CLAIMED'
                AND "leaseExpiresAt" IS NOT NULL
                AND "leaseExpiresAt" <= NOW()
              )
            )
          ORDER BY
            "availableAt" ASC,
            "receivedAt" ASC,
            "id" ASC
          FOR UPDATE SKIP LOCKED
          LIMIT 1
        )
        UPDATE
          "meta_webhook_envelopes" AS envelope
        SET
          "status" = 'CLAIMED',
          "claimedAt" = NOW(),
          "claimedByWorkerId" = $1,
          "leaseExpiresAt" =
            NOW() + ($2::int * INTERVAL '1 millisecond'),
          "attempts" =
            envelope."attempts" + 1,
          "failureReason" = NULL,
          "updatedAt" = NOW()
        FROM
          candidate
        WHERE
          envelope."id" = candidate."id"
        RETURNING
          envelope."id",
          envelope."organizationId",
          envelope."whatsAppNumberId",
          envelope."metaPhoneNumberId"
        `,
      this.workerId,
      this.config.inboxLeaseMs,
    );

    return rows[0] ?? null;
  }

  private async processEnvelope(claimed: ClaimedEnvelope): Promise<
    Readonly<{
      messages: number;

      statuses: number;
    }>
  > {
    const envelope = await this.database.metaWebhookEnvelope.findFirst({
      where: {
        id: claimed.id,

        status: 'CLAIMED',

        claimedByWorkerId: this.workerId,

        leaseExpiresAt: {
          gt: new Date(),
        },
      },
    });

    if (!envelope) {
      return {
        messages: 0,

        statuses: 0,
      };
    }

    if (!envelope.organizationId || !envelope.whatsAppNumberId) {
      throw new Error('Claimed webhook envelope has no tenant/number mapping.');
    }

    const events = parseWhatsAppWebhookEvents(envelope.payload);

    let messageCount = 0;

    let statusCount = 0;

    for (const event of events) {
      if (
        envelope.metaPhoneNumberId &&
        event.phoneNumberId &&
        envelope.metaPhoneNumberId !== event.phoneNumberId
      ) {
        throw new Error(
          'Webhook event phone number does not match the persisted envelope mapping.',
        );
      }

      if (event.kind === 'MESSAGE') {
        const created = await this.processInboundMessage(
          envelope.organizationId,
          envelope.whatsAppNumberId,
          envelope.id,
          envelope.receivedAt,
          event,
        );

        if (created) {
          messageCount += 1;
        }
      } else {
        const created = await this.processStatusEvent(
          envelope.organizationId,
          envelope.whatsAppNumberId,
          envelope.id,
          envelope.receivedAt,
          event,
        );

        if (created) {
          statusCount += 1;
        }
      }
    }

    await this.database.metaWebhookEnvelope.updateMany({
      where: {
        id: envelope.id,

        status: 'CLAIMED',

        claimedByWorkerId: this.workerId,
      },

      data: {
        status: 'PROCESSED',

        processedAt: new Date(),

        claimedAt: null,

        claimedByWorkerId: null,

        leaseExpiresAt: null,

        failureReason: null,
      },
    });

    return {
      messages: messageCount,

      statuses: statusCount,
    };
  }

  private async processInboundMessage(
    organizationId: string,
    whatsAppNumberId: string,
    sourceEnvelopeId: string,
    receivedAt: Date,
    event: WhatsAppInboundWebhookEvent,
  ): Promise<boolean> {
    return this.database.$transaction(async (transaction) => {
      await transaction.$queryRawUnsafe(
        'WITH lock_guard AS MATERIALIZED (SELECT pg_advisory_xact_lock(hashtextextended($1, 0))) SELECT TRUE AS locked FROM lock_guard',
        `wa-message:${organizationId}:${event.messageId}`,
      );

      const existing = await transaction.whatsAppMessage.findUnique({
        where: {
          metaMessageId: event.messageId,
        },

        select: {
          id: true,

          organizationId: true,
        },
      });

      if (existing) {
        if (existing.organizationId !== organizationId) {
          throw new Error('Meta message id collision across organizations.');
        }

        return false;
      }

      const providerTimestamp = parseProviderTimestamp(event.timestamp, receivedAt);

      const windowExpiresAt = addHours(providerTimestamp, 24);

      let contact = await transaction.whatsAppContact.upsert({
        where: {
          organizationId_waId: {
            organizationId,
            waId: event.from,
          },
        },

        create: {
          organizationId,
          waId: event.from,

          profileName: event.profileName,

          lastInboundAt: providerTimestamp,
        },

        update: {
          ...(event.profileName
            ? {
                profileName: event.profileName,
              }
            : {}),
        },
      });

      if (!contact.lastInboundAt || contact.lastInboundAt < providerTimestamp) {
        contact = await transaction.whatsAppContact.update({
          where: {
            id: contact.id,
          },

          data: {
            lastInboundAt: providerTimestamp,
          },
        });
      }

      const number = await transaction.whatsAppNumber.findFirst({
        where: {
          id: whatsAppNumberId,

          organizationId,

          deletedAt: null,
        },

        select: {
          id: true,

          assignedEmployeeId: true,
        },
      });

      if (!number) {
        throw new Error('WhatsApp number disappeared while processing an inbound event.');
      }

      let conversation = await transaction.whatsAppConversation.upsert({
        where: {
          organizationId_whatsAppNumberId_contactId: {
            organizationId,
            whatsAppNumberId: number.id,

            contactId: contact.id,
          },
        },

        create: {
          organizationId,

          whatsAppNumberId: number.id,

          contactId: contact.id,

          assignedEmployeeId: number.assignedEmployeeId,

          status: 'OPEN',

          customerServiceWindowExpiresAt: windowExpiresAt,

          lastMessageAt: providerTimestamp,

          lastInboundAt: providerTimestamp,

          unreadCount: 0,
        },

        update: {},
      });

      const nextWindowExpiresAt =
        !conversation.customerServiceWindowExpiresAt ||
        conversation.customerServiceWindowExpiresAt < windowExpiresAt
          ? windowExpiresAt
          : conversation.customerServiceWindowExpiresAt;

      const nextLastInboundAt =
        !conversation.lastInboundAt || conversation.lastInboundAt < providerTimestamp
          ? providerTimestamp
          : conversation.lastInboundAt;

      const nextLastMessageAt =
        !conversation.lastMessageAt || conversation.lastMessageAt < providerTimestamp
          ? providerTimestamp
          : conversation.lastMessageAt;

      conversation = await transaction.whatsAppConversation.update({
        where: {
          id: conversation.id,
        },

        data: {
          status: 'OPEN',

          customerServiceWindowExpiresAt: nextWindowExpiresAt,

          lastInboundAt: nextLastInboundAt,

          lastMessageAt: nextLastMessageAt,

          unreadCount: {
            increment: 1,
          },

          ...(!conversation.assignedEmployeeId && number.assignedEmployeeId
            ? {
                assignedEmployeeId: number.assignedEmployeeId,
              }
            : {}),
        },
      });

      const inboundMessage = await transaction.whatsAppMessage.create({
        data: {
          organizationId,

          conversationId: conversation.id,

          whatsAppNumberId: number.id,

          contactId: contact.id,

          sourceEnvelopeId,

          direction: 'INBOUND',

          type: mapMessageType(event.messageType),

          status: 'RECEIVED',

          metaMessageId: event.messageId,

          replyToMetaMessageId: event.replyToMessageId,

          textBody: event.textBody,

          content: normalizeJsonObject(event.payload),

          providerTimestamp,

          availableAt: providerTimestamp,
        },
      });

      await this.leadAttributionService.recordInboundLead(transaction, {
        organizationId,

        contactId: contact.id,

        whatsAppNumberId: number.id,

        ownerEmployeeId: number.assignedEmployeeId,

        inboundMessageId: inboundMessage.id,

        waId: event.from,

        profileName: event.profileName,

        providerTimestamp,
      });

      return true;
    });
  }

  private async processStatusEvent(
    organizationId: string,
    whatsAppNumberId: string,
    sourceEnvelopeId: string,
    receivedAt: Date,
    event: WhatsAppStatusWebhookEvent,
  ): Promise<boolean> {
    const status = mapStatus(event.status);

    if (!status) {
      return false;
    }

    const providerTimestamp = parseProviderTimestamp(event.timestamp, receivedAt);

    return this.database.$transaction(async (transaction) => {
      await transaction.$queryRawUnsafe(
        'WITH lock_guard AS MATERIALIZED (SELECT pg_advisory_xact_lock(hashtextextended($1, 0))) SELECT TRUE AS locked FROM lock_guard',
        `wa-status:${organizationId}:${event.messageId}:${status}:${providerTimestamp.toISOString()}`,
      );

      const existingEvent = await transaction.whatsAppMessageStatusEvent.findUnique({
        where: {
          organizationId_metaMessageId_status_providerTimestamp: {
            organizationId,

            metaMessageId: event.messageId,

            status,

            providerTimestamp,
          },
        },

        select: {
          id: true,
        },
      });

      if (existingEvent) {
        return false;
      }

      const message = await transaction.whatsAppMessage.findUnique({
        where: {
          metaMessageId: event.messageId,
        },
      });

      if (message && message.organizationId !== organizationId) {
        throw new Error('Meta status message id collision across organizations.');
      }

      const statusEvent = await transaction.whatsAppMessageStatusEvent.create({
        data: {
          organizationId,

          whatsAppNumberId,

          sourceEnvelopeId,

          metaMessageId: event.messageId,

          status,

          recipientWaId: event.recipientId,

          providerTimestamp,

          ...(event.errors.length > 0
            ? {
                errors: normalizeJsonArray(event.errors),
              }
            : {}),

          payload: normalizeJsonObject(event.payload),

          appliedAt: message ? new Date() : null,
        },
      });

      if (!message) {
        void statusEvent;

        return true;
      }

      if (
        status === 'SENT' &&
        (message.status === 'QUEUED' || message.status === 'SENDING' || message.status === 'SENT')
      ) {
        await transaction.whatsAppMessage.update({
          where: {
            id: message.id,
          },

          data: {
            status: 'SENT',

            sentAt: message.sentAt ?? providerTimestamp,
          },
        });
      }

      if (status === 'DELIVERED' && message.status !== 'READ' && message.status !== 'DELETED') {
        await transaction.whatsAppMessage.update({
          where: {
            id: message.id,
          },

          data: {
            status: 'DELIVERED',

            sentAt: message.sentAt ?? providerTimestamp,

            deliveredAt: providerTimestamp,
          },
        });
      }

      if (status === 'READ' && message.status !== 'DELETED') {
        await transaction.whatsAppMessage.update({
          where: {
            id: message.id,
          },

          data: {
            status: 'READ',

            sentAt: message.sentAt ?? providerTimestamp,

            deliveredAt: message.deliveredAt ?? providerTimestamp,

            readAt: providerTimestamp,
          },
        });
      }

      if (
        status === 'FAILED' &&
        message.status !== 'DELIVERED' &&
        message.status !== 'READ' &&
        message.status !== 'DELETED'
      ) {
        await transaction.whatsAppMessage.update({
          where: {
            id: message.id,
          },

          data: {
            status: 'FAILED',

            failedAt: providerTimestamp,

            errorCode: 'META_DELIVERY_FAILED',

            errorMessage: 'Meta reported message delivery failure.',
          },
        });
      }

      if (status === 'DELETED') {
        await transaction.whatsAppMessage.update({
          where: {
            id: message.id,
          },

          data: {
            status: 'DELETED',
          },
        });
      }

      return true;
    });
  }

  private async handleEnvelopeFailure(envelope: ClaimedEnvelope, error: unknown): Promise<void> {
    const current = await this.database.metaWebhookEnvelope.findUnique({
      where: {
        id: envelope.id,
      },

      select: {
        attempts: true,
      },
    });

    if (!current) {
      return;
    }

    const terminal = current.attempts >= this.config.inboxMaxAttempts;

    const multiplier = Math.max(0, current.attempts - 1);

    const retryDelay = Math.min(this.config.inboxRetryBaseMs * 2 ** multiplier, 15 * 60 * 1000);

    await this.database.metaWebhookEnvelope.updateMany({
      where: {
        id: envelope.id,

        status: 'CLAIMED',

        claimedByWorkerId: this.workerId,
      },

      data: {
        status: terminal ? 'FAILED' : 'RECEIVED',

        availableAt: terminal ? new Date() : addMilliseconds(new Date(), retryDelay),

        claimedAt: null,

        claimedByWorkerId: null,

        leaseExpiresAt: null,

        failureReason: getErrorMessage(error),
      },
    });
  }
}
