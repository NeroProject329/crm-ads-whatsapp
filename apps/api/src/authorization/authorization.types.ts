import type { AuthenticatedPrincipal, Role } from '@crm/auth';

export type PermissionCode =
  | 'organization.read'
  | 'organization.manage'
  | 'team.read'
  | 'team.manage'
  | 'user.read'
  | 'user.manage'
  | 'employee.read'
  | 'employee.manage'
  | 'audit.read'
  | 'profile.read'
  | 'profile.update';

export type AuthorizationContext = Readonly<{
  permissions: readonly PermissionCode[];
  principal: AuthenticatedPrincipal;
  roles: readonly Role[];
}>;

export type AuthenticatedHttpRequest = {
  headers: Readonly<Record<string, string | string[] | undefined>>;

  authorization?: AuthorizationContext;
};
