import { Module } from '@nestjs/common';

import { AuthorizationModule } from '../authorization/authorization.module.js';

import { DatabaseModule } from '../database/database.module.js';

import { LeadsController } from './leads.controller.js';

import { LeadsService } from './leads.service.js';

@Module({
  imports: [AuthorizationModule, DatabaseModule],

  controllers: [LeadsController],

  providers: [LeadsService],

  exports: [LeadsService],
})
export class LeadsModule {}
