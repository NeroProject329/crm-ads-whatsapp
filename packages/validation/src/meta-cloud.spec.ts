import { describe, expect, it } from 'vitest';

import { configureWhatsAppMetaSchema } from './meta-cloud.js';

describe('configureWhatsAppMetaSchema', () => {
  it('accepts numeric WABA and Phone Number IDs', () => {
    expect(
      configureWhatsAppMetaSchema.safeParse({
        wabaId: '1234567890',

        phoneNumberId: '9988776655',
      }).success,
    ).toBe(true);
  });

  it('accepts disconnect with both fields null', () => {
    expect(
      configureWhatsAppMetaSchema.safeParse({
        wabaId: null,

        phoneNumberId: null,
      }).success,
    ).toBe(true);
  });

  it('rejects partial connection data', () => {
    expect(
      configureWhatsAppMetaSchema.safeParse({
        wabaId: '1234567890',

        phoneNumberId: null,
      }).success,
    ).toBe(false);
  });

  it('rejects organization injection', () => {
    expect(
      configureWhatsAppMetaSchema.safeParse({
        wabaId: '1234567890',

        phoneNumberId: '9988776655',

        organizationId: '123e4567-e89b-42d3-a456-426614174000',
      }).success,
    ).toBe(false);
  });
});
