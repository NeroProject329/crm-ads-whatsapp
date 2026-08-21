import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';

import type { AuthenticatedPrincipal } from '@crm/auth';

import type {
  SiteModel,
  TrafficPoolMemberModel,
  TrafficPoolModel,
  WhatsAppNumberModel,
} from '@crm/database';

import type {
  TrafficPoolListResponse,
  TrafficPoolMemberDeleteResponse,
  TrafficPoolMemberResponse,
  TrafficPoolResponse,
} from '@crm/contracts';

import type {
  AddTrafficPoolMemberInput,
  CreateTrafficPoolInput,
  ReorderTrafficPoolMembersInput,
  UpdateTrafficPoolInput,
  UpdateTrafficPoolMemberInput,
} from '@crm/validation';

import { DatabaseService } from '../database/database.service.js';

type LoadedMember = TrafficPoolMemberModel & {
  whatsAppNumber: WhatsAppNumberModel;
};

type LoadedPool = TrafficPoolModel & {
  site: SiteModel;
  members: LoadedMember[];
};

@Injectable()
export class TrafficPoolsService {
  constructor(
    @Inject(DatabaseService)
    private readonly database: DatabaseService,
  ) {}

  async list(principal: AuthenticatedPrincipal): Promise<TrafficPoolListResponse> {
    const employeeId = this.isAdmin(principal) ? null : await this.getCurrentEmployeeId(principal);

    const pools = await this.database.client.trafficPool.findMany({
      where: {
        organizationId: principal.organizationId,
        deletedAt: null,
        ...(employeeId
          ? {
              members: {
                some: {
                  status: 'ACTIVE',
                  whatsAppNumber: {
                    deletedAt: null,
                    assignedEmployeeId: employeeId,
                  },
                },
              },
            }
          : {}),
      },
      include: {
        site: true,
        members: {
          include: { whatsAppNumber: true },
          orderBy: { position: 'asc' },
        },
      },
      orderBy: { name: 'asc' },
    });

    return pools.map((pool) => this.mapPool(pool));
  }

  async getById(principal: AuthenticatedPrincipal, poolId: string): Promise<TrafficPoolResponse> {
    return this.mapPool(await this.getAccessiblePool(principal, poolId));
  }

  async create(
    principal: AuthenticatedPrincipal,
    input: CreateTrafficPoolInput,
  ): Promise<TrafficPoolResponse> {
    const site = await this.getOrganizationSite(principal.organizationId, input.siteId);

    if (site.status === 'ARCHIVED') {
      throw new ConflictException({
        code: 'TRAFFIC_POOL_SITE_ARCHIVED',
        message: 'Traffic pools cannot be created for an archived site.',
      });
    }

    try {
      const pool = await this.database.client.$transaction(async (transaction) => {
        const created = await transaction.trafficPool.create({
          data: {
            organizationId: principal.organizationId,
            siteId: input.siteId,
            name: input.name,
            slug: input.slug,
            description: input.description ?? null,
          },
          include: {
            site: true,
            members: { include: { whatsAppNumber: true } },
          },
        });

        await transaction.auditLog.create({
          data: {
            organizationId: principal.organizationId,
            actorType: 'USER',
            actorUserId: principal.userId,
            action: 'traffic_pool.created',
            resourceType: 'traffic_pool',
            resourceId: created.id,
            outcome: 'SUCCESS',
            metadata: { siteId: created.siteId, slug: created.slug },
          },
        });

        return created;
      });

      return this.mapPool(pool);
    } catch (error) {
      if (this.isUniqueConstraintError(error)) {
        throw new ConflictException({
          code: 'TRAFFIC_POOL_ALREADY_EXISTS',
          message: 'A traffic pool with this slug already exists in the organization.',
        });
      }

      throw error;
    }
  }

