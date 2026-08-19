import { Module } from '@nestjs/common';

import { AuthorizationModule } from '../authorization/authorization.module.js';
import { DatabaseModule } from '../database/database.module.js';

import { AdsQueueController } from './ads-queue.controller.js';
import { AdsRequestsController } from './ads-requests.controller.js';
import { AdsService } from './ads.service.js';

@Module({
  imports: [AuthorizationModule, DatabaseModule],

  controllers: [AdsRequestsController, AdsQueueController],

  providers: [AdsService],

  exports: [AdsService],
})
export class AdsModule {}
