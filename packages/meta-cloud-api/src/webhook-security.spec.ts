import { createHmac } from 'node:crypto';

import { describe, expect, it } from 'vitest';

import { verifyMetaWebhookChallenge, verifyMetaWebhookSignature } from './webhook-security.js';

describe('verifyMetaWebhookChallenge', () => {
  it('accepts the expected verification token', () => {
    expect(
      verifyMetaWebhookChallenge({
        mode: 'subscribe',

        providedToken: 'expected-token',

        expectedToken: 'expected-token',

        challenge: '123456',
      }),
    ).toBe('123456');
  });

  it('rejects a wrong verification token', () => {
    expect(
      verifyMetaWebhookChallenge({
        mode: 'subscribe',

        providedToken: 'wrong',

        expectedToken: 'expected-token',

        challenge: '123456',
      }),
    ).toBeNull();
  });
});

describe('verifyMetaWebhookSignature', () => {
  it('validates HMAC SHA-256 over the raw request body', () => {
    const secret = 'stage8-secret';

    const rawBody = Buffer.from('{"object":"whatsapp_business_account"}');

    const digest = createHmac('sha256', secret).update(rawBody).digest('hex');

    expect(verifyMetaWebhookSignature(secret, rawBody, `sha256=${digest}`)).toBe(true);

    expect(verifyMetaWebhookSignature(secret, rawBody, `sha256=${'0'.repeat(64)}`)).toBe(false);
  });
});
