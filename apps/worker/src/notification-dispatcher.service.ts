import type { CrmDatabaseClient } from '@crm/database';

import {
  isNotificationDispatcherEnabled,
  type NotificationDispatcherConfig,
} from './notification-dispatcher.config.js';

import { sendOneSignalPush, type PushMessage, type PushSendResult } from './onesignal-sender.js';

type ClaimedDelivery = Readonly<{
  id: string;
}>;

export type NotificationSender = (
  config: NotificationDispatcherConfig,
  message: PushMessage,
) => Promise<PushSendResult>;

export type NotificationTickSummary = Readonly<{
  enabled: boolean;
  claimed: number;
  sent: number;
  failed: number;
  deferred: number;
  skipped: number;
}>;

function addMilliseconds(value: Date, milliseconds: number): Date {
  return new Date(value.getTime() + milliseconds);
}

function errorMessage(error: unknown): string {
  return (error instanceof Error ? error.message : String(error)).slice(0, 500);
}

export class NotificationDispatcherService {
  constructor(
    private readonly database: CrmDatabaseClient,

    private readonly workerId: string,

    private readonly config: NotificationDispatcherConfig,

    private readonly sender: NotificationSender = sendOneSignalPush,
  ) {}

  async runTick(): Promise<NotificationTickSummary> {
    if (!isNotificationDispatcherEnabled(this.config)) {
      return {
        enabled: false,
        claimed: 0,
        sent: 0,
        failed: 0,
        deferred: 0,
        skipped: 0,
      };
    }

    let claimed = 0;
    let sent = 0;
    let failed = 0;
    let deferred = 0;
    let skipped = 0;

    for (let index = 0; index < this.config.maxClaimsPerTick; index += 1) {
      const delivery = await this.claimNext();

      if (!delivery) {
        break;
      }

      claimed += 1;

      const result = await this.process(delivery.id);

      if (result === 'SENT') {
        sent += 1;
      }

      if (result === 'FAILED') {
        failed += 1;
      }

      if (result === 'DEFERRED') {
        deferred += 1;
      }

      if (result === 'SKIPPED') {
        skipped += 1;
      }
    }

    return {
      enabled: true,
      claimed,
      sent,
      failed,
      deferred,
      skipped,
    };
  }

  private async claimNext(): Promise<ClaimedDelivery | null> {
    const rows = await this.database.$queryRawUnsafe<ClaimedDelivery[]>(
      `
          WITH candidate AS (
            SELECT
              "id"
            FROM
              "notification_deliveries"
            WHERE
              (
                (
                  "status" = 'WAITING'
                  AND "nextAttemptAt" <= NOW()
                )
                OR
                (
                  "status" = 'CLAIMED'
                  AND "leaseExpiresAt" IS NOT NULL
                  AND "leaseExpiresAt" <= NOW()
                )
              )
            ORDER BY
              "nextAttemptAt" ASC,
              "createdAt" ASC,
              "id" ASC
            FOR UPDATE SKIP LOCKED
            LIMIT 1
          )
          UPDATE
            "notification_deliveries" delivery
          SET
            "status" = 'CLAIMED',
            "claimedAt" = NOW(),
            "claimedByWorkerId" = $1,
            "leaseExpiresAt" =
              NOW() + ($2::int * INTERVAL '1 millisecond'),
            "attempts" =
              delivery."attempts" + 1,
            "updatedAt" = NOW()
          FROM
            candidate
          WHERE
            delivery."id" =
              candidate."id"
          RETURNING
            delivery."id"
        `,
      this.workerId,
      this.config.leaseMs,
    );

    return rows[0] ?? null;
  }

