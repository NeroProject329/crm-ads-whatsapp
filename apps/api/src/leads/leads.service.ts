import { ForbiddenException, Inject, Injectable, NotFoundException } from '@nestjs/common';

import type { AuthenticatedPrincipal } from '@crm/auth';

import type {
  AdsMicrobatchModel,
  AdsRequestModel,
  EmployeeModel,
  LeadAttributionModel,
  LeadModel,
  UserModel,
  WhatsAppContactModel,
  WhatsAppNumberModel,
} from '@crm/database';

import type { LeadListResponse, LeadResponse, LeadSummaryResponse } from '@crm/contracts';

import type { LeadListQuery } from '@crm/validation';

import { DatabaseService } from '../database/database.service.js';

type LoadedOwnerEmployee = Pick<EmployeeModel, 'id' | 'employeeCode' | 'userId'> & {
  user: Pick<UserModel, 'displayName'>;
};

type LoadedAttribution = LeadAttributionModel & {
  adsRequest: Pick<
    AdsRequestModel,
    'id' | 'requestedLeadCount' | 'scheduledLeadCount' | 'fulfilledLeadCount' | 'status'
  >;

  adsMicrobatch: Pick<
    AdsMicrobatchModel,
    'id' | 'sequence' | 'reservedLeadCount' | 'deliveredLeadCount' | 'status'
  >;
};

type LoadedLead = LeadModel & {
  contact: Pick<WhatsAppContactModel, 'id' | 'waId' | 'profileName'>;

  firstWhatsAppNumber: Pick<WhatsAppNumberModel, 'id' | 'displayName' | 'e164'>;

  ownerEmployee: LoadedOwnerEmployee | null;

  attribution: LoadedAttribution | null;
};

@Injectable()
export class LeadsService {
  constructor(
    @Inject(DatabaseService)
    private readonly database: DatabaseService,
  ) {}

  async list(
    principal: AuthenticatedPrincipal,

    query: LeadListQuery,
  ): Promise<LeadListResponse> {
    const employeeId = this.isAdmin(principal) ? null : await this.getCurrentEmployeeId(principal);

    const leads = await this.database.client.lead.findMany({
      where: {
        organizationId: principal.organizationId,

        ...(employeeId
          ? {
              ownerEmployeeId: employeeId,
            }
          : {}),

        ...(query.status
          ? {
              status: query.status,
            }
          : {}),

        ...(query.whatsAppNumberId
          ? {
              firstWhatsAppNumberId: query.whatsAppNumberId,
            }
          : {}),

        ...(query.adsRequestId
          ? {
              attribution: {
                is: {
                  adsRequestId: query.adsRequestId,
                },
              },
            }
          : {}),

        ...(query.search
          ? {
              OR: [
                {
                  waIdSnapshot: {
                    contains: query.search,
                  },
                },

                {
                  profileNameSnapshot: {
                    contains: query.search,

                    mode: 'insensitive',
                  },
                },
              ],
            }
          : {}),
      },

      include: {
        contact: {
          select: {
            id: true,

            waId: true,

            profileName: true,
          },
        },

        firstWhatsAppNumber: {
          select: {
            id: true,

            displayName: true,

            e164: true,
          },
        },

        ownerEmployee: {
          include: {
            user: {
              select: {
                displayName: true,
              },
            },
          },
        },

        attribution: {
          include: {
            adsRequest: {
              select: {
                id: true,

                requestedLeadCount: true,

                scheduledLeadCount: true,

                fulfilledLeadCount: true,

                status: true,
              },
            },

            adsMicrobatch: {
              select: {
                id: true,

                sequence: true,

                reservedLeadCount: true,

                deliveredLeadCount: true,

                status: true,
              },
            },
          },
        },
      },

      orderBy: [
        {
          firstSeenAt: 'desc',
        },

        {
          id: 'desc',
        },
      ],

      take: query.limit + 1,

      ...(query.cursor
        ? {
            cursor: {
              id: query.cursor,
            },

            skip: 1,
          }
        : {}),
    });

    const hasMore = leads.length > query.limit;

    const page = hasMore ? leads.slice(0, query.limit) : leads;

    return {
      items: page.map((lead) => this.mapLead(lead)),

      nextCursor: hasMore ? (page.at(-1)?.id ?? null) : null,
    };
  }

