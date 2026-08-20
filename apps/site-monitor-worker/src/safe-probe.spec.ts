import { describe, expect, it } from 'vitest';

import { isPublicIpAddress } from './safe-probe.js';

describe('isPublicIpAddress', () => {
  it('allows public IPv4 addresses', () => {
    expect(isPublicIpAddress('8.8.8.8')).toBe(true);

    expect(isPublicIpAddress('1.1.1.1')).toBe(true);
  });

  it('blocks private IPv4 addresses', () => {
    expect(isPublicIpAddress('10.0.0.1')).toBe(false);

    expect(isPublicIpAddress('192.168.1.10')).toBe(false);

    expect(isPublicIpAddress('172.16.0.1')).toBe(false);
  });

  it('blocks loopback and link-local addresses', () => {
    expect(isPublicIpAddress('127.0.0.1')).toBe(false);

    expect(isPublicIpAddress('169.254.169.254')).toBe(false);

    expect(isPublicIpAddress('::1')).toBe(false);
  });

  it('blocks documentation ranges', () => {
    expect(isPublicIpAddress('192.0.2.1')).toBe(false);

    expect(isPublicIpAddress('198.51.100.1')).toBe(false);

    expect(isPublicIpAddress('203.0.113.1')).toBe(false);
  });
});
