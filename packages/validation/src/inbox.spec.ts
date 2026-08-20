import { describe, expect, it } from 'vitest';

import {
  createInboxQuickReplySchema,
  sendInboxMessageSchema,
  updateInboxConversationSchema,
} from './inbox.js';

describe('Stage 9 inbox validation', () => {
  it('accepts a text message', () => {
    expect(
      sendInboxMessageSchema.safeParse({
        clientMessageId: '8eaa25de-f318-47c4-b86b-20735f887e00',

        type: 'TEXT',

        text: 'Ola',
      }).success,
    ).toBe(true);
  });

  it('accepts a template message', () => {
    expect(
      sendInboxMessageSchema.safeParse({
        clientMessageId: '1b024628-7958-46f3-8be1-658ee446b07d',

        type: 'TEMPLATE',

        templateName: 'order_update',

        languageCode: 'pt_BR',
      }).success,
    ).toBe(true);
  });

  it('rejects unknown fields', () => {
    expect(
      sendInboxMessageSchema.safeParse({
        clientMessageId: '8eaa25de-f318-47c4-b86b-20735f887e00',

        type: 'TEXT',

        text: 'Ola',

        organizationId: '24a9b07c-ea64-47b9-b0e3-6c4a550c1733',
      }).success,
    ).toBe(false);
  });

  it('requires an update field', () => {
    expect(updateInboxConversationSchema.safeParse({}).success).toBe(false);
  });

  it('normalizes quick reply shortcut', () => {
    const parsed = createInboxQuickReplySchema.parse({
      title: 'Boas vindas',

      shortcut: '  BOAS_VINDAS  ',

      body: 'Ola!',
    });

    expect(parsed.shortcut).toBe('boas_vindas');
  });
});