  async summary(principal: AuthenticatedPrincipal): Promise<LeadSummaryResponse> {
    const employeeId = this.isAdmin(principal) ? null : await this.getCurrentEmployeeId(principal);

    const visibility = {
      organizationId: principal.organizationId,

      ...(employeeId
        ? {
            ownerEmployeeId: employeeId,
          }
        : {}),
    };

    const [totalUniqueLeads, attributedLeads, excessLeads] = await Promise.all([
      this.database.client.lead.count({
        where: visibility,
      }),

      this.database.client.lead.count({
        where: {
          ...visibility,

          status: 'ATTRIBUTED',
        },
      }),

      this.database.client.lead.count({
        where: {
          ...visibility,

          status: 'EXCESS',
        },
      }),
    ]);

    return {
      totalUniqueLeads,
      attributedLeads,
      excessLeads,
    };
  }

  async getById(
    principal: AuthenticatedPrincipal,

    leadId: string,
  ): Promise<LeadResponse> {
    const employeeId = this.isAdmin(principal) ? null : await this.getCurrentEmployeeId(principal);

    const lead = await this.database.client.lead.findFirst({
      where: {
        id: leadId,

        organizationId: principal.organizationId,

        ...(employeeId
          ? {
              ownerEmployeeId: employeeId,
            }
          : {}),
      },

      include: {
        contact: {
          select: {
            id: true,

            waId: true,

            profileName: true,
          },
        },

        firstWhatsAppNumber: {
          select: {
            id: true,

            displayName: true,

            e164: true,
          },
        },

        ownerEmployee: {
          include: {
            user: {
              select: {
                displayName: true,
              },
            },
          },
        },

        attribution: {
          include: {
            adsRequest: {
              select: {
                id: true,

                requestedLeadCount: true,

                scheduledLeadCount: true,

                fulfilledLeadCount: true,

                status: true,
              },
            },

            adsMicrobatch: {
              select: {
                id: true,

                sequence: true,

                reservedLeadCount: true,

                deliveredLeadCount: true,

                status: true,
              },
            },
          },
        },
      },
    });

    if (!lead) {
      throw new NotFoundException({
        code: 'LEAD_NOT_FOUND',

        message: 'Lead not found.',
      });
    }

    return this.mapLead(lead);
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

  private mapLead(lead: LoadedLead): LeadResponse {
    return {
      id: lead.id,

      organizationId: lead.organizationId,

      contact: {
        id: lead.contact.id,

        waId: lead.contact.waId,

        profileName: lead.contact.profileName,
      },

      firstInboundMessageId: lead.firstInboundMessageId,

      firstWhatsAppNumber: {
        id: lead.firstWhatsAppNumber.id,

        displayName: lead.firstWhatsAppNumber.displayName,

        e164: lead.firstWhatsAppNumber.e164,
      },

      ownerEmployee: lead.ownerEmployee
        ? {
            employeeId: lead.ownerEmployee.id,

            employeeCode: lead.ownerEmployee.employeeCode,

            userId: lead.ownerEmployee.userId,

            displayName: lead.ownerEmployee.user.displayName,
          }
        : null,

      waIdSnapshot: lead.waIdSnapshot,

      profileNameSnapshot: lead.profileNameSnapshot,

      status: lead.status,

      excessReason: lead.excessReason,

      firstSeenAt: lead.firstSeenAt.toISOString(),

      lastSeenAt: lead.lastSeenAt.toISOString(),

      inboundMessageCount: lead.inboundMessageCount,

      attributedAt: lead.attributedAt?.toISOString() ?? null,

      attribution: lead.attribution
        ? {
            id: lead.attribution.id,

            adsRequestId: lead.attribution.adsRequestId,

            adsMicrobatchId: lead.attribution.adsMicrobatchId,

            employeeId: lead.attribution.employeeId,

            whatsAppNumberId: lead.attribution.whatsAppNumberId,

            inboundMessageId: lead.attribution.inboundMessageId,

            attributedAt: lead.attribution.attributedAt.toISOString(),

            adsRequest: {
              id: lead.attribution.adsRequest.id,

              requestedLeadCount: lead.attribution.adsRequest.requestedLeadCount,

              scheduledLeadCount: lead.attribution.adsRequest.scheduledLeadCount,

              fulfilledLeadCount: lead.attribution.adsRequest.fulfilledLeadCount,

              status: lead.attribution.adsRequest.status,
            },

            microbatch: {
              id: lead.attribution.adsMicrobatch.id,

              sequence: lead.attribution.adsMicrobatch.sequence,

              reservedLeadCount: lead.attribution.adsMicrobatch.reservedLeadCount,

              deliveredLeadCount: lead.attribution.adsMicrobatch.deliveredLeadCount,

              status: lead.attribution.adsMicrobatch.status,
            },
          }
        : null,

      createdAt: lead.createdAt.toISOString(),

      updatedAt: lead.updatedAt.toISOString(),
    };
  }
}
