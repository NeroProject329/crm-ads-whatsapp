import { Controller, Get, Inject, Param, ParseUUIDPipe, UseGuards } from '@nestjs/common';

import type { AuthenticatedPrincipal } from '@crm/auth';

import type { SiteMonitorCheckListResponse, SiteMonitoringResponse } from '@crm/contracts';

import { AccessTokenGuard } from '../authorization/access-token.guard.js';
import { AuthorizationGuard } from '../authorization/authorization.guard.js';
import { CurrentPrincipal } from '../authorization/current-principal.decorator.js';
import { RequirePermissions } from '../authorization/require-permissions.decorator.js';

import { SiteMonitoringService } from './site-monitoring.service.js';

@Controller('sites')
@UseGuards(AccessTokenGuard, AuthorizationGuard)
export class SiteMonitoringController {
  constructor(
    @Inject(SiteMonitoringService)
    private readonly siteMonitoringService: SiteMonitoringService,
  ) {}

  @Get(':siteId/monitoring')
  @RequirePermissions('site.read', 'domain.read')
  getSiteMonitoring(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('siteId', new ParseUUIDPipe())
    siteId: string,
  ): Promise<SiteMonitoringResponse> {
    return this.siteMonitoringService.getSiteMonitoring(principal, siteId);
  }

  @Get(':siteId/domains/:domainId/monitoring/checks')
  @RequirePermissions('site.read', 'domain.read')
  listChecks(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('siteId', new ParseUUIDPipe())
    siteId: string,

    @Param('domainId', new ParseUUIDPipe())
    domainId: string,
  ): Promise<SiteMonitorCheckListResponse> {
    return this.siteMonitoringService.listChecks(principal, siteId, domainId);
  }
}
