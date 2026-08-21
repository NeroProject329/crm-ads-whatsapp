import { cookies } from 'next/headers';

import type { AuthIdentity, AuthPrincipal, AuthTokenResponse, AuthUser } from './types';
import { isAuthPrincipal } from './types';

const ACCESS_COOKIE = 'crm_access_token';
const REFRESH_COOKIE = 'crm_refresh_token';
const IDENTITY_COOKIE = 'crm_identity';

const productionLike =
  process.env.APP_ENV === 'staging' || process.env.APP_ENV === 'production';

function apiBaseUrl(): string {
  const configured = process.env.CRM_API_BASE_URL?.trim();

  if (configured) {
    return configured.replace(/\/+$/, '');
  }

  if (productionLike) {
    throw new Error('CRM_API_BASE_URL is required in staging and production.');
  }

  return 'http://localhost:3001/api/v1';
}

function cookieOptions(maxAge: number) {
  return {
    httpOnly: true,
    secure: productionLike,
    sameSite: 'lax' as const,
    path: '/',
    maxAge,
  };
}

function encodeIdentity(identity: AuthIdentity): string {
  return Buffer.from(JSON.stringify(identity), 'utf8').toString('base64url');
}

function decodeIdentity(value: string | undefined): AuthIdentity | null {
  if (!value) {
    return null;
  }

  try {
    const parsed = JSON.parse(Buffer.from(value, 'base64url').toString('utf8')) as unknown;

    if (!parsed || typeof parsed !== 'object') {
      return null;
    }

    const candidate = parsed as Record<string, unknown>;

    if (typeof candidate.displayName !== 'string' || typeof candidate.email !== 'string') {
      return null;
    }

    return {
      displayName: candidate.displayName,
      email: candidate.email,
    };
  } catch {
    return null;
  }
}

export async function setAuthCookies(tokens: AuthTokenResponse): Promise<void> {
  const store = await cookies();

  store.set(ACCESS_COOKIE, tokens.accessToken, cookieOptions(tokens.accessTokenExpiresInSeconds));
  store.set(REFRESH_COOKIE, tokens.refreshToken, cookieOptions(tokens.refreshTokenExpiresInSeconds));
  store.set(
    IDENTITY_COOKIE,
    encodeIdentity({
      displayName: tokens.user.displayName,
      email: tokens.user.email,
    }),
    cookieOptions(tokens.refreshTokenExpiresInSeconds),
  );
}

export async function clearAuthCookies(): Promise<void> {
  const store = await cookies();

  for (const name of [ACCESS_COOKIE, REFRESH_COOKIE, IDENTITY_COOKIE]) {
    store.set(name, '', {
      ...cookieOptions(0),
      expires: new Date(0),
    });
  }
}

async function backendRequest(path: string, init: RequestInit): Promise<Response> {
  const headers = new Headers(init.headers);
  headers.set('Accept', 'application/json');

  if (init.body !== undefined && !headers.has('Content-Type')) {
    headers.set('Content-Type', 'application/json');
  }

  return fetch(`${apiBaseUrl()}${path}`, {
    ...init,
    cache: 'no-store',
    headers,
  });
}

async function readPrincipal(accessToken: string): Promise<AuthPrincipal | null> {
  const response = await backendRequest('/auth/me', {
    method: 'GET',
    headers: {
      Authorization: `Bearer ${accessToken}`,
    },
  });

  if (!response.ok) {
    return null;
  }

  const payload = (await response.json()) as unknown;
  return isAuthPrincipal(payload) ? payload : null;
}

async function refreshSession(refreshToken: string): Promise<AuthTokenResponse | null> {
  const response = await backendRequest('/auth/refresh', {
    method: 'POST',
    body: JSON.stringify({ refreshToken }),
  });

  if (!response.ok) {
    return null;
  }

  return (await response.json()) as AuthTokenResponse;
}

export async function getRefreshToken(): Promise<string | null> {
  const store = await cookies();
  return store.get(REFRESH_COOKIE)?.value ?? null;
}

export async function hasSessionCookie(): Promise<boolean> {
  const store = await cookies();
  return Boolean(store.get(REFRESH_COOKIE)?.value || store.get(ACCESS_COOKIE)?.value);
}

export async function resolveSession(): Promise<AuthUser | null> {
  const store = await cookies();
  const identity = decodeIdentity(store.get(IDENTITY_COOKIE)?.value);
  const accessToken = store.get(ACCESS_COOKIE)?.value;
  const refreshToken = store.get(REFRESH_COOKIE)?.value;

  if (accessToken) {
    const principal = await readPrincipal(accessToken);

    if (principal && identity) {
      return { ...principal, ...identity };
    }
  }

  if (!refreshToken) {
    return null;
  }

  const refreshed = await refreshSession(refreshToken);

  if (!refreshed) {
    await clearAuthCookies();
    return null;
  }

  await setAuthCookies(refreshed);

  return {
    organizationId: refreshed.user.organizationId,
    roles: refreshed.user.roles,
    sessionId: refreshed.sessionId,
    userId: refreshed.user.userId,
    displayName: refreshed.user.displayName,
    email: refreshed.user.email,
  };
}

export async function loginWithPassword(input: Readonly<{
  email: string;
  organizationSlug: string;
  password: string;
}>): Promise<Response> {
  return backendRequest('/auth/login', {
    method: 'POST',
    body: JSON.stringify(input),
  });
}

export async function logoutCurrentSession(): Promise<void> {
  const refreshToken = await getRefreshToken();

  if (refreshToken) {
    await backendRequest('/auth/logout', {
      method: 'POST',
      body: JSON.stringify({ refreshToken }),
    }).catch(() => undefined);
  }

  await clearAuthCookies();
}
