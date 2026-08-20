import type { CrmDatabaseClient } from '@crm/database';

import { computeBatchSize, selectRoundRobinMember } from './scheduler-engine.js';

import type { AdsSchedulerConfig } from './scheduler.config.js';

type ClaimedQueueItem = Readonly<{
  id: string;
  employeeId: string;
  trafficPoolId: string;
}>;

type ProcessResult = 'PLANNED' | 'DEFERRED' | 'FAILED' | 'LOST_LEASE' | 'SKIPPED';

export type SchedulerTickSummary = Readonly<{
  claimed: number;
  planned: number;
  deferred: number;
  failed: number;
  lostLease: number;
}>;

function addMilliseconds(date: Date, milliseconds: number): Date {
  return new Date(date.getTime() + milliseconds);
}

function getErrorMessage(error: unknown): string {
  if (error instanceof Error) {
    return error.message.slice(0, 500);
  }

  return String(error).slice(0, 500);
}

export class AdsSchedulerService {
  constructor(
    private readonly database: CrmDatabaseClient,
    private readonly workerId: string,
    private readonly config: AdsSchedulerConfig,
  ) {}

  async runTick(): Promise<SchedulerTickSummary> {
    let claimedCount = 0;
    let plannedCount = 0;
    let deferredCount = 0;
    let failedCount = 0;
    let lostLeaseCount = 0;

    for (let index = 0; index < this.config.maxClaimsPerTick; index += 1) {
      const claimed = await this.claimNextQueueItem();

      if (!claimed) {
        break;
      }

      claimedCount += 1;

      try {
        const result = await this.processClaimedQueueItem(claimed);

        if (result === 'PLANNED') {
          plannedCount += 1;
        }

        if (result === 'DEFERRED') {
          deferredCount += 1;
        }

        if (result === 'FAILED') {
          failedCount += 1;
        }

        if (result === 'LOST_LEASE') {
          lostLeaseCount += 1;
        }
      } catch (error) {
        const recoveryResult = await this.handleProcessingError(claimed, error);

        if (recoveryResult === 'FAILED') {
          failedCount += 1;
        }

        if (recoveryResult === 'DEFERRED') {
          deferredCount += 1;
        }

        if (recoveryResult === 'LOST_LEASE') {
          lostLeaseCount += 1;
        }
      }
    }

    return {
      claimed: claimedCount,
      planned: plannedCount,
      deferred: deferredCount,
      failed: failedCount,
      lostLease: lostLeaseCount,
    };
  }

  private async claimNextQueueItem(): Promise<ClaimedQueueItem | null> {
    const rows = await this.database.$queryRawUnsafe<ClaimedQueueItem[]>(
      `
          WITH candidate AS (
            SELECT
              "id"
            FROM
              "ads_queue_items"
            WHERE
              (
                (
                  "status" = 'WAITING'
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
              "priority" ASC,
              "availableAt" ASC,
              "enqueuedAt" ASC,
              "id" ASC
            FOR UPDATE SKIP LOCKED
            LIMIT 1
          )
          UPDATE
            "ads_queue_items" AS queue
          SET
            "status" = 'CLAIMED',
            "claimedAt" = NOW(),
            "claimedByWorkerId" = $1,
            "leaseExpiresAt" =
              NOW() + ($2::int * INTERVAL '1 millisecond'),
            "lastAttemptAt" = NOW(),
            "attempts" = queue."attempts" + 1,
            "updatedAt" = NOW()
          FROM
            candidate
          WHERE
            queue."id" = candidate."id"
          RETURNING
            queue."id",
            queue."employeeId",
            queue."trafficPoolId"
        `,
      this.workerId,
      this.config.leaseMs,
    );

    return rows[0] ?? null;
  }

