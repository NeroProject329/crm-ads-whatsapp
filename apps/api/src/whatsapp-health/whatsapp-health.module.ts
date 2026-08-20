import { Module } from '@nestjs/common';

import { AuthorizationModule } from '../authorization/authorization.module.js';

import { DatabaseModule } from '../database/database.module.js';

import { WhatsAppHealthController } from './whatsapp-health.controller.js';

import { WhatsAppHealthService } from './whatsapp-health.service.js';

@Module({
  imports: [AuthorizationModule, DatabaseModule],

  controllers: [WhatsAppHealthController],

  providers: [WhatsAppHealthService],

  exports: [WhatsAppHealthService],
})
export class WhatsAppHealthModule {}
