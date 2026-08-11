import { describe, expect, it } from 'vitest';

import { parseDatabaseEnvironment } from './database.js';

describe('parseDatabaseEnvironment', () => {
  it('applies safe defaults', () => {
    const result = parseDatabaseEnvironment({
      DATABASE_URL: 'postgresql://user:password@localhost:5432/crm',
    });

    expect(result.DATABASE_CONNECTION_TIMEOUT_MS).toBe(5_000);
    expect(result.DATABASE_IDLE_TIMEOUT_MS).toBe(300_000);
    expect(result.DATABASE_MAX_CONNECTIONS).toBe(10);
    expect(result.NODE_ENV).toBe('development');
  });

  it('rejects non-PostgreSQL URLs', () => {
    expect(() =>
      parseDatabaseEnvironment({
        DATABASE_URL: 'mongodb://localhost:27017/crm',
      }),
    ).toThrow();
  });
});