  private async processClaimedQueueItem(claimed: ClaimedQueueItem): Promise<ProcessResult> {
    return this.database.$transaction(async (transaction) => {
      await transaction.$queryRawUnsafe(
        'WITH lock_guard AS MATERIALIZED (SELECT pg_advisory_xact_lock(hashtextextended($1, 0))) SELECT TRUE AS locked FROM lock_guard',
        `employee:${claimed.employeeId}`,
      );

      await transaction.$queryRawUnsafe(
        'WITH lock_guard AS MATERIALIZED (SELECT pg_advisory_xact_lock(hashtextextended($1, 0))) SELECT TRUE AS locked FROM lock_guard',
        `traffic-pool:${claimed.trafficPoolId}`,
      );

      const now = new Date();

      const queueItem = await transaction.adsQueueItem.findFirst({
        where: {
          id: claimed.id,
          status: 'CLAIMED',
          claimedByWorkerId: this.workerId,
          leaseExpiresAt: {
            gt: now,
          },
        },

        include: {
          adsRequest: true,

          trafficPool: {
            include: {
              site: true,
            },
          },
        },
      });

      if (!queueItem) {
        return 'LOST_LEASE';
      }

      const request = queueItem.adsRequest;

      if (request.status === 'CANCELLED') {
        await transaction.adsQueueItem.update({
          where: {
            id: queueItem.id,
          },

          data: {
            status: 'CANCELLED',
            cancelledAt: request.cancelledAt ?? now,
            claimedAt: null,
            claimedByWorkerId: null,
            leaseExpiresAt: null,
          },
        });

        return 'SKIPPED';
      }

      if (request.status === 'FULFILLED' || request.status === 'FAILED') {
        await transaction.adsQueueItem.update({
          where: {
            id: queueItem.id,
          },

          data: {
            status: request.status === 'FULFILLED' ? 'COMPLETED' : 'FAILED',

            completedAt: request.status === 'FULFILLED' ? now : null,

            claimedAt: null,
            claimedByWorkerId: null,
            leaseExpiresAt: null,
          },
        });

        return 'SKIPPED';
      }

      if (request.scheduledLeadCount >= request.requestedLeadCount) {
        await transaction.adsQueueItem.update({
          where: {
            id: queueItem.id,
          },

          data: {
            status: 'COMPLETED',
            completedAt: queueItem.completedAt ?? now,
            claimedAt: null,
            claimedByWorkerId: null,
            leaseExpiresAt: null,
          },
        });

        return 'SKIPPED';
      }

      const employee = await transaction.employee.findFirst({
        where: {
          id: queueItem.employeeId,
          organizationId: queueItem.organizationId,
          status: 'ACTIVE',
          deletedAt: null,
        },

        select: {
          id: true,
        },
      });

      if (!employee) {
        await this.deferClaimedQueueItem(
          transaction,
          queueItem.id,
          queueItem.organizationId,
          request.id,
          now,
          this.config.backpressureDelayMs,
          'ads_queue.employee_unavailable',
        );

        return 'DEFERRED';
      }

      if (
        queueItem.trafficPool.status !== 'ACTIVE' ||
        queueItem.trafficPool.deletedAt !== null ||
        queueItem.trafficPool.site.status !== 'ACTIVE' ||
        queueItem.trafficPool.site.deletedAt !== null
      ) {
        await this.deferClaimedQueueItem(
          transaction,
          queueItem.id,
          queueItem.organizationId,
          request.id,
          now,
          this.config.backpressureDelayMs,
          'ads_queue.pool_unavailable',
        );

        return 'DEFERRED';
      }

      const primaryDomain = await transaction.siteDomain.findFirst({
        where: {
          organizationId: queueItem.organizationId,

          siteId: queueItem.trafficPool.site.id,

          isPrimary: true,
          status: 'ACTIVE',
          deletedAt: null,
        },

        include: {
          monitorState: true,
        },
      });

      if (
        primaryDomain?.monitoringEnabled === true &&
        primaryDomain.monitorState?.status === 'DOWN'
      ) {
        await this.deferClaimedQueueItem(
          transaction,
          queueItem.id,
          queueItem.organizationId,
          request.id,
          now,
          this.config.backpressureDelayMs,
          'ads_queue.site_down',
        );

        return 'DEFERRED';
      }
      const eligibleMembers = await transaction.trafficPoolMember.findMany({
        where: {
          organizationId: queueItem.organizationId,
          trafficPoolId: queueItem.trafficPoolId,
          status: 'ACTIVE',

          whatsAppNumber: {
            deletedAt: null,
            status: 'ACTIVE',
            assignedEmployeeId: queueItem.employeeId,
          },
        },

        include: {
          whatsAppNumber: true,
        },

        orderBy: {
          position: 'asc',
        },
      });

      if (eligibleMembers.length === 0) {
        await this.deferClaimedQueueItem(
          transaction,
          queueItem.id,
          queueItem.organizationId,
          request.id,
          now,
          this.config.backpressureDelayMs,
          'ads_queue.no_eligible_number',
        );

        return 'DEFERRED';
      }

      const inflightAggregate = await transaction.adsMicrobatch.aggregate({
        where: {
          organizationId: queueItem.organizationId,
          employeeId: queueItem.employeeId,

          status: {
            in: ['PLANNED', 'DELIVERING'],
          },
        },

        _sum: {
          reservedLeadCount: true,
          deliveredLeadCount: true,
        },
      });

      const reservedLeadCount = inflightAggregate._sum.reservedLeadCount ?? 0;

      const deliveredLeadCount = inflightAggregate._sum.deliveredLeadCount ?? 0;

      const inflightLeadCount = Math.max(0, reservedLeadCount - deliveredLeadCount);

      const batchSize = computeBatchSize({
        requestedLeadCount: request.requestedLeadCount,
        scheduledLeadCount: request.scheduledLeadCount,
        inflightLeadCount,
        maxInflightPerEmployee: this.config.maxInflightPerEmployee,
        microbatchSize: this.config.microbatchSize,
      });

      if (batchSize <= 0) {
        await this.deferClaimedQueueItem(
          transaction,
          queueItem.id,
          queueItem.organizationId,
          request.id,
          now,
          this.config.backpressureDelayMs,
          'ads_queue.backpressure',
        );

        return 'DEFERRED';
      }

      const schedulerState = await transaction.trafficPoolSchedulerState.findUnique({
        where: {
          organizationId_trafficPoolId: {
            organizationId: queueItem.organizationId,
            trafficPoolId: queueItem.trafficPoolId,
          },
        },
      });

      const initialNextPosition = schedulerState?.nextPosition ?? eligibleMembers[0]?.position ?? 1;

      const selection = selectRoundRobinMember(eligibleMembers, initialNextPosition);

      const maxSequence = await transaction.adsMicrobatch.aggregate({
        where: {
          adsRequestId: request.id,
        },

        _max: {
          sequence: true,
        },
      });

      const sequence = (maxSequence._max.sequence ?? 0) + 1;

      const microbatch = await transaction.adsMicrobatch.create({
        data: {
          organizationId: queueItem.organizationId,
          adsRequestId: request.id,
          adsQueueItemId: queueItem.id,
          employeeId: queueItem.employeeId,
          trafficPoolId: queueItem.trafficPoolId,
          trafficPoolMemberId: selection.member.id,
          whatsAppNumberId: selection.member.whatsAppNumberId,
          sequence,
          reservedLeadCount: batchSize,
        },
      });

      await transaction.trafficPoolSchedulerState.upsert({
        where: {
          organizationId_trafficPoolId: {
            organizationId: queueItem.organizationId,
            trafficPoolId: queueItem.trafficPoolId,
          },
        },

        create: {
          organizationId: queueItem.organizationId,
          trafficPoolId: queueItem.trafficPoolId,
          nextPosition: selection.nextPosition,
        },

        update: {
          nextPosition: selection.nextPosition,
        },
      });

      const scheduledLeadCount = request.scheduledLeadCount + batchSize;

      await transaction.adsRequest.update({
        where: {
          id: request.id,
        },

        data: {
          scheduledLeadCount: {
            increment: batchSize,
          },

          status: request.fulfilledLeadCount > 0 ? 'PARTIALLY_FULFILLED' : 'PROCESSING',

          startedAt: request.startedAt ?? now,
        },
      });

      const schedulingCompleted = scheduledLeadCount >= request.requestedLeadCount;

      await transaction.adsQueueItem.update({
        where: {
          id: queueItem.id,
        },

        data: schedulingCompleted
          ? {
              status: 'COMPLETED',
              completedAt: now,
              claimedAt: null,
              claimedByWorkerId: null,
              leaseExpiresAt: null,
            }
          : {
              status: 'WAITING',
              availableAt: addMilliseconds(now, this.config.microbatchYieldMs),
              claimedAt: null,
              claimedByWorkerId: null,
              leaseExpiresAt: null,
            },
      });

      await transaction.auditLog.create({
        data: {
          organizationId: queueItem.organizationId,
          actorType: 'SYSTEM',
          action: 'ads_microbatch.planned',
          resourceType: 'ads_microbatch',
          resourceId: microbatch.id,
          outcome: 'SUCCESS',

          metadata: {
            adsRequestId: request.id,
            adsQueueItemId: queueItem.id,
            employeeId: queueItem.employeeId,
            trafficPoolId: queueItem.trafficPoolId,
            trafficPoolMemberId: selection.member.id,
            whatsAppNumberId: selection.member.whatsAppNumberId,
            sequence,
            reservedLeadCount: batchSize,
            scheduledLeadCount,
            requestedLeadCount: request.requestedLeadCount,
            nextPosition: selection.nextPosition,
          },
        },
      });

      if (schedulingCompleted) {
        await transaction.auditLog.create({
          data: {
            organizationId: queueItem.organizationId,
            actorType: 'SYSTEM',
            action: 'ads_queue.scheduling_completed',
            resourceType: 'ads_queue_item',
            resourceId: queueItem.id,
            outcome: 'SUCCESS',

            metadata: {
              adsRequestId: request.id,
              scheduledLeadCount,
            },
          },
        });
      }

      return 'PLANNED';
    });
  }

