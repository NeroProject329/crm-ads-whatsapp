import { ForbiddenException, Inject, Injectable, NotFoundException } from '@nestjs/common';

import type { AuthenticatedPrincipal } from '@crm/auth';

import type { CrmDatabaseClient } from '@crm/database';

import type {
  WhatsAppNumberHealthEventResponse,
  WhatsAppNumberHealthResponse,
  WhatsAppNumberIncidentResponse,
} from '@crm/contracts';

import { DatabaseService } from '../database/database.service.js';

type TransactionClient = Parameters<Parameters<CrmDatabaseClient['$transaction']>[0]>[0];
@Injectable()
export class WhatsAppHealthService {
  constructor(
    @Inject(DatabaseService)
    private readonly database: DatabaseService,
  ) {}

  async getHealth(
    principal: AuthenticatedPrincipal,

    whatsAppNumberId: string,
  ): Promise<WhatsAppNumberHealthResponse> {
    const number = await this.getAccessibleNumber(principal, whatsAppNumberId);

    const state = await this.database.client.whatsAppNumberHealthState.upsert({
      where: {
        organizationId_whatsAppNumberId: {
          organizationId: principal.organizationId,

          whatsAppNumberId: number.id,
        },
      },

      create: {
        organizationId: principal.organizationId,

        whatsAppNumberId: number.id,
      },

      update: {},
    });

    return this.mapHealth(state);
  }

  async listEvents(
    principal: AuthenticatedPrincipal,

    whatsAppNumberId: string,

    limit: number,
  ): Promise<readonly WhatsAppNumberHealthEventResponse[]> {
    await this.getAccessibleNumber(principal, whatsAppNumberId);

    const events = await this.database.client.whatsAppNumberHealthEvent.findMany({
      where: {
        organizationId: principal.organizationId,

        whatsAppNumberId,
      },

      orderBy: [
        {
          occurredAt: 'desc',
        },

        {
          id: 'desc',
        },
      ],

      take: limit,
    });

    return events.map((event) => ({
      id: event.id,

      source: event.source,

      previousStatus: event.previousStatus,

      currentStatus: event.currentStatus,

      metaQualityRating: event.metaQualityRating,

      metaQualityEvent: event.metaQualityEvent,

      messagingLimitTier: event.messagingLimitTier,

      schedulerEligible: event.schedulerEligible,

      reasonCode: event.reasonCode,

      reasonMessage: event.reasonMessage,

      occurredAt: event.occurredAt.toISOString(),
    }));
  }

  async listIncidents(
    principal: AuthenticatedPrincipal,

    whatsAppNumberId: string,

    limit: number,
  ): Promise<readonly WhatsAppNumberIncidentResponse[]> {
    await this.getAccessibleNumber(principal, whatsAppNumberId);

    const incidents = await this.database.client.whatsAppNumberIncident.findMany({
      where: {
        organizationId: principal.organizationId,

        whatsAppNumberId,
      },

      orderBy: [
        {
          openedAt: 'desc',
        },

        {
          id: 'desc',
        },
      ],

      take: limit,
    });

    return incidents.map((incident) => ({
      id: incident.id,

      status: incident.status,

      type: incident.type,

      severity: incident.severity,

      openedReasonCode: incident.openedReasonCode,

      openedReason: incident.openedReason,

      openedAt: incident.openedAt.toISOString(),

      resolvedReason: incident.resolvedReason,

      resolvedAt: incident.resolvedAt?.toISOString() ?? null,
    }));
  }