  async update(
    principal: AuthenticatedPrincipal,
    poolId: string,
    input: UpdateTrafficPoolInput,
  ): Promise<TrafficPoolResponse> {
    await this.getOrganizationPool(principal.organizationId, poolId);

    try {
      const pool = await this.database.client.$transaction(async (transaction) => {
        const updated = await transaction.trafficPool.update({
          where: { id: poolId },
          data: {
            ...(input.name !== undefined ? { name: input.name } : {}),
            ...(input.slug !== undefined ? { slug: input.slug } : {}),
            ...(input.description !== undefined ? { description: input.description } : {}),
            ...(input.status !== undefined ? { status: input.status } : {}),
          },
          include: {
            site: true,
            members: {
              include: { whatsAppNumber: true },
              orderBy: { position: 'asc' },
            },
          },
        });

        await transaction.auditLog.create({
          data: {
            organizationId: principal.organizationId,
            actorType: 'USER',
            actorUserId: principal.userId,
            action: 'traffic_pool.updated',
            resourceType: 'traffic_pool',
            resourceId: updated.id,
            outcome: 'SUCCESS',
          },
        });

        return updated;
      });

      return this.mapPool(pool);
    } catch (error) {
      if (this.isUniqueConstraintError(error)) {
        throw new ConflictException({
          code: 'TRAFFIC_POOL_ALREADY_EXISTS',
          message: 'A traffic pool with this slug already exists in the organization.',
        });
      }

      throw error;
    }
  }

  async listMembers(
    principal: AuthenticatedPrincipal,
    poolId: string,
  ): Promise<readonly TrafficPoolMemberResponse[]> {
    const pool = await this.getAccessiblePool(principal, poolId);
    return pool.members.map((member) => this.mapMember(member));
  }

  async addMember(
    principal: AuthenticatedPrincipal,
    poolId: string,
    input: AddTrafficPoolMemberInput,
  ): Promise<TrafficPoolMemberResponse> {
    const pool = await this.getOrganizationPool(principal.organizationId, poolId);
    this.assertPoolMutable(pool);

    const number = await this.database.client.whatsAppNumber.findFirst({
      where: {
        id: input.whatsAppNumberId,
        organizationId: principal.organizationId,
        deletedAt: null,
      },
    });

    if (!number) {
      throw new BadRequestException({
        code: 'TRAFFIC_POOL_NUMBER_INVALID',
        message: 'WhatsApp number does not exist in this organization.',
      });
    }

    if (number.status !== 'ACTIVE') {
      throw new ConflictException({
        code: 'TRAFFIC_POOL_NUMBER_NOT_ACTIVE',
        message: 'Only ACTIVE WhatsApp numbers can be added to a traffic pool.',
      });
    }

    if (number.assignedEmployeeId === null) {
      throw new ConflictException({
        code: 'TRAFFIC_POOL_NUMBER_UNASSIGNED',
        message: 'The WhatsApp number must be assigned to an employee before entering a traffic pool.',
      });
    }

    try {
      const member = await this.database.client.$transaction(async (transaction) => {
        const lastMember = await transaction.trafficPoolMember.findFirst({
          where: {
            organizationId: principal.organizationId,
            trafficPoolId: poolId,
          },
          orderBy: { position: 'desc' },
          select: { position: true },
        });

        const position = (lastMember?.position ?? 0) + 1;

        const created = await transaction.trafficPoolMember.create({
          data: {
            organizationId: principal.organizationId,
            trafficPoolId: poolId,
            whatsAppNumberId: number.id,
            position,
          },
          include: { whatsAppNumber: true },
        });

        await transaction.auditLog.create({
          data: {
            organizationId: principal.organizationId,
            actorType: 'USER',
            actorUserId: principal.userId,
            action: 'traffic_pool.member_added',
            resourceType: 'traffic_pool_member',
            resourceId: created.id,
            outcome: 'SUCCESS',
            metadata: {
              trafficPoolId: poolId,
              whatsAppNumberId: number.id,
              assignedEmployeeId: number.assignedEmployeeId,
              position,
            },
          },
        });

        return created;
      });

      return this.mapMember(member);
    } catch (error) {
      if (this.isUniqueConstraintError(error)) {
        throw new ConflictException({
          code: 'TRAFFIC_POOL_MEMBER_ALREADY_EXISTS',
          message: 'This WhatsApp number is already a member of the traffic pool.',
        });
      }

      throw error;
    }
  }

