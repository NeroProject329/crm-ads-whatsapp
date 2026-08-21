import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Inject,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  UseGuards,
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
import {
  createManagedEmployeeSchema,
  createTeamManagementSchema,
  updateManagedEmployeeSchema,
  updateOrganizationManagementSchema,
  updateTeamManagementSchema,
} from '@crm/validation';

import { AccessTokenGuard } from '../authorization/access-token.guard.js';
import { AuthorizationGuard } from '../authorization/authorization.guard.js';
import { CurrentPrincipal } from '../authorization/current-principal.decorator.js';
import { RequirePermissions } from '../authorization/require-permissions.decorator.js';
import { ManagementService } from './management.service.js';

@Controller('management')
@UseGuards(AccessTokenGuard, AuthorizationGuard)
export class ManagementController {
  constructor(
    @Inject(ManagementService)
    private readonly managementService: ManagementService,
  ) {}

  @Get('overview')
  @RequirePermissions('organization.read')
  overview(
    @CurrentPrincipal() principal: AuthenticatedPrincipal,
  ): Promise<ManagementOverviewResponse> {
    return this.managementService.overview(principal);
  }

  @Get('organization')
  @RequirePermissions('organization.read')
  organization(
    @CurrentPrincipal() principal: AuthenticatedPrincipal,
  ): Promise<OrganizationManagementResponse> {
    return this.managementService.organization(principal);
  }

  @Patch('organization')
  @RequirePermissions('organization.manage')
  updateOrganization(
    @CurrentPrincipal() principal: AuthenticatedPrincipal,
    @Body() body: unknown,
  ): Promise<OrganizationManagementResponse> {
    const parsed = updateOrganizationManagementSchema.safeParse(body);

    if (!parsed.success) {
      throw this.validationError('MANAGEMENT_ORGANIZATION_VALIDATION_ERROR', parsed.error.issues);
    }

    return this.managementService.updateOrganization(principal, parsed.data);
  }

  @Get('teams')
  @RequirePermissions('team.read')
  teams(
    @CurrentPrincipal() principal: AuthenticatedPrincipal,
  ): Promise<TeamManagementListResponse> {
    return this.managementService.teams(principal);
  }

  @Post('teams')
  @RequirePermissions('team.manage')
  createTeam(
    @CurrentPrincipal() principal: AuthenticatedPrincipal,
    @Body() body: unknown,
  ): Promise<TeamManagementResponse> {
    const parsed = createTeamManagementSchema.safeParse(body);

    if (!parsed.success) {
      throw this.validationError('MANAGEMENT_TEAM_VALIDATION_ERROR', parsed.error.issues);
    }

    return this.managementService.createTeam(principal, parsed.data);
  }

  @Patch('teams/:teamId')
  @RequirePermissions('team.manage')
  updateTeam(
    @CurrentPrincipal() principal: AuthenticatedPrincipal,
    @Param('teamId', new ParseUUIDPipe()) teamId: string,
    @Body() body: unknown,
  ): Promise<TeamManagementResponse> {
    const parsed = updateTeamManagementSchema.safeParse(body);

    if (!parsed.success) {
      throw this.validationError('MANAGEMENT_TEAM_VALIDATION_ERROR', parsed.error.issues);
    }

    return this.managementService.updateTeam(principal, teamId, parsed.data);
  }

  @Get('employees')
  @RequirePermissions('employee.read', 'user.read')
  employees(
    @CurrentPrincipal() principal: AuthenticatedPrincipal,
  ): Promise<ManagedEmployeeListResponse> {
    return this.managementService.employees(principal);
  }

  @Post('employees')
  @RequirePermissions('employee.manage', 'user.manage')
  createEmployee(
    @CurrentPrincipal() principal: AuthenticatedPrincipal,
    @Body() body: unknown,
  ): Promise<ManagedEmployeeResponse> {
    const parsed = createManagedEmployeeSchema.safeParse(body);

    if (!parsed.success) {
      throw this.validationError('MANAGEMENT_EMPLOYEE_VALIDATION_ERROR', parsed.error.issues);
    }

    return this.managementService.createEmployee(principal, parsed.data);
  }

  @Patch('employees/:employeeId')
  @RequirePermissions('employee.manage', 'user.manage')
  updateEmployee(
    @CurrentPrincipal() principal: AuthenticatedPrincipal,
    @Param('employeeId', new ParseUUIDPipe()) employeeId: string,
    @Body() body: unknown,
  ): Promise<ManagedEmployeeResponse> {
    const parsed = updateManagedEmployeeSchema.safeParse(body);

    if (!parsed.success) {
      throw this.validationError('MANAGEMENT_EMPLOYEE_VALIDATION_ERROR', parsed.error.issues);
    }

    return this.managementService.updateEmployee(principal, employeeId, parsed.data);
  }

  private validationError(code: string, issues: readonly { code: string; path: PropertyKey[] }[]) {
    return new BadRequestException({
      code,
      message: 'Invalid management payload.',
      issues: issues.map((issue) => ({
        code: issue.code,
        path: issue.path.join('.'),
      })),
    });
  }
}
