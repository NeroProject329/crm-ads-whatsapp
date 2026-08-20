import type { CrmDatabaseClient } from '@crm/database';

type TransactionClient = Parameters<Parameters<CrmDatabaseClient['$transaction']>[0]>[0];

type CandidateMicrobatch = Readonly<{
  id: string;
  adsRequestId: string;
  employeeId: string;
  whatsAppNumberId: string;

  reservedLeadCount: number;
  deliveredLeadCount: number;

  startedAt: Date | null;

  requestedLeadCount: number;
  fulfilledLeadCount: number;
}>;

export type RecordInboundLeadInput = Readonly<{
  organizationId: string;
  contactId: string;
  whatsAppNumberId: string;
  ownerEmployeeId: string | null;
  inboundMessageId: string;

  waId: string;
  profileName: string | null;

  providerTimestamp: Date;
}>;

export type RecordInboundLeadResult = 'ATTRIBUTED' | 'EXCESS' | 'DUPLICATE';

export class LeadAttributionService {
  async recordInboundLead(
    transaction: TransactionClient,

    input: RecordInboundLeadInput,
  ): Promise<RecordInboundLeadResult> {
    /*
     * A WhatsAppContact is unique by
     * organizationId + waId.
     *
     * Locking the contact identity makes the unique-lead
     * decision deterministic even when separate webhook
     * workers receive simultaneous messages from the same
     * customer.
     */
    await transaction.$queryRawUnsafe(
      'WITH lock_guard AS MATERIALIZED (SELECT pg_advisory_xact_lock(hashtextextended($1, 0))) SELECT TRUE AS locked FROM lock_guard',
      `lead:${input.organizationId}:${input.contactId}`,
    );

    const existing = await transaction.lead.findUnique({
      where: {
        organizationId_contactId: {
          organizationId: input.organizationId,

          contactId: input.contactId,
        },
      },
    });

    if (existing) {
      const nextLastSeenAt =
        existing.lastSeenAt < input.providerTimestamp
          ? input.providerTimestamp
          : existing.lastSeenAt;

      await transaction.lead.update({
        where: {
          id: existing.id,
        },

        data: {
          lastSeenAt: nextLastSeenAt,

          inboundMessageCount: {
            increment: 1,
          },
        },
      });

      return 'DUPLICATE';
    }

    const lead = await transaction.lead.create({
      data: {
        organizationId: input.organizationId,

        contactId: input.contactId,

        firstInboundMessageId: input.inboundMessageId,

        firstWhatsAppNumberId: input.whatsAppNumberId,

        ownerEmployeeId: input.ownerEmployeeId,

        waIdSnapshot: input.waId,

        profileNameSnapshot: input.profileName,

        status: 'EXCESS',

        excessReason: input.ownerEmployeeId ? 'NO_RESERVED_CAPACITY' : 'NUMBER_UNASSIGNED',

        firstSeenAt: input.providerTimestamp,

        lastSeenAt: input.providerTimestamp,
      },
    });

    if (!input.ownerEmployeeId) {
      await transaction.auditLog.create({
        data: {
          organizationId: input.organizationId,

          actorType: 'SYSTEM',

          action: 'lead.excess',

          resourceType: 'lead',

          resourceId: lead.id,

          outcome: 'SUCCESS',

          metadata: {
            reason: 'NUMBER_UNASSIGNED',

            contactId: input.contactId,

            whatsAppNumberId: input.whatsAppNumberId,

            inboundMessageId: input.inboundMessageId,
          },
        },
      });

      return 'EXCESS';
    }

    /*
     * Only one worker at a time may consume a reserved
     * lead slot for a WhatsApp number.
     */
    await transaction.$queryRawUnsafe(
      'WITH lock_guard AS MATERIALIZED (SELECT pg_advisory_xact_lock(hashtextextended($1, 0))) SELECT TRUE AS locked FROM lock_guard',
      `lead-slot:${input.organizationId}:${input.whatsAppNumberId}`,
    );

    const candidates = await transaction.$queryRawUnsafe<CandidateMicrobatch[]>(
      `
        SELECT
          microbatch."id",
          microbatch."adsRequestId",
          microbatch."employeeId",
          microbatch."whatsAppNumberId",
          microbatch."reservedLeadCount",
          microbatch."deliveredLeadCount",
          microbatch."startedAt",
          ads_request."requestedLeadCount",
          ads_request."fulfilledLeadCount"
        FROM
          "ads_microbatches" AS microbatch
        INNER JOIN
          "ads_requests" AS ads_request
          ON ads_request."organizationId" =
             microbatch."organizationId"
          AND ads_request."id" =
              microbatch."adsRequestId"
        WHERE
          microbatch."organizationId" = $1
          AND microbatch."whatsAppNumberId" = $2
          AND microbatch."employeeId" = $3
          AND microbatch."status" IN (
            'PLANNED',
            'DELIVERING'
          )
          AND microbatch."deliveredLeadCount" <
              microbatch."reservedLeadCount"
          AND ads_request."status" IN (
            'PROCESSING',
            'PARTIALLY_FULFILLED'
          )
        ORDER BY
          microbatch."plannedAt" ASC,
          microbatch."sequence" ASC,
          microbatch."id" ASC
        FOR UPDATE OF
          microbatch,
          ads_request
        LIMIT 1
        `,
      input.organizationId,
      input.whatsAppNumberId,
      input.ownerEmployeeId,
    );

    const candidate = candidates[0];

    if (!candidate) {
      await transaction.auditLog.create({
        data: {
          organizationId: input.organizationId,

          actorType: 'SYSTEM',

          action: 'lead.excess',

          resourceType: 'lead',

          resourceId: lead.id,

          outcome: 'SUCCESS',

          metadata: {
            reason: 'NO_RESERVED_CAPACITY',

            contactId: input.contactId,

            employeeId: input.ownerEmployeeId,

            whatsAppNumberId: input.whatsAppNumberId,

            inboundMessageId: input.inboundMessageId,
          },
        },
      });

      return 'EXCESS';
    }

    const attributedAt = new Date();

    const nextDeliveredLeadCount = candidate.deliveredLeadCount + 1;

    const microbatchCompleted = nextDeliveredLeadCount >= candidate.reservedLeadCount;

    const nextFulfilledLeadCount = candidate.fulfilledLeadCount + 1;

    const requestFulfilled = nextFulfilledLeadCount >= candidate.requestedLeadCount;

    const attribution = await transaction.leadAttribution.create({
      data: {
        organizationId: input.organizationId,

        leadId: lead.id,

        adsRequestId: candidate.adsRequestId,

        adsMicrobatchId: candidate.id,

        employeeId: candidate.employeeId,

        whatsAppNumberId: candidate.whatsAppNumberId,

        inboundMessageId: input.inboundMessageId,

        attributedAt,
      },
    });

    await transaction.lead.update({
      where: {
        id: lead.id,
      },

      data: {
        status: 'ATTRIBUTED',

        excessReason: null,

        ownerEmployeeId: candidate.employeeId,

        attributedAt,
      },
    });

    await transaction.adsMicrobatch.update({
      where: {
        id: candidate.id,
      },

      data: {
        deliveredLeadCount: {
          increment: 1,
        },

        status: microbatchCompleted ? 'COMPLETED' : 'DELIVERING',

        startedAt: candidate.startedAt ?? attributedAt,

        completedAt: microbatchCompleted ? attributedAt : null,
      },
    });

    await transaction.adsRequest.update({
      where: {
        id: candidate.adsRequestId,
      },

      data: {
        fulfilledLeadCount: {
          increment: 1,
        },

        status: requestFulfilled ? 'FULFILLED' : 'PARTIALLY_FULFILLED',

        completedAt: requestFulfilled ? attributedAt : null,

        failureReason: null,
      },
    });

    await transaction.auditLog.create({
      data: {
        organizationId: input.organizationId,

        actorType: 'SYSTEM',

        action: 'lead.attributed',

        resourceType: 'lead',

        resourceId: lead.id,

        outcome: 'SUCCESS',

        metadata: {
          leadAttributionId: attribution.id,

          contactId: input.contactId,

          inboundMessageId: input.inboundMessageId,

          adsRequestId: candidate.adsRequestId,

          adsMicrobatchId: candidate.id,

          employeeId: candidate.employeeId,

          whatsAppNumberId: candidate.whatsAppNumberId,

          microbatchDeliveredLeadCount: nextDeliveredLeadCount,

          microbatchReservedLeadCount: candidate.reservedLeadCount,

          requestFulfilledLeadCount: nextFulfilledLeadCount,

          requestRequestedLeadCount: candidate.requestedLeadCount,
        },
      },
    });

    if (microbatchCompleted) {
      await transaction.auditLog.create({
        data: {
          organizationId: input.organizationId,

          actorType: 'SYSTEM',

          action: 'ads_microbatch.completed',

          resourceType: 'ads_microbatch',

          resourceId: candidate.id,

          outcome: 'SUCCESS',

          metadata: {
            adsRequestId: candidate.adsRequestId,

            deliveredLeadCount: nextDeliveredLeadCount,

            reservedLeadCount: candidate.reservedLeadCount,
          },
        },
      });
    }

    if (requestFulfilled) {
      await transaction.auditLog.create({
        data: {
          organizationId: input.organizationId,

          actorType: 'SYSTEM',

          action: 'ads_request.fulfilled',

          resourceType: 'ads_request',

          resourceId: candidate.adsRequestId,

          outcome: 'SUCCESS',

          metadata: {
            requestedLeadCount: candidate.requestedLeadCount,

            fulfilledLeadCount: nextFulfilledLeadCount,
          },
        },
      });
    }

    return 'ATTRIBUTED';
  }
}
