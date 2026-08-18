import { Controller, Get, UseGuards } from '@nestjs/common';

import type { AuthenticatedPrincipal } from '@crm/auth';

import { AccessTokenGuard } from '../authorization/access-token.guard.js';

import { AuthorizationGuard } from '../authorization/authorization.guard.js';

import { CurrentPrincipal } from '../authorization/current-principal.decorator.js';

import { RequirePermissions } from '../authorization/require-permissions.decorator.js';

import { RequireRoles } from '../authorization/require-roles.decorator.js';

@Controller('auth')
@UseGuards(AccessTokenGuard, AuthorizationGuard)
export class ProfileController {
  @Get('me')
  @RequirePermissions('profile.read')
  me(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,
  ): AuthenticatedPrincipal {
    return principal;
  }

  @Get('admin-check')
  @RequireRoles('ADMIN')
  @RequirePermissions('organization.manage')
  adminCheck(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,
  ): AuthenticatedPrincipal {
    return principal;
  }
}
