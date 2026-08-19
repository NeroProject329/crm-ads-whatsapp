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

import type { SiteDomainResponse, SiteListResponse, SiteResponse } from '@crm/contracts';

import {
  createSiteDomainSchema,
  createSiteSchema,
  updateSiteDomainSchema,
  updateSiteSchema,
} from '@crm/validation';

import { AccessTokenGuard } from '../authorization/access-token.guard.js';

import { AuthorizationGuard } from '../authorization/authorization.guard.js';

import { CurrentPrincipal } from '../authorization/current-principal.decorator.js';

import { RequirePermissions } from '../authorization/require-permissions.decorator.js';

import { SitesService } from './sites.service.js';

@Controller('sites')
@UseGuards(AccessTokenGuard, AuthorizationGuard)
export class SitesController {
  constructor(
    @Inject(SitesService)
    private readonly sitesService: SitesService,
  ) {}

  @Get()
  @RequirePermissions('site.read')
  list(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,
  ): Promise<SiteListResponse> {
    return this.sitesService.list(principal);
  }

  @Get(':siteId')
  @RequirePermissions('site.read')
  getById(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('siteId', new ParseUUIDPipe())
    siteId: string,
  ): Promise<SiteResponse> {
    return this.sitesService.getById(principal, siteId);
  }

  @Post()
  @RequirePermissions('site.manage')
  create(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Body()
    body: unknown,
  ): Promise<SiteResponse> {
    const parsed = createSiteSchema.safeParse(body);

    if (!parsed.success) {
      throw new BadRequestException({
        code: 'SITE_VALIDATION_ERROR',

        message: 'Invalid site payload.',

        issues: parsed.error.issues.map((issue) => ({
          code: issue.code,

          path: issue.path.join('.'),
        })),
      });
    }

    return this.sitesService.create(principal, parsed.data);
  }

  @Patch(':siteId')
  @RequirePermissions('site.manage')
  update(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('siteId', new ParseUUIDPipe())
    siteId: string,

    @Body()
    body: unknown,
  ): Promise<SiteResponse> {
    const parsed = updateSiteSchema.safeParse(body);

    if (!parsed.success) {
      throw new BadRequestException({
        code: 'SITE_VALIDATION_ERROR',

        message: 'Invalid site payload.',

        issues: parsed.error.issues.map((issue) => ({
          code: issue.code,

          path: issue.path.join('.'),
        })),
      });
    }

    return this.sitesService.update(principal, siteId, parsed.data);
  }

  @Get(':siteId/domains')
  @RequirePermissions('site.read', 'domain.read')
  listDomains(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('siteId', new ParseUUIDPipe())
    siteId: string,
  ): Promise<readonly SiteDomainResponse[]> {
    return this.sitesService.listDomains(principal, siteId);
  }

  @Post(':siteId/domains')
  @RequirePermissions('domain.manage')
  createDomain(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('siteId', new ParseUUIDPipe())
    siteId: string,

    @Body()
    body: unknown,
  ): Promise<SiteDomainResponse> {
    const parsed = createSiteDomainSchema.safeParse(body);

    if (!parsed.success) {
      throw new BadRequestException({
        code: 'DOMAIN_VALIDATION_ERROR',

        message: 'Invalid domain payload.',

        issues: parsed.error.issues.map((issue) => ({
          code: issue.code,

          path: issue.path.join('.'),
        })),
      });
    }

    return this.sitesService.createDomain(principal, siteId, parsed.data);
  }

  @Patch(':siteId/domains/:domainId')
  @RequirePermissions('domain.manage')
  updateDomain(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('siteId', new ParseUUIDPipe())
    siteId: string,

    @Param('domainId', new ParseUUIDPipe())
    domainId: string,

    @Body()
    body: unknown,
  ): Promise<SiteDomainResponse> {
    const parsed = updateSiteDomainSchema.safeParse(body);

    if (!parsed.success) {
      throw new BadRequestException({
        code: 'DOMAIN_VALIDATION_ERROR',

        message: 'Invalid domain payload.',

        issues: parsed.error.issues.map((issue) => ({
          code: issue.code,

          path: issue.path.join('.'),
        })),
      });
    }

    return this.sitesService.updateDomain(principal, siteId, domainId, parsed.data);
  }
}
