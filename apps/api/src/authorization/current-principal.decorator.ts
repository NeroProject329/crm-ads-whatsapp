import { createParamDecorator, type ExecutionContext } from '@nestjs/common';

import type { AuthenticatedPrincipal } from '@crm/auth';

import type { AuthenticatedHttpRequest } from './authorization.types.js';

export const CurrentPrincipal = createParamDecorator(
  (_data: unknown, context: ExecutionContext): AuthenticatedPrincipal => {
    const request = context.switchToHttp().getRequest<AuthenticatedHttpRequest>();

    const principal = request.authorization?.principal;

    if (!principal) {
      throw new Error('Authenticated principal is unavailable.');
    }

    return principal;
  },
);
