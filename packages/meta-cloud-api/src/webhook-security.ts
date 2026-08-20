import { createHmac, timingSafeEqual } from 'node:crypto';

function safeEqual(left: string, right: string): boolean {
  const leftBuffer = Buffer.from(left, 'utf8');

  const rightBuffer = Buffer.from(right, 'utf8');

  if (leftBuffer.length !== rightBuffer.length) {
    return false;
  }

  return timingSafeEqual(leftBuffer, rightBuffer);
}

export function verifyMetaWebhookChallenge(
  input: Readonly<{
    mode: string | undefined;
    providedToken: string | undefined;
    challenge: string | undefined;
    expectedToken: string;
  }>,
): string | null {
  if (input.mode !== 'subscribe') {
    return null;
  }

  if (!input.providedToken || !safeEqual(input.providedToken, input.expectedToken)) {
    return null;
  }

  if (input.challenge === undefined) {
    return null;
  }

  return input.challenge;
}

export function verifyMetaWebhookSignature(
  appSecret: string,
  rawBody: Buffer,
  signatureHeader: string | undefined,
): boolean {
  if (!signatureHeader || !signatureHeader.startsWith('sha256=')) {
    return false;
  }

  const received = signatureHeader.slice('sha256='.length);

  if (!/^[a-fA-F0-9]{64}$/.test(received)) {
    return false;
  }

  const expected = createHmac('sha256', appSecret).update(rawBody).digest('hex');

  return safeEqual(received.toLowerCase(), expected);
}
