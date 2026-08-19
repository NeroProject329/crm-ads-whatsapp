import { Module } from '@nestjs/common';

import { AuthorizationModule } from '../authorization/authorization.module.js';

import { DatabaseModule } from '../database/database.module.js';

import { SitesController } from './sites.controller.js';

import { SitesService } from './sites.service.js';

@Module({
  imports: [AuthorizationModule, DatabaseModule],

  controllers: [SitesController],

  providers: [SitesService],

  exports: [SitesService],
})
export class SitesModule {}
