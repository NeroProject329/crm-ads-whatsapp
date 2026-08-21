export type UserRole = 'ADMIN' | 'EMPLOYEE';

export type AuthIdentity = Readonly<{
  displayName: string;
  email: string;
}>;

export type AuthPrincipal = Readonly<{
  organizationId: string;
  roles: readonly UserRole[];
  sessionId: string;
  userId: string;
}>;

export type AuthUser = AuthIdentity & AuthPrincipal;

export type AuthTokenResponse = Readonly<{
  accessToken: string;
  accessTokenExpiresInSeconds: number;
  refreshToken: string;
  refreshTokenExpiresInSeconds: number;
  sessionId: string;
  tokenType: 'Bearer';
  user: Readonly<{
    displayName: string;
    email: string;
    organizationId: string;
    roles: readonly UserRole[];
    userId: string;
  }>;
}>;

export type ApiErrorPayload = Readonly<{
  code?: string;
  message?: string;
}>;

export function isUserRole(value: unknown): value is UserRole {
  return value === 'ADMIN' || value === 'EMPLOYEE';
}

export function isAuthPrincipal(value: unknown): value is AuthPrincipal {
  if (!value || typeof value !== 'object') {
    return false;
  }

  const candidate = value as Record<string, unknown>;

  return (
    typeof candidate.organizationId === 'string' &&
    typeof candidate.sessionId === 'string' &&
    typeof candidate.userId === 'string' &&
    Array.isArray(candidate.roles) &&
    candidate.roles.every(isUserRole)
  );
}
