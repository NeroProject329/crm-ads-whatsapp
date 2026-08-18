import { jwtVerify, SignJWT } from 'jose';

import type { Role } from './index.js';

export type AccessTokenConfiguration = Readonly<{
  audience: string;
  issuer: string;
  secret: string;
  ttlSeconds: number;
}>;

export type AccessTokenPrincipal = Readonly<{
  organizationId: string;
  roles: readonly Role[];
  sessionId: string;
  userId: string;
}>;

export type VerifiedAccessToken = Readonly<{
  organizationId: string;
  roles: readonly Role[];
  sessionId: string;
  userId: string;
}>;

function secretKey(secret: string): Uint8Array {
  return new TextEncoder().encode(secret);
}

export async function issueAccessToken(
  principal: AccessTokenPrincipal,
  configuration: AccessTokenConfiguration,
): Promise<string> {
  const nowSeconds = Math.floor(Date.now() / 1000);

  return new SignJWT({
    org: principal.organizationId,
    roles: [...principal.roles],
    sid: principal.sessionId,
  })
    .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
    .setAudience(configuration.audience)
    .setIssuer(configuration.issuer)
    .setSubject(principal.userId)
    .setIssuedAt(nowSeconds)
    .setExpirationTime(nowSeconds + configuration.ttlSeconds)
    .sign(secretKey(configuration.secret));
}

export async function verifyAccessToken(
  token: string,
  configuration: AccessTokenConfiguration,
): Promise<VerifiedAccessToken> {
  const result = await jwtVerify(token, secretKey(configuration.secret), {
    algorithms: ['HS256'],
    audience: configuration.audience,
    issuer: configuration.issuer,
  });

  const organizationId = result.payload.org;
  const sessionId = result.payload.sid;
  const roles = result.payload.roles;
  const userId = result.payload.sub;

  if (
    typeof organizationId !== 'string' ||
    typeof sessionId !== 'string' ||
    typeof userId !== 'string' ||
    !Array.isArray(roles) ||
    roles.some((role) => typeof role !== 'string' || !isRole(role))
  ) {
    throw new Error('Invalid access token claims.');
  }

  return {
    organizationId,
    roles,
    sessionId,
    userId,
  };
}

function isRole(value: string): value is Role {
  return value === 'ADMIN' || value === 'EMPLOYEE';
}
