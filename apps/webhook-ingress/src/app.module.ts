import { Module } from '@nestjs/common';

import { DatabaseService } from './database.service.js';

import { HealthController } from './health.controller.js';

import { MetaWebhookController } from './meta-webhook.controller.js';

import { MetaWebhookService } from './meta-webhook.service.js';

@Module({
  controllers: [HealthController, MetaWebhookController],

  providers: [DatabaseService, MetaWebhookService],
})
export class AppModule {}
