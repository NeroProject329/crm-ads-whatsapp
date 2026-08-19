import { Module } from '@nestjs/common';

import { AuthorizationModule } from '../authorization/authorization.module.js';

import { DatabaseModule } from '../database/database.module.js';

import { WhatsAppNumbersController } from './whatsapp-numbers.controller.js';

import { WhatsAppNumbersService } from './whatsapp-numbers.service.js';

@Module({
  imports: [AuthorizationModule, DatabaseModule],

  controllers: [WhatsAppNumbersController],

  providers: [WhatsAppNumbersService],

  exports: [WhatsAppNumbersService],
})
export class WhatsAppNumbersModule {}
