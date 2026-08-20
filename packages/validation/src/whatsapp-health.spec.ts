import { describe, expect, it } from 'vitest';

import { whatsAppHealthHistoryQuerySchema } from './whatsapp-health.js';

describe('Stage 11 WhatsApp health validation', () => {
  it('accepts a valid history limit', () => {
    const result = whatsAppHealthHistoryQuerySchema.safeParse({
      limit: '100',
    });

    expect(result.success).toBe(true);

    if (result.success) {
      expect(result.data.limit).toBe(100);
    }
  });

  it('rejects excessive limits', () => {
    expect(
      whatsAppHealthHistoryQuerySchema.safeParse({
        limit: 201,
      }).success,
    ).toBe(false);
  });

  it('rejects unknown query fields', () => {
    expect(
      whatsAppHealthHistoryQuerySchema.safeParse({
        organizationId: 'foreign',
      }).success,
    ).toBe(false);
  });
});
