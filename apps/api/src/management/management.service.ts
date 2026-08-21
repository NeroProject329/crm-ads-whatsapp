import {
  ConflictException,
  ForbiddenException,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';

import type { AuthenticatedPrincipal } from '@crm/auth';
import type {
  ManagedEmployeeListResponse,
  ManagedEmployeeResponse,
  ManagementOverviewResponse,
  OrganizationManagementResponse,
  TeamManagementListResponse,
  TeamManagementResponse,
} from '@crm/contracts';
import { hashPassword } from '@crm/security';
import type {
  CreateManagedEmployeeInput,
  CreateTeamManagementInput,
  UpdateManagedEmployeeInput,
  UpdateOrganizationManagementInput,
  UpdateTeamManagementInput,
} from '@crm/validation';

import { DatabaseService } from '../database/database.service.js';

@Injectable()
export class ManagementService {
  constructor(
    @Inject(DatabaseService)
    private readonly database: DatabaseService,
  ) {}

  async overview(principal: AuthenticatedPrincipal): Promise<ManagementOverviewResponse> {
    const organizationId = principal.organizationId;

    const [
      employeeTotal,
      employeeActive,
      employeeInactive,
      employeeOnLeave,
      teamTotal,
      teamActive,
      siteTotal,
      siteActive,
      domainTotal,
      domainActive,
      whatsAppNumberTotal,
      whatsAppNumberActive,
      leadTotal,
      leadAttributed,
      leadExcess,
    ] = await Promise.all([
      this.database.client.employee.count({ where: { organizationId, deletedAt: null } }),
      this.database.client.employee.count({
        where: { organizationId, deletedAt: null, status: 'ACTIVE' },
      }),
      this.database.client.employee.count({
        where: { organizationId, deletedAt: null, status: 'INACTIVE' },
      }),
      this.database.client.employee.count({
        where: { organizationId, deletedAt: null, status: 'ON_LEAVE' },
      }),
      this.database.client.team.count({ where: { organizationId, deletedAt: null } }),
      this.database.client.team.count({
        where: { organizationId, deletedAt: null, status: 'ACTIVE' },
      }),
      this.database.client.site.count({ where: { organizationId, deletedAt: null } }),
      this.database.client.site.count({
        where: { organizationId, deletedAt: null, status: 'ACTIVE' },
      }),
      this.database.client.siteDomain.count({ where: { organizationId, deletedAt: null } }),
      this.database.client.siteDomain.count({
        where: { organizationId, deletedAt: null, status: 'ACTIVE' },
      }),
      this.database.client.whatsAppNumber.count({ where: { organizationId, deletedAt: null } }),
      this.database.client.whatsAppNumber.count({
        where: { organizationId, deletedAt: null, status: 'ACTIVE' },
      }),
      this.database.client.lead.count({ where: { organizationId } }),
      this.database.client.lead.count({ where: { organizationId, status: 'ATTRIBUTED' } }),
      this.database.client.lead.count({ where: { organizationId, status: 'EXCESS' } }),
    ]);

    return {
      employees: {
        total: employeeTotal,
        active: employeeActive,
        inactive: employeeInactive,
        onLeave: employeeOnLeave,
      },
      teams: {
        total: teamTotal,
        active: teamActive,
      },
      sites: {
        total: siteTotal,
        active: siteActive,
      },
      domains: {
        total: domainTotal,
        active: domainActive,
      },
      whatsAppNumbers: {
        total: whatsAppNumberTotal,
        active: whatsAppNumberActive,
      },
      leads: {
        total: leadTotal,
        attributed: leadAttributed,
        excess: leadExcess,
      },
    };
  }

  async organization(principal: AuthenticatedPrincipal): Promise<OrganizationManagementResponse> {
    const organization = await this.database.client.organization.findUnique({
      where: { id: principal.organizationId },
    });

    if (!organization) {
      throw new NotFoundException({
        code: 'ORGANIZATION_NOT_FOUND',
        message: 'Organization was not found.',
      });
    }

    return this.mapOrganization(organization);
  }

  async updateOrganization(
    principal: AuthenticatedPrincipal,
    input: UpdateOrganizationManagementInput,
  ): Promise<OrganizationManagementResponse> {
    const organization = await this.database.client.$transaction(async (transaction) => {
      const updated = await transaction.organization.update({
        where: { id: principal.organizationId },
        data: {
          ...(input.name !== undefined ? { name: input.name } : {}),
          ...(input.timezone !== undefined ? { timezone: input.timezone } : {}),
        },
      });

      await transaction.auditLog.create({
        data: {
          organizationId: principal.organizationId,
          actorType: 'USER',
          actorUserId: principal.userId,
          action: 'organization.updated',
          resourceType: 'organization',
          resourceId: principal.organizationId,
          outcome: 'SUCCESS',
        },
      });

      return updated;
    });

    return this.mapOrganization(organization);
  }

  async teams(principal: AuthenticatedPrincipal): Promise<TeamManagementListResponse> {
    const teams = await this.database.client.team.findMany({
      where: {
        organizationId: principal.organizationId,
        deletedAt: null,
      },
      include: {
        _count: {
          select: {
            employees: {
              where: { deletedAt: null },
            },
          },
        },
      },
      orderBy: [{ status: 'asc' }, { name: 'asc' }],
    });

    return teams.map((team) => this.mapTeam(team));
  }

  async createTeam(
    principal: AuthenticatedPrincipal,
    input: CreateTeamManagementInput,
  ): Promise<TeamManagementResponse> {
    try {
      const team = await this.database.client.$transaction(async (transaction) => {
        const created = await transaction.team.create({
          data: {
            organizationId: principal.organizationId,
            name: input.name,
            slug: input.slug,
            description: input.description ?? null,
          },
          include: {
            _count: {
              select: { employees: true },
            },
          },
        });

        await transaction.auditLog.create({
          data: {
            organizationId: principal.organizationId,
            actorType: 'USER',
            actorUserId: principal.userId,
            action: 'team.created',
            resourceType: 'team',
            resourceId: created.id,
            outcome: 'SUCCESS',
            metadata: { slug: created.slug },
          },
        });

        return created;
      });

      return this.mapTeam(team);
    } catch (error) {
      this.rethrowUniqueConflict(error, 'TEAM_ALREADY_EXISTS', 'A team with this slug already exists.');
      throw error;
    }
  }

  async updateTeam(
    principal: AuthenticatedPrincipal,
    teamId: string,
    input: UpdateTeamManagementInput,
  ): Promise<TeamManagementResponse> {
    await this.assertTeam(principal.organizationId, teamId);

    try {
      const team = await this.database.client.$transaction(async (transaction) => {
        const updated = await transaction.team.update({
          where: { id: teamId },
          data: {
            ...(input.name !== undefined ? { name: input.name } : {}),
            ...(input.slug !== undefined ? { slug: input.slug } : {}),
            ...(input.description !== undefined ? { description: input.description } : {}),
            ...(input.status !== undefined ? { status: input.status } : {}),
          },
          include: {
            _count: {
              select: { employees: true },
            },
          },
        });

        await transaction.auditLog.create({
          data: {
            organizationId: principal.organizationId,
            actorType: 'USER',
            actorUserId: principal.userId,
            action: 'team.updated',
            resourceType: 'team',
            resourceId: updated.id,
            outcome: 'SUCCESS',
          },
        });

        return updated;
      });

      return this.mapTeam(team);
    } catch (error) {
      this.rethrowUniqueConflict(error, 'TEAM_ALREADY_EXISTS', 'A team with this slug already exists.');
      throw error;
    }
  }

  async employees(principal: AuthenticatedPrincipal): Promise<ManagedEmployeeListResponse> {
    const employees = await this.database.client.employee.findMany({
      where: {
        organizationId: principal.organizationId,
        deletedAt: null,
      },
      include: {
        team: true,
        user: {
          include: {
            userRoles: {
              include: { role: true },
            },
          },
        },
      },
      orderBy: [{ status: 'asc' }, { user: { displayName: 'asc' } }],
    });

    return employees.map((employee) => this.mapEmployee(employee));
  }

  async createEmployee(
    principal: AuthenticatedPrincipal,
    input: CreateManagedEmployeeInput,
  ): Promise<ManagedEmployeeResponse> {
    await this.assertActiveTeam(principal.organizationId, input.teamId);

    const role = await this.database.client.role.findUnique({
      where: {
        organizationId_code: {
          organizationId: principal.organizationId,
          code: 'EMPLOYEE',
        },
      },
    });

    if (!role) {
      throw new NotFoundException({
        code: 'EMPLOYEE_ROLE_NOT_FOUND',
        message: 'EMPLOYEE role was not found.',
      });
    }

    const passwordHash = await hashPassword(input.password);
    const now = new Date();

    try {
      const employeeId = await this.database.client.$transaction(async (transaction) => {
        const user = await transaction.user.create({
          data: {
            organizationId: principal.organizationId,
            email: input.email,
            emailNormalized: input.email,
            displayName: input.displayName,
            passwordHash,
            passwordChangedAt: now,
            status: 'ACTIVE',
          },
        });

        const employee = await transaction.employee.create({
          data: {
            organizationId: principal.organizationId,
            teamId: input.teamId,
            userId: user.id,
            employeeCode: input.employeeCode,
            status: 'ACTIVE',
          },
        });

        await transaction.userRole.create({
          data: {
            organizationId: principal.organizationId,
            userId: user.id,
            roleId: role.id,
          },
        });

        await transaction.auditLog.create({
          data: {
            organizationId: principal.organizationId,
            actorType: 'USER',
            actorUserId: principal.userId,
            action: 'employee.created',
            resourceType: 'employee',
            resourceId: employee.id,
            outcome: 'SUCCESS',
            metadata: {
              employeeCode: employee.employeeCode,
              emailNormalized: input.email,
            },
          },
        });

        return employee.id;
      });

      return this.getEmployee(principal.organizationId, employeeId);
    } catch (error) {
      this.rethrowUniqueConflict(
        error,
        'EMPLOYEE_ALREADY_EXISTS',
        'An employee with this email or employee code already exists.',
      );
      throw error;
    }
  }

  async updateEmployee(
    principal: AuthenticatedPrincipal,
    employeeId: string,
    input: UpdateManagedEmployeeInput,
  ): Promise<ManagedEmployeeResponse> {
    const current = await this.getEmployeeRecord(principal.organizationId, employeeId);

    if (current.user.userRoles.some((assignment) => assignment.role.code === 'ADMIN')) {
      throw new ForbiddenException({
        code: 'ADMIN_EMPLOYEE_PROTECTED',
        message: 'Administrator accounts cannot be changed from employee management.',
      });
    }

    if (input.teamId !== undefined) {
      await this.assertActiveTeam(principal.organizationId, input.teamId);
    }

    const passwordHash = input.password !== undefined ? await hashPassword(input.password) : undefined;
    const shouldRevokeSessions =
      passwordHash !== undefined ||
      input.userStatus === 'SUSPENDED' ||
      input.userStatus === 'DISABLED';

    try {
      await this.database.client.$transaction(async (transaction) => {
        await transaction.employee.update({
          where: { id: employeeId },
          data: {
            ...(input.teamId !== undefined ? { teamId: input.teamId } : {}),
            ...(input.employeeCode !== undefined ? { employeeCode: input.employeeCode } : {}),
            ...(input.employeeStatus !== undefined ? { status: input.employeeStatus } : {}),
          },
        });

        await transaction.user.update({
          where: { id: current.userId },
          data: {
            ...(input.displayName !== undefined ? { displayName: input.displayName } : {}),
            ...(input.userStatus !== undefined ? { status: input.userStatus } : {}),
            ...(passwordHash !== undefined
              ? {
                  passwordHash,
                  passwordChangedAt: new Date(),
                  failedLoginAttempts: 0,
                  lockedUntil: null,
                }
              : {}),
          },
        });

        if (shouldRevokeSessions) {
          await transaction.session.updateMany({
            where: {
              organizationId: principal.organizationId,
              userId: current.userId,
              status: 'ACTIVE',
            },
            data: {
              status: 'REVOKED',
              revokedAt: new Date(),
              revokeReason: 'employee_management_change',
            },
          });
        }

        await transaction.auditLog.create({
          data: {
            organizationId: principal.organizationId,
            actorType: 'USER',
            actorUserId: principal.userId,
            action: 'employee.updated',
            resourceType: 'employee',
            resourceId: employeeId,
            outcome: 'SUCCESS',
          },
        });
      });

      return this.getEmployee(principal.organizationId, employeeId);
    } catch (error) {
      this.rethrowUniqueConflict(
        error,
        'EMPLOYEE_ALREADY_EXISTS',
        'An employee with this employee code already exists.',
      );
      throw error;
    }
  }

  private async assertTeam(organizationId: string, teamId: string): Promise<void> {
    const team = await this.database.client.team.findFirst({
      where: { id: teamId, organizationId, deletedAt: null },
      select: { id: true },
    });

    if (!team) {
      throw new NotFoundException({
        code: 'TEAM_NOT_FOUND',
        message: 'Team was not found.',
      });
    }
  }

  private async assertActiveTeam(organizationId: string, teamId: string): Promise<void> {
    const team = await this.database.client.team.findFirst({
      where: { id: teamId, organizationId, deletedAt: null, status: 'ACTIVE' },
      select: { id: true },
    });

    if (!team) {
      throw new NotFoundException({
        code: 'ACTIVE_TEAM_NOT_FOUND',
        message: 'An active team was not found.',
      });
    }
  }

  private async getEmployeeRecord(organizationId: string, employeeId: string) {
    const employee = await this.database.client.employee.findFirst({
      where: { id: employeeId, organizationId, deletedAt: null },
      include: {
        team: true,
        user: {
          include: {
            userRoles: {
              include: { role: true },
            },
          },
        },
      },
    });

    if (!employee) {
      throw new NotFoundException({
        code: 'EMPLOYEE_NOT_FOUND',
        message: 'Employee was not found.',
      });
    }

    return employee;
  }

  private async getEmployee(
    organizationId: string,
    employeeId: string,
  ): Promise<ManagedEmployeeResponse> {
    return this.mapEmployee(await this.getEmployeeRecord(organizationId, employeeId));
  }

  private mapOrganization(organization: {
    id: string;
    name: string;
    slug: string;
    status: 'ACTIVE' | 'SUSPENDED' | 'ARCHIVED';
    timezone: string;
    createdAt: Date;
    updatedAt: Date;
  }): OrganizationManagementResponse {
    return {
      id: organization.id,
      name: organization.name,
      slug: organization.slug,
      status: organization.status,
      timezone: organization.timezone,
      createdAt: organization.createdAt.toISOString(),
      updatedAt: organization.updatedAt.toISOString(),
    };
  }

  private mapTeam(team: {
    id: string;
    organizationId: string;
    name: string;
    slug: string;
    description: string | null;
    status: 'ACTIVE' | 'INACTIVE';
    createdAt: Date;
    updatedAt: Date;
    _count: { employees: number };
  }): TeamManagementResponse {
    return {
      id: team.id,
      organizationId: team.organizationId,
      name: team.name,
      slug: team.slug,
      description: team.description,
      status: team.status,
      employeeCount: team._count.employees,
      createdAt: team.createdAt.toISOString(),
      updatedAt: team.updatedAt.toISOString(),
    };
  }

  private mapEmployee(employee: Awaited<ReturnType<ManagementService['getEmployeeRecord']>>): ManagedEmployeeResponse {
    const roles = employee.user.userRoles
      .map((assignment) => assignment.role.code)
      .filter((role): role is 'ADMIN' | 'EMPLOYEE' => role === 'ADMIN' || role === 'EMPLOYEE');

    return {
      id: employee.id,
      organizationId: employee.organizationId,
      employeeCode: employee.employeeCode,
      status: employee.status,
      team: {
        id: employee.team.id,
        name: employee.team.name,
        slug: employee.team.slug,
        status: employee.team.status,
      },
      user: {
        id: employee.user.id,
        email: employee.user.email,
        displayName: employee.user.displayName,
        status: employee.user.status,
        lastLoginAt: employee.user.lastLoginAt?.toISOString() ?? null,
        createdAt: employee.user.createdAt.toISOString(),
      },
      roles,
      createdAt: employee.createdAt.toISOString(),
      updatedAt: employee.updatedAt.toISOString(),
    };
  }

  private rethrowUniqueConflict(error: unknown, code: string, message: string): void {
    if (
      typeof error === 'object' &&
      error !== null &&
      'code' in error &&
      (error as { code?: unknown }).code === 'P2002'
    ) {
      throw new ConflictException({ code, message });
    }
  }
}
