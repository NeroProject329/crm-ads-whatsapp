import {
  BadRequestException,
  Controller,
  Delete,
  Get,
  Headers,
  Inject,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Body,
  UseGuards,
} from '@nestjs/common';

import type { AuthenticatedPrincipal } from '@crm/auth';

import type {
  NotificationListResponse,
  NotificationPreferenceResponse,
  PushDeviceListResponse,
  PushDeviceResponse,
} from '@crm/contracts';

import { registerPushDeviceSchema, updateNotificationPreferenceSchema } from '@crm/validation';

import { AccessTokenGuard } from '../authorization/access-token.guard.js';

import { AuthorizationGuard } from '../authorization/authorization.guard.js';

import { CurrentPrincipal } from '../authorization/current-principal.decorator.js';

import { RequirePermissions } from '../authorization/require-permissions.decorator.js';

import { NotificationsService } from './notifications.service.js';

@Controller()
@UseGuards(AccessTokenGuard, AuthorizationGuard)
export class NotificationsController {
  constructor(
    @Inject(NotificationsService)
    private readonly notificationsService: NotificationsService,
  ) {}

  @Get('push/devices')
  @RequirePermissions('profile.read')
  listDevices(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,
  ): Promise<PushDeviceListResponse> {
    return this.notificationsService.listDevices(principal);
  }

  @Post('push/devices')
  @RequirePermissions('profile.update')
  registerDevice(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Body()
    body: unknown,

    @Headers('user-agent')
    userAgent: string | undefined,
  ): Promise<PushDeviceResponse> {
    const parsed = registerPushDeviceSchema.safeParse(body);

    if (!parsed.success) {
      throw new BadRequestException({
        code: 'PUSH_DEVICE_VALIDATION_ERROR',

        message: 'Invalid push device payload.',

        issues: parsed.error.issues.map((issue) => ({
          code: issue.code,

          path: issue.path.join('.'),
        })),
      });
    }

    return this.notificationsService.registerDevice(principal, parsed.data, userAgent ?? null);
  }

  @Delete('push/devices/:subscriptionId')
  @RequirePermissions('profile.update')
  async unregisterDevice(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Param('subscriptionId', new ParseUUIDPipe())
    subscriptionId: string,
  ): Promise<Readonly<{ success: true }>> {
    await this.notificationsService.unregisterDevice(principal, subscriptionId);

    return {
      success: true,
    };
  }

  @Get('notifications/preferences')
  @RequirePermissions('profile.read')
  getPreferences(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,
  ): Promise<NotificationPreferenceResponse> {
    return this.notificationsService.getPreferences(principal);
  }

  @Patch('notifications/preferences')
  @RequirePermissions('profile.update')
  updatePreferences(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,

    @Body()
    body: unknown,
  ): Promise<NotificationPreferenceResponse> {
    const parsed = updateNotificationPreferenceSchema.safeParse(body);

    if (!parsed.success) {
      throw new BadRequestException({
        code: 'NOTIFICATION_PREFERENCE_VALIDATION_ERROR',

        message: 'Invalid notification preference payload.',

        issues: parsed.error.issues.map((issue) => ({
          code: issue.code,

          path: issue.path.join('.'),
        })),
      });
    }

    return this.notificationsService.updatePreferences(principal, parsed.data);
  }

  @Get('notifications')
  @RequirePermissions('profile.read')
  listNotifications(
    @CurrentPrincipal()
    principal: AuthenticatedPrincipal,
  ): Promise<NotificationListResponse> {
    return this.notificationsService.listNotifications(principal);
  }
}
