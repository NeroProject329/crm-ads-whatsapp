import { describe, expect, it } from 'vitest';

import { registerPushDeviceSchema, updateNotificationPreferenceSchema } from './notifications.js';

describe('registerPushDeviceSchema', () => {
  it('accepts a valid OneSignal subscription', () => {
    const parsed = registerPushDeviceSchema.safeParse({
      subscriptionId: '123e4567-e89b-42d3-a456-426614174000',

      oneSignalId: '123e4567-e89b-42d3-a456-426614174001',

      optedIn: true,

      platform: 'iPhone',

      browser: 'Safari',
    });

    expect(parsed.success).toBe(true);
  });

  it('rejects unknown properties', () => {
    const parsed = registerPushDeviceSchema.safeParse({
      subscriptionId: '123e4567-e89b-42d3-a456-426614174000',

      optedIn: true,

      organizationId: '123e4567-e89b-42d3-a456-426614174099',
    });

    expect(parsed.success).toBe(false);
  });
});

describe('updateNotificationPreferenceSchema', () => {
  it('accepts explicit false values', () => {
    const parsed = updateNotificationPreferenceSchema.safeParse({
      pushEnabled: false,

      siteMonitoring: false,
    });

    expect(parsed.success).toBe(true);
  });

  it('rejects an empty update', () => {
    const parsed = updateNotificationPreferenceSchema.safeParse({});

    expect(parsed.success).toBe(false);
  });
});
