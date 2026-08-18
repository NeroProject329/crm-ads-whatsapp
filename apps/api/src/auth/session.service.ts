import { Inject, Injectable, UnauthorizedException } from '@nestjs/common';
import { isRole, issueAccessToken, type Role } from '@crm/auth';
import { parseAuthEnvironment } from '@crm/config';
import type { AuthLogoutResponse, AuthRefreshResponse } from '@crm/contracts';
import { createOpaqueToken, hashOpaqueToken } from '@crm/security';

import { DatabaseService } from '../database/database.service.js';
import type { RefreshTransactionResult, SessionRequestContext } from './session.types.js';

@Injectable()
export class SessionService {
  private readonly environment = parseAuthEnvironment();

  constructor(
    @Inject(DatabaseService)
    private readonly database: DatabaseService,
  ) {}

  async refresh(
    refreshToken: string,
    context: SessionRequestContext,
  ): Promise<AuthRefreshResponse> {
    const tokenHash = hashOpaqueToken(refreshToken, this.environment.AUTH_REFRESH_TOKEN_PEPPER);

    const now = new Date();

    const result = await this.database.client.$transaction<RefreshTransactionResult>(
      async (transaction) => {
        const currentToken = await transaction.refreshToken.findUnique({
          where: {
            tokenHash,
          },
          include: {
            session: {
              include: {
                user: {
                  include: {
                    userRoles: {
                      include: {
                        role: true,
                      },
                    },
                  },
                },
              },
            },
          },
        });

        if (!currentToken) {
          return {
            kind: 'rejected',
          };
        }

        const session = currentToken.session;

        if (
          session.status !== 'ACTIVE' ||
          session.expiresAt <= now ||
          currentToken.revokedAt ||
          currentToken.expiresAt <= now
        ) {
          return {
            kind: 'rejected',
          };
        }

        if (currentToken.consumedAt) {
          await this.revokeRefreshFamily(
            transaction,
            currentToken.familyId,
            session.id,
            session.organizationId,
            session.userId,
            context.userAgent,
            now,
          );

          return {
            kind: 'reuse-detected',
          };
        }

        const claimResult = await transaction.refreshToken.updateMany({
          where: {
            id: currentToken.id,
            consumedAt: null,
            revokedAt: null,
            expiresAt: {
              gt: now,
            },
          },
          data: {
            consumedAt: now,
          },
        });

        if (claimResult.count !== 1) {
          const latestToken = await transaction.refreshToken.findUnique({
            where: {
              id: currentToken.id,
            },
          });

          if (latestToken?.consumedAt) {
            await this.revokeRefreshFamily(
              transaction,
              currentToken.familyId,
              session.id,
              session.organizationId,
              session.userId,
              context.userAgent,
              now,
            );

            return {
              kind: 'reuse-detected',
            };
          }

          return {
            kind: 'rejected',
          };
        }

        const roles = session.user.userRoles
          .map((assignment) => assignment.role.code)
          .filter((role): role is Role => isRole(role));

        if (session.user.status !== 'ACTIVE' || roles.length === 0) {
          await this.revokeSession(
            transaction,
            session.id,
            session.organizationId,
            session.userId,
            'user_not_authorized',
            context.userAgent,
            now,
          );

          return {
            kind: 'rejected',
          };
        }

        const nextRefreshToken = createOpaqueToken();

        const nextRefreshTokenHash = hashOpaqueToken(
          nextRefreshToken,
          this.environment.AUTH_REFRESH_TOKEN_PEPPER,
        );

        await transaction.refreshToken.create({
          data: {
            sessionId: session.id,
            tokenHash: nextRefreshTokenHash,
            familyId: currentToken.familyId,
            parentTokenId: currentToken.id,
            expiresAt: session.expiresAt,
          },
        });

        await transaction.session.update({
          where: {
            id: session.id,
          },
          data: {
            lastSeenAt: now,
          },
        });

        await transaction.auditLog.create({
          data: {
            organizationId: session.organizationId,
            actorType: 'USER',
            actorUserId: session.userId,
            action: 'auth.refresh',
            resourceType: 'session',
            resourceId: session.id,
            outcome: 'SUCCESS',
            userAgent: context.userAgent,
          },
        });

        return {
          kind: 'success',
          principal: {
            displayName: session.user.displayName,
            email: session.user.email,
            organizationId: session.organizationId,
            roles,
            sessionId: session.id,
            userId: session.userId,
          },
          refreshExpiresAt: session.expiresAt,
          refreshToken: nextRefreshToken,
        };
      },
    );

    if (result.kind === 'reuse-detected') {
      throw new UnauthorizedException({
        code: 'AUTH_REFRESH_REUSE_DETECTED',
        message: 'Refresh token reuse detected.',
      });
    }

    if (result.kind === 'rejected') {
      throw this.invalidRefreshToken();
    }

    const accessToken = await issueAccessToken(
      {
        organizationId: result.principal.organizationId,
        roles: result.principal.roles,
        sessionId: result.principal.sessionId,
        userId: result.principal.userId,
      },
      {
        audience: this.environment.AUTH_ACCESS_TOKEN_AUDIENCE,
        issuer: this.environment.AUTH_ACCESS_TOKEN_ISSUER,
        secret: this.environment.AUTH_ACCESS_TOKEN_SECRET,
        ttlSeconds: this.environment.AUTH_ACCESS_TOKEN_TTL_SECONDS,
      },
    );

    const refreshTokenExpiresInSeconds = Math.max(
      0,
      Math.floor((result.refreshExpiresAt.getTime() - Date.now()) / 1000),
    );

    return {
      accessToken,
      accessTokenExpiresInSeconds: this.environment.AUTH_ACCESS_TOKEN_TTL_SECONDS,
      refreshToken: result.refreshToken,
      refreshTokenExpiresInSeconds,
      sessionId: result.principal.sessionId,
      tokenType: 'Bearer',
      user: {
        displayName: result.principal.displayName,
        email: result.principal.email,
        organizationId: result.principal.organizationId,
        roles: result.principal.roles,
        userId: result.principal.userId,
      },
    };
  }

