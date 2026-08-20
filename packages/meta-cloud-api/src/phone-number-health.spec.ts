import { describe, expect, it } from 'vitest';

import { MetaCloudApiClient } from './client.js';

import { getMetaPhoneNumberProfile } from './phone-number-profile.js';

import { parseMetaPhoneNumberQualityUpdates } from './phone-number-quality-webhook.js';

describe('Stage 11 Meta phone health', () => {
  it('parses phone_number_quality_update', () => {
    const updates = parseMetaPhoneNumberQualityUpdates({
      object: 'whatsapp_business_account',

      entry: [
        {
          id: '123456',

          changes: [
            {
              field: 'phone_number_quality_update',

              value: {
                display_phone_number: '+55 11 99999-0000',

                event: 'FLAGGED',

                current_limit: 'TIER_1K',
              },
            },
          ],
        },
      ],
    });

    expect(updates).toEqual([
      {
        wabaId: '123456',

        displayPhoneNumber: '+55 11 99999-0000',

        event: 'FLAGGED',

        currentLimit: 'TIER_1K',
      },
    ]);
  });

  it('reads official quality_rating from phone profile', async () => {
    const client = new MetaCloudApiClient(
      {
        graphBaseUrl: 'https://graph.facebook.com',

        graphApiVersion: 'v99.0',

        accessToken: 'stage11-test-token',

        timeoutMs: 5000,
      },

      async (input) => {
        const url = new URL(String(input));

        expect(url.pathname).toContain('/v99.0/123456789');

        expect(url.searchParams.get('fields')).toContain('quality_rating');

        return new Response(
          JSON.stringify({
            id: '123456789',

            verified_name: 'Stage 11',

            display_phone_number: '+5511999990000',

            quality_rating: 'GREEN',
          }),

          {
            status: 200,

            headers: {
              'content-type': 'application/json',
            },
          },
        );
      },
    );

    const profile = await getMetaPhoneNumberProfile(client, '123456789');

    expect(profile.qualityRating).toBe('GREEN');
  });

  it('maps unknown quality ratings safely', async () => {
    const client = new MetaCloudApiClient(
      {
        graphBaseUrl: 'https://graph.facebook.com',

        graphApiVersion: 'v99.0',

        accessToken: 'stage11-test-token',

        timeoutMs: 5000,
      },

      async () =>
        new Response(
          JSON.stringify({
            id: '123456789',

            quality_rating: 'SOMETHING_NEW',
          }),

          {
            status: 200,
          },
        ),
    );

    const profile = await getMetaPhoneNumberProfile(client, '123456789');

    expect(profile.qualityRating).toBe('UNKNOWN');
  });
});
