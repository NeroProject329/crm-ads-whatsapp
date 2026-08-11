import { describe, expect, it } from 'vitest';

import { createHealthPayload } from './index.js';

describe('createHealthPayload', () => {
  it('cria um payload saudável e identificável', () => {
    const payload = createHealthPayload('contracts-test', '0.1.0');

    expect(payload.service).toBe('contracts-test');
    expect(payload.status).toBe('ok');
    expect(payload.version).toBe('0.1.0');
    expect(Number.isNaN(Date.parse(payload.timestamp))).toBe(false);
  });
});
