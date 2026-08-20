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

export type AuthTokenResponse = Readonly<{
  accessToken: string;

  accessTokenExpiresInSeconds: number;

  refreshToken: string;

  refreshTokenExpiresInSeconds: number;

  sessionId: string;

  tokenType: 'Bearer';

  user: AuthUserResponse;
}>;

export type AuthLoginResponse = AuthTokenResponse;

export type AuthRefreshRequest = Readonly<{
  refreshToken: string;
}>;

export type AuthRefreshResponse = AuthTokenResponse;

export type AuthLogoutRequest = Readonly<{
  refreshToken: string;
}>;

export type AuthLogoutResponse = Readonly<{
  success: true;
}>;

export type SiteStatus = 'ACTIVE' | 'PAUSED' | 'ARCHIVED';

export type SiteDomainStatus = 'ACTIVE' | 'PAUSED' | 'ARCHIVED';

export type SiteOwnerResponse = Readonly<{
  employeeCode: string;
  employeeId: string;
  displayName: string;
  userId: string;
}>;

export type SiteDomainResponse = Readonly<{
  id: string;
  organizationId: string;
  siteId: string;
  hostname: string;
  isPrimary: boolean;
  status: SiteDomainStatus;
  monitoringEnabled: boolean;
  createdAt: string;
  updatedAt: string;
}>;

export type SiteResponse = Readonly<{
  id: string;
  organizationId: string;
  ownerEmployeeId: string;
  name: string;
  slug: string;

  description: string | null;

  status: SiteStatus;

  owner: SiteOwnerResponse;

  domains: readonly SiteDomainResponse[];

  createdAt: string;
  updatedAt: string;
}>;

export type SiteListResponse = readonly SiteResponse[];

export type CreateSiteRequest = Readonly<{
  ownerEmployeeId: string;
  name: string;
  slug: string;

  description?: string | null;
}>;

export type UpdateSiteRequest = Readonly<{
  ownerEmployeeId?: string;
  name?: string;
  slug?: string;

  description?: string | null;

  status?: SiteStatus;
}>;

export type CreateSiteDomainRequest = Readonly<{
  hostname: string;
  isPrimary?: boolean;
  monitoringEnabled?: boolean;
}>;

export type UpdateSiteDomainRequest = Readonly<{
  hostname?: string;
  isPrimary?: boolean;
  monitoringEnabled?: boolean;

  status?: SiteDomainStatus;
}>;

export type WhatsAppNumberStatus = 'ACTIVE' | 'PAUSED' | 'DISABLED' | 'ARCHIVED';

export type WhatsAppNumberAssigneeResponse = Readonly<{
  employeeId: string;
  employeeCode: string;
  userId: string;
  displayName: string;
}>;

export type WhatsAppNumberResponse = Readonly<{
  id: string;
  organizationId: string;

  assignedEmployeeId: string | null;

  displayName: string;
  e164: string;

  status: WhatsAppNumberStatus;

  notes: string | null;
  metaWabaId: string | null;

  metaPhoneNumberId: string | null;

  metaConnectedAt: string | null;

  metaWebhookLastSeenAt: string | null;

  assignedEmployee: WhatsAppNumberAssigneeResponse | null;

  createdAt: string;
  updatedAt: string;
}>;

export type WhatsAppNumberListResponse = readonly WhatsAppNumberResponse[];

export type CreateWhatsAppNumberRequest = Readonly<{
  displayName: string;
  e164: string;

  assignedEmployeeId?: string | null;

  notes?: string | null;
}>;

export type UpdateWhatsAppNumberRequest = Readonly<{
  displayName?: string;
  e164?: string;

  assignedEmployeeId?: string | null;

  notes?: string | null;

  status?: WhatsAppNumberStatus;
}>;

export * from './traffic-pool.js';

export * from './ads.js';
export * from './site-monitoring.js';
export * from './notifications.js';
export * from './meta-cloud.js';
export * from './inbox.js';
export * from './leads.js';
export * from './whatsapp-health.js';
