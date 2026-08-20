import {
  BadRequestException,
  Controller,
  Get,
  Inject,
  Param,
  ParseUUIDPipe,
  Query,
  UseGuards,
} from '@nestjs/common';

import type { AuthenticatedPrincipal } from '@crm/auth';

import type { LeadListResponse, LeadResponse, LeadSummaryResponse } from '@crm/contracts';

import { leadListQuerySchema } from '@crm/validation';

import { AccessTokenGuard } from '../authorization/access-token.guard.js';

import { AuthorizationGuard } from '../authorization/authorization.guard.js';

import { CurrentPrincipal } from '../authorization/current-principal.decorator.js';

import { RequirePermissions } from '../authorization/require-permissions.decorator.js';

import { LeadsService } from './leads.service.js';

@Controller('leads')
@UseGuards(AccessTokenGuard, AuthorizationGuard)
export class LeadsController {
  constructor(
    @Inject(LeadsService)
    private readonly leadsService: LeadsService,
  ) {}

  @Get()
  @RequirePermissions('lead.read')
  list(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Query()
    query: unknown,
  ): Promise<LeadListResponse> {
    const parsed = leadListQuerySchema.safeParse(query);

    if (!parsed.success) {
      throw new BadRequestException({
        code: 'LEAD_QUERY_VALIDATION_ERROR',

        message: 'Invalid lead query.',

        issues: parsed.error.issues.map((issue) => ({
          code: issue.code,

          path: issue.path.join('.'),
        })),
      });
    }

    return this.leadsService.list(principal, parsed.data);
  }

  @Get('summary')
  @RequirePermissions('lead.read')
  summary(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,
  ): Promise<LeadSummaryResponse> {
    return this.leadsService.summary(principal);
  }

  @Get(':leadId')
  @RequirePermissions('lead.read')
  getById(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('leadId', new ParseUUIDPipe())
    leadId: string,
  ): Promise<LeadResponse> {
    return this.leadsService.getById(principal, leadId);
  }
}
