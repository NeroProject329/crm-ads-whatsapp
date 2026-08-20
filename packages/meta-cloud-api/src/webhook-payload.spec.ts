import { describe, expect, it } from 'vitest';

import { extractMetaWebhookSummary } from './webhook-payload.js';

describe('extractMetaWebhookSummary', () => {
  it('extracts WABA, field and phone number metadata', () => {
    expect(
      extractMetaWebhookSummary({
        object: 'whatsapp_business_account',

        entry: [
          {
            id: '123456789',

            changes: [
              {
                field: 'messages',

                value: {
                  metadata: {
                    phone_number_id: '9988776655',
                  },
                },
              },
            ],
          },
        ],
      }),
    ).toEqual({
      object: 'whatsapp_business_account',

      wabaId: '123456789',

      field: 'messages',

      phoneNumberId: '9988776655',
    });
  });

  it('returns nullable metadata for unknown payloads', () => {
    expect(extractMetaWebhookSummary({})).toEqual({
      object: null,
      wabaId: null,
      field: null,
      phoneNumberId: null,
    });
  });
});