  private async process(deliveryId: string): Promise<'SENT' | 'FAILED' | 'DEFERRED' | 'SKIPPED'> {
    const delivery = await this.database.notificationDelivery.findFirst({
      where: {
        id: deliveryId,

        status: 'CLAIMED',

        claimedByWorkerId: this.workerId,

        leaseExpiresAt: {
          gt: new Date(),
        },
      },

      include: {
        notification: true,
      },
    });

    if (!delivery) {
      return 'DEFERRED';
    }

    const notification = delivery.notification;

    if (notification.status === 'CANCELLED') {
      await this.skip(delivery.id, notification.id, 'Notification cancelled.');

      return 'SKIPPED';
    }

    const preference = await this.database.notificationPreference.findUnique({
      where: {
        organizationId_userId: {
          organizationId: delivery.organizationId,

          userId: delivery.userId,
        },
      },
    });

    if (preference && !preference.pushEnabled) {
      await this.skip(delivery.id, notification.id, 'Push notifications disabled by user.');

      return 'SKIPPED';
    }

    const activeDeviceCount = await this.database.pushDevice.count({
      where: {
        organizationId: delivery.organizationId,

        userId: delivery.userId,

        status: 'ACTIVE',

        optedIn: true,
      },
    });

    if (activeDeviceCount === 0) {
      await this.skip(delivery.id, notification.id, 'No active push device.');

      return 'SKIPPED';
    }

    await this.database.notification.update({
      where: {
        id: notification.id,
      },

      data: {
        status: 'PROCESSING',
      },
    });

    try {
      const result = await this.sender(this.config, {
        externalId: delivery.userId,

        title: notification.title,

        body: notification.body,

        url: notification.url,

        data: notification.data,
      });

      const now = new Date();

      await this.database.$transaction(async (transaction) => {
        await transaction.notificationDelivery.update({
          where: {
            id: delivery.id,
          },

          data: {
            status: 'SENT',

            providerMessageId: result.providerMessageId,

            sentAt: now,

            claimedAt: null,

            claimedByWorkerId: null,

            leaseExpiresAt: null,

            lastError: null,
          },
        });

        await transaction.notification.update({
          where: {
            id: notification.id,
          },

          data: {
            status: 'SENT',

            processedAt: now,

            failureReason: null,
          },
        });

        await transaction.auditLog.create({
          data: {
            organizationId: delivery.organizationId,

            actorType: 'SYSTEM',

            action: 'notification.sent',

            resourceType: 'notification',

            resourceId: notification.id,

            outcome: 'SUCCESS',

            metadata: {
              provider: delivery.provider,

              providerMessageId: result.providerMessageId,

              attempts: delivery.attempts,
            },
          },
        });
      });

      return 'SENT';
    } catch (error) {
      const message = errorMessage(error);

      if (delivery.attempts >= this.config.maxAttempts) {
        const now = new Date();

        await this.database.$transaction(async (transaction) => {
          await transaction.notificationDelivery.update({
            where: {
              id: delivery.id,
            },

            data: {
              status: 'FAILED',

              failedAt: now,

              lastError: message,

              claimedAt: null,

              claimedByWorkerId: null,

              leaseExpiresAt: null,
            },
          });

          await transaction.notification.update({
            where: {
              id: notification.id,
            },

            data: {
              status: 'FAILED',

              processedAt: now,

              failureReason: message,
            },
          });

          await transaction.auditLog.create({
            data: {
              organizationId: delivery.organizationId,

              actorType: 'SYSTEM',

              action: 'notification.failed',

              resourceType: 'notification',

              resourceId: notification.id,

              outcome: 'FAILURE',

              metadata: {
                provider: delivery.provider,

                attempts: delivery.attempts,
              },
            },
          });
        });

        return 'FAILED';
      }

      const retryDelay =
        this.config.retryBaseMs * Math.min(2 ** Math.max(0, delivery.attempts - 1), 64);

      await this.database.$transaction(async (transaction) => {
        await transaction.notificationDelivery.update({
          where: {
            id: delivery.id,
          },

          data: {
            status: 'WAITING',

            nextAttemptAt: addMilliseconds(new Date(), retryDelay),

            lastError: message,

            claimedAt: null,

            claimedByWorkerId: null,

            leaseExpiresAt: null,
          },
        });

        await transaction.notification.update({
          where: {
            id: notification.id,
          },

          data: {
            status: 'QUEUED',

            failureReason: null,
          },
        });
      });

      return 'DEFERRED';
    }
  }

  private async skip(deliveryId: string, notificationId: string, reason: string): Promise<void> {
    const now = new Date();

    await this.database.$transaction(async (transaction) => {
      await transaction.notificationDelivery.update({
        where: {
          id: deliveryId,
        },

        data: {
          status: 'SKIPPED',

          claimedAt: null,

          claimedByWorkerId: null,

          leaseExpiresAt: null,

          lastError: reason,
        },
      });

      await transaction.notification.update({
        where: {
          id: notificationId,
        },

        data: {
          status: 'SKIPPED',

          processedAt: now,

          failureReason: reason,
        },
      });
    });
  }
}
