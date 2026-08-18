import { describe, expect, it } from 'vitest';

import { createOpaqueToken, hashOpaqueToken, hashPassword, verifyPassword } from './password.js';

describe('password security', () => {
  it('hashes and verifies a password', async () => {
    const hash = await hashPassword('A-valid-password-123');

    expect(hash.startsWith('scrypt$1$')).toBe(true);
    await expect(verifyPassword('A-valid-password-123', hash)).resolves.toBe(true);
    await expect(verifyPassword('wrong-password-123', hash)).resolves.toBe(false);
  });

  it('rejects malformed hashes', async () => {
    await expect(verifyPassword('A-valid-password-123', 'invalid')).resolves.toBe(false);
  });

  it('creates opaque tokens and hashes them with a pepper', () => {
    const token = createOpaqueToken();
    const pepper = 'p'.repeat(48);

    expect(token.length).toBeGreaterThan(40);
    expect(hashOpaqueToken(token, pepper)).toBe(hashOpaqueToken(token, pepper));
    expect(hashOpaqueToken(`${token}x`, pepper)).not.toBe(hashOpaqueToken(token, pepper));
  });
});
