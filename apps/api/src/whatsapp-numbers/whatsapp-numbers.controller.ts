import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Inject,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';

import type { AuthenticatedPrincipal } from '@crm/auth';

import type { WhatsAppNumberListResponse, WhatsAppNumberResponse } from '@crm/contracts';

import {
  configureWhatsAppMetaSchema,
  createWhatsAppNumberSchema,
  updateWhatsAppNumberSchema,
} from '@crm/validation';

import { AccessTokenGuard } from '../authorization/access-token.guard.js';

import { AuthorizationGuard } from '../authorization/authorization.guard.js';

import { CurrentPrincipal } from '../authorization/current-principal.decorator.js';

import { RequirePermissions } from '../authorization/require-permissions.decorator.js';

import { WhatsAppNumbersService } from './whatsapp-numbers.service.js';

@Controller('whatsapp-numbers')
@UseGuards(AccessTokenGuard, AuthorizationGuard)
export class WhatsAppNumbersController {
  constructor(
    @Inject(WhatsAppNumbersService)
    private readonly whatsAppNumbersService: WhatsAppNumbersService,
  ) {}

  @Get()
  @RequirePermissions('whatsapp_number.read')
  list(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,
  ): Promise<WhatsAppNumberListResponse> {
    return this.whatsAppNumbersService.list(principal);
  }

  @Get(':numberId')
  @RequirePermissions('whatsapp_number.read')
  getById(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('numberId', new ParseUUIDPipe())
    numberId: string,
  ): Promise<WhatsAppNumberResponse> {
    return this.whatsAppNumbersService.getById(principal, numberId);
  }

  @Post()
  @RequirePermissions('whatsapp_number.manage')
  create(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Body()
    body: unknown,
  ): Promise<WhatsAppNumberResponse> {
    const parsed = createWhatsAppNumberSchema.safeParse(body);

    if (!parsed.success) {
      throw new BadRequestException({
        code: 'WHATSAPP_NUMBER_VALIDATION_ERROR',

        message: 'Invalid WhatsApp number payload.',

        issues: parsed.error.issues.map((issue) => ({
          code: issue.code,

          path: issue.path.join('.'),
        })),
      });
    }

    return this.whatsAppNumbersService.create(principal, parsed.data);
  }

  @Patch(':numberId')
  @RequirePermissions('whatsapp_number.manage')
  update(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('numberId', new ParseUUIDPipe())
    numberId: string,

    @Body()
    body: unknown,
  ): Promise<WhatsAppNumberResponse> {
    const parsed = updateWhatsAppNumberSchema.safeParse(body);

    if (!parsed.success) {
      throw new BadRequestException({
        code: 'WHATSAPP_NUMBER_VALIDATION_ERROR',

        message: 'Invalid WhatsApp number payload.',

        issues: parsed.error.issues.map((issue) => ({
          code: issue.code,

          path: issue.path.join('.'),
        })),
      });
    }

    return this.whatsAppNumbersService.update(principal, numberId, parsed.data);
  }

  @Patch(':numberId/meta-cloud')
  @RequirePermissions('whatsapp_number.manage')
  configureMetaCloud(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('numberId', new ParseUUIDPipe())
    numberId: string,

    @Body()
    body: unknown,
  ): Promise<WhatsAppNumberResponse> {
    const parsed = configureWhatsAppMetaSchema.safeParse(body);

    if (!parsed.success) {
      throw new BadRequestException({
        code: 'WHATSAPP_META_VALIDATION_ERROR',

        message: 'Invalid Meta Cloud API connection payload.',

        issues: parsed.error.issues.map((issue) => ({
          code: issue.code,

          path: issue.path.join('.'),
        })),
      });
    }

    return this.whatsAppNumbersService.configureMetaCloud(principal, numberId, parsed.data);
  }
}
