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
  | 'profile.update'
  | 'site.read'
  | 'site.manage'
  | 'domain.read'
  | 'domain.manage'
  | 'whatsapp_number.read'
  | 'whatsapp_number.manage'
  | 'traffic_pool.read'
  | 'traffic_pool.manage'
  | 'ads_request.read'
  | 'ads_request.manage'
  | 'ads_queue.read'
  | 'ads_queue.manage';

export type AuthorizationContext = Readonly<{
  permissions: readonly PermissionCode[];

  principal: AuthenticatedPrincipal;

  roles: readonly Role[];
}>;

export type AuthenticatedHttpRequest = {
  headers: Readonly<Record<string, string | string[] | undefined>>;

  authorization?: AuthorizationContext;
};
