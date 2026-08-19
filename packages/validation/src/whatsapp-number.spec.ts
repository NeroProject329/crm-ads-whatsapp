import { describe, expect, it } from 'vitest';

import { createWhatsAppNumberSchema, normalizeWhatsAppPhone } from './index.js';

describe('WhatsApp phone normalization', () => {
  it.each([
    ['11973946730', '+5511973946730'],

    ['5511973946730', '+5511973946730'],

    ['+5511973946730', '+5511973946730'],

    ['+55 11 97394-6730', '+5511973946730'],

    ['(11) 97394-6730', '+5511973946730'],

    ['11 97394-6730', '+5511973946730'],

    ['011973946730', '+5511973946730'],

    ['005511973946730', '+5511973946730'],

    ['1132345678', '+551132345678'],
  ])('normalizes %s to %s', (input, expected) => {
    expect(normalizeWhatsAppPhone(input)).toBe(expected);
  });

  it('preserves international E.164 numbers', () => {
    expect(normalizeWhatsAppPhone('+14155552671')).toBe('+14155552671');
  });

  it('normalizes the value inside the create schema', () => {
    const result = createWhatsAppNumberSchema.parse({
      displayName: 'WhatsApp Teste',

      e164: '(11) 97394-6730',
    });

    expect(result.e164).toBe('+5511973946730');
  });

  it.each(['', '123', 'telefone', '000000'])('rejects invalid value %s', (input) => {
    const result = createWhatsAppNumberSchema.safeParse({
      displayName: 'WhatsApp Teste',

      e164: input,
    });

    expect(result.success).toBe(false);
  });
});
