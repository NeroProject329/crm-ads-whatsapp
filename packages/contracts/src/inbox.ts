export type WhatsAppConversationStatus = 'OPEN' | 'CLOSED' | 'ARCHIVED';

export type WhatsAppMessageDirection = 'INBOUND' | 'OUTBOUND';

export type WhatsAppMessageType =
  | 'TEXT'
  | 'TEMPLATE'
  | 'IMAGE'
  | 'AUDIO'
  | 'VIDEO'
  | 'DOCUMENT'
  | 'STICKER'
  | 'LOCATION'
  | 'CONTACTS'
  | 'INTERACTIVE'
  | 'REACTION'
  | 'UNKNOWN';

export type WhatsAppMessageStatus =
  'RECEIVED' | 'QUEUED' | 'SENDING' | 'SENT' | 'DELIVERED' | 'READ' | 'FAILED' | 'DELETED';

export type InboxContactResponse = Readonly<{
  id: string;
  waId: string;
  profileName: string | null;
}>;

export type InboxNumberResponse = Readonly<{
  id: string;
  displayName: string;
  e164: string;
}>;

export type InboxAssigneeResponse = Readonly<{
  employeeId: string;
  employeeCode: string;
  userId: string;
  displayName: string;
}>;

export type InboxMessageResponse = Readonly<{
  id: string;
  organizationId: string;
  conversationId: string;
  whatsAppNumberId: string;
  contactId: string;

  direction: WhatsAppMessageDirection;
  type: WhatsAppMessageType;
  status: WhatsAppMessageStatus;

  metaMessageId: string | null;
  clientMessageId: string | null;
  replyToMetaMessageId: string | null;

  textBody: string | null;
  content: unknown;

  providerTimestamp: string | null;

  errorCode: string | null;
  errorMessage: string | null;

  queuedAt: string | null;
  sentAt: string | null;
  deliveredAt: string | null;
  readAt: string | null;
  failedAt: string | null;

  createdAt: string;
  updatedAt: string;
}>;

export type InboxConversationResponse = Readonly<{
  id: string;
  organizationId: string;

  status: WhatsAppConversationStatus;

  contact: InboxContactResponse;
  whatsAppNumber: InboxNumberResponse;
  assignedEmployee: InboxAssigneeResponse | null;

  customerServiceWindowExpiresAt: string | null;
  isCustomerServiceWindowOpen: boolean;

  lastMessageAt: string | null;
  lastInboundAt: string | null;
  lastOutboundAt: string | null;

  unreadCount: number;

  lastMessage: InboxMessageResponse | null;

  createdAt: string;
  updatedAt: string;
}>;

export type InboxConversationListResponse = Readonly<{
  items: readonly InboxConversationResponse[];
  nextCursor: string | null;
}>;

export type InboxMessageListResponse = Readonly<{
  items: readonly InboxMessageResponse[];
  nextCursor: string | null;
}>;

export type SendInboxTextMessageRequest = Readonly<{
  clientMessageId: string;
  type: 'TEXT';
  text: string;

  replyToMetaMessageId?: string | null;
}>;

export type SendInboxTemplateMessageRequest = Readonly<{
  clientMessageId: string;
  type: 'TEMPLATE';

  templateName: string;
  languageCode: string;

  components?: readonly unknown[];
}>;

export type SendInboxMessageRequest = SendInboxTextMessageRequest | SendInboxTemplateMessageRequest;

export type UpdateInboxConversationRequest = Readonly<{
  status?: WhatsAppConversationStatus;
  assignedEmployeeId?: string | null;
}>;

export type InboxQuickReplyResponse = Readonly<{
  id: string;
  organizationId: string;
  title: string;
  shortcut: string;
  body: string;
  createdAt: string;
  updatedAt: string;
}>;

export type InboxQuickReplyListResponse = readonly InboxQuickReplyResponse[];

export type CreateInboxQuickReplyRequest = Readonly<{
  title: string;
  shortcut: string;
  body: string;
}>;

export type UpdateInboxQuickReplyRequest = Readonly<{
  title?: string;
  shortcut?: string;
  body?: string;
}>;
