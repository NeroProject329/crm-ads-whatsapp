import { describe, expect, it } from 'vitest';

import { loginSchema } from './index.js';

describe('loginSchema', () => {
  it('normalizes email and organization slug', () => {
    const result = loginSchema.parse({
      email: 'Admin@Example.com',
      organizationSlug: 'CRM-ADS-WHATSAPP',
      password: 'some-password',
    });

    expect(result.email).toBe('admin@example.com');
    expect(result.organizationSlug).toBe('crm-ads-whatsapp');
  });

  it('rejects malformed organization slugs', () => {
    expect(() =>
      loginSchema.parse({
        email: 'admin@example.com',
        organizationSlug: 'invalid slug',
        password: 'some-password',
      }),
    ).toThrow();
  });
});
