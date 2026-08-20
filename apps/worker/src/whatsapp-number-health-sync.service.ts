import type { CrmDatabaseClient } from '@crm/database';

import { getMetaPhoneNumberProfile } from '@crm/meta-cloud-api';

import type { MetaCloudApiClient } from '@crm/meta-cloud-api';

import type { WhatsAppNumberHealthConfig } from './whatsapp-number-health.config.js';

import { WhatsAppNumberHealthDomainService } from './whatsapp-number-health.service.js';

type ClaimedHealthState = Readonly<{
  id: string;
  organizationId: string;
  whatsAppNumberId: string;
  metaPhoneNumberId: string;
}>;

export type WhatsAppNumberHealthTickSummary = Readonly<{
  claimed: number;
  synced: number;
  failed: number;
}>;

function addMilliseconds(
  date: Date,

  milliseconds: number,
): Date {
  return new Date(date.getTime() + milliseconds);
}

function getErrorMessage(error: unknown): string {
  return (error instanceof Error ? error.message : String(error)).slice(0, 500);
}

export class WhatsAppNumberHealthSyncService {
  private readonly domain: WhatsAppNumberHealthDomainService;

  constructor(
    private readonly database: CrmDatabaseClient,

    private readonly workerId: string,

    private readonly config: WhatsAppNumberHealthConfig,

    private readonly metaClient: MetaCloudApiClient | null,
  ) {
    this.domain = new WhatsAppNumberHealthDomainService(config.recoveryHealthyChecks);
  }

  async runTick(): Promise<WhatsAppNumberHealthTickSummary> {
    if (!this.metaClient) {
      return {
        claimed: 0,

        synced: 0,

        failed: 0,
      };
    }

    await this.ensureMissingStates();

    let claimed = 0;

    let synced = 0;

    let failed = 0;

    for (let index = 0; index < this.config.maxClaimsPerTick; index += 1) {
      const item = await this.claimNext();

      if (!item) {
        break;
      }

      claimed += 1;

      try {
        const profile = await getMetaPhoneNumberProfile(this.metaClient, item.metaPhoneNumberId);

        const observedAt = new Date();

        await this.database.$transaction(async (transaction) => {
          await this.domain.applyMetaApi(transaction, {
            organizationId: item.organizationId,

            whatsAppNumberId: item.whatsAppNumberId,

            qualityRating: profile.qualityRating,

            observedAt,
          });

          await transaction.whatsAppNumberHealthState.updateMany({
            where: {
              id: item.id,

              claimedByWorkerId: this.workerId,
            },

            data: {
              nextCheckAt: addMilliseconds(observedAt, this.config.pollIntervalMs),

              claimedAt: null,

              claimedByWorkerId: null,

              leaseExpiresAt: null,
            },
          });
        });

        synced += 1;
      } catch (error) {
        failed += 1;

        const now = new Date();

        const current = await this.database.whatsAppNumberHealthState.findUnique({
          where: {
            id: item.id,
          },
        });

        if (current) {
          await this.database.$transaction(async (transaction) => {
            await transaction.whatsAppNumberHealthState.updateMany({
              where: {
                id: item.id,

                claimedByWorkerId: this.workerId,
              },

              data: {
                consecutiveSyncFailures: {
                  increment: 1,
                },

                lastReasonCode: 'META_HEALTH_SYNC_FAILED',

                lastReasonMessage: getErrorMessage(error),

                nextCheckAt: addMilliseconds(now, this.config.failureRetryMs),

                claimedAt: null,

                claimedByWorkerId: null,

                leaseExpiresAt: null,
              },
            });

            await transaction.whatsAppNumberHealthEvent.create({
              data: {
                organizationId: item.organizationId,

                whatsAppNumberId: item.whatsAppNumberId,

                source: 'META_API',

                previousStatus: current.status,

                currentStatus: current.status,

                metaQualityRating: current.metaQualityRating,

                metaQualityEvent: current.metaQualityEvent,

                messagingLimitTier: current.messagingLimitTier,

                schedulerEligible: current.schedulerEligible,

                reasonCode: 'META_HEALTH_SYNC_FAILED',

                reasonMessage: getErrorMessage(error),

                occurredAt: now,
              },
            });
          });
        }
      }
    }

    return {
      claimed,
      synced,
      failed,
    };
  }

  private async ensureMissingStates(): Promise<void> {
    const numbers = await this.database.whatsAppNumber.findMany({
      where: {
        deletedAt: null,

        status: 'ACTIVE',

        metaPhoneNumberId: {
          not: null,
        },

        healthState: {
          is: null,
        },
      },

      select: {
        id: true,

        organizationId: true,
      },

      take: 100,
    });

    if (numbers.length === 0) {
      return;
    }

    await this.database.whatsAppNumberHealthState.createMany({
      data: numbers.map((number) => ({
        organizationId: number.organizationId,

        whatsAppNumberId: number.id,
      })),

      skipDuplicates: true,
    });
  }

  private async claimNext(): Promise<ClaimedHealthState | null> {
    const rows = await this.database.$queryRawUnsafe<ClaimedHealthState[]>(
      `
        WITH candidate AS (
          SELECT
            state."id"
          FROM
            "whatsapp_number_health_states" AS state
          INNER JOIN
            "whatsapp_numbers" AS number
            ON number."organizationId" =
               state."organizationId"
            AND number."id" =
                state."whatsAppNumberId"
          WHERE
            number."deletedAt" IS NULL
            AND number."status" = 'ACTIVE'
            AND number."metaPhoneNumberId" IS NOT NULL
            AND (
              (
                state."nextCheckAt" <= NOW()
                AND state."claimedByWorkerId" IS NULL
              )
              OR
              (
                state."leaseExpiresAt" IS NOT NULL
                AND state."leaseExpiresAt" <= NOW()
              )
            )
          ORDER BY
            state."nextCheckAt" ASC,
            state."id" ASC
          FOR UPDATE OF state SKIP LOCKED
          LIMIT 1
        )
        UPDATE
          "whatsapp_number_health_states" AS state
        SET
          "claimedAt" = NOW(),
          "claimedByWorkerId" = $1,
          "leaseExpiresAt" =
            NOW() + ($2::int * INTERVAL '1 millisecond'),
          "updatedAt" = NOW()
        FROM
          candidate,
          "whatsapp_numbers" AS number
        WHERE
          state."id" = candidate."id"
          AND number."organizationId" =
              state."organizationId"
          AND number."id" =
              state."whatsAppNumberId"
        RETURNING
          state."id",
          state."organizationId",
          state."whatsAppNumberId",
          number."metaPhoneNumberId"
        `,
      this.workerId,
      this.config.leaseMs,
    );

    return rows.at(0) ?? null;
  }
}
