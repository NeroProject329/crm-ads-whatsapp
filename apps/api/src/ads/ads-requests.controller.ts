import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Inject,
  Param,
  ParseUUIDPipe,
  Post,
  UseGuards,
} from '@nestjs/common';

import type { AuthenticatedPrincipal } from '@crm/auth';

import type { AdsRequestListResponse, AdsRequestResponse } from '@crm/contracts';

import { createAdsRequestSchema } from '@crm/validation';

import { AccessTokenGuard } from '../authorization/access-token.guard.js';
import { AuthorizationGuard } from '../authorization/authorization.guard.js';
import { CurrentPrincipal } from '../authorization/current-principal.decorator.js';
import { RequirePermissions } from '../authorization/require-permissions.decorator.js';

import { AdsService } from './ads.service.js';

@Controller('ads-requests')
@UseGuards(AccessTokenGuard, AuthorizationGuard)
export class AdsRequestsController {
  constructor(
    @Inject(AdsService)
    private readonly service: AdsService,
  ) {}

  @Get()
  @RequirePermissions('ads_request.read')
  list(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,
  ): Promise<AdsRequestListResponse> {
    return this.service.listRequests(principal);
  }

  @Get(':requestId')
  @RequirePermissions('ads_request.read')
  getById(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('requestId', new ParseUUIDPipe())
    requestId: string,
  ): Promise<AdsRequestResponse> {
    return this.service.getRequest(principal, requestId);
  }

  @Post()
  @RequirePermissions('ads_request.manage')
  create(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Body()
    body: unknown,
  ): Promise<AdsRequestResponse> {
    const parsed = createAdsRequestSchema.safeParse(body);

    if (!parsed.success) {
      throw new BadRequestException({
        code: 'ADS_REQUEST_VALIDATION_ERROR',
        message: 'Invalid ADS request payload.',

        issues: parsed.error.issues.map((issue) => ({
          code: issue.code,
          path: issue.path.map(String).join('.'),
        })),
      });
    }

    return this.service.createRequest(principal, parsed.data);
  }

  @Post(':requestId/cancel')
  @RequirePermissions('ads_request.manage')
  cancel(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('requestId', new ParseUUIDPipe())
    requestId: string,
  ): Promise<AdsRequestResponse> {
    return this.service.cancelRequest(principal, requestId);
  }
}
