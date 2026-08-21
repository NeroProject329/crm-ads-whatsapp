import { ForbiddenException, Inject, Injectable, NotFoundException } from '@nestjs/common';

import type { AuthenticatedPrincipal } from '@crm/auth';
import type { SiteMonitorCheckListResponse, SiteMonitoringResponse } from '@crm/contracts';

import { DatabaseService } from '../database/database.service.js';

@Injectable()
export class SiteMonitoringService {
  constructor(
    @Inject(DatabaseService)
    private readonly database: DatabaseService,
  ) {}

  async getSiteMonitoring(
    principal: AuthenticatedPrincipal,
    siteId: string,
  ): Promise<SiteMonitoringResponse> {
    await this.assertAccessibleSite(principal, siteId);

    const domains = await this.database.client.siteDomain.findMany({
      where: {
        organizationId: principal.organizationId,
        siteId,
        deletedAt: null,
      },
      include: {
        monitorState: true,
        monitorIncidents: {
          where: { status: 'OPEN' },
          orderBy: { openedAt: 'desc' },
          take: 1,
        },
      },
      orderBy: [{ isPrimary: 'desc' }, { hostname: 'asc' }],
    });

    const primaryDomain = domains.find((domain) => domain.isPrimary) ?? null;
    const status =
      primaryDomain?.monitoringEnabled === true
        ? (primaryDomain.monitorState?.status ?? 'UNKNOWN')
        : 'UNKNOWN';

    return {
      siteId,
      status,
      primaryDomainId: primaryDomain?.id ?? null,
      domains: domains.map((domain) => {
        const state = domain.monitorState;
        const incident = domain.monitorIncidents[0] ?? null;

        return {
          domainId: domain.id,
          hostname: domain.hostname,
          isPrimary: domain.isPrimary,
          monitoringEnabled: domain.monitoringEnabled,
          status: state?.status ?? 'UNKNOWN',
          consecutiveFailures: state?.consecutiveFailures ?? 0,
          consecutiveSuccesses: state?.consecutiveSuccesses ?? 0,
          lastCheckedAt: state?.lastCheckedAt?.toISOString() ?? null,
          lastSuccessAt: state?.lastSuccessAt?.toISOString() ?? null,
          lastFailureAt: state?.lastFailureAt?.toISOString() ?? null,
          lastHttpStatus: state?.lastHttpStatus ?? null,
          lastLatencyMs: state?.lastLatencyMs ?? null,
          lastResolvedAddress: state?.lastResolvedAddress ?? null,
          lastFailureCode: state?.lastFailureCode ?? null,
          lastFailureMessage: state?.lastFailureMessage ?? null,
          downSince: state?.downSince?.toISOString() ?? null,
          recoveredAt: state?.recoveredAt?.toISOString() ?? null,
          nextCheckAt: state?.nextCheckAt?.toISOString() ?? null,
          openIncident: incident
            ? {
                id: incident.id,
                status: incident.status,
                openedAt: incident.openedAt.toISOString(),
                resolvedAt: incident.resolvedAt?.toISOString() ?? null,
                openedAfterFailures: incident.openedAfterFailures,
                lastFailureCode: incident.lastFailureCode,
                lastFailureMessage: incident.lastFailureMessage,
              }
            : null,
        };
      }),
    };
  }

  async listChecks(
    principal: AuthenticatedPrincipal,
    siteId: string,
    domainId: string,
  ): Promise<SiteMonitorCheckListResponse> {
    await this.assertAccessibleSite(principal, siteId);

    const domain = await this.database.client.siteDomain.findFirst({
      where: {
        id: domainId,
        organizationId: principal.organizationId,
        siteId,
        deletedAt: null,
      },
      select: { id: true },
    });

    if (!domain) {
      throw new NotFoundException({
        code: 'DOMAIN_NOT_FOUND',
        message: 'Domain not found.',
      });
    }

    const checks = await this.database.client.siteMonitorCheck.findMany({
      where: {
        organizationId: principal.organizationId,
        siteId,
        siteDomainId: domainId,
      },
      orderBy: { checkedAt: 'desc' },
      take: 100,
    });

    return checks.map((check) => ({
      id: check.id,
      siteId: check.siteId,
      siteDomainId: check.siteDomainId,
      outcome: check.outcome,
      statusBefore: check.statusBefore,
      statusAfter: check.statusAfter,
      httpStatus: check.httpStatus,
      latencyMs: check.latencyMs,
      resolvedAddress: check.resolvedAddress,
      failureCode: check.failureCode,
      failureMessage: check.failureMessage,
      checkedAt: check.checkedAt.toISOString(),
    }));
  }

  private async assertAccessibleSite(
    principal: AuthenticatedPrincipal,
    siteId: string,
  ): Promise<void> {
    const employeeId = principal.roles.includes('ADMIN')
      ? null
      : await this.getCurrentEmployeeId(principal);

    const site = await this.database.client.site.findFirst({
      where: {
        id: siteId,
        organizationId: principal.organizationId,
        deletedAt: null,
        ...(employeeId
          ? {
              trafficPools: {
                some: {
                  deletedAt: null,
                  members: {
                    some: {
                      status: 'ACTIVE',
                      whatsAppNumber: {
                        deletedAt: null,
                        assignedEmployeeId: employeeId,
                      },
                    },
                  },
                },
              },
            }
          : {}),
      },
      select: { id: true },
    });

    if (!site) {
      throw new NotFoundException({
        code: 'SITE_NOT_FOUND',
        message: 'Site not found.',
      });
    }
  }

  private async getCurrentEmployeeId(principal: AuthenticatedPrincipal): Promise<string> {
    const employee = await this.database.client.employee.findFirst({
      where: {
        organizationId: principal.organizationId,
        userId: principal.userId,
        status: 'ACTIVE',
        deletedAt: null,
      },
      select: { id: true },
    });

    if (!employee) {
      throw new ForbiddenException({
        code: 'EMPLOYEE_PROFILE_REQUIRED',
        message: 'An active employee profile is required.',
      });
    }

    return employee.id;
  }
}
