export const roles = ['ADMIN', 'EMPLOYEE'] as const;

export type Role = (typeof roles)[number];

export type AuthenticatedPrincipal = Readonly<{
  organizationId: string;
  roles: readonly Role[];
  sessionId: string;
  userId: string;
}>;

export function isRole(value: string): value is Role {
  return roles.includes(value as Role);
}

export {
  issueAccessToken,
  verifyAccessToken,
  type AccessTokenConfiguration,
  type AccessTokenPrincipal,
  type VerifiedAccessToken,
} from './tokens.js';
