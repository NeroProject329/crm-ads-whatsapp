import {
  BadRequestException,
  Controller,
  Get,
  Inject,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';

import type { AuthenticatedPrincipal } from '@crm/auth';

import type {
  WhatsAppNumberHealthEventResponse,
  WhatsAppNumberHealthResponse,
  WhatsAppNumberIncidentResponse,
} from '@crm/contracts';

import { whatsAppHealthHistoryQuerySchema } from '@crm/validation';

import { AccessTokenGuard } from '../authorization/access-token.guard.js';

import { AuthorizationGuard } from '../authorization/authorization.guard.js';

import { CurrentPrincipal } from '../authorization/current-principal.decorator.js';

import { RequirePermissions } from '../authorization/require-permissions.decorator.js';

import { WhatsAppHealthService } from './whatsapp-health.service.js';

@Controller('whatsapp-numbers/:whatsAppNumberId/health')
@UseGuards(AccessTokenGuard, AuthorizationGuard)
export class WhatsAppHealthController {
  constructor(
    @Inject(WhatsAppHealthService)
    private readonly healthService: WhatsAppHealthService,
  ) {}

  @Get()
  @RequirePermissions('whatsapp_health.read')
  getHealth(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('whatsAppNumberId', new ParseUUIDPipe())
    whatsAppNumberId: string,
  ): Promise<WhatsAppNumberHealthResponse> {
    return this.healthService.getHealth(principal, whatsAppNumberId);
  }

  @Get('events')
  @RequirePermissions('whatsapp_health.read')
  listEvents(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('whatsAppNumberId', new ParseUUIDPipe())
    whatsAppNumberId: string,

    @Query()
    query: unknown,
  ): Promise<readonly WhatsAppNumberHealthEventResponse[]> {
    const parsed = whatsAppHealthHistoryQuerySchema.safeParse(query);

    if (!parsed.success) {
      throw new BadRequestException({
        code: 'WHATSAPP_HEALTH_QUERY_VALIDATION_ERROR',

        message: 'Invalid WhatsApp health query.',
      });
    }

    return this.healthService.listEvents(principal, whatsAppNumberId, parsed.data.limit);
  }

  @Get('incidents')
  @RequirePermissions('whatsapp_health.read')
  listIncidents(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('whatsAppNumberId', new ParseUUIDPipe())
    whatsAppNumberId: string,

    @Query()
    query: unknown,
  ): Promise<readonly WhatsAppNumberIncidentResponse[]> {
    const parsed = whatsAppHealthHistoryQuerySchema.safeParse(query);

    if (!parsed.success) {
      throw new BadRequestException({
        code: 'WHATSAPP_HEALTH_QUERY_VALIDATION_ERROR',

        message: 'Invalid WhatsApp health query.',
      });
    }

    return this.healthService.listIncidents(principal, whatsAppNumberId, parsed.data.limit);
  }

  @Post('pause')
  @RequirePermissions('whatsapp_health.manage')
  pause(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('whatsAppNumberId', new ParseUUIDPipe())
    whatsAppNumberId: string,
  ): Promise<WhatsAppNumberHealthResponse> {
    return this.healthService.pause(principal, whatsAppNumberId);
  }

  @Post('resume')
  @RequirePermissions('whatsapp_health.manage')
  resume(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('whatsAppNumberId', new ParseUUIDPipe())
    whatsAppNumberId: string,
  ): Promise<WhatsAppNumberHealthResponse> {
    return this.healthService.resume(principal, whatsAppNumberId);
  }

  @Post('sync')
  @RequirePermissions('whatsapp_health.manage')
  requestSync(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('whatsAppNumberId', new ParseUUIDPipe())
    whatsAppNumberId: string,
  ): Promise<WhatsAppNumberHealthResponse> {
    return this.healthService.requestSync(principal, whatsAppNumberId);
  }
}
