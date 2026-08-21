export type InboxMessage = Readonly<{
  id: string;
  conversationId: string;
  direction: 'INBOUND' | 'OUTBOUND';
  type: 'TEXT' | 'TEMPLATE' | 'IMAGE' | 'AUDIO' | 'VIDEO' | 'DOCUMENT' | 'STICKER' | 'LOCATION' | 'CONTACTS' | 'INTERACTIVE' | 'REACTION' | 'UNKNOWN';
  status: 'RECEIVED' | 'QUEUED' | 'SENDING' | 'SENT' | 'DELIVERED' | 'READ' | 'FAILED' | 'DELETED';
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

export type InboxConversation = Readonly<{
  id: string;
  status: 'OPEN' | 'CLOSED' | 'ARCHIVED';
  contact: Readonly<{ id: string; waId: string; profileName: string | null }>;
  whatsAppNumber: Readonly<{ id: string; displayName: string; e164: string }>;
  assignedEmployee: Readonly<{
    employeeId: string;
    employeeCode: string;
    userId: string;
    displayName: string;
  }> | null;
  customerServiceWindowExpiresAt: string | null;
  isCustomerServiceWindowOpen: boolean;
  lastMessageAt: string | null;
  lastInboundAt: string | null;
  lastOutboundAt: string | null;
  unreadCount: number;
  lastMessage: InboxMessage | null;
  createdAt: string;
  updatedAt: string;
}>;

export type InboxConversationList = Readonly<{
  items: readonly InboxConversation[];
  nextCursor: string | null;
}>;

export type InboxMessageList = Readonly<{
  items: readonly InboxMessage[];
  nextCursor: string | null;
}>;

export type InboxQuickReply = Readonly<{
  id: string;
  title: string;
  shortcut: string;
  body: string;
  createdAt: string;
  updatedAt: string;
}>;
