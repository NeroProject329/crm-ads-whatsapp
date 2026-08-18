import { BadRequestException, Body, Controller, Headers, Inject, Post } from '@nestjs/common';
import type { AuthLoginResponse } from '@crm/contracts';
import { loginSchema } from '@crm/validation';

import { AuthService } from './auth.service.js';

@Controller('auth')
export class AuthController {
  constructor(
    @Inject(AuthService)
    private readonly authService: AuthService,
  ) {}

  @Post('login')
  async login(
    @Body() body: unknown,
    @Headers('user-agent') userAgent?: string,
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
}
