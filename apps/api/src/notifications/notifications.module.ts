import { Module } from '@nestjs/common';

import { AuthorizationModule } from '../authorization/authorization.module.js';

import { DatabaseModule } from '../database/database.module.js';

import { NotificationsController } from './notifications.controller.js';

import { NotificationsService } from './notifications.service.js';

@Module({
  imports: [AuthorizationModule, DatabaseModule],

  controllers: [NotificationsController],

  providers: [NotificationsService],

  exports: [NotificationsService],
})
export class NotificationsModule {}