  private async deferClaimedQueueItem(
    transaction: Parameters<Parameters<CrmDatabaseClient['$transaction']>[0]>[0],
    queueItemId: string,
    organizationId: string,
    adsRequestId: string,
    now: Date,
    delayMs: number,
    auditAction: string,
  ): Promise<void> {
    await transaction.adsQueueItem.update({
      where: {
        id: queueItemId,
      },

      data: {
        status: 'WAITING',
        availableAt: addMilliseconds(now, delayMs),
        claimedAt: null,
        claimedByWorkerId: null,
        leaseExpiresAt: null,
      },
    });

    await transaction.auditLog.create({
      data: {
        organizationId,
        actorType: 'SYSTEM',
        action: auditAction,
        resourceType: 'ads_queue_item',
        resourceId: queueItemId,
        outcome: 'SUCCESS',

        metadata: {
          adsRequestId,
          retryAfterMs: delayMs,
        },
      },
    });
  }

  private async handleProcessingError(
    claimed: ClaimedQueueItem,
    error: unknown,
  ): Promise<'DEFERRED' | 'FAILED' | 'LOST_LEASE'> {
    const message = getErrorMessage(error);

    const queueItem = await this.database.adsQueueItem.findFirst({
      where: {
        id: claimed.id,
        status: 'CLAIMED',
        claimedByWorkerId: this.workerId,
      },

      select: {
        id: true,
        organizationId: true,
        adsRequestId: true,
        attempts: true,
      },
    });

    if (!queueItem) {
      return 'LOST_LEASE';
    }

    if (queueItem.attempts >= this.config.maxQueueAttempts) {
      await this.database.$transaction(async (transaction) => {
        await transaction.adsQueueItem.update({
          where: {
            id: queueItem.id,
          },

          data: {
            status: 'FAILED',
            claimedAt: null,
            claimedByWorkerId: null,
            leaseExpiresAt: null,
          },
        });

        await transaction.adsRequest.updateMany({
          where: {
            id: queueItem.adsRequestId,

            status: {
              notIn: ['CANCELLED', 'FULFILLED'],
            },
          },

          data: {
            status: 'FAILED',
            failureReason: message,
          },
        });

        await transaction.auditLog.create({
          data: {
            organizationId: queueItem.organizationId,
            actorType: 'SYSTEM',
            action: 'ads_queue.failed',
            resourceType: 'ads_queue_item',
            resourceId: queueItem.id,
            outcome: 'FAILURE',

            metadata: {
              adsRequestId: queueItem.adsRequestId,
              attempts: queueItem.attempts,
              reason: message,
            },
          },
        });
      });

      return 'FAILED';
    }

    await this.database.adsQueueItem.updateMany({
      where: {
        id: queueItem.id,
        status: 'CLAIMED',
        claimedByWorkerId: this.workerId,
      },

      data: {
        status: 'WAITING',

        availableAt: addMilliseconds(new Date(), this.config.backpressureDelayMs),

        claimedAt: null,
        claimedByWorkerId: null,
        leaseExpiresAt: null,
      },
    });

    return 'DEFERRED';
  }
}
