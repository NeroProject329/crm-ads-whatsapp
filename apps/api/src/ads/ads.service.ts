import {
  ConflictException,
  ForbiddenException,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';

import type { AuthenticatedPrincipal } from '@crm/auth';

import type {
  AdsQueueItemModel,
  AdsRequestModel,
  EmployeeModel,
  SiteModel,
  TrafficPoolModel,
} from '@crm/database';

import type {
  AdsQueueItemResponse,
  AdsQueueListResponse,
  AdsRequestListResponse,
  AdsRequestResponse,
} from '@crm/contracts';

import type { CreateAdsRequestInput } from '@crm/validation';

import { DatabaseService } from '../database/database.service.js';

type LoadedAdsRequest = AdsRequestModel & {
  employee: EmployeeModel;
  site: SiteModel;
  trafficPool: TrafficPoolModel;
  queueItem: AdsQueueItemModel | null;
};

type LoadedAdsQueueItem = AdsQueueItemModel & {
  adsRequest: AdsRequestModel;
};

type SiteWithOwner = SiteModel & {
  ownerEmployee: EmployeeModel;
};

@Injectable()
export class AdsService {
  constructor(
    @Inject(DatabaseService)
    private readonly database: DatabaseService,
  ) {}

  async listRequests(principal: AuthenticatedPrincipal): Promise<AdsRequestListResponse> {
    const employeeId = this.isAdmin(principal) ? null : await this.getCurrentEmployeeId(principal);

    const requests = await this.database.client.adsRequest.findMany({
      where: {
        organizationId: principal.organizationId,

        ...(employeeId
          ? {
              employeeId,
            }
          : {}),
      },

      include: {
        employee: true,
        site: true,
        trafficPool: true,
        queueItem: true,
      },

      orderBy: [
        {
          queuedAt: 'desc',
        },
        {
          id: 'desc',
        },
      ],
    });

    return requests.map((request) => this.mapRequest(request));
  }

  async getRequest(
    principal: AuthenticatedPrincipal,
    requestId: string,
  ): Promise<AdsRequestResponse> {
    const request = await this.getAccessibleRequest(principal, requestId);

    return this.mapRequest(request);
  }

  async createRequest(
    principal: AuthenticatedPrincipal,
    input: CreateAdsRequestInput,
  ): Promise<AdsRequestResponse> {
    const site = await this.getRequestSite(principal.organizationId, input.siteId);

    if (site.status !== 'ACTIVE') {
      throw new ConflictException({
        code: 'ADS_REQUEST_SITE_NOT_ACTIVE',
        message: 'ADS requests require an ACTIVE site.',
      });
    }

    if (site.ownerEmployee.status !== 'ACTIVE' || site.ownerEmployee.deletedAt !== null) {
      throw new ConflictException({
        code: 'ADS_REQUEST_EMPLOYEE_NOT_ACTIVE',
        message: 'The site owner must be an ACTIVE employee.',
      });
    }

    if (!this.isAdmin(principal)) {
      const currentEmployeeId = await this.getCurrentEmployeeId(principal);

      if (site.ownerEmployeeId !== currentEmployeeId) {
        throw new ForbiddenException({
          code: 'ADS_REQUEST_SITE_FORBIDDEN',
          message: 'Employees can request ADS only for their own sites.',
        });
      }
    }

    const trafficPool = await this.database.client.trafficPool.findFirst({
      where: {
        id: input.trafficPoolId,
        organizationId: principal.organizationId,
        siteId: site.id,
        deletedAt: null,
      },
    });

    if (!trafficPool) {
      throw new NotFoundException({
        code: 'ADS_REQUEST_TRAFFIC_POOL_NOT_FOUND',
        message: 'Traffic Pool was not found for this site.',
      });
    }

    if (trafficPool.status !== 'ACTIVE') {
      throw new ConflictException({
        code: 'ADS_REQUEST_TRAFFIC_POOL_NOT_ACTIVE',
        message: 'ADS requests require an ACTIVE Traffic Pool.',
      });
    }

    const eligibleMember = await this.database.client.trafficPoolMember.findFirst({
      where: {
        organizationId: principal.organizationId,
        trafficPoolId: trafficPool.id,
        status: 'ACTIVE',

        whatsAppNumber: {
          deletedAt: null,
          status: 'ACTIVE',
          assignedEmployeeId: site.ownerEmployeeId,
        },
      },

      select: {
        id: true,
      },
    });

    if (!eligibleMember) {
      throw new ConflictException({
        code: 'ADS_REQUEST_NO_ELIGIBLE_NUMBER',
        message: 'Traffic Pool does not contain an eligible ACTIVE WhatsApp number.',
      });
    }

    const result = await this.database.client.$transaction(async (transaction) => {
      const request = await transaction.adsRequest.create({
        data: {
          organizationId: principal.organizationId,
          employeeId: site.ownerEmployeeId,
          siteId: site.id,
          trafficPoolId: trafficPool.id,
          requestedByUserId: principal.userId,
          requestedLeadCount: input.requestedLeadCount,
          notes: input.notes ?? null,
        },
      });

      const queueItem = await transaction.adsQueueItem.create({
        data: {
          organizationId: principal.organizationId,
          adsRequestId: request.id,
          employeeId: site.ownerEmployeeId,
          trafficPoolId: trafficPool.id,
        },
      });

      await transaction.auditLog.create({
        data: {
          organizationId: principal.organizationId,
          actorType: 'USER',
          actorUserId: principal.userId,
          action: 'ads_request.created',
          resourceType: 'ads_request',
          resourceId: request.id,
          outcome: 'SUCCESS',

          metadata: {
            employeeId: site.ownerEmployeeId,
            siteId: site.id,
            trafficPoolId: trafficPool.id,
            requestedLeadCount: input.requestedLeadCount,
          },
        },
      });

      await transaction.auditLog.create({
        data: {
          organizationId: principal.organizationId,
          actorType: 'USER',
          actorUserId: principal.userId,
          action: 'ads_queue.enqueued',
          resourceType: 'ads_queue_item',
          resourceId: queueItem.id,
          outcome: 'SUCCESS',

          metadata: {
            adsRequestId: request.id,
            employeeId: site.ownerEmployeeId,
            trafficPoolId: trafficPool.id,
            priority: queueItem.priority,
          },
        },
      });

      return transaction.adsRequest.findUniqueOrThrow({
        where: {
          id: request.id,
        },

        include: {
          employee: true,
          site: true,
          trafficPool: true,
          queueItem: true,
        },
      });
    });

    return this.mapRequest(result);
  }

  async cancelRequest(
    principal: AuthenticatedPrincipal,
    requestId: string,
  ): Promise<AdsRequestResponse> {
    const request = await this.getAccessibleRequest(principal, requestId);

    if (request.status === 'CANCELLED') {
      return this.mapRequest(request);
    }

    if (
      request.status !== 'QUEUED' &&
      request.status !== 'PROCESSING' &&
      request.status !== 'PARTIALLY_FULFILLED'
    ) {
      throw new ConflictException({
        code: 'ADS_REQUEST_NOT_CANCELLABLE',
        message: 'This ADS request can no longer be cancelled.',
      });
    }

    if (!request.queueItem) {
      throw new ConflictException({
        code: 'ADS_QUEUE_ITEM_NOT_FOUND',
        message: 'ADS queue item was not found for this request.',
      });
    }

    const queueItemId = request.queueItem.id;
    const now = new Date();

    const updated = await this.database.client.$transaction(async (transaction) => {
      const requestUpdate = await transaction.adsRequest.updateMany({
        where: {
          id: request.id,
          organizationId: principal.organizationId,
          status: {
            in: ['QUEUED', 'PROCESSING', 'PARTIALLY_FULFILLED'],
          },
        },

        data: {
          status: 'CANCELLED',
          cancelledAt: now,
        },
      });

      if (requestUpdate.count !== 1) {
        throw new ConflictException({
          code: 'ADS_REQUEST_CANCEL_CONFLICT',
          message: 'ADS request changed before cancellation could complete.',
        });
      }

      const queueUpdate = await transaction.adsQueueItem.updateMany({
        where: {
          organizationId: principal.organizationId,
          adsRequestId: request.id,
          status: {
            in: ['WAITING', 'CLAIMED'],
          },
        },

        data: {
          status: 'CANCELLED',
          cancelledAt: now,
          claimedAt: null,
          claimedByWorkerId: null,
          leaseExpiresAt: null,
        },
      });

      const microbatchUpdate = await transaction.adsMicrobatch.updateMany({
        where: {
          organizationId: principal.organizationId,
          adsRequestId: request.id,
          status: {
            in: ['PLANNED', 'DELIVERING'],
          },
        },

        data: {
          status: 'CANCELLED',
          cancelledAt: now,
        },
      });

      await transaction.auditLog.create({
        data: {
          organizationId: principal.organizationId,
          actorType: 'USER',
          actorUserId: principal.userId,
          action: 'ads_request.cancelled',
          resourceType: 'ads_request',
          resourceId: request.id,
          outcome: 'SUCCESS',

          metadata: {
            queueItemsCancelled: queueUpdate.count,
            microbatchesCancelled: microbatchUpdate.count,
          },
        },
      });

      if (queueUpdate.count > 0) {
        await transaction.auditLog.create({
          data: {
            organizationId: principal.organizationId,
            actorType: 'USER',
            actorUserId: principal.userId,
            action: 'ads_queue.cancelled',
            resourceType: 'ads_queue_item',
            resourceId: queueItemId,
            outcome: 'SUCCESS',

            metadata: {
              adsRequestId: request.id,
            },
          },
        });
      }

      if (microbatchUpdate.count > 0) {
        await transaction.auditLog.create({
          data: {
            organizationId: principal.organizationId,
            actorType: 'USER',
            actorUserId: principal.userId,
            action: 'ads_microbatch.cancelled',
            resourceType: 'ads_request',
            resourceId: request.id,
            outcome: 'SUCCESS',

            metadata: {
              count: microbatchUpdate.count,
            },
          },
        });
      }

      return transaction.adsRequest.findUniqueOrThrow({
        where: {
          id: request.id,
        },

        include: {
          employee: true,
          site: true,
          trafficPool: true,
          queueItem: true,
        },
      });
    });

    return this.mapRequest(updated);
  }
  async listQueue(principal: AuthenticatedPrincipal): Promise<AdsQueueListResponse> {
    const employeeId = this.isAdmin(principal) ? null : await this.getCurrentEmployeeId(principal);

    const items = await this.database.client.adsQueueItem.findMany({
      where: {
        organizationId: principal.organizationId,

        ...(employeeId
          ? {
              employeeId,
            }
          : {}),
      },

      include: {
        adsRequest: true,
      },

      orderBy: [
        {
          priority: 'asc',
        },
        {
          availableAt: 'asc',
        },
        {
          enqueuedAt: 'asc',
        },
        {
          id: 'asc',
        },
      ],
    });

    return items.map((item) => this.mapQueueItem(item));
  }

  async getQueueItem(
    principal: AuthenticatedPrincipal,
    queueItemId: string,
  ): Promise<AdsQueueItemResponse> {
    const employeeId = this.isAdmin(principal) ? null : await this.getCurrentEmployeeId(principal);

    const item = await this.database.client.adsQueueItem.findFirst({
      where: {
        id: queueItemId,
        organizationId: principal.organizationId,

        ...(employeeId
          ? {
              employeeId,
            }
          : {}),
      },

      include: {
        adsRequest: true,
      },
    });

    if (!item) {
      throw new NotFoundException({
        code: 'ADS_QUEUE_ITEM_NOT_FOUND',
        message: 'ADS queue item not found.',
      });
    }

    return this.mapQueueItem(item);
  }

  private async getAccessibleRequest(
    principal: AuthenticatedPrincipal,
    requestId: string,
  ): Promise<LoadedAdsRequest> {
    const employeeId = this.isAdmin(principal) ? null : await this.getCurrentEmployeeId(principal);

    const request = await this.database.client.adsRequest.findFirst({
      where: {
        id: requestId,
        organizationId: principal.organizationId,

        ...(employeeId
          ? {
              employeeId,
            }
          : {}),
      },

      include: {
        employee: true,
        site: true,
        trafficPool: true,
        queueItem: true,
      },
    });

    if (!request) {
      throw new NotFoundException({
        code: 'ADS_REQUEST_NOT_FOUND',
        message: 'ADS request not found.',
      });
    }

    return request;
  }

  private async getRequestSite(organizationId: string, siteId: string): Promise<SiteWithOwner> {
    const site = await this.database.client.site.findFirst({
      where: {
        id: siteId,
        organizationId,
        deletedAt: null,
      },

      include: {
        ownerEmployee: true,
      },
    });

    if (!site) {
      throw new NotFoundException({
        code: 'ADS_REQUEST_SITE_NOT_FOUND',
        message: 'Site not found.',
      });
    }

    return site;
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

  private mapRequest(request: LoadedAdsRequest): AdsRequestResponse {
    return {
      id: request.id,
      organizationId: request.organizationId,
      employeeId: request.employeeId,
      siteId: request.siteId,
      trafficPoolId: request.trafficPoolId,
      requestedByUserId: request.requestedByUserId,
      requestedLeadCount: request.requestedLeadCount,
      scheduledLeadCount: request.scheduledLeadCount,
      fulfilledLeadCount: request.fulfilledLeadCount,
      status: request.status,
      notes: request.notes,
      queuedAt: request.queuedAt.toISOString(),
      startedAt: request.startedAt?.toISOString() ?? null,
      completedAt: request.completedAt?.toISOString() ?? null,
      cancelledAt: request.cancelledAt?.toISOString() ?? null,
      failureReason: request.failureReason,

      site: {
        id: request.site.id,
        name: request.site.name,
        slug: request.site.slug,
      },

      trafficPool: {
        id: request.trafficPool.id,
        name: request.trafficPool.name,
        slug: request.trafficPool.slug,
      },

      employee: {
        id: request.employee.id,
        employeeCode: request.employee.employeeCode,
      },

      queueItem: request.queueItem
        ? {
            id: request.queueItem.id,
            status: request.queueItem.status,
            priority: request.queueItem.priority,
            attempts: request.queueItem.attempts,
            claimedByWorkerId: request.queueItem.claimedByWorkerId,
            leaseExpiresAt: request.queueItem.leaseExpiresAt?.toISOString() ?? null,
            lastAttemptAt: request.queueItem.lastAttemptAt?.toISOString() ?? null,
            enqueuedAt: request.queueItem.enqueuedAt.toISOString(),
            availableAt: request.queueItem.availableAt.toISOString(),
            claimedAt: request.queueItem.claimedAt?.toISOString() ?? null,
            completedAt: request.queueItem.completedAt?.toISOString() ?? null,
            cancelledAt: request.queueItem.cancelledAt?.toISOString() ?? null,
          }
        : null,

      createdAt: request.createdAt.toISOString(),
      updatedAt: request.updatedAt.toISOString(),
    };
  }

  private mapQueueItem(item: LoadedAdsQueueItem): AdsQueueItemResponse {
    return {
      id: item.id,
      organizationId: item.organizationId,
      adsRequestId: item.adsRequestId,
      employeeId: item.employeeId,
      trafficPoolId: item.trafficPoolId,
      status: item.status,
      priority: item.priority,
      attempts: item.attempts,
      claimedByWorkerId: item.claimedByWorkerId,
      leaseExpiresAt: item.leaseExpiresAt?.toISOString() ?? null,
      lastAttemptAt: item.lastAttemptAt?.toISOString() ?? null,
      enqueuedAt: item.enqueuedAt.toISOString(),
      availableAt: item.availableAt.toISOString(),
      claimedAt: item.claimedAt?.toISOString() ?? null,
      completedAt: item.completedAt?.toISOString() ?? null,
      cancelledAt: item.cancelledAt?.toISOString() ?? null,

      adsRequest: {
        id: item.adsRequest.id,
        status: item.adsRequest.status,
        requestedLeadCount: item.adsRequest.requestedLeadCount,
        scheduledLeadCount: item.adsRequest.scheduledLeadCount,
        fulfilledLeadCount: item.adsRequest.fulfilledLeadCount,
      },

      createdAt: item.createdAt.toISOString(),
      updatedAt: item.updatedAt.toISOString(),
    };
  }
}
