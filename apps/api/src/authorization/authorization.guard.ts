import { ForbiddenException, Inject, Injectable } from '@nestjs/common';

import type { CanActivate, ExecutionContext } from '@nestjs/common';

import { Reflector } from '@nestjs/core';

import type { Role } from '@crm/auth';

import { REQUIRED_PERMISSIONS_KEY, REQUIRED_ROLES_KEY } from './authorization.constants.js';

import type { AuthenticatedHttpRequest, PermissionCode } from './authorization.types.js';

@Injectable()
export class AuthorizationGuard implements CanActivate {
  constructor(
    @Inject(Reflector)
    private readonly reflector: Reflector,
  ) {}

  canActivate(context: ExecutionContext): boolean {
    const requiredRoles =
      this.reflector.getAllAndOverride<readonly Role[]>(REQUIRED_ROLES_KEY, [
        context.getHandler(),
        context.getClass(),
      ]) ?? [];

    const requiredPermissions =
      this.reflector.getAllAndOverride<readonly PermissionCode[]>(REQUIRED_PERMISSIONS_KEY, [
        context.getHandler(),
        context.getClass(),
      ]) ?? [];

    const request = context.switchToHttp().getRequest<AuthenticatedHttpRequest>();

    const authorization = request.authorization;

    if (!authorization) {
      throw this.forbidden();
    }

    const hasRequiredRoles = requiredRoles.every((requiredRole) =>
      authorization.roles.includes(requiredRole),
    );

    if (!hasRequiredRoles) {
      throw this.forbidden();
    }

    const hasRequiredPermissions = requiredPermissions.every((requiredPermission) =>
      authorization.permissions.includes(requiredPermission),
    );

    if (!hasRequiredPermissions) {
      throw this.forbidden();
    }

    return true;
  }

  private forbidden(): ForbiddenException {
    return new ForbiddenException({
      code: 'AUTH_FORBIDDEN',
      message: 'You do not have permission to access this resource.',
    });
  }
}