  async logout(refreshToken: string, context: SessionRequestContext): Promise<AuthLogoutResponse> {
    const tokenHash = hashOpaqueToken(refreshToken, this.environment.AUTH_REFRESH_TOKEN_PEPPER);

    const now = new Date();

    await this.database.client.$transaction(async (transaction) => {
      const token = await transaction.refreshToken.findUnique({
        where: {
          tokenHash,
        },
        include: {
          session: true,
        },
      });

      if (!token) {
        return;
      }

      const session = token.session;

      await transaction.refreshToken.updateMany({
        where: {
          sessionId: session.id,
          revokedAt: null,
        },
        data: {
          revokedAt: now,
        },
      });

      if (session.status === 'ACTIVE') {
        await transaction.session.update({
          where: {
            id: session.id,
          },
          data: {
            status: 'REVOKED',
            revokedAt: now,
            revokeReason: 'logout',
            lastSeenAt: now,
          },
        });

        await transaction.auditLog.create({
          data: {
            organizationId: session.organizationId,
            actorType: 'USER',
            actorUserId: session.userId,
            action: 'auth.logout',
            resourceType: 'session',
            resourceId: session.id,
            outcome: 'SUCCESS',
            userAgent: context.userAgent,
          },
        });
      }
    });

    return {
      success: true,
    };
  }

