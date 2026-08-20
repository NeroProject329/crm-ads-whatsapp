import { describe, expect, it } from 'vitest';

import { leadListQuerySchema } from './leads.js';

describe('Stage 10 lead validation', () => {
  it('accepts lead filters', () => {
    const result = leadListQuerySchema.safeParse({
      limit: '50',

      status: 'ATTRIBUTED',

      search: '551199',
    });

    expect(result.success).toBe(true);

    if (result.success) {
      expect(result.data.limit).toBe(50);
    }
  });

  it('rejects unknown fields', () => {
    expect(
      leadListQuerySchema.safeParse({
        organizationId: '0f138502-b180-4eaa-b04b-627362642a83',
      }).success,
    ).toBe(false);
  });

  it('limits page size', () => {
    expect(
      leadListQuerySchema.safeParse({
        limit: 101,
      }).success,
    ).toBe(false);
  });
});
