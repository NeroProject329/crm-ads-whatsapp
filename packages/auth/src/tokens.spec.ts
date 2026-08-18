import { describe, expect, it } from 'vitest';

import { issueAccessToken, verifyAccessToken } from './tokens.js';

const configuration = {
  audience: 'crm-web',
  issuer: 'crm-api',
  secret: 's'.repeat(48),
  ttlSeconds: 900,
} as const;

describe('access tokens', () => {
  it('issues and verifies an access token', async () => {
    const token = await issueAccessToken(
      {
        organizationId: 'org-1',
        roles: ['ADMIN'],
        sessionId: 'session-1',
        userId: 'user-1',
      },
      configuration,
    );

    await expect(verifyAccessToken(token, configuration)).resolves.toEqual({
      organizationId: 'org-1',
      roles: ['ADMIN'],
      sessionId: 'session-1',
      userId: 'user-1',
    });
  });

  it('rejects tokens signed with a different secret', async () => {
    const token = await issueAccessToken(
      {
        organizationId: 'org-1',
        roles: ['ADMIN'],
        sessionId: 'session-1',
        userId: 'user-1',
      },
      configuration,
    );

    await expect(
      verifyAccessToken(token, {
        ...configuration,
        secret: 'x'.repeat(48),
      }),
    ).rejects.toThrow();
  });
});
