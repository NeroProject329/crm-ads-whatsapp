import { z } from 'zod';

const uuidSchema = z.string().uuid();

const conversationStatusSchema = z.enum(['OPEN', 'CLOSED', 'ARCHIVED']);

export const inboxConversationListQuerySchema = z
  .object({
    cursor: uuidSchema.optional(),

    limit: z.coerce.number().int().min(1).max(100).default(30),

    status: conversationStatusSchema.optional(),

    whatsAppNumberId: uuidSchema.optional(),

    search: z.string().trim().min(1).max(120).optional(),
  })
  .strict();

export const inboxMessageListQuerySchema = z
  .object({
    cursor: uuidSchema.optional(),

    limit: z.coerce.number().int().min(1).max(100).default(50),
  })
  .strict();

const clientMessageIdSchema = uuidSchema;

const replyToMetaMessageIdSchema = z.string().trim().min(1).max(255).nullable().optional();

const sendTextMessageSchema = z
  .object({
    clientMessageId: clientMessageIdSchema,

    type: z.literal('TEXT'),

    text: z.string().trim().min(1).max(4096),

    replyToMetaMessageId: replyToMetaMessageIdSchema,
  })
  .strict();

const sendTemplateMessageSchema = z
  .object({
    clientMessageId: clientMessageIdSchema,

    type: z.literal('TEMPLATE'),

    templateName: z.string().trim().min(1).max(512),

    languageCode: z.string().trim().min(2).max(20),

    components: z.array(z.unknown()).max(50).optional(),
  })
  .strict();

export const sendInboxMessageSchema = z.discriminatedUnion('type', [
  sendTextMessageSchema,
  sendTemplateMessageSchema,
]);

export const updateInboxConversationSchema = z
  .object({
    status: conversationStatusSchema.optional(),

    assignedEmployeeId: uuidSchema.nullable().optional(),
  })
  .strict()
  .refine((value) => Object.keys(value).length > 0, {
    message: 'At least one conversation field must be provided.',
  });

const quickReplyTitleSchema = z.string().trim().min(1).max(120);

const quickReplyShortcutSchema = z
  .string()
  .trim()
  .toLowerCase()
  .min(1)
  .max(80)
  .regex(/^[a-z0-9_-]+$/);

const quickReplyBodySchema = z.string().trim().min(1).max(4096);

export const createInboxQuickReplySchema = z
  .object({
    title: quickReplyTitleSchema,

    shortcut: quickReplyShortcutSchema,

    body: quickReplyBodySchema,
  })
  .strict();

export const updateInboxQuickReplySchema = z
  .object({
    title: quickReplyTitleSchema.optional(),

    shortcut: quickReplyShortcutSchema.optional(),

    body: quickReplyBodySchema.optional(),
  })
  .strict()
  .refine((value) => Object.keys(value).length > 0, {
    message: 'At least one quick reply field must be provided.',
  });

export type InboxConversationListQuery = z.infer<typeof inboxConversationListQuerySchema>;

export type InboxMessageListQuery = z.infer<typeof inboxMessageListQuerySchema>;

export type SendInboxMessageInput = z.infer<typeof sendInboxMessageSchema>;

export type UpdateInboxConversationInput = z.infer<typeof updateInboxConversationSchema>;

export type CreateInboxQuickReplyInput = z.infer<typeof createInboxQuickReplySchema>;

export type UpdateInboxQuickReplyInput = z.infer<typeof updateInboxQuickReplySchema>;