  async pause(
    principal: AuthenticatedPrincipal,

    whatsAppNumberId: string,
  ): Promise<WhatsAppNumberHealthResponse> {
    this.assertAdmin(principal);

    const number = await this.getAccessibleNumber(principal, whatsAppNumberId);

    const now = new Date();

    const state = await this.database.client.$transaction(async (transaction) => {
      await transaction.$queryRawUnsafe(
        'WITH lock_guard AS MATERIALIZED (SELECT pg_advisory_xact_lock(hashtextextended($1, 0))) SELECT TRUE AS locked FROM lock_guard',
        `whatsapp-number-health:${principal.organizationId}:${number.id}`,
      );

      const current = await transaction.whatsAppNumberHealthState.upsert({
        where: {
          organizationId_whatsAppNumberId: {
            organizationId: principal.organizationId,

            whatsAppNumberId: number.id,
          },
        },

        create: {
          organizationId: principal.organizationId,

          whatsAppNumberId: number.id,
        },

        update: {},
      });

      if (!current.manualPaused) {
        await this.releaseReservedCapacity(transaction, principal.organizationId, number.id, now);

        await transaction.whatsAppNumberHealthEvent.create({
          data: {
            organizationId: principal.organizationId,

            whatsAppNumberId: number.id,

            source: 'MANUAL',

            previousStatus: current.status,

            currentStatus: 'DISABLED',

            metaQualityRating: current.metaQualityRating,

            metaQualityEvent: current.metaQualityEvent,

            messagingLimitTier: current.messagingLimitTier,

            schedulerEligible: false,

            reasonCode: 'MANUAL_PAUSE',

            reasonMessage: 'Number manually paused by administrator.',

            occurredAt: now,
          },
        });

        const incident = await transaction.whatsAppNumberIncident.findFirst({
          where: {
            organizationId: principal.organizationId,

            whatsAppNumberId: number.id,

            status: 'OPEN',

            type: 'MANUAL_PAUSE',
          },
        });

        if (!incident) {
          await transaction.whatsAppNumberIncident.create({
            data: {
              organizationId: principal.organizationId,

              whatsAppNumberId: number.id,

              type: 'MANUAL_PAUSE',

              severity: 'DISABLED',

              openedReasonCode: 'MANUAL_PAUSE',

              openedReason: 'Number manually paused by administrator.',

              openedAt: now,
            },
          });
        }
      }

      const updated = await transaction.whatsAppNumberHealthState.update({
        where: {
          id: current.id,
        },

        data: {
          manualPaused: true,

          status: 'DISABLED',

          schedulerEligible: false,

          consecutiveHealthyChecks: 0,

          lastReasonCode: 'MANUAL_PAUSE',

          lastReasonMessage: 'Number manually paused by administrator.',
        },
      });

      await transaction.auditLog.create({
        data: {
          organizationId: principal.organizationId,

          actorType: 'USER',

          actorUserId: principal.userId,

          action: 'whatsapp_number.health_paused',

          resourceType: 'whatsapp_number',

          resourceId: number.id,

          outcome: 'SUCCESS',
        },
      });

      return updated;
    });

    return this.mapHealth(state);
  }

