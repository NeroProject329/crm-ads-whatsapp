import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  Inject,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';

import type { AuthenticatedPrincipal } from '@crm/auth';

import type {
  InboxConversationListResponse,
  InboxConversationResponse,
  InboxMessageListResponse,
  InboxMessageResponse,
  InboxQuickReplyListResponse,
  InboxQuickReplyResponse,
} from '@crm/contracts';

import {
  createInboxQuickReplySchema,
  inboxConversationListQuerySchema,
  inboxMessageListQuerySchema,
  sendInboxMessageSchema,
  updateInboxConversationSchema,
  updateInboxQuickReplySchema,
} from '@crm/validation';

import { AccessTokenGuard } from '../authorization/access-token.guard.js';

import { AuthorizationGuard } from '../authorization/authorization.guard.js';

import { CurrentPrincipal } from '../authorization/current-principal.decorator.js';

import { RequirePermissions } from '../authorization/require-permissions.decorator.js';

import { InboxService } from './inbox.service.js';

@Controller('inbox')
@UseGuards(AccessTokenGuard, AuthorizationGuard)
export class InboxController {
  constructor(
    @Inject(InboxService)
    private readonly inboxService: InboxService,
  ) {}

  @Get('conversations')
  @RequirePermissions('inbox.read')
  listConversations(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Query()
    query: unknown,
  ): Promise<InboxConversationListResponse> {
    const parsed = inboxConversationListQuerySchema.safeParse(query);

    if (!parsed.success) {
      throw this.validationError('INBOX_QUERY_VALIDATION_ERROR', parsed.error.issues);
    }

    return this.inboxService.listConversations(principal, parsed.data);
  }

  @Get('conversations/:conversationId')
  @RequirePermissions('inbox.read')
  getConversation(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('conversationId', new ParseUUIDPipe())
    conversationId: string,
  ): Promise<InboxConversationResponse> {
    return this.inboxService.getConversation(principal, conversationId);
  }

  @Get('conversations/:conversationId/messages')
  @RequirePermissions('inbox.read')
  listMessages(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('conversationId', new ParseUUIDPipe())
    conversationId: string,

    @Query()
    query: unknown,
  ): Promise<InboxMessageListResponse> {
    const parsed = inboxMessageListQuerySchema.safeParse(query);

    if (!parsed.success) {
      throw this.validationError('INBOX_MESSAGE_QUERY_VALIDATION_ERROR', parsed.error.issues);
    }

    return this.inboxService.listMessages(principal, conversationId, parsed.data);
  }

  @Post('conversations/:conversationId/messages')
  @RequirePermissions('inbox.manage')
  sendMessage(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('conversationId', new ParseUUIDPipe())
    conversationId: string,

    @Body()
    body: unknown,
  ): Promise<InboxMessageResponse> {
    const parsed = sendInboxMessageSchema.safeParse(body);

    if (!parsed.success) {
      throw this.validationError('INBOX_MESSAGE_VALIDATION_ERROR', parsed.error.issues);
    }

    return this.inboxService.sendMessage(principal, conversationId, parsed.data);
  }

  @Patch('conversations/:conversationId')
  @RequirePermissions('inbox.manage')
  updateConversation(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('conversationId', new ParseUUIDPipe())
    conversationId: string,

    @Body()
    body: unknown,
  ): Promise<InboxConversationResponse> {
    const parsed = updateInboxConversationSchema.safeParse(body);

    if (!parsed.success) {
      throw this.validationError('INBOX_CONVERSATION_VALIDATION_ERROR', parsed.error.issues);
    }

    return this.inboxService.updateConversation(principal, conversationId, parsed.data);
  }

  @Post('conversations/:conversationId/read')
  @RequirePermissions('inbox.manage')
  markRead(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('conversationId', new ParseUUIDPipe())
    conversationId: string,
  ): Promise<InboxConversationResponse> {
    return this.inboxService.markConversationRead(principal, conversationId);
  }

  @Get('quick-replies')
  @RequirePermissions('quick_reply.read')
  listQuickReplies(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,
  ): Promise<InboxQuickReplyListResponse> {
    return this.inboxService.listQuickReplies(principal);
  }

  @Post('quick-replies')
  @RequirePermissions('quick_reply.manage')
  createQuickReply(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Body()
    body: unknown,
  ): Promise<InboxQuickReplyResponse> {
    const parsed = createInboxQuickReplySchema.safeParse(body);

    if (!parsed.success) {
      throw this.validationError('QUICK_REPLY_VALIDATION_ERROR', parsed.error.issues);
    }

    return this.inboxService.createQuickReply(principal, parsed.data);
  }

  @Patch('quick-replies/:quickReplyId')
  @RequirePermissions('quick_reply.manage')
  updateQuickReply(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('quickReplyId', new ParseUUIDPipe())
    quickReplyId: string,

    @Body()
    body: unknown,
  ): Promise<InboxQuickReplyResponse> {
    const parsed = updateInboxQuickReplySchema.safeParse(body);

    if (!parsed.success) {
      throw this.validationError('QUICK_REPLY_VALIDATION_ERROR', parsed.error.issues);
    }

    return this.inboxService.updateQuickReply(principal, quickReplyId, parsed.data);
  }

  @Delete('quick-replies/:quickReplyId')
  @RequirePermissions('quick_reply.manage')
  deleteQuickReply(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('quickReplyId', new ParseUUIDPipe())
    quickReplyId: string,
  ): Promise<InboxQuickReplyResponse> {
    return this.inboxService.deleteQuickReply(principal, quickReplyId);
  }

  private validationError(
    code: string,
    issues: readonly {
      code: string;

      path: PropertyKey[];
    }[],
  ): BadRequestException {
    return new BadRequestException({
      code,

      message: 'Invalid inbox request.',

      issues: issues.map((issue) => ({
        code: issue.code,

        path: issue.path.join('.'),
      })),
    });
  }
}
