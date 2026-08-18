import type { Role } from '@crm/auth';

export type SessionRequestContext = Readonly<{
  userAgent: string | null;
}>;

export type RefreshPrincipal = Readonly<{
  displayName: string;
  email: string;
  organizationId: string;
  roles: readonly Role[];
  sessionId: string;
  userId: string;
}>;

export type RefreshSuccess = Readonly<{
  kind: 'success';
  principal: RefreshPrincipal;
  refreshExpiresAt: Date;
  refreshToken: string;
}>;

export type RefreshReuseDetected = Readonly<{
  kind: 'reuse-detected';
}>;

export type RefreshRejected = Readonly<{
  kind: 'rejected';
}>;

export type RefreshTransactionResult = RefreshSuccess | RefreshReuseDetected | RefreshRejected;
