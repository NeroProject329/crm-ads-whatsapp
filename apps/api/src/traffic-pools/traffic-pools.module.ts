import { Module } from '@nestjs/common';

import { AuthorizationModule } from '../authorization/authorization.module.js';

import { DatabaseModule } from '../database/database.module.js';

import { TrafficPoolsController } from './traffic-pools.controller.js';

import { TrafficPoolsService } from './traffic-pools.service.js';

@Module({
  imports: [AuthorizationModule, DatabaseModule],

  controllers: [TrafficPoolsController],

  providers: [TrafficPoolsService],

  exports: [TrafficPoolsService],
})
export class TrafficPoolsModule {}