  async resume(
    principal: AuthenticatedPrincipal,

    whatsAppNumberId: string,
  ): Promise<WhatsAppNumberHealthResponse> {
    this.assertAdmin(principal);

    const number = await this.getAccessibleNumber(principal, whatsAppNumberId);

    const now = new Date();

    const state = await this.database.client.$transaction(async (transaction) => {
      await transaction.$queryRawUnsafe(
        'WITH lock_guard AS MATERIALIZED (SELECT pg_advisory_xact_lock(hashtextextended($1, 0))) SELECT TRUE AS locked FROM lock_guard',
        `whatsapp-number-health:${principal.organizationId}:${number.id}`,
      );

      const current = await transaction.whatsAppNumberHealthState.upsert({
        where: {
          organizationId_whatsAppNumberId: {
            organizationId: principal.organizationId,

            whatsAppNumberId: number.id,
          },
        },

        create: {
          organizationId: principal.organizationId,

          whatsAppNumberId: number.id,
        },

        update: {},
      });

      const metaConnected = Boolean(number.metaPhoneNumberId);

      const nextStatus = metaConnected ? 'RECOVERING' : 'UNKNOWN';

      const nextEligible = !metaConnected;

      const updated = await transaction.whatsAppNumberHealthState.update({
        where: {
          id: current.id,
        },

        data: {
          manualPaused: false,

          status: nextStatus,

          schedulerEligible: nextEligible,

          consecutiveHealthyChecks: 0,

          recoveringSinceAt: metaConnected ? now : null,

          nextCheckAt: now,

          lastReasonCode: metaConnected
            ? 'MANUAL_RESUME_AWAITING_META_CONFIRMATION'
            : 'MANUAL_RESUME_NO_META_PROFILE',

          lastReasonMessage: metaConnected
            ? 'Manual pause removed; Meta green confirmation is required before scheduling resumes.'
            : 'Manual pause removed; no Meta phone profile is connected.',
        },
      });

      await transaction.whatsAppNumberHealthEvent.create({
        data: {
          organizationId: principal.organizationId,

          whatsAppNumberId: number.id,

          source: 'MANUAL',

          previousStatus: current.status,

          currentStatus: nextStatus,

          metaQualityRating: current.metaQualityRating,

          metaQualityEvent: current.metaQualityEvent,

          messagingLimitTier: current.messagingLimitTier,

          schedulerEligible: nextEligible,

          reasonCode: 'MANUAL_RESUME',

          reasonMessage: 'Manual pause removed.',

          occurredAt: now,
        },
      });

      await transaction.whatsAppNumberIncident.updateMany({
        where: {
          organizationId: principal.organizationId,

          whatsAppNumberId: number.id,

          status: 'OPEN',

          type: 'MANUAL_PAUSE',
        },

        data: {
          status: 'RESOLVED',

          resolvedAt: now,

          resolvedReason: 'Manual pause removed by administrator.',
        },
      });

      await transaction.auditLog.create({
        data: {
          organizationId: principal.organizationId,

          actorType: 'USER',

          actorUserId: principal.userId,

          action: 'whatsapp_number.health_resumed',

          resourceType: 'whatsapp_number',

          resourceId: number.id,

          outcome: 'SUCCESS',

          metadata: {
            metaConnected,
            nextStatus,
            schedulerEligible: nextEligible,
          },
        },
      });

      return updated;
    });

    return this.mapHealth(state);
  }

  async requestSync(
    principal: AuthenticatedPrincipal,

    whatsAppNumberId: string,
  ): Promise<WhatsAppNumberHealthResponse> {
    this.assertAdmin(principal);

    const number = await this.getAccessibleNumber(principal, whatsAppNumberId);

    const state = await this.database.client.whatsAppNumberHealthState.upsert({
      where: {
        organizationId_whatsAppNumberId: {
          organizationId: principal.organizationId,

          whatsAppNumberId: number.id,
        },
      },

      create: {
        organizationId: principal.organizationId,

        whatsAppNumberId: number.id,

        nextCheckAt: new Date(),
      },

      update: {
        nextCheckAt: new Date(),
      },
    });

    await this.database.client.auditLog.create({
      data: {
        organizationId: principal.organizationId,

        actorType: 'USER',

        actorUserId: principal.userId,

        action: 'whatsapp_number.health_sync_requested',

        resourceType: 'whatsapp_number',

        resourceId: number.id,

        outcome: 'SUCCESS',
      },
    });

    return this.mapHealth(state);
  }

  private async getAccessibleNumber(
    principal: AuthenticatedPrincipal,

    whatsAppNumberId: string,
  ) {
    const employeeId = this.isAdmin(principal) ? null : await this.getCurrentEmployeeId(principal);

    const number = await this.database.client.whatsAppNumber.findFirst({
      where: {
        id: whatsAppNumberId,

        organizationId: principal.organizationId,

        deletedAt: null,

        ...(employeeId
          ? {
              assignedEmployeeId: employeeId,
            }
          : {}),
      },

      select: {
        id: true,

        metaPhoneNumberId: true,
      },
    });

    if (!number) {
      throw new NotFoundException({
        code: 'WHATSAPP_NUMBER_NOT_FOUND',

        message: 'WhatsApp number not found.',
      });
    }

    return number;
  }

  private async getCurrentEmployeeId(principal: AuthenticatedPrincipal): Promise<string> {
    const employee = await this.database.client.employee.findFirst({
      where: {
        organizationId: principal.organizationId,

        userId: principal.userId,

        status: 'ACTIVE',

        deletedAt: null,
      },

      select: {
        id: true,
      },
    });

    if (!employee) {
      throw new ForbiddenException({
        code: 'EMPLOYEE_PROFILE_REQUIRED',

        message: 'An active employee profile is required.',
      });
    }

    return employee.id;
  }

