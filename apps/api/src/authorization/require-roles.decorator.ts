import { SetMetadata } from '@nestjs/common';

import type { Role } from '@crm/auth';

import { REQUIRED_ROLES_KEY } from './authorization.constants.js';

export function RequireRoles(...roles: readonly Role[]): MethodDecorator & ClassDecorator {
  return SetMetadata(REQUIRED_ROLES_KEY, roles);
}
