import { Inject, Injectable, UnauthorizedException } from '@nestjs/common';

import type { CanActivate, ExecutionContext } from '@nestjs/common';

import { isRole, verifyAccessToken, type AuthenticatedPrincipal, type Role } from '@crm/auth';

import { parseAuthEnvironment } from '@crm/config';

import { DatabaseService } from '../database/database.service.js';

import type { AuthenticatedHttpRequest, PermissionCode } from './authorization.types.js';

@Injectable()
export class AccessTokenGuard implements CanActivate {
  private readonly environment = parseAuthEnvironment();

  constructor(
    @Inject(DatabaseService)
    private readonly database: DatabaseService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<AuthenticatedHttpRequest>();

    const token = this.extractBearerToken(request.headers.authorization);

    if (!token) {
      throw this.unauthorized();
    }

    let verifiedToken;

    try {
      verifiedToken = await verifyAccessToken(token, {
        audience: this.environment.AUTH_ACCESS_TOKEN_AUDIENCE,

        issuer: this.environment.AUTH_ACCESS_TOKEN_ISSUER,

        secret: this.environment.AUTH_ACCESS_TOKEN_SECRET,

        ttlSeconds: this.environment.AUTH_ACCESS_TOKEN_TTL_SECONDS,
      });
    } catch {
      throw this.unauthorized();
    }

    const now = new Date();

    const session = await this.database.client.session.findUnique({
      where: {
        id: verifiedToken.sessionId,
      },

      include: {
        user: {
          include: {
            userRoles: {
              include: {
                role: {
                  include: {
                    rolePermissions: {
                      include: {
                        permission: true,
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
    });

    if (
      !session ||
      session.status !== 'ACTIVE' ||
      session.expiresAt <= now ||
      session.organizationId !== verifiedToken.organizationId ||
      session.userId !== verifiedToken.userId ||
      session.user.status !== 'ACTIVE'
    ) {
      throw this.unauthorized();
    }

    const roles = session.user.userRoles
      .map((assignment) => assignment.role.code)
      .filter((role): role is Role => isRole(role));

    if (roles.length === 0) {
      throw this.unauthorized();
    }

    const permissions = Array.from(
      new Set(
        session.user.userRoles.flatMap((assignment) =>
          assignment.role.rolePermissions.map((rolePermission) => rolePermission.permission.code),
        ),
      ),
    ).filter((permission): permission is PermissionCode => this.isPermissionCode(permission));

    const principal: AuthenticatedPrincipal = {
      organizationId: session.organizationId,

      roles,

      sessionId: session.id,

      userId: session.userId,
    };

    request.authorization = {
      permissions,
      principal,
      roles,
    };

    await this.database.client.session.update({
      where: {
        id: session.id,
      },

      data: {
        lastSeenAt: now,
      },
    });

    return true;
  }

  private extractBearerToken(authorization: string | string[] | undefined): string | null {
    if (typeof authorization !== 'string') {
      return null;
    }

    const match = /^Bearer\s+(.+)$/i.exec(authorization.trim());

    if (!match) {
      return null;
    }

    const token = match[1];

    if (!token) {
      return null;
    }

    return token.trim() || null;
  }

  private isPermissionCode(value: string): value is PermissionCode {
    return (
      value === 'organization.read' ||
      value === 'organization.manage' ||
      value === 'team.read' ||
      value === 'team.manage' ||
      value === 'user.read' ||
      value === 'user.manage' ||
      value === 'employee.read' ||
      value === 'employee.manage' ||
      value === 'audit.read' ||
      value === 'profile.read' ||
      value === 'profile.update' ||
      value === 'site.read' ||
      value === 'site.manage' ||
      value === 'domain.read' ||
      value === 'domain.manage' ||
      value === 'whatsapp_number.read' ||
      value === 'whatsapp_number.manage' ||
      value === 'traffic_pool.read' ||
      value === 'traffic_pool.manage' ||
      value === 'ads_request.read' ||
      value === 'ads_request.manage' ||
      value === 'ads_queue.read' ||
      value === 'ads_queue.manage'
    );
  }

  private unauthorized(): UnauthorizedException {
    return new UnauthorizedException({
      code: 'AUTH_ACCESS_DENIED',

      message: 'Authentication is required.',
    });
  }
}