  private isAdmin(principal: AuthenticatedPrincipal): boolean {
    return principal.roles.includes('ADMIN');
  }

  private assertAdmin(principal: AuthenticatedPrincipal): void {
    if (!this.isAdmin(principal)) {
      throw new ForbiddenException({
        code: 'WHATSAPP_HEALTH_ADMIN_REQUIRED',

        message: 'Only administrators can change WhatsApp number health controls.',
      });
    }
  }

  private async releaseReservedCapacity(
    transaction: TransactionClient,

    organizationId: string,

    whatsAppNumberId: string,

    now: Date,
  ): Promise<void> {
    const batches = await transaction.adsMicrobatch.findMany({
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
    });

    for (const batch of batches) {
      const outstanding = Math.max(0, batch.reservedLeadCount - batch.deliveredLeadCount);

      if (outstanding <= 0) {
        continue;
      }

      await transaction.adsMicrobatch.update({
        where: {
          id: batch.id,
        },

        data: {
          status: 'CANCELLED',

          cancelledAt: now,

          failureReason: 'WHATSAPP_NUMBER_MANUAL_PAUSE',
        },
      });

      await transaction.adsRequest.update({
        where: {
          id: batch.adsRequestId,
        },

        data: {
          scheduledLeadCount: {
            decrement: outstanding,
          },

          status: batch.adsRequest.fulfilledLeadCount > 0 ? 'PARTIALLY_FULFILLED' : 'PROCESSING',

          completedAt: null,
        },
      });

      await transaction.adsQueueItem.updateMany({
        where: {
          organizationId,

          adsRequestId: batch.adsRequestId,

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
    }
  }

  private mapHealth(
    state: Readonly<{
      whatsAppNumberId: string;

      status: 'UNKNOWN' | 'HEALTHY' | 'DEGRADED' | 'CRITICAL' | 'RECOVERING' | 'DISABLED';

      schedulerEligible: boolean;

      manualPaused: boolean;

      metaQualityRating: 'UNKNOWN' | 'GREEN' | 'YELLOW' | 'RED' | 'NA';

      metaQualityEvent: string | null;

      messagingLimitTier: string | null;

      lastReasonCode: string | null;

      lastReasonMessage: string | null;

      lastMetaSyncAt: Date | null;

      lastMetaWebhookAt: Date | null;

      lastHealthyAt: Date | null;

      degradedSinceAt: Date | null;

      criticalSinceAt: Date | null;

      recoveringSinceAt: Date | null;

      consecutiveHealthyChecks: number;

      consecutiveSyncFailures: number;

      nextCheckAt: Date;

      updatedAt: Date;
    }>,
  ): WhatsAppNumberHealthResponse {
    return {
      whatsAppNumberId: state.whatsAppNumberId,

      status: state.status,

      schedulerEligible: state.schedulerEligible,

      manualPaused: state.manualPaused,

      metaQualityRating: state.metaQualityRating,

      metaQualityEvent: state.metaQualityEvent,

      messagingLimitTier: state.messagingLimitTier,

      lastReasonCode: state.lastReasonCode,

      lastReasonMessage: state.lastReasonMessage,

      lastMetaSyncAt: state.lastMetaSyncAt?.toISOString() ?? null,

      lastMetaWebhookAt: state.lastMetaWebhookAt?.toISOString() ?? null,

      lastHealthyAt: state.lastHealthyAt?.toISOString() ?? null,

      degradedSinceAt: state.degradedSinceAt?.toISOString() ?? null,

      criticalSinceAt: state.criticalSinceAt?.toISOString() ?? null,

      recoveringSinceAt: state.recoveringSinceAt?.toISOString() ?? null,

      consecutiveHealthyChecks: state.consecutiveHealthyChecks,

      consecutiveSyncFailures: state.consecutiveSyncFailures,

      nextCheckAt: state.nextCheckAt.toISOString(),

      updatedAt: state.updatedAt.toISOString(),
    };
  }
}
