import { Controller, Get, Inject, Param, ParseUUIDPipe, UseGuards } from '@nestjs/common';

import type { AuthenticatedPrincipal } from '@crm/auth';

import type { AdsQueueItemResponse, AdsQueueListResponse } from '@crm/contracts';

import { AccessTokenGuard } from '../authorization/access-token.guard.js';
import { AuthorizationGuard } from '../authorization/authorization.guard.js';
import { CurrentPrincipal } from '../authorization/current-principal.decorator.js';
import { RequirePermissions } from '../authorization/require-permissions.decorator.js';

import { AdsService } from './ads.service.js';

@Controller('ads-queue')
@UseGuards(AccessTokenGuard, AuthorizationGuard)
export class AdsQueueController {
  constructor(
    @Inject(AdsService)
    private readonly service: AdsService,
  ) {}

  @Get()
  @RequirePermissions('ads_queue.read')
  list(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,
  ): Promise<AdsQueueListResponse> {
    return this.service.listQueue(principal);
  }

  @Get(':queueItemId')
  @RequirePermissions('ads_queue.read')
  getById(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('queueItemId', new ParseUUIDPipe())
    queueItemId: string,
  ): Promise<AdsQueueItemResponse> {
    return this.service.getQueueItem(principal, queueItemId);
  }
}
