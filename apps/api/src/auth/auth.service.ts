import { randomUUID } from 'node:crypto';

import { Inject, Injectable, UnauthorizedException } from '@nestjs/common';
import { isRole, issueAccessToken, type Role } from '@crm/auth';
import { parseAuthEnvironment } from '@crm/config';
import type { AuthLoginResponse } from '@crm/contracts';
import { createOpaqueToken, hashOpaqueToken, verifyPassword } from '@crm/security';
import type { LoginInput } from '@crm/validation';

import { DatabaseService } from '../database/database.service.js';

type LoginContext = Readonly<{
  userAgent: string | null;
}>;

@Injectable()
export class AuthService {
  private readonly environment = parseAuthEnvironment();

  constructor(
    @Inject(DatabaseService)
    private readonly database: DatabaseService,
  ) {}

  async login(input: LoginInput, context: LoginContext): Promise<AuthLoginResponse> {
    const organization = await this.database.client.organization.findUnique({
      where: {
        slug: input.organizationSlug,
      },
    });

    if (!organization || organization.status !== 'ACTIVE') {
      throw this.invalidCredentials();
    }

    const user = await this.database.client.user.findUnique({
      where: {
        organizationId_emailNormalized: {
          organizationId: organization.id,
          emailNormalized: input.email,
        },
      },
      include: {
        userRoles: {
          include: {
            role: true,
          },
        },
      },
    });

    if (!user || user.status !== 'ACTIVE' || !user.passwordHash) {
      throw this.invalidCredentials();
    }

    const now = new Date();

    if (user.lockedUntil && user.lockedUntil > now) {
      await this.writeDeniedAudit(organization.id, user.id, context.userAgent, 'account_locked');
      throw this.invalidCredentials();
    }

    const passwordMatches = await verifyPassword(input.password, user.passwordHash);

    if (!passwordMatches) {
      await this.recordFailedLogin(
        organization.id,
        user.id,
        user.failedLoginAttempts,
        user.lockedUntil,
        context.userAgent,
      );
      throw this.invalidCredentials();
    }

    const roles = user.userRoles
      .map((assignment) => assignment.role.code)
      .filter((role): role is Role => isRole(role));

    if (roles.length === 0) {
      await this.writeDeniedAudit(organization.id, user.id, context.userAgent, 'missing_role');
      throw this.invalidCredentials();
    }

    const sessionId = randomUUID();
    const familyId = randomUUID();
    const refreshToken = createOpaqueToken();
    const refreshTokenHash = hashOpaqueToken(
      refreshToken,
      this.environment.AUTH_REFRESH_TOKEN_PEPPER,
    );

    const refreshExpiresAt = new Date(
      now.getTime() + this.environment.AUTH_REFRESH_TOKEN_TTL_SECONDS * 1000,
    );

    const accessToken = await issueAccessToken(
      {
        organizationId: organization.id,
        roles,
        sessionId,
        userId: user.id,
      },
      {
        audience: this.environment.AUTH_ACCESS_TOKEN_AUDIENCE,
        issuer: this.environment.AUTH_ACCESS_TOKEN_ISSUER,
        secret: this.environment.AUTH_ACCESS_TOKEN_SECRET,
        ttlSeconds: this.environment.AUTH_ACCESS_TOKEN_TTL_SECONDS,
      },
    );

    await this.database.client.$transaction([
      this.database.client.session.create({
        data: {
          id: sessionId,
          organizationId: organization.id,
          userId: user.id,
          expiresAt: refreshExpiresAt,
          lastSeenAt: now,
          userAgent: context.userAgent,
        },
      }),
      this.database.client.refreshToken.create({
        data: {
          sessionId,
          tokenHash: refreshTokenHash,
          familyId,
          expiresAt: refreshExpiresAt,
        },
      }),
      this.database.client.user.update({
        where: {
          id: user.id,
        },
        data: {
          failedLoginAttempts: 0,
          lastLoginAt: now,
          lockedUntil: null,
        },
      }),
      this.database.client.auditLog.create({
        data: {
          organizationId: organization.id,
          actorType: 'USER',
          actorUserId: user.id,
          action: 'auth.login',
          resourceType: 'session',
          resourceId: sessionId,
          outcome: 'SUCCESS',
          userAgent: context.userAgent,
        },
      }),
    ]);

    return {
      accessToken,
      accessTokenExpiresInSeconds: this.environment.AUTH_ACCESS_TOKEN_TTL_SECONDS,
      refreshToken,
      refreshTokenExpiresInSeconds: this.environment.AUTH_REFRESH_TOKEN_TTL_SECONDS,
      sessionId,
      tokenType: 'Bearer',
      user: {
        displayName: user.displayName,
        email: user.email,
        organizationId: organization.id,
        roles,
        userId: user.id,
      },
    };
  }

  private async recordFailedLogin(
    organizationId: string,
    userId: string,
    currentFailedAttempts: number,
    previousLockedUntil: Date | null,
    userAgent: string | null,
  ): Promise<void> {
    const now = new Date();
    const previousLockExpired = Boolean(previousLockedUntil && previousLockedUntil <= now);
    const baseAttempts = previousLockExpired ? 0 : currentFailedAttempts;
    const nextAttempts = baseAttempts + 1;
    const shouldLock = nextAttempts >= this.environment.AUTH_MAX_FAILED_LOGIN_ATTEMPTS;

    const lockedUntil = shouldLock
      ? new Date(now.getTime() + this.environment.AUTH_LOGIN_LOCK_SECONDS * 1000)
      : null;

    await this.database.client.$transaction([
      this.database.client.user.update({
        where: {
          id: userId,
        },
        data: {
          failedLoginAttempts: nextAttempts,
          lockedUntil,
        },
      }),
      this.database.client.auditLog.create({
        data: {
          organizationId,
          actorType: 'USER',
          actorUserId: userId,
          action: 'auth.login',
          resourceType: 'user',
          resourceId: userId,
          outcome: 'DENIED',
          userAgent,
          metadata: {
            reason: shouldLock ? 'invalid_credentials_locked' : 'invalid_credentials',
          },
        },
      }),
    ]);
  }

  private async writeDeniedAudit(
    organizationId: string,
    userId: string,
    userAgent: string | null,
    reason: string,
  ): Promise<void> {
    await this.database.client.auditLog.create({
      data: {
        organizationId,
        actorType: 'USER',
        actorUserId: userId,
        action: 'auth.login',
        resourceType: 'user',
        resourceId: userId,
        outcome: 'DENIED',
        userAgent,
        metadata: {
          reason,
        },
      },
    });
  }

  private invalidCredentials(): UnauthorizedException {
    return new UnauthorizedException({
      code: 'AUTH_INVALID_CREDENTIALS',
      message: 'Invalid credentials.',
    });
  }
}