  async logoutAll(
    refreshToken: string,
    context: SessionRequestContext,
  ): Promise<AuthLogoutResponse> {
    const tokenHash = hashOpaqueToken(refreshToken, this.environment.AUTH_REFRESH_TOKEN_PEPPER);

    const now = new Date();

    const authenticated = await this.database.client.$transaction(async (transaction) => {
      const token = await transaction.refreshToken.findUnique({
        where: {
          tokenHash,
        },
        include: {
          session: true,
        },
      });

      if (
        !token ||
        token.revokedAt ||
        token.consumedAt ||
        token.expiresAt <= now ||
        token.session.status !== 'ACTIVE' ||
        token.session.expiresAt <= now
      ) {
        return false;
      }

      const activeSessions = await transaction.session.findMany({
        where: {
          organizationId: token.session.organizationId,
          userId: token.session.userId,
          status: 'ACTIVE',
        },
        select: {
          id: true,
        },
      });

      const sessionIds = activeSessions.map((session) => session.id);

      if (sessionIds.length > 0) {
        await transaction.refreshToken.updateMany({
          where: {
            sessionId: {
              in: sessionIds,
            },
            revokedAt: null,
          },
          data: {
            revokedAt: now,
          },
        });

        await transaction.session.updateMany({
          where: {
            id: {
              in: sessionIds,
            },
            status: 'ACTIVE',
          },
          data: {
            status: 'REVOKED',
            revokedAt: now,
            revokeReason: 'logout_all',
            lastSeenAt: now,
          },
        });
      }

      await transaction.auditLog.create({
        data: {
          organizationId: token.session.organizationId,
          actorType: 'USER',
          actorUserId: token.session.userId,
          action: 'auth.logout_all',
          resourceType: 'user',
          resourceId: token.session.userId,
          outcome: 'SUCCESS',
          userAgent: context.userAgent,
          metadata: {
            revokedSessionCount: sessionIds.length,
          },
        },
      });

      return true;
    });

    if (!authenticated) {
      throw this.invalidRefreshToken();
    }

    return {
      success: true,
    };
  }

  private async revokeRefreshFamily(
    transaction: Parameters<Parameters<typeof this.database.client.$transaction>[0]>[0],
    familyId: string,
    sessionId: string,
    organizationId: string,
    userId: string,
    userAgent: string | null,
    now: Date,
  ): Promise<void> {
    await transaction.refreshToken.updateMany({
      where: {
        familyId,
        revokedAt: null,
      },
      data: {
        revokedAt: now,
      },
    });

    await transaction.session.updateMany({
      where: {
        id: sessionId,
        status: 'ACTIVE',
      },
      data: {
        status: 'REVOKED',
        revokedAt: now,
        revokeReason: 'refresh_token_reuse_detected',
        lastSeenAt: now,
      },
    });

    await transaction.auditLog.create({
      data: {
        organizationId,
        actorType: 'USER',
        actorUserId: userId,
        action: 'auth.refresh_reuse_detected',
        resourceType: 'session',
        resourceId: sessionId,
        outcome: 'DENIED',
        userAgent,
        metadata: {
          familyId,
        },
      },
    });
  }

  private async revokeSession(
    transaction: Parameters<Parameters<typeof this.database.client.$transaction>[0]>[0],
    sessionId: string,
    organizationId: string,
    userId: string,
    reason: string,
    userAgent: string | null,
    now: Date,
  ): Promise<void> {
    await transaction.refreshToken.updateMany({
      where: {
        sessionId,
        revokedAt: null,
      },
      data: {
        revokedAt: now,
      },
    });

    await transaction.session.updateMany({
      where: {
        id: sessionId,
        status: 'ACTIVE',
      },
      data: {
        status: 'REVOKED',
        revokedAt: now,
        revokeReason: reason,
        lastSeenAt: now,
      },
    });

    await transaction.auditLog.create({
      data: {
        organizationId,
        actorType: 'USER',
        actorUserId: userId,
        action: 'auth.session_revoke',
        resourceType: 'session',
        resourceId: sessionId,
        outcome: 'SUCCESS',
        userAgent,
        metadata: {
          reason,
        },
      },
    });
  }

  private invalidRefreshToken(): UnauthorizedException {
    return new UnauthorizedException({
      code: 'AUTH_INVALID_REFRESH_TOKEN',
      message: 'Invalid refresh token.',
    });
  }
}