  async updateMember(
    principal: AuthenticatedPrincipal,
    poolId: string,
    memberId: string,
    input: UpdateTrafficPoolMemberInput,
  ): Promise<TrafficPoolMemberResponse> {
    const pool = await this.getOrganizationPool(principal.organizationId, poolId);
    this.assertPoolMutable(pool);

    const member = await this.database.client.trafficPoolMember.findFirst({
      where: {
        id: memberId,
        organizationId: principal.organizationId,
        trafficPoolId: poolId,
      },
    });

    if (!member) {
      throw new NotFoundException({
        code: 'TRAFFIC_POOL_MEMBER_NOT_FOUND',
        message: 'Traffic pool member not found.',
      });
    }

    const updated = await this.database.client.$transaction(async (transaction) => {
      const result = await transaction.trafficPoolMember.update({
        where: { id: memberId },
        data: { status: input.status },
        include: { whatsAppNumber: true },
      });

      await transaction.auditLog.create({
        data: {
          organizationId: principal.organizationId,
          actorType: 'USER',
          actorUserId: principal.userId,
          action: 'traffic_pool.member_updated',
          resourceType: 'traffic_pool_member',
          resourceId: memberId,
          outcome: 'SUCCESS',
          metadata: { trafficPoolId: poolId, status: input.status },
        },
      });

      return result;
    });

    return this.mapMember(updated);
  }

  async reorderMembers(
    principal: AuthenticatedPrincipal,
    poolId: string,
    input: ReorderTrafficPoolMembersInput,
  ): Promise<readonly TrafficPoolMemberResponse[]> {
    const pool = await this.getOrganizationPool(principal.organizationId, poolId);
    this.assertPoolMutable(pool);

    const members = await this.database.client.trafficPoolMember.findMany({
      where: {
        organizationId: principal.organizationId,
        trafficPoolId: poolId,
      },
      orderBy: { position: 'asc' },
    });

    const currentIds = members.map((member) => member.id).sort();
    const requestedIds = [...input.memberIds].sort();

    if (
      currentIds.length !== requestedIds.length ||
      currentIds.some((id, index) => id !== requestedIds[index])
    ) {
      throw new BadRequestException({
        code: 'TRAFFIC_POOL_REORDER_INVALID',
        message: 'memberIds must contain every current traffic pool member exactly once.',
      });
    }

    const reordered = await this.database.client.$transaction(async (transaction) => {
      for (const [index, memberId] of input.memberIds.entries()) {
        await transaction.trafficPoolMember.update({
          where: { id: memberId },
          data: { position: -(index + 1) },
        });
      }

      for (const [index, memberId] of input.memberIds.entries()) {
        await transaction.trafficPoolMember.update({
          where: { id: memberId },
          data: { position: index + 1 },
        });
      }

      await transaction.auditLog.create({
        data: {
          organizationId: principal.organizationId,
          actorType: 'USER',
          actorUserId: principal.userId,
          action: 'traffic_pool.members_reordered',
          resourceType: 'traffic_pool',
          resourceId: poolId,
          outcome: 'SUCCESS',
          metadata: { memberIds: input.memberIds },
        },
      });

      return transaction.trafficPoolMember.findMany({
        where: {
          organizationId: principal.organizationId,
          trafficPoolId: poolId,
        },
        include: { whatsAppNumber: true },
        orderBy: { position: 'asc' },
      });
    });

    return reordered.map((member) => this.mapMember(member));
  }

  async removeMember(
    principal: AuthenticatedPrincipal,
    poolId: string,
    memberId: string,
  ): Promise<TrafficPoolMemberDeleteResponse> {
    const pool = await this.getOrganizationPool(principal.organizationId, poolId);
    this.assertPoolMutable(pool);

    const member = await this.database.client.trafficPoolMember.findFirst({
      where: {
        id: memberId,
        organizationId: principal.organizationId,
        trafficPoolId: poolId,
      },
    });

    if (!member) {
      throw new NotFoundException({
        code: 'TRAFFIC_POOL_MEMBER_NOT_FOUND',
        message: 'Traffic pool member not found.',
      });
    }

    await this.database.client.$transaction(async (transaction) => {
      await transaction.trafficPoolMember.delete({ where: { id: memberId } });

      const remaining = await transaction.trafficPoolMember.findMany({
        where: {
          organizationId: principal.organizationId,
          trafficPoolId: poolId,
        },
        orderBy: { position: 'asc' },
      });

      for (const [index, remainingMember] of remaining.entries()) {
        await transaction.trafficPoolMember.update({
          where: { id: remainingMember.id },
          data: { position: -(index + 1) },
        });
      }

      for (const [index, remainingMember] of remaining.entries()) {
        await transaction.trafficPoolMember.update({
          where: { id: remainingMember.id },
          data: { position: index + 1 },
        });
      }

      await transaction.auditLog.create({
        data: {
          organizationId: principal.organizationId,
          actorType: 'USER',
          actorUserId: principal.userId,
          action: 'traffic_pool.member_removed',
          resourceType: 'traffic_pool_member',
          resourceId: memberId,
          outcome: 'SUCCESS',
          metadata: {
            trafficPoolId: poolId,
            whatsAppNumberId: member.whatsAppNumberId,
          },
        },
      });
    });

    return { success: true };
  }

