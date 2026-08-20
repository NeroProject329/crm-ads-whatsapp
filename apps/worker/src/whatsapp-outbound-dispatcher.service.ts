import type { CrmDatabaseClient } from '@crm/database';

import { type MetaCloudApiClient, MetaCloudApiError } from '@crm/meta-cloud-api';

import type { WhatsAppRuntimeConfig } from './whatsapp-runtime.config.js';

type ClaimedMessage = Readonly<{
  id: string;
}>;

type UnknownRecord = Record<string, unknown>;

type MetaSendResponse = Readonly<{
  messages?: readonly Readonly<{
    id?: string;
  }>[];
}>;

export type WhatsAppOutboundTickSummary = Readonly<{
  claimed: number;

  sent: number;

  retried: number;

  failed: number;

  disabled: number;
}>;

function addMilliseconds(date: Date, milliseconds: number): Date {
  return new Date(date.getTime() + milliseconds);
}

function isRecord(value: unknown): value is UnknownRecord {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function readString(value: unknown): string | null {
  return typeof value === 'string' ? value : null;
}

function getErrorMessage(error: unknown): string {
  return (error instanceof Error ? error.message : String(error)).slice(0, 500);
}

export class WhatsAppOutboundDispatcherService {
  constructor(
    private readonly database: CrmDatabaseClient,

    private readonly workerId: string,

    private readonly config: WhatsAppRuntimeConfig,

    private readonly metaClient: MetaCloudApiClient | null,
  ) {}

  async runTick(): Promise<WhatsAppOutboundTickSummary> {
    await this.failExpiredSendingMessages();
    let claimed = 0;

    let sent = 0;

    let retried = 0;

    let failed = 0;

    let disabled = 0;

    for (let index = 0; index < this.config.outboundMaxClaimsPerTick; index += 1) {
      const message = await this.claimNextMessage();

      if (!message) {
        break;
      }

      claimed += 1;

      if (!this.metaClient) {
        await this.releaseDisabled(message);

        disabled += 1;

        continue;
      }

      try {
        await this.sendClaimedMessage(message);

        sent += 1;
      } catch (error) {
        const result = await this.handleSendFailure(message, error);

        if (result === 'RETRY') {
          retried += 1;
        } else {
          failed += 1;
        }
      }
    }

    return {
      claimed,
      sent,
      retried,
      failed,
      disabled,
    };
  }

  private async failExpiredSendingMessages(): Promise<void> {
    const now = new Date();

    const expired = await this.database.whatsAppMessage.findMany({
      where: {
        direction: 'OUTBOUND',

        status: 'SENDING',

        metaMessageId: null,

        leaseExpiresAt: {
          lte: now,
        },
      },

      select: {
        id: true,

        organizationId: true,

        attempts: true,
      },

      take: 100,
    });

    for (const message of expired) {
      const updated = await this.database.whatsAppMessage.updateMany({
        where: {
          id: message.id,

          direction: 'OUTBOUND',

          status: 'SENDING',

          metaMessageId: null,

          leaseExpiresAt: {
            lte: now,
          },
        },

        data: {
          status: 'FAILED',

          failedAt: now,

          errorCode: 'OUTBOUND_DELIVERY_UNKNOWN_AFTER_LEASE',

          errorMessage:
            'Worker lease expired while provider delivery outcome was unknown. Automatic resend was blocked to prevent duplicate customer messages.',

          claimedAt: null,

          claimedByWorkerId: null,

          leaseExpiresAt: null,
        },
      });

      if (updated.count !== 1) {
        continue;
      }

      await this.database.auditLog.create({
        data: {
          organizationId: message.organizationId,

          actorType: 'SYSTEM',

          action: 'whatsapp.outbound.delivery_unknown_after_lease',

          resourceType: 'whatsapp_message',

          resourceId: message.id,

          outcome: 'FAILURE',

          metadata: {
            attempts: message.attempts,

            automaticResendBlocked: true,
          },
        },
      });
    }
  }
  private async claimNextMessage(): Promise<ClaimedMessage | null> {
    const rows = await this.database.$queryRawUnsafe<ClaimedMessage[]>(
      `
        WITH candidate AS (
          SELECT
            "id"
          FROM
            "whatsapp_messages"
          WHERE
            "direction" = 'OUTBOUND'
            AND "status" = 'QUEUED'
            AND "availableAt" <= NOW()
          ORDER BY
            "availableAt" ASC,
            "createdAt" ASC,
            "id" ASC
          FOR UPDATE SKIP LOCKED
          LIMIT 1
        )
        UPDATE
          "whatsapp_messages" AS message
        SET
          "status" = 'SENDING',
          "claimedAt" = NOW(),
          "claimedByWorkerId" = $1,
          "leaseExpiresAt" =
            NOW() + ($2::int * INTERVAL '1 millisecond'),
          "lastAttemptAt" = NOW(),
          "attempts" =
            message."attempts" + 1,
          "updatedAt" = NOW()
        FROM
          candidate
        WHERE
          message."id" = candidate."id"
        RETURNING
          message."id"
        `,
      this.workerId,
      this.config.outboundLeaseMs,
    );

    return rows[0] ?? null;
  }

  private async sendClaimedMessage(claimed: ClaimedMessage): Promise<void> {
    if (!this.metaClient) {
      throw new Error('Meta Cloud API is not configured.');
    }

    const message = await this.database.whatsAppMessage.findFirst({
      where: {
        id: claimed.id,

        direction: 'OUTBOUND',

        status: 'SENDING',

        claimedByWorkerId: this.workerId,

        leaseExpiresAt: {
          gt: new Date(),
        },
      },

      include: {
        contact: {
          select: {
            waId: true,
          },
        },

        conversation: {
          select: {
            customerServiceWindowExpiresAt: true,
          },
        },

        whatsAppNumber: {
          select: {
            metaPhoneNumberId: true,

            status: true,
          },
        },
      },
    });

    if (!message) {
      return;
    }

    if (message.whatsAppNumber.status !== 'ACTIVE' || !message.whatsAppNumber.metaPhoneNumberId) {
      throw new MetaCloudApiError({
        status: 400,

        message: 'WhatsApp number is not connected to Meta.',

        code: null,

        errorSubcode: null,

        metaType: 'LOCAL_CONFIGURATION',

        fbtraceId: null,

        requestId: null,
      });
    }

    if (
      message.type === 'TEXT' &&
      (!message.conversation.customerServiceWindowExpiresAt ||
        message.conversation.customerServiceWindowExpiresAt <= new Date())
    ) {
      throw new MetaCloudApiError({
        status: 400,

        message: 'The 24-hour customer service window is closed.',

        code: null,

        errorSubcode: null,

        metaType: 'LOCAL_POLICY_WINDOW_CLOSED',

        fbtraceId: null,

        requestId: null,
      });
    }
    const body = this.buildMetaPayload(
      message.type,
      message.textBody,
      message.replyToMetaMessageId,
      message.content,
      message.contact.waId,
    );

    const response = await this.metaClient.post<MetaSendResponse>(
      `${message.whatsAppNumber.metaPhoneNumberId}/messages`,
      body,
    );

    const metaMessageId = response.messages?.[0]?.id?.trim();

    if (!metaMessageId) {
      throw new Error('Meta accepted the request without returning a WhatsApp message id.');
    }

    const sentAt = new Date();

    const updated = await this.database.whatsAppMessage.updateMany({
      where: {
        id: message.id,

        status: 'SENDING',

        claimedByWorkerId: this.workerId,
      },

      data: {
        status: 'SENT',

        metaMessageId,

        sentAt,

        claimedAt: null,

        claimedByWorkerId: null,

        leaseExpiresAt: null,

        errorCode: null,

        errorMessage: null,
      },
    });

    if (updated.count === 0) {
      throw new Error(
        'Outbound send succeeded but the local worker lease was lost before persistence.',
      );
    }

    await this.database.whatsAppConversation.update({
      where: {
        id: message.conversationId,
      },

      data: {
        lastOutboundAt: sentAt,

        lastMessageAt: sentAt,
      },
    });

    await this.database.whatsAppContact.update({
      where: {
        id: message.contactId,
      },

      data: {
        lastOutboundAt: sentAt,
      },
    });

    await this.reconcilePendingStatuses(message.organizationId, message.id, metaMessageId);
  }

  private buildMetaPayload(
    type: string,
    textBody: string | null,
    replyToMetaMessageId: string | null,
    content: unknown,
    recipientWaId: string,
  ): Readonly<Record<string, unknown>> {
    if (type === 'TEXT') {
      if (!textBody) {
        throw new Error('TEXT outbound message has no text body.');
      }

      return {
        messaging_product: 'whatsapp',

        recipient_type: 'individual',

        to: recipientWaId,

        type: 'text',

        text: {
          body: textBody,
        },

        ...(replyToMetaMessageId
          ? {
              context: {
                message_id: replyToMetaMessageId,
              },
            }
          : {}),
      };
    }

    if (type === 'TEMPLATE') {
      const root = isRecord(content) ? content : null;

      const template = root && isRecord(root.template) ? root.template : null;

      const name = readString(template?.name);

      const languageCode = readString(template?.languageCode);

      if (!name || !languageCode) {
        throw new Error('TEMPLATE outbound message is missing template metadata.');
      }

      return {
        messaging_product: 'whatsapp',

        recipient_type: 'individual',

        to: recipientWaId,

        type: 'template',

        template: {
          name,

          language: {
            code: languageCode,
          },

          ...(Array.isArray(template?.components)
            ? {
                components: template.components,
              }
            : {}),
        },
      };
    }

    throw new Error(`Outbound message type ${type} is not supported in Stage 9.`);
  }

  private async reconcilePendingStatuses(
    organizationId: string,
    messageId: string,
    metaMessageId: string,
  ): Promise<void> {
    const events = await this.database.whatsAppMessageStatusEvent.findMany({
      where: {
        organizationId,

        metaMessageId,
      },

      orderBy: [
        {
          providerTimestamp: 'asc',
        },

        {
          createdAt: 'asc',
        },
      ],
    });

    if (events.length === 0) {
      return;
    }

    let status: 'SENT' | 'DELIVERED' | 'READ' | 'FAILED' | 'DELETED' = 'SENT';

    let sentAt: Date | null = null;

    let deliveredAt: Date | null = null;

    let readAt: Date | null = null;

    let failedAt: Date | null = null;

    for (const event of events) {
      if (event.status === 'SENT') {
        sentAt = sentAt ?? event.providerTimestamp;
      }

      if (event.status === 'DELIVERED') {
        status = 'DELIVERED';

        sentAt = sentAt ?? event.providerTimestamp;

        deliveredAt = event.providerTimestamp;
      }

      if (event.status === 'READ') {
        status = 'READ';

        sentAt = sentAt ?? event.providerTimestamp;

        deliveredAt = deliveredAt ?? event.providerTimestamp;

        readAt = event.providerTimestamp;
      }

      if (event.status === 'FAILED' && status !== 'DELIVERED' && status !== 'READ') {
        status = 'FAILED';

        failedAt = event.providerTimestamp;
      }

      if (event.status === 'DELETED') {
        status = 'DELETED';
      }
    }

    await this.database.whatsAppMessage.update({
      where: {
        id: messageId,
      },

      data: {
        status,

        ...(sentAt
          ? {
              sentAt,
            }
          : {}),

        ...(deliveredAt
          ? {
              deliveredAt,
            }
          : {}),

        ...(readAt
          ? {
              readAt,
            }
          : {}),

        ...(failedAt
          ? {
              failedAt,
            }
          : {}),
      },
    });

    await this.database.whatsAppMessageStatusEvent.updateMany({
      where: {
        organizationId,

        metaMessageId,

        appliedAt: null,
      },

      data: {
        appliedAt: new Date(),
      },
    });
  }

  private async releaseDisabled(claimed: ClaimedMessage): Promise<void> {
    await this.database.whatsAppMessage.updateMany({
      where: {
        id: claimed.id,

        status: 'SENDING',

        claimedByWorkerId: this.workerId,
      },

      data: {
        status: 'QUEUED',

        availableAt: addMilliseconds(new Date(), this.config.outboundDisabledRetryMs),

        claimedAt: null,

        claimedByWorkerId: null,

        leaseExpiresAt: null,
      },
    });
  }

  private async handleSendFailure(
    claimed: ClaimedMessage,
    error: unknown,
  ): Promise<'RETRY' | 'FAILED'> {
    const message = await this.database.whatsAppMessage.findUnique({
      where: {
        id: claimed.id,
      },

      select: {
        attempts: true,

        status: true,

        claimedByWorkerId: true,
      },
    });

    if (!message || message.status !== 'SENDING' || message.claimedByWorkerId !== this.workerId) {
      return 'FAILED';
    }

    /*
     * A generic network/timeout error has uncertain provider outcome.
     * We do NOT blindly resend it because that could duplicate a
     * customer-facing WhatsApp message.
     */
    const uncertainOutcome = !(error instanceof MetaCloudApiError);

    const metaError = error instanceof MetaCloudApiError ? error : null;

    const retryableMetaError = Boolean(
      metaError && (metaError.status === 429 || metaError.status >= 500),
    );

    const terminal =
      uncertainOutcome ||
      !retryableMetaError ||
      message.attempts >= this.config.outboundMaxAttempts;

    if (terminal) {
      await this.database.whatsAppMessage.update({
        where: {
          id: claimed.id,
        },

        data: {
          status: 'FAILED',

          failedAt: new Date(),

          errorCode: uncertainOutcome
            ? 'OUTBOUND_DELIVERY_UNKNOWN'
            : metaError?.metaType === 'LOCAL_POLICY_WINDOW_CLOSED'
              ? 'WHATSAPP_CUSTOMER_SERVICE_WINDOW_CLOSED'
              : metaError?.code !== null && metaError?.code !== undefined
                ? `META_${metaError.code}`
                : 'META_SEND_FAILED',

          errorMessage: getErrorMessage(error),

          claimedAt: null,

          claimedByWorkerId: null,

          leaseExpiresAt: null,
        },
      });

      return 'FAILED';
    }

    const retryDelay = Math.min(
      this.config.outboundRetryBaseMs * 2 ** Math.max(0, message.attempts - 1),
      15 * 60 * 1000,
    );

    await this.database.whatsAppMessage.update({
      where: {
        id: claimed.id,
      },

      data: {
        status: 'QUEUED',

        availableAt: addMilliseconds(new Date(), retryDelay),

        errorCode:
          metaError?.code !== null && metaError?.code !== undefined
            ? `META_${metaError.code}`
            : 'META_RETRYABLE_ERROR',

        errorMessage: getErrorMessage(error),

        claimedAt: null,

        claimedByWorkerId: null,

        leaseExpiresAt: null,
      },
    });

    return 'RETRY';
  }
}
