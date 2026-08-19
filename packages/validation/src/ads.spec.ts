import { describe, expect, it } from 'vitest';

import { createAdsRequestSchema } from './ads.js';

const siteId = '11111111-1111-4111-8111-111111111111';

const trafficPoolId = '22222222-2222-4222-8222-222222222222';

describe('ADS request validation', () => {
  it('accepts a valid request', () => {
    const result = createAdsRequestSchema.safeParse({
      siteId,
      trafficPoolId,
      requestedLeadCount: 100,
      notes: 'Campanha principal',
    });

    expect(result.success).toBe(true);
  });

  it.each([0, -1, 100_001, 1.5])('rejects invalid requestedLeadCount %s', (requestedLeadCount) => {
    const result = createAdsRequestSchema.safeParse({
      siteId,
      trafficPoolId,
      requestedLeadCount,
    });

    expect(result.success).toBe(false);
  });

  it('rejects tenant injection', () => {
    const result = createAdsRequestSchema.safeParse({
      siteId,
      trafficPoolId,
      requestedLeadCount: 100,
      organizationId: '33333333-3333-4333-8333-333333333333',
    });

    expect(result.success).toBe(false);
  });
});
