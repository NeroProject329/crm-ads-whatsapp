import {
  ConflictException,
  ForbiddenException,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';

import type { AuthenticatedPrincipal } from '@crm/auth';

import type {
  EmployeeModel,
  UserModel,
  WhatsAppContactModel,
  WhatsAppConversationModel,
  WhatsAppMessageModel,
  WhatsAppNumberModel,
  WhatsAppQuickReplyModel,
} from '@crm/database';

import type {
  InboxConversationListResponse,
  InboxConversationResponse,
  InboxMessageListResponse,
  InboxMessageResponse,
  InboxQuickReplyListResponse,
  InboxQuickReplyResponse,
} from '@crm/contracts';

import type {
  CreateInboxQuickReplyInput,
  InboxConversationListQuery,
  InboxMessageListQuery,
  SendInboxMessageInput,
  UpdateInboxConversationInput,
  UpdateInboxQuickReplyInput,
} from '@crm/validation';

import { DatabaseService } from '../database/database.service.js';

type JsonPrimitive = string | number | boolean | null;

type JsonValue =
  | JsonPrimitive
  | JsonValue[]
  | {
      [key: string]: JsonValue;
    };

type JsonObject = {
  [key: string]: JsonValue;
};

type LoadedAssignee = Pick<EmployeeModel, 'id' | 'employeeCode' | 'userId'> & {
  user: Pick<UserModel, 'displayName'>;
};

type LoadedConversation = WhatsAppConversationModel & {
  contact: Pick<WhatsAppContactModel, 'id' | 'waId' | 'profileName'>;

  whatsAppNumber: Pick<
    WhatsAppNumberModel,
    'id' | 'displayName' | 'e164' | 'metaPhoneNumberId' | 'status'
  >;

  assignedEmployee: LoadedAssignee | null;

  messages: WhatsAppMessageModel[];
};

function normalizeJsonValue(value: unknown): JsonValue {
  if (value === null || typeof value === 'string' || typeof value === 'boolean') {
    return value;
  }

  if (typeof value === 'number') {
    return Number.isFinite(value) ? value : null;
  }

  if (Array.isArray(value)) {
    return value.map(normalizeJsonValue);
  }

  if (typeof value === 'object' && value !== null) {
    const result: JsonObject = {};

    for (const [key, item] of Object.entries(value)) {
      result[key] = normalizeJsonValue(item);
    }

    return result;
  }

  return null;
}

@Injectable()
export class InboxService {
  constructor(
    @Inject(DatabaseService)
    private readonly database: DatabaseService,
  ) {}

  async listConversations(
    principal: AuthenticatedPrincipal,
    query: InboxConversationListQuery,
  ): Promise<InboxConversationListResponse> {
    const employeeId = this.isAdmin(principal) ? null : await this.getCurrentEmployeeId(principal);

    const conversations = await this.database.client.whatsAppConversation.findMany({
      where: {
        organizationId: principal.organizationId,

        ...(employeeId
          ? {
              assignedEmployeeId: employeeId,
            }
          : {}),

        ...(query.status
          ? {
              status: query.status,
            }
          : {}),

        ...(query.whatsAppNumberId
          ? {
              whatsAppNumberId: query.whatsAppNumberId,
            }
          : {}),

        ...(query.search
          ? {
              OR: [
                {
                  contact: {
                    profileName: {
                      contains: query.search,

                      mode: 'insensitive',
                    },
                  },
                },

                {
                  contact: {
                    waId: {
                      contains: query.search,
                    },
                  },
                },

                {
                  whatsAppNumber: {
                    displayName: {
                      contains: query.search,

                      mode: 'insensitive',
                    },
                  },
                },
              ],
            }
          : {}),
      },

      include: {
        contact: {
          select: {
            id: true,
            waId: true,
            profileName: true,
          },
        },

        whatsAppNumber: {
          select: {
            id: true,
            displayName: true,
            e164: true,
            metaPhoneNumberId: true,
            status: true,
          },
        },

        assignedEmployee: {
          include: {
            user: {
              select: {
                displayName: true,
              },
            },
          },
        },

        messages: {
          orderBy: {
            createdAt: 'desc',
          },

          take: 1,
        },
      },

      orderBy: [
        {
          lastMessageAt: 'desc',
        },

        {
          id: 'desc',
        },
      ],

      take: query.limit + 1,

      ...(query.cursor
        ? {
            cursor: {
              id: query.cursor,
            },

            skip: 1,
          }
        : {}),
    });

    const hasMore = conversations.length > query.limit;

    const page = hasMore ? conversations.slice(0, query.limit) : conversations;

    return {
      items: page.map((conversation) => this.mapConversation(conversation)),

      nextCursor: hasMore ? (page.at(-1)?.id ?? null) : null,
    };
  }

  async getConversation(
    principal: AuthenticatedPrincipal,
    conversationId: string,
  ): Promise<InboxConversationResponse> {
    const conversation = await this.getAccessibleConversation(principal, conversationId);

    return this.mapConversation(conversation);
  }

  async listMessages(
    principal: AuthenticatedPrincipal,
    conversationId: string,
    query: InboxMessageListQuery,
  ): Promise<InboxMessageListResponse> {
    const conversation = await this.getAccessibleConversation(principal, conversationId);

    const messages = await this.database.client.whatsAppMessage.findMany({
      where: {
        organizationId: principal.organizationId,

        conversationId: conversation.id,
      },

      orderBy: [
        {
          createdAt: 'desc',
        },

        {
          id: 'desc',
        },
      ],

      take: query.limit + 1,

      ...(query.cursor
        ? {
            cursor: {
              id: query.cursor,
            },

            skip: 1,
          }
        : {}),
    });

    const hasMore = messages.length > query.limit;

    const page = hasMore ? messages.slice(0, query.limit) : messages;

    return {
      items: page.map((message) => this.mapMessage(message)),

      nextCursor: hasMore ? (page.at(-1)?.id ?? null) : null,
    };
  }

  async sendMessage(
    principal: AuthenticatedPrincipal,
    conversationId: string,
    input: SendInboxMessageInput,
  ): Promise<InboxMessageResponse> {
    const conversation = await this.getAccessibleConversation(principal, conversationId);

    if (
      conversation.whatsAppNumber.status !== 'ACTIVE' ||
      !conversation.whatsAppNumber.metaPhoneNumberId
    ) {
      throw new ConflictException({
        code: 'WHATSAPP_NUMBER_NOT_CONNECTED',

        message: 'The WhatsApp number is not active and connected to Meta Cloud API.',
      });
    }

    const existing = await this.database.client.whatsAppMessage.findUnique({
      where: {
        clientMessageId: input.clientMessageId,
      },
    });

    if (existing) {
      if (
        existing.organizationId !== principal.organizationId ||
        existing.conversationId !== conversation.id
      ) {
        throw new ConflictException({
          code: 'WHATSAPP_CLIENT_MESSAGE_ID_CONFLICT',

          message: 'This client message id is already used by another conversation.',
        });
      }

      return this.mapMessage(existing);
    }

    const now = new Date();

    const windowOpen = Boolean(
      conversation.customerServiceWindowExpiresAt &&
      conversation.customerServiceWindowExpiresAt > now,
    );

    if (input.type === 'TEXT' && !windowOpen) {
      throw new ConflictException({
        code: 'WHATSAPP_CUSTOMER_SERVICE_WINDOW_CLOSED',

        message: 'The 24-hour customer service window is closed. Use an approved template message.',
      });
    }

    const content: JsonObject =
      input.type === 'TEXT'
        ? {
            type: 'text',

            text: {
              body: input.text,
            },

            ...(input.replyToMetaMessageId
              ? {
                  context: {
                    messageId: input.replyToMetaMessageId,
                  },
                }
              : {}),
          }
        : {
            type: 'template',

            template: {
              name: input.templateName,

              languageCode: input.languageCode,

              ...(input.components !== undefined
                ? {
                    components: normalizeJsonValue(input.components),
                  }
                : {}),
            },
          };

    const message = await this.database.client.$transaction(async (transaction) => {
      const created = await transaction.whatsAppMessage.create({
        data: {
          organizationId: principal.organizationId,

          conversationId: conversation.id,

          whatsAppNumberId: conversation.whatsAppNumberId,

          contactId: conversation.contactId,

          direction: 'OUTBOUND',

          type: input.type,

          status: 'QUEUED',

          clientMessageId: input.clientMessageId,

          replyToMetaMessageId: input.type === 'TEXT' ? (input.replyToMetaMessageId ?? null) : null,

          textBody: input.type === 'TEXT' ? input.text : null,

          content,

          queuedAt: now,

          availableAt: now,
        },
      });

      await transaction.whatsAppConversation.update({
        where: {
          id: conversation.id,
        },

        data: {
          lastMessageAt: now,
        },
      });

      await transaction.auditLog.create({
        data: {
          organizationId: principal.organizationId,

          actorType: 'USER',

          actorUserId: principal.userId,

          action: 'whatsapp_message.queued',

          resourceType: 'whatsapp_message',

          resourceId: created.id,

          outcome: 'SUCCESS',

          metadata: {
            conversationId: conversation.id,

            direction: 'OUTBOUND',

            type: created.type,

            clientMessageId: created.clientMessageId,
          },
        },
      });

      return created;
    });

    return this.mapMessage(message);
  }

  async updateConversation(
    principal: AuthenticatedPrincipal,
    conversationId: string,
    input: UpdateInboxConversationInput,
  ): Promise<InboxConversationResponse> {
    const conversation = await this.getAccessibleConversation(principal, conversationId);

    if (input.assignedEmployeeId !== undefined && !this.isAdmin(principal)) {
      throw new ForbiddenException({
        code: 'INBOX_ASSIGNMENT_ADMIN_REQUIRED',

        message: 'Only ADMIN can change conversation assignment.',
      });
    }

    if (input.assignedEmployeeId) {
      await this.assertActiveEmployee(principal.organizationId, input.assignedEmployeeId);
    }

    await this.database.client.$transaction(async (transaction) => {
      await transaction.whatsAppConversation.update({
        where: {
          id: conversation.id,
        },

        data: {
          ...(input.status !== undefined
            ? {
                status: input.status,
              }
            : {}),

          ...(input.assignedEmployeeId !== undefined
            ? {
                assignedEmployeeId: input.assignedEmployeeId,
              }
            : {}),
        },
      });

      await transaction.auditLog.create({
        data: {
          organizationId: principal.organizationId,

          actorType: 'USER',

          actorUserId: principal.userId,

          action: 'whatsapp_conversation.updated',

          resourceType: 'whatsapp_conversation',

          resourceId: conversation.id,

          outcome: 'SUCCESS',

          metadata: {
            ...(input.status !== undefined
              ? {
                  status: input.status,
                }
              : {}),

            ...(input.assignedEmployeeId !== undefined
              ? {
                  assignedEmployeeId: input.assignedEmployeeId,
                }
              : {}),
          },
        },
      });
    });

    return this.getConversation(principal, conversation.id);
  }

  async markConversationRead(
    principal: AuthenticatedPrincipal,
    conversationId: string,
  ): Promise<InboxConversationResponse> {
    const conversation = await this.getAccessibleConversation(principal, conversationId);

    await this.database.client.$transaction(async (transaction) => {
      await transaction.whatsAppConversation.update({
        where: {
          id: conversation.id,
        },

        data: {
          unreadCount: 0,
        },
      });

      await transaction.auditLog.create({
        data: {
          organizationId: principal.organizationId,

          actorType: 'USER',

          actorUserId: principal.userId,

          action: 'whatsapp_conversation.read',

          resourceType: 'whatsapp_conversation',

          resourceId: conversation.id,

          outcome: 'SUCCESS',
        },
      });
    });

    return this.getConversation(principal, conversation.id);
  }

  async listQuickReplies(principal: AuthenticatedPrincipal): Promise<InboxQuickReplyListResponse> {
    const replies = await this.database.client.whatsAppQuickReply.findMany({
      where: {
        organizationId: principal.organizationId,

        deletedAt: null,
      },

      orderBy: [
        {
          title: 'asc',
        },

        {
          shortcut: 'asc',
        },
      ],
    });

    return replies.map((reply) => this.mapQuickReply(reply));
  }

  async createQuickReply(
    principal: AuthenticatedPrincipal,
    input: CreateInboxQuickReplyInput,
  ): Promise<InboxQuickReplyResponse> {
    try {
      const reply = await this.database.client.$transaction(async (transaction) => {
        const created = await transaction.whatsAppQuickReply.create({
          data: {
            organizationId: principal.organizationId,

            title: input.title,

            shortcut: input.shortcut,

            body: input.body,
          },
        });

        await transaction.auditLog.create({
          data: {
            organizationId: principal.organizationId,

            actorType: 'USER',

            actorUserId: principal.userId,

            action: 'whatsapp_quick_reply.created',

            resourceType: 'whatsapp_quick_reply',

            resourceId: created.id,

            outcome: 'SUCCESS',

            metadata: {
              shortcut: created.shortcut,
            },
          },
        });

        return created;
      });

      return this.mapQuickReply(reply);
    } catch (error) {
      if (this.isUniqueConstraintError(error)) {
        throw new ConflictException({
          code: 'QUICK_REPLY_SHORTCUT_EXISTS',

          message: 'This quick reply shortcut already exists.',
        });
      }

      throw error;
    }
  }

  async updateQuickReply(
    principal: AuthenticatedPrincipal,
    quickReplyId: string,
    input: UpdateInboxQuickReplyInput,
  ): Promise<InboxQuickReplyResponse> {
    await this.getOrganizationQuickReply(principal.organizationId, quickReplyId);

    try {
      const reply = await this.database.client.whatsAppQuickReply.update({
        where: {
          id: quickReplyId,
        },

        data: {
          ...(input.title !== undefined
            ? {
                title: input.title,
              }
            : {}),

          ...(input.shortcut !== undefined
            ? {
                shortcut: input.shortcut,
              }
            : {}),

          ...(input.body !== undefined
            ? {
                body: input.body,
              }
            : {}),
        },
      });

      return this.mapQuickReply(reply);
    } catch (error) {
      if (this.isUniqueConstraintError(error)) {
        throw new ConflictException({
          code: 'QUICK_REPLY_SHORTCUT_EXISTS',

          message: 'This quick reply shortcut already exists.',
        });
      }

      throw error;
    }
  }

  async deleteQuickReply(
    principal: AuthenticatedPrincipal,
    quickReplyId: string,
  ): Promise<InboxQuickReplyResponse> {
    const existing = await this.getOrganizationQuickReply(principal.organizationId, quickReplyId);

    if (existing.deletedAt) {
      throw new NotFoundException({
        code: 'QUICK_REPLY_NOT_FOUND',

        message: 'Quick reply not found.',
      });
    }

    const reply = await this.database.client.whatsAppQuickReply.update({
      where: {
        id: quickReplyId,
      },

      data: {
        deletedAt: new Date(),
      },
    });

    return this.mapQuickReply(reply);
  }

  private async getAccessibleConversation(
    principal: AuthenticatedPrincipal,
    conversationId: string,
  ): Promise<LoadedConversation> {
    const employeeId = this.isAdmin(principal) ? null : await this.getCurrentEmployeeId(principal);

    const conversation = await this.database.client.whatsAppConversation.findFirst({
      where: {
        id: conversationId,

        organizationId: principal.organizationId,

        ...(employeeId
          ? {
              assignedEmployeeId: employeeId,
            }
          : {}),
      },

      include: {
        contact: {
          select: {
            id: true,
            waId: true,
            profileName: true,
          },
        },

        whatsAppNumber: {
          select: {
            id: true,
            displayName: true,
            e164: true,
            metaPhoneNumberId: true,
            status: true,
          },
        },

        assignedEmployee: {
          include: {
            user: {
              select: {
                displayName: true,
              },
            },
          },
        },

        messages: {
          orderBy: {
            createdAt: 'desc',
          },

          take: 1,
        },
      },
    });

    if (!conversation) {
      throw new NotFoundException({
        code: 'INBOX_CONVERSATION_NOT_FOUND',

        message: 'Conversation not found.',
      });
    }

    return conversation;
  }

  private async getOrganizationQuickReply(
    organizationId: string,
    quickReplyId: string,
  ): Promise<WhatsAppQuickReplyModel> {
    const reply = await this.database.client.whatsAppQuickReply.findFirst({
      where: {
        id: quickReplyId,

        organizationId,
      },
    });

    if (!reply) {
      throw new NotFoundException({
        code: 'QUICK_REPLY_NOT_FOUND',

        message: 'Quick reply not found.',
      });
    }

    return reply;
  }

  private async getCurrentEmployeeId(principal: AuthenticatedPrincipal): Promise<string> {
    const employee = await this.database.client.employee.findFirst({
      where: {
        organizationId: principal.organizationId,

        userId: principal.userId,

        status: 'ACTIVE',

        deletedAt: null,
      },

      select: {
        id: true,
      },
    });

    if (!employee) {
      throw new ForbiddenException({
        code: 'EMPLOYEE_PROFILE_REQUIRED',

        message: 'An active employee profile is required.',
      });
    }

    return employee.id;
  }

  private async assertActiveEmployee(organizationId: string, employeeId: string): Promise<void> {
    const employee = await this.database.client.employee.findFirst({
      where: {
        id: employeeId,

        organizationId,

        status: 'ACTIVE',

        deletedAt: null,
      },

      select: {
        id: true,
      },
    });

    if (!employee) {
      throw new NotFoundException({
        code: 'INBOX_EMPLOYEE_NOT_FOUND',

        message: 'Active employee not found.',
      });
    }
  }

  private mapConversation(conversation: LoadedConversation): InboxConversationResponse {
    const now = new Date();

    return {
      id: conversation.id,

      organizationId: conversation.organizationId,

      status: conversation.status,

      contact: {
        id: conversation.contact.id,

        waId: conversation.contact.waId,

        profileName: conversation.contact.profileName,
      },

      whatsAppNumber: {
        id: conversation.whatsAppNumber.id,

        displayName: conversation.whatsAppNumber.displayName,

        e164: conversation.whatsAppNumber.e164,
      },

      assignedEmployee: conversation.assignedEmployee
        ? {
            employeeId: conversation.assignedEmployee.id,

            employeeCode: conversation.assignedEmployee.employeeCode,

            userId: conversation.assignedEmployee.userId,

            displayName: conversation.assignedEmployee.user.displayName,
          }
        : null,

      customerServiceWindowExpiresAt:
        conversation.customerServiceWindowExpiresAt?.toISOString() ?? null,

      isCustomerServiceWindowOpen: Boolean(
        conversation.customerServiceWindowExpiresAt &&
        conversation.customerServiceWindowExpiresAt > now,
      ),

      lastMessageAt: conversation.lastMessageAt?.toISOString() ?? null,

      lastInboundAt: conversation.lastInboundAt?.toISOString() ?? null,

      lastOutboundAt: conversation.lastOutboundAt?.toISOString() ?? null,

      unreadCount: conversation.unreadCount,

      lastMessage: conversation.messages[0] ? this.mapMessage(conversation.messages[0]) : null,

      createdAt: conversation.createdAt.toISOString(),

      updatedAt: conversation.updatedAt.toISOString(),
    };
  }

  private mapMessage(message: WhatsAppMessageModel): InboxMessageResponse {
    return {
      id: message.id,

      organizationId: message.organizationId,

      conversationId: message.conversationId,

      whatsAppNumberId: message.whatsAppNumberId,

      contactId: message.contactId,

      direction: message.direction,

      type: message.type,

      status: message.status,

      metaMessageId: message.metaMessageId,

      clientMessageId: message.clientMessageId,

      replyToMetaMessageId: message.replyToMetaMessageId,

      textBody: message.textBody,

      content: message.content,

      providerTimestamp: message.providerTimestamp?.toISOString() ?? null,

      errorCode: message.errorCode,

      errorMessage: message.errorMessage,

      queuedAt: message.queuedAt?.toISOString() ?? null,

      sentAt: message.sentAt?.toISOString() ?? null,

      deliveredAt: message.deliveredAt?.toISOString() ?? null,

      readAt: message.readAt?.toISOString() ?? null,

      failedAt: message.failedAt?.toISOString() ?? null,

      createdAt: message.createdAt.toISOString(),

      updatedAt: message.updatedAt.toISOString(),
    };
  }

  private mapQuickReply(reply: WhatsAppQuickReplyModel): InboxQuickReplyResponse {
    return {
      id: reply.id,

      organizationId: reply.organizationId,

      title: reply.title,

      shortcut: reply.shortcut,

      body: reply.body,

      createdAt: reply.createdAt.toISOString(),

      updatedAt: reply.updatedAt.toISOString(),
    };
  }

  private isAdmin(principal: AuthenticatedPrincipal): boolean {
    return principal.roles.includes('ADMIN');
  }

  private isUniqueConstraintError(error: unknown): boolean {
    if (typeof error !== 'object' || error === null) {
      return false;
    }

    return (
      'code' in error &&
      (
        error as {
          code?: unknown;
        }
      ).code === 'P2002'
    );
  }
}
