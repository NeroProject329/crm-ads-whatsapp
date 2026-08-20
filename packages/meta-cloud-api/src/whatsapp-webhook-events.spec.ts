import { describe, expect, it } from 'vitest';

import { parseWhatsAppWebhookEvents } from './whatsapp-webhook-events.js';

describe('parseWhatsAppWebhookEvents', () => {
  it('extracts inbound messages', () => {
    const events = parseWhatsAppWebhookEvents({
      object: 'whatsapp_business_account',

      entry: [
        {
          id: '123456789',

          changes: [
            {
              field: 'messages',

              value: {
                metadata: {
                  phone_number_id: '987654321',
                },

                contacts: [
                  {
                    wa_id: '5511999999999',

                    profile: {
                      name: 'Cliente Stage 9',
                    },
                  },
                ],

                messages: [
                  {
                    id: 'wamid.stage9.parser.inbound',

                    from: '5511999999999',

                    timestamp: '1700000000',

                    type: 'text',

                    text: {
                      body: 'Ola',
                    },
                  },
                ],
              },
            },
          ],
        },
      ],
    });

    expect(events).toHaveLength(1);

    expect(events[0]).toMatchObject({
      kind: 'MESSAGE',

      messageId: 'wamid.stage9.parser.inbound',

      from: '5511999999999',

      messageType: 'text',

      textBody: 'Ola',

      profileName: 'Cliente Stage 9',

      phoneNumberId: '987654321',

      wabaId: '123456789',
    });
  });

  it('extracts delivery statuses', () => {
    const events = parseWhatsAppWebhookEvents({
      entry: [
        {
          id: '123456789',

          changes: [
            {
              field: 'messages',

              value: {
                metadata: {
                  phone_number_id: '987654321',
                },

                statuses: [
                  {
                    id: 'wamid.stage9.parser.outbound',

                    recipient_id: '5511999999999',

                    status: 'delivered',

                    timestamp: '1700000001',
                  },
                ],
              },
            },
          ],
        },
      ],
    });

    expect(events).toHaveLength(1);

    expect(events[0]).toMatchObject({
      kind: 'STATUS',

      messageId: 'wamid.stage9.parser.outbound',

      status: 'delivered',

      recipientId: '5511999999999',
    });
  });

  it('ignores malformed events safely', () => {
    expect(parseWhatsAppWebhookEvents(null)).toEqual([]);

    expect(
      parseWhatsAppWebhookEvents({
        entry: [null, {}],
      }),
    ).toEqual([]);
  });
});
