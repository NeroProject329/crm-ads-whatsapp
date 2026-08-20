import type {
  CrmDatabaseClient,
  MetaPhoneQualityRating,
  WhatsAppNumberHealthSource,
  WhatsAppNumberHealthStatus,
} from '@crm/database';

import type {
  MetaPhoneNumberQualityRating,
  MetaPhoneNumberQualityUpdate,
} from '@crm/meta-cloud-api';

type TransactionClient = Parameters<Parameters<CrmDatabaseClient['$transaction']>[0]>[0];

type ApplySignalInput = Readonly<{
  organizationId: string;

  whatsAppNumberId: string;

  source: WhatsAppNumberHealthSource;

  sourceEnvelopeId?: string | null;

  qualityRating?: MetaPhoneNumberQualityRating;

  qualityEvent?: string | null;

  currentLimit?: string | null;

  observedAt: Date;
}>;

function mapQuality(value: MetaPhoneNumberQualityRating): MetaPhoneQualityRating {
  switch (value) {
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

export class WhatsAppNumberHealthDomainService {
  constructor(private readonly recoveryHealthyChecks: number = 2) {}

  async applyMetaWebhook(
    transaction: TransactionClient,

    input: Readonly<{
      organizationId: string;

      whatsAppNumberId: string;

      sourceEnvelopeId: string;

      update: MetaPhoneNumberQualityUpdate;

      observedAt: Date;
    }>,
  ): Promise<void> {
    await this.applySignal(transaction, {
      organizationId: input.organizationId,

      whatsAppNumberId: input.whatsAppNumberId,

      source: 'META_WEBHOOK',

      sourceEnvelopeId: input.sourceEnvelopeId,

      qualityEvent: input.update.event,

      currentLimit: input.update.currentLimit,

      observedAt: input.observedAt,
    });
  }

  async applyMetaApi(
    transaction: TransactionClient,

    input: Readonly<{
      organizationId: string;

      whatsAppNumberId: string;

      qualityRating: MetaPhoneNumberQualityRating;

      observedAt: Date;
    }>,
  ): Promise<void> {
    await this.applySignal(transaction, {
      organizationId: input.organizationId,

      whatsAppNumberId: input.whatsAppNumberId,

      source: 'META_API',

      qualityRating: input.qualityRating,

      observedAt: input.observedAt,
    });
  }

  private async applySignal(
    transaction: TransactionClient,

    input: ApplySignalInput,
  ): Promise<void> {
    await transaction.$queryRawUnsafe(
      'WITH lock_guard AS MATERIALIZED (SELECT pg_advisory_xact_lock(hashtextextended($1, 0))) SELECT TRUE AS locked FROM lock_guard',
      `whatsapp-number-health:${input.organizationId}:${input.whatsAppNumberId}`,
    );

    const state = await transaction.whatsAppNumberHealthState.upsert({
      where: {
        organizationId_whatsAppNumberId: {
          organizationId: input.organizationId,

          whatsAppNumberId: input.whatsAppNumberId,
        },
      },

      create: {
        organizationId: input.organizationId,

        whatsAppNumberId: input.whatsAppNumberId,
      },

      update: {},
    });

    const nextQuality = input.qualityRating
      ? mapQuality(input.qualityRating)
      : state.metaQualityRating;

    const normalizedEvent = input.qualityEvent?.trim().toUpperCase() ?? null;

    let nextStatus: WhatsAppNumberHealthStatus = state.status;

    let nextEligible = state.schedulerEligible;

    let healthyChecks = state.consecutiveHealthyChecks;

    let reasonCode: string | null = state.lastReasonCode;

    let reasonMessage: string | null = state.lastReasonMessage;

    if (state.manualPaused) {
      nextStatus = 'DISABLED';

      nextEligible = false;

      reasonCode = 'MANUAL_PAUSE';

      reasonMessage = 'WhatsApp number is manually paused.';
    } else if (
      normalizedEvent === 'FLAGGED' ||
      (nextQuality === 'RED' && normalizedEvent !== 'UNFLAGGED')
    ) {
      nextStatus = 'CRITICAL';

      nextEligible = false;

      healthyChecks = 0;

      reasonCode = normalizedEvent === 'FLAGGED' ? 'META_QUALITY_FLAGGED' : 'META_QUALITY_RED';

      reasonMessage = 'Meta reported a critical phone number quality signal.';
    } else if (
      (nextQuality === 'YELLOW' && normalizedEvent !== 'UNFLAGGED') ||
      normalizedEvent === 'DOWNGRADE'
    ) {
      nextStatus = 'DEGRADED';

      nextEligible = false;

      healthyChecks = 0;

      reasonCode =
        normalizedEvent === 'DOWNGRADE' ? 'META_QUALITY_DOWNGRADE' : 'META_QUALITY_YELLOW';

      reasonMessage = 'Meta reported a degraded phone number quality signal.';
    } else if (normalizedEvent === 'UNFLAGGED') {
      nextStatus = 'RECOVERING';

      nextEligible = false;

      healthyChecks = 0;

      reasonCode = 'META_QUALITY_UNFLAGGED';

      reasonMessage = 'Meta removed the quality flag; recovery confirmation is required.';
    } else if (nextQuality === 'GREEN') {
      if (
        state.status === 'CRITICAL' ||
        state.status === 'DEGRADED' ||
        state.status === 'RECOVERING'
      ) {
        healthyChecks = state.consecutiveHealthyChecks + 1;

        if (healthyChecks >= this.recoveryHealthyChecks) {
          nextStatus = 'HEALTHY';

          nextEligible = true;

          reasonCode = 'META_QUALITY_GREEN_CONFIRMED';

          reasonMessage = 'Meta quality recovered and passed consecutive green confirmation.';
        } else {
          nextStatus = 'RECOVERING';

          nextEligible = false;

          reasonCode = 'META_QUALITY_GREEN_RECOVERING';

          reasonMessage = 'Meta quality is green but recovery confirmation is still in progress.';
        }
      } else {
        nextStatus = 'HEALTHY';

        nextEligible = true;

        healthyChecks = Math.max(1, state.consecutiveHealthyChecks);

        reasonCode = 'META_QUALITY_GREEN';

        reasonMessage = 'Meta reported high phone number quality.';
      }
    } else if (state.status === 'UNKNOWN' && (nextQuality === 'NA' || nextQuality === 'UNKNOWN')) {
      nextStatus = 'UNKNOWN';

      nextEligible = true;

      reasonCode = 'META_QUALITY_UNDETERMINED';

      reasonMessage = 'Meta has not determined phone number quality.';
    }

    if (state.schedulerEligible && !nextEligible) {
      await this.releaseReservedCapacity(
        transaction,
        input.organizationId,
        input.whatsAppNumberId,
        nextStatus,
        input.observedAt,
      );
    }

    const statusChanged = nextStatus !== state.status;

    const qualityChanged = nextQuality !== state.metaQualityRating;

    const eventChanged = normalizedEvent !== null && normalizedEvent !== state.metaQualityEvent;

    const limitChanged =
      input.currentLimit !== undefined && (input.currentLimit ?? null) !== state.messagingLimitTier;

    await transaction.whatsAppNumberHealthState.update({
      where: {
        id: state.id,
      },

      data: {
        status: nextStatus,

        schedulerEligible: nextEligible,

        metaQualityRating: nextQuality,

        ...(normalizedEvent !== null
          ? {
              metaQualityEvent: normalizedEvent,
            }
          : {}),

        ...(input.currentLimit !== undefined
          ? {
              messagingLimitTier: input.currentLimit,
            }
          : {}),

        lastReasonCode: reasonCode,

        lastReasonMessage: reasonMessage,

        ...(input.source === 'META_API'
          ? {
              lastMetaSyncAt: input.observedAt,

              consecutiveSyncFailures: 0,
            }
          : {}),

        ...(input.source === 'META_WEBHOOK'
          ? {
              lastMetaWebhookAt: input.observedAt,

              nextCheckAt: input.observedAt,
            }
          : {}),

        consecutiveHealthyChecks: healthyChecks,

        ...(nextStatus === 'HEALTHY'
          ? {
              lastHealthyAt: input.observedAt,

              degradedSinceAt: null,

              criticalSinceAt: null,

              recoveringSinceAt: null,
            }
          : {}),

        ...(nextStatus === 'DEGRADED' && state.status !== 'DEGRADED'
          ? {
              degradedSinceAt: input.observedAt,
            }
          : {}),

        ...(nextStatus === 'CRITICAL' && state.status !== 'CRITICAL'
          ? {
              criticalSinceAt: input.observedAt,
            }
          : {}),

        ...(nextStatus === 'RECOVERING' && state.status !== 'RECOVERING'
          ? {
              recoveringSinceAt: input.observedAt,
            }
          : {}),
      },
    });

    if (statusChanged || qualityChanged || eventChanged || limitChanged) {
      await transaction.whatsAppNumberHealthEvent.create({
        data: {
          organizationId: input.organizationId,

          whatsAppNumberId: input.whatsAppNumberId,

          sourceEnvelopeId: input.sourceEnvelopeId ?? null,

          source: input.source,

          previousStatus: state.status,

          currentStatus: nextStatus,

          metaQualityRating: nextQuality,

          metaQualityEvent: normalizedEvent,

          messagingLimitTier: input.currentLimit ?? state.messagingLimitTier,

          schedulerEligible: nextEligible,

          reasonCode,

          reasonMessage,

          occurredAt: input.observedAt,
        },
      });
    }

    if (nextStatus === 'DEGRADED' || nextStatus === 'CRITICAL') {
      const openIncident = await transaction.whatsAppNumberIncident.findFirst({
        where: {
          organizationId: input.organizationId,

          whatsAppNumberId: input.whatsAppNumberId,

          status: 'OPEN',

          type: 'META_QUALITY',
        },
      });

      if (openIncident) {
        await transaction.whatsAppNumberIncident.update({
          where: {
            id: openIncident.id,
          },

          data: {
            severity: nextStatus,

            openedReasonCode: reasonCode,

            openedReason: reasonMessage,
          },
        });
      } else {
        await transaction.whatsAppNumberIncident.create({
          data: {
            organizationId: input.organizationId,

            whatsAppNumberId: input.whatsAppNumberId,

            type: 'META_QUALITY',

            severity: nextStatus,

            openedReasonCode: reasonCode,

            openedReason: reasonMessage,

            openedAt: input.observedAt,
          },
        });
      }
    }

    if (nextStatus === 'HEALTHY') {
      await transaction.whatsAppNumberIncident.updateMany({
        where: {
          organizationId: input.organizationId,

          whatsAppNumberId: input.whatsAppNumberId,

          status: 'OPEN',

          type: 'META_QUALITY',
        },

        data: {
          status: 'RESOLVED',

          resolvedAt: input.observedAt,

          resolvedReason: 'Meta quality returned to confirmed GREEN.',
        },
      });
    }
  }

  private async releaseReservedCapacity(
    transaction: TransactionClient,

    organizationId: string,

    whatsAppNumberId: string,

    healthStatus: WhatsAppNumberHealthStatus,

    now: Date,
  ): Promise<void> {
    const microbatches = await transaction.adsMicrobatch.findMany({
      where: {
        organizationId,

        whatsAppNumberId,

        status: {
          in: ['PLANNED', 'DELIVERING'],
        },

        adsRequest: {
          status: {
            in: ['PROCESSING', 'PARTIALLY_FULFILLED'],
          },
        },
      },

      include: {
        adsRequest: true,
      },

      orderBy: [
        {
          plannedAt: 'asc',
        },

        {
          sequence: 'asc',
        },

        {
          id: 'asc',
        },
      ],
    });

    let totalReleased = 0;

    for (const microbatch of microbatches) {
      const outstanding = Math.max(0, microbatch.reservedLeadCount - microbatch.deliveredLeadCount);

      if (outstanding <= 0) {
        continue;
      }

      await transaction.adsMicrobatch.update({
        where: {
          id: microbatch.id,
        },

        data: {
          status: 'CANCELLED',

          cancelledAt: now,

          failureReason: `WHATSAPP_NUMBER_${healthStatus}`,
        },
      });

      await transaction.adsRequest.update({
        where: {
          id: microbatch.adsRequestId,
        },

        data: {
          scheduledLeadCount: {
            decrement: outstanding,
          },

          status:
            microbatch.adsRequest.fulfilledLeadCount > 0 ? 'PARTIALLY_FULFILLED' : 'PROCESSING',

          completedAt: null,
        },
      });

      await transaction.adsQueueItem.updateMany({
        where: {
          organizationId,

          adsRequestId: microbatch.adsRequestId,

          status: {
            in: ['WAITING', 'CLAIMED', 'COMPLETED'],
          },
        },

        data: {
          status: 'WAITING',

          availableAt: now,

          completedAt: null,

          claimedAt: null,

          claimedByWorkerId: null,

          leaseExpiresAt: null,
        },
      });

      await transaction.auditLog.create({
        data: {
          organizationId,

          actorType: 'SYSTEM',

          action: 'ads_microbatch.contingency_released',

          resourceType: 'ads_microbatch',

          resourceId: microbatch.id,

          outcome: 'SUCCESS',

          metadata: {
            adsRequestId: microbatch.adsRequestId,

            whatsAppNumberId,

            healthStatus,

            reservedLeadCount: microbatch.reservedLeadCount,

            deliveredLeadCount: microbatch.deliveredLeadCount,

            releasedLeadCount: outstanding,
          },
        },
      });

      totalReleased += outstanding;
    }

    if (totalReleased > 0) {
      await transaction.auditLog.create({
        data: {
          organizationId,

          actorType: 'SYSTEM',

          action: 'whatsapp_number.contingency_activated',

          resourceType: 'whatsapp_number',

          resourceId: whatsAppNumberId,

          outcome: 'SUCCESS',

          metadata: {
            healthStatus,

            releasedLeadCount: totalReleased,

            microbatchesReleased: microbatches.length,
          },
        },
      });
    }
  }
}
