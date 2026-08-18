import { describe, expect, it } from 'vitest';

import { parseAuthEnvironment } from './auth.js';

describe('parseAuthEnvironment', () => {
  it('parses explicit auth configuration', () => {
    const environment = parseAuthEnvironment({
      AUTH_ACCESS_TOKEN_AUDIENCE: 'crm-web',
      AUTH_ACCESS_TOKEN_ISSUER: 'crm-api',
      AUTH_ACCESS_TOKEN_SECRET: 'a'.repeat(48),
      AUTH_ACCESS_TOKEN_TTL_SECONDS: '900',
      AUTH_LOGIN_LOCK_SECONDS: '900',
      AUTH_MAX_FAILED_LOGIN_ATTEMPTS: '5',
      AUTH_REFRESH_TOKEN_PEPPER: 'b'.repeat(48),
      AUTH_REFRESH_TOKEN_TTL_SECONDS: '2592000',
    });

    expect(environment.AUTH_ACCESS_TOKEN_AUDIENCE).toBe('crm-web');
    expect(environment.AUTH_ACCESS_TOKEN_TTL_SECONDS).toBe(900);
    expect(environment.AUTH_MAX_FAILED_LOGIN_ATTEMPTS).toBe(5);
  });

  it('rejects short secrets', () => {
    expect(() =>
      parseAuthEnvironment({
        AUTH_ACCESS_TOKEN_SECRET: 'short',
        AUTH_REFRESH_TOKEN_PEPPER: 'also-short',
      }),
    ).toThrow();
  });
});
