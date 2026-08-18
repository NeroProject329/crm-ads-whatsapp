import { SetMetadata } from '@nestjs/common';

import { REQUIRED_PERMISSIONS_KEY } from './authorization.constants.js';
import type { PermissionCode } from './authorization.types.js';

export function RequirePermissions(
  ...permissions: readonly PermissionCode[]
): MethodDecorator & ClassDecorator {
  return SetMetadata(REQUIRED_PERMISSIONS_KEY, permissions);
}
