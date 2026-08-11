import { describe, expect, it, vi } from 'vitest';

import { checkDatabaseConnection } from './health.js';

describe('checkDatabaseConnection', () => {
  it('returns true when SELECT 1 succeeds', async () => {
    const client = {
      $queryRaw: vi.fn().mockResolvedValue([{ value: 1 }]),
    };

    await expect(checkDatabaseConnection(client as never)).resolves.toBe(true);
  });
});
