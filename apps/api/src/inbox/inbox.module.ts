import { Module } from '@nestjs/common';

import { AuthorizationModule } from '../authorization/authorization.module.js';

import { DatabaseModule } from '../database/database.module.js';

import { InboxController } from './inbox.controller.js';

import { InboxService } from './inbox.service.js';

@Module({
  imports: [AuthorizationModule, DatabaseModule],

  controllers: [InboxController],

  providers: [InboxService],

  exports: [InboxService],
})
export class InboxModule {}
