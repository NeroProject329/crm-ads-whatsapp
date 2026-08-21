import {
  ConflictException,
  ForbiddenException,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';

import type { AuthenticatedPrincipal } from '@crm/auth';
import type { SiteDomainModel, SiteModel } from '@crm/database';
import type { SiteDomainResponse, SiteListResponse, SiteResponse } from '@crm/contracts';
import type {
  CreateSiteDomainInput,
  CreateSiteInput,
  UpdateSiteDomainInput,
  UpdateSiteInput,
} from '@crm/validation';

import { DatabaseService } from '../database/database.service.js';

type LoadedSite = SiteModel & {
  domains: SiteDomainModel[];
};

@Injectable()
export class SitesService {
  constructor(
    @Inject(DatabaseService)
    private readonly database: DatabaseService,
  ) {}

  async list(principal: AuthenticatedPrincipal): Promise<SiteListResponse> {
    const employeeId = this.isAdmin(principal) ? null : await this.getCurrentEmployeeId(principal);

    const sites = await this.database.client.site.findMany({
      where: {
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
      include: {
        domains: {
          where: { deletedAt: null },
          orderBy: [{ isPrimary: 'desc' }, { hostname: 'asc' }],
        },
      },
      orderBy: { name: 'asc' },
    });

    return sites.map((site) => this.mapSite(site));
  }

  async getById(principal: AuthenticatedPrincipal, siteId: string): Promise<SiteResponse> {
    return this.mapSite(await this.getAccessibleSite(principal, siteId));
  }

  async create(principal: AuthenticatedPrincipal, input: CreateSiteInput): Promise<SiteResponse> {
    const legacyOwnerEmployeeId = await this.getLegacyAdminEmployeeId(principal);

    try {
      const site = await this.database.client.$transaction(async (transaction) => {
        const created = await transaction.site.create({
          data: {
            organizationId: principal.organizationId,
            ownerEmployeeId: legacyOwnerEmployeeId,
            name: input.name,
            slug: input.slug,
            description: input.description ?? null,
          },
          include: { domains: true },
        });

        await transaction.auditLog.create({
          data: {
            organizationId: principal.organizationId,
            actorType: 'USER',
            actorUserId: principal.userId,
            action: 'site.created',
            resourceType: 'site',
            resourceId: created.id,
            outcome: 'SUCCESS',
            metadata: { slug: created.slug },
          },
        });

        return created;
      });

      return this.mapSite(site);
    } catch (error) {
      if (this.isUniqueConstraintError(error)) {
        throw new ConflictException({
          code: 'SITE_ALREADY_EXISTS',
          message: 'A site with this slug already exists in the organization.',
        });
      }

      throw error;
    }
  }

  async update(
    principal: AuthenticatedPrincipal,
    siteId: string,
    input: UpdateSiteInput,
  ): Promise<SiteResponse> {
    await this.getOrganizationSite(principal.organizationId, siteId);

    try {
      const site = await this.database.client.$transaction(async (transaction) => {
        const updated = await transaction.site.update({
          where: { id: siteId },
          data: {
            ...(input.name !== undefined ? { name: input.name } : {}),
            ...(input.slug !== undefined ? { slug: input.slug } : {}),
            ...(input.description !== undefined ? { description: input.description } : {}),
            ...(input.status !== undefined ? { status: input.status } : {}),
          },
          include: {
            domains: {
              where: { deletedAt: null },
              orderBy: [{ isPrimary: 'desc' }, { hostname: 'asc' }],
            },
          },
        });

        await transaction.auditLog.create({
          data: {
            organizationId: principal.organizationId,
            actorType: 'USER',
            actorUserId: principal.userId,
            action: 'site.updated',
            resourceType: 'site',
            resourceId: updated.id,
            outcome: 'SUCCESS',
          },
        });

        return updated;
      });

      return this.mapSite(site);
    } catch (error) {
      if (this.isUniqueConstraintError(error)) {
        throw new ConflictException({
          code: 'SITE_ALREADY_EXISTS',
          message: 'A site with this slug already exists in the organization.',
        });
      }

      throw error;
    }
  }

  async listDomains(
    principal: AuthenticatedPrincipal,
    siteId: string,
  ): Promise<readonly SiteDomainResponse[]> {
    const site = await this.getAccessibleSite(principal, siteId);
    return site.domains.map((domain) => this.mapDomain(domain));
  }

  async createDomain(
    principal: AuthenticatedPrincipal,
    siteId: string,
    input: CreateSiteDomainInput,
  ): Promise<SiteDomainResponse> {
    await this.getOrganizationSite(principal.organizationId, siteId);

    try {
      const domain = await this.database.client.$transaction(async (transaction) => {
        if (input.isPrimary) {
          await transaction.siteDomain.updateMany({
            where: {
              organizationId: principal.organizationId,
              siteId,
              deletedAt: null,
              isPrimary: true,
            },
            data: { isPrimary: false },
          });
        }

        const created = await transaction.siteDomain.create({
          data: {
            organizationId: principal.organizationId,
            siteId,
            hostname: input.hostname,
            isPrimary: input.isPrimary,
            monitoringEnabled: input.monitoringEnabled === true,
          },
        });

        await transaction.auditLog.create({
          data: {
            organizationId: principal.organizationId,
            actorType: 'USER',
            actorUserId: principal.userId,
            action: 'site_domain.created',
            resourceType: 'site_domain',
            resourceId: created.id,
            outcome: 'SUCCESS',
            metadata: {
              siteId,
              hostname: created.hostname,
              isPrimary: created.isPrimary,
            },
          },
        });

        return created;
      });

      return this.mapDomain(domain);
    } catch (error) {
      if (this.isUniqueConstraintError(error)) {
        throw new ConflictException({
          code: 'DOMAIN_ALREADY_EXISTS',
          message: 'This hostname is already registered.',
        });
      }

      throw error;
    }
  }

  async updateDomain(
    principal: AuthenticatedPrincipal,
    siteId: string,
    domainId: string,
    input: UpdateSiteDomainInput,
  ): Promise<SiteDomainResponse> {
    await this.getOrganizationSite(principal.organizationId, siteId);

    const current = await this.database.client.siteDomain.findFirst({
      where: {
        id: domainId,
        organizationId: principal.organizationId,
        siteId,
        deletedAt: null,
      },
    });

    if (!current) {
      throw new NotFoundException({
        code: 'DOMAIN_NOT_FOUND',
        message: 'Domain not found.',
      });
    }

    try {
      const domain = await this.database.client.$transaction(async (transaction) => {
        if (input.isPrimary === true) {
          await transaction.siteDomain.updateMany({
            where: {
              organizationId: principal.organizationId,
              siteId,
              deletedAt: null,
              isPrimary: true,
              id: { not: domainId },
            },
            data: { isPrimary: false },
          });
        }

        const updated = await transaction.siteDomain.update({
          where: { id: domainId },
          data: {
            ...(input.hostname !== undefined ? { hostname: input.hostname } : {}),
            ...(input.isPrimary !== undefined ? { isPrimary: input.isPrimary } : {}),
            ...(input.monitoringEnabled !== undefined
              ? { monitoringEnabled: input.monitoringEnabled === true }
              : {}),
            ...(input.status !== undefined ? { status: input.status } : {}),
          },
        });

        await transaction.auditLog.create({
          data: {
            organizationId: principal.organizationId,
            actorType: 'USER',
            actorUserId: principal.userId,
            action: 'site_domain.updated',
            resourceType: 'site_domain',
            resourceId: updated.id,
            outcome: 'SUCCESS',
            metadata: { siteId },
          },
        });

        return updated;
      });

      return this.mapDomain(domain);
    } catch (error) {
      if (this.isUniqueConstraintError(error)) {
        throw new ConflictException({
          code: 'DOMAIN_ALREADY_EXISTS',
          message: 'This hostname is already registered.',
        });
      }

      throw error;
    }
  }

  private async getAccessibleSite(
    principal: AuthenticatedPrincipal,
    siteId: string,
  ): Promise<LoadedSite> {
    const employeeId = this.isAdmin(principal) ? null : await this.getCurrentEmployeeId(principal);

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
      include: {
        domains: {
          where: { deletedAt: null },
          orderBy: [{ isPrimary: 'desc' }, { hostname: 'asc' }],
        },
      },
    });

    if (!site) {
      throw new NotFoundException({
        code: 'SITE_NOT_FOUND',
        message: 'Site not found.',
      });
    }

    return site;
  }

  private async getOrganizationSite(organizationId: string, siteId: string): Promise<SiteModel> {
    const site = await this.database.client.site.findFirst({
      where: { id: siteId, organizationId, deletedAt: null },
    });

    if (!site) {
      throw new NotFoundException({
        code: 'SITE_NOT_FOUND',
        message: 'Site not found.',
      });
    }

    return site;
  }

  private async getLegacyAdminEmployeeId(principal: AuthenticatedPrincipal): Promise<string> {
    const employee = await this.database.client.employee.findFirst({
      where: {
        organizationId: principal.organizationId,
        deletedAt: null,
        user: {
          userRoles: {
            some: {
              role: { code: 'ADMIN' },
            },
          },
        },
      },
      select: { id: true },
    });

    if (!employee) {
      throw new NotFoundException({
        code: 'ADMIN_PROFILE_REQUIRED',
        message: 'Administrator profile required to create sites.',
      });
    }

    return employee.id;
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

  private isAdmin(principal: AuthenticatedPrincipal): boolean {
    return principal.roles.includes('ADMIN');
  }

  private mapSite(site: LoadedSite): SiteResponse {
    return {
      id: site.id,
      organizationId: site.organizationId,
      name: site.name,
      slug: site.slug,
      description: site.description,
      status: site.status,
      domains: site.domains.map((domain) => this.mapDomain(domain)),
      createdAt: site.createdAt.toISOString(),
      updatedAt: site.updatedAt.toISOString(),
    };
  }

  private mapDomain(domain: SiteDomainModel): SiteDomainResponse {
    return {
      id: domain.id,
      organizationId: domain.organizationId,
      siteId: domain.siteId,
      hostname: domain.hostname,
      isPrimary: domain.isPrimary,
      status: domain.status,
      monitoringEnabled: domain.monitoringEnabled,
      createdAt: domain.createdAt.toISOString(),
      updatedAt: domain.updatedAt.toISOString(),
    };
  }

  private isUniqueConstraintError(error: unknown): boolean {
    return (
      typeof error === 'object' &&
      error !== null &&
      'code' in error &&
      (error as { code?: unknown }).code === 'P2002'
    );
  }
}
