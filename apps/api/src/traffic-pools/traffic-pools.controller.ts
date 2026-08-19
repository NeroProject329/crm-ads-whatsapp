import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  Inject,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Put,
  UseGuards,
} from '@nestjs/common';

import type { AuthenticatedPrincipal } from '@crm/auth';

import type {
  TrafficPoolListResponse,
  TrafficPoolMemberDeleteResponse,
  TrafficPoolMemberResponse,
  TrafficPoolResponse,
} from '@crm/contracts';

import {
  addTrafficPoolMemberSchema,
  createTrafficPoolSchema,
  reorderTrafficPoolMembersSchema,
  updateTrafficPoolMemberSchema,
  updateTrafficPoolSchema,
} from '@crm/validation';

import { AccessTokenGuard } from '../authorization/access-token.guard.js';

import { AuthorizationGuard } from '../authorization/authorization.guard.js';

import { CurrentPrincipal } from '../authorization/current-principal.decorator.js';

import { RequirePermissions } from '../authorization/require-permissions.decorator.js';

import { TrafficPoolsService } from './traffic-pools.service.js';

@Controller('traffic-pools')
@UseGuards(AccessTokenGuard, AuthorizationGuard)
export class TrafficPoolsController {
  constructor(
    @Inject(TrafficPoolsService)
    private readonly service: TrafficPoolsService,
  ) {}

  @Get()
  @RequirePermissions('traffic_pool.read')
  list(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,
  ): Promise<TrafficPoolListResponse> {
    return this.service.list(principal);
  }

  @Get(':poolId')
  @RequirePermissions('traffic_pool.read')
  getById(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('poolId', new ParseUUIDPipe())
    poolId: string,
  ): Promise<TrafficPoolResponse> {
    return this.service.getById(principal, poolId);
  }

  @Post()
  @RequirePermissions('traffic_pool.manage')
  create(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Body()
    body: unknown,
  ): Promise<TrafficPoolResponse> {
    const parsed = createTrafficPoolSchema.safeParse(body);

    if (!parsed.success) {
      throw this.validationError(parsed.error.issues);
    }

    return this.service.create(principal, parsed.data);
  }

  @Patch(':poolId')
  @RequirePermissions('traffic_pool.manage')
  update(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('poolId', new ParseUUIDPipe())
    poolId: string,

    @Body()
    body: unknown,
  ): Promise<TrafficPoolResponse> {
    const parsed = updateTrafficPoolSchema.safeParse(body);

    if (!parsed.success) {
      throw this.validationError(parsed.error.issues);
    }

    return this.service.update(principal, poolId, parsed.data);
  }

  @Get(':poolId/members')
  @RequirePermissions('traffic_pool.read')
  listMembers(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('poolId', new ParseUUIDPipe())
    poolId: string,
  ): Promise<readonly TrafficPoolMemberResponse[]> {
    return this.service.listMembers(principal, poolId);
  }

  @Post(':poolId/members')
  @RequirePermissions('traffic_pool.manage')
  addMember(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('poolId', new ParseUUIDPipe())
    poolId: string,

    @Body()
    body: unknown,
  ): Promise<TrafficPoolMemberResponse> {
    const parsed = addTrafficPoolMemberSchema.safeParse(body);

    if (!parsed.success) {
      throw this.validationError(parsed.error.issues);
    }

    return this.service.addMember(principal, poolId, parsed.data);
  }

  @Patch(':poolId/members/:memberId')
  @RequirePermissions('traffic_pool.manage')
  updateMember(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('poolId', new ParseUUIDPipe())
    poolId: string,

    @Param('memberId', new ParseUUIDPipe())
    memberId: string,

    @Body()
    body: unknown,
  ): Promise<TrafficPoolMemberResponse> {
    const parsed = updateTrafficPoolMemberSchema.safeParse(body);

    if (!parsed.success) {
      throw this.validationError(parsed.error.issues);
    }

    return this.service.updateMember(principal, poolId, memberId, parsed.data);
  }

  @Put(':poolId/members/order')
  @RequirePermissions('traffic_pool.manage')
  reorderMembers(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('poolId', new ParseUUIDPipe())
    poolId: string,

    @Body()
    body: unknown,
  ): Promise<readonly TrafficPoolMemberResponse[]> {
    const parsed = reorderTrafficPoolMembersSchema.safeParse(body);

    if (!parsed.success) {
      throw this.validationError(parsed.error.issues);
    }

    return this.service.reorderMembers(principal, poolId, parsed.data);
  }

  @Delete(':poolId/members/:memberId')
  @RequirePermissions('traffic_pool.manage')
  removeMember(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('poolId', new ParseUUIDPipe())
    poolId: string,

    @Param('memberId', new ParseUUIDPipe())
    memberId: string,
  ): Promise<TrafficPoolMemberDeleteResponse> {
    return this.service.removeMember(principal, poolId, memberId);
  }

  private validationError(
    issues: readonly {
      code: string;
      path: PropertyKey[];
    }[],
  ): BadRequestException {
    return new BadRequestException({
      code: 'TRAFFIC_POOL_VALIDATION_ERROR',

      message: 'Invalid traffic pool payload.',

      issues: issues.map((issue) => ({
        code: issue.code,

        path: issue.path.map(String).join('.'),
      })),
    });
  }
}
