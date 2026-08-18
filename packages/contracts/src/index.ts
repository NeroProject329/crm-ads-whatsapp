export type HealthStatus = 'ok' | 'degraded' | 'error';

export type HealthPayload = Readonly<{
  service: string;
  status: HealthStatus;
  timestamp: string;
  version: string;
}>;

export function createHealthPayload(service: string, version: string): HealthPayload {
  return {
    service,
    status: 'ok',
    timestamp: new Date().toISOString(),
    version,
  };
}

export type AuthLoginRequest = Readonly<{
  email: string;
  organizationSlug: string;
  password: string;
}>;

export type AuthUserResponse = Readonly<{
  displayName: string;
  email: string;
  organizationId: string;
  roles: readonly ('ADMIN' | 'EMPLOYEE')[];
  userId: string;
}>;

export type AuthLoginResponse = Readonly<{
  accessToken: string;
  accessTokenExpiresInSeconds: number;
  refreshToken: string;
  refreshTokenExpiresInSeconds: number;
  sessionId: string;
  tokenType: 'Bearer';
  user: AuthUserResponse;
}>;
