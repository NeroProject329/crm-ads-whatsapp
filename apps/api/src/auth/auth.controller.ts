import { BadRequestException, Body, Controller, Headers, Inject, Post } from '@nestjs/common';

import { Throttle } from '@nestjs/throttler';

import type { AuthLoginResponse, AuthLogoutResponse, AuthRefreshResponse } from '@crm/contracts';

import { parseHttpSecurityEnvironment } from '@crm/config';

import { loginSchema, refreshTokenSchema } from '@crm/validation';

import { AuthService } from './auth.service.js';

import { SessionService } from './session.service.js';

const security = parseHttpSecurityEnvironment();

@Controller('auth')
export class AuthController {
  constructor(
    @Inject(AuthService)
    private readonly authService: AuthService,

    @Inject(SessionService)
    private readonly sessionService: SessionService,
  ) {}

  @Post('login')
  @Throttle({
    default: {
      limit: security.authLoginRateLimit,

      ttl: security.apiRateLimitTtlMs,
    },
  })
  async login(
    @Body()
    body: unknown,

    @Headers('user-agent')
    userAgent?: string,
  ): Promise<AuthLoginResponse> {
    const parsed = loginSchema.safeParse(body);

    if (!parsed.success) {
      throw new BadRequestException({
        code: 'AUTH_LOGIN_VALIDATION_ERROR',

        message: 'Invalid login payload.',

        issues: parsed.error.issues.map((issue) => ({
          code: issue.code,

          path: issue.path.join('.'),
        })),
      });
    }

    return this.authService.login(parsed.data, {
      userAgent: userAgent?.slice(0, 500) ?? null,
    });
  }

  @Post('refresh')
  @Throttle({
    default: {
      limit: security.authRefreshRateLimit,

      ttl: security.apiRateLimitTtlMs,
    },
  })
  async refresh(
    @Body()
    body: unknown,

    @Headers('user-agent')
    userAgent?: string,
  ): Promise<AuthRefreshResponse> {
    const parsed = refreshTokenSchema.safeParse(body);

    if (!parsed.success) {
      throw new BadRequestException({
        code: 'AUTH_REFRESH_VALIDATION_ERROR',

        message: 'Invalid refresh payload.',

        issues: parsed.error.issues.map((issue) => ({
          code: issue.code,

          path: issue.path.join('.'),
        })),
      });
    }

    return this.sessionService.refresh(parsed.data.refreshToken, {
      userAgent: userAgent?.slice(0, 500) ?? null,
    });
  }

  @Post('logout')
  async logout(
    @Body()
    body: unknown,

    @Headers('user-agent')
    userAgent?: string,
  ): Promise<AuthLogoutResponse> {
    const parsed = refreshTokenSchema.safeParse(body);

    if (!parsed.success) {
      throw new BadRequestException({
        code: 'AUTH_LOGOUT_VALIDATION_ERROR',

        message: 'Invalid logout payload.',

        issues: parsed.error.issues.map((issue) => ({
          code: issue.code,

          path: issue.path.join('.'),
        })),
      });
    }

    return this.sessionService.logout(parsed.data.refreshToken, {
      userAgent: userAgent?.slice(0, 500) ?? null,
    });
  }

  @Post('logout-all')
  async logoutAll(
    @Body()
    body: unknown,

    @Headers('user-agent')
    userAgent?: string,
  ): Promise<AuthLogoutResponse> {
    const parsed = refreshTokenSchema.safeParse(body);

    if (!parsed.success) {
      throw new BadRequestException({
        code: 'AUTH_LOGOUT_ALL_VALIDATION_ERROR',

        message: 'Invalid logout-all payload.',

        issues: parsed.error.issues.map((issue) => ({
          code: issue.code,

          path: issue.path.join('.'),
        })),
      });
    }

    return this.sessionService.logoutAll(parsed.data.refreshToken, {
      userAgent: userAgent?.slice(0, 500) ?? null,
    });
  }
}