  private async getAccessiblePool(
    principal: AuthenticatedPrincipal,
    poolId: string,
  ): Promise<LoadedPool> {
    const employeeId = this.isAdmin(principal) ? null : await this.getCurrentEmployeeId(principal);

    const pool = await this.database.client.trafficPool.findFirst({
      where: {
        id: poolId,
        organizationId: principal.organizationId,
        deletedAt: null,
        ...(employeeId
          ? {
              members: {
                some: {
                  status: 'ACTIVE',
                  whatsAppNumber: {
                    deletedAt: null,
                    assignedEmployeeId: employeeId,
                  },
                },
              },
            }
          : {}),
      },
      include: {
        site: true,
        members: {
          include: { whatsAppNumber: true },
          orderBy: { position: 'asc' },
        },
      },
    });

    if (!pool) {
      throw new NotFoundException({
        code: 'TRAFFIC_POOL_NOT_FOUND',
        message: 'Traffic pool not found.',
      });
    }

    return pool;
  }

  private async getOrganizationPool(
    organizationId: string,
    poolId: string,
  ): Promise<TrafficPoolModel> {
    const pool = await this.database.client.trafficPool.findFirst({
      where: { id: poolId, organizationId, deletedAt: null },
    });

    if (!pool) {
      throw new NotFoundException({
        code: 'TRAFFIC_POOL_NOT_FOUND',
        message: 'Traffic pool not found.',
      });
    }

    return pool;
  }

  private async getOrganizationSite(organizationId: string, siteId: string): Promise<SiteModel> {
    const site = await this.database.client.site.findFirst({
      where: { id: siteId, organizationId, deletedAt: null },
    });

    if (!site) {
      throw new BadRequestException({
        code: 'TRAFFIC_POOL_SITE_INVALID',
        message: 'Site does not exist in this organization.',
      });
    }

    return site;
  }

  private assertPoolMutable(pool: TrafficPoolModel): void {
    if (pool.status === 'ARCHIVED') {
      throw new ConflictException({
        code: 'TRAFFIC_POOL_ARCHIVED',
        message: 'Archived traffic pools cannot have their membership changed.',
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

  private isAdmin(principal: AuthenticatedPrincipal): boolean {
    return principal.roles.includes('ADMIN');
  }

  private mapPool(pool: LoadedPool): TrafficPoolResponse {
    return {
      id: pool.id,
      organizationId: pool.organizationId,
      siteId: pool.siteId,
      name: pool.name,
      slug: pool.slug,
      description: pool.description,
      status: pool.status,
      site: {
        id: pool.site.id,
        name: pool.site.name,
        slug: pool.site.slug,
      },
      members: pool.members.map((member) => this.mapMember(member)),
      createdAt: pool.createdAt.toISOString(),
      updatedAt: pool.updatedAt.toISOString(),
    };
  }

  private mapMember(member: LoadedMember): TrafficPoolMemberResponse {
    return {
      id: member.id,
      organizationId: member.organizationId,
      trafficPoolId: member.trafficPoolId,
      whatsAppNumberId: member.whatsAppNumberId,
      position: member.position,
      status: member.status,
      number: {
        id: member.whatsAppNumber.id,
        displayName: member.whatsAppNumber.displayName,
        e164: member.whatsAppNumber.e164,
        assignedEmployeeId: member.whatsAppNumber.assignedEmployeeId,
        status: member.whatsAppNumber.status,
      },
      createdAt: member.createdAt.toISOString(),
      updatedAt: member.updatedAt.toISOString(),
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
