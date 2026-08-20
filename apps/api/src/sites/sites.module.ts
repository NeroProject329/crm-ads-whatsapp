import { Module } from '@nestjs/common';

import { AuthorizationModule } from '../authorization/authorization.module.js';
import { DatabaseModule } from '../database/database.module.js';

import { SiteMonitoringController } from './site-monitoring.controller.js';
import { SiteMonitoringService } from './site-monitoring.service.js';
import { SitesController } from './sites.controller.js';
import { SitesService } from './sites.service.js';

@Module({
  imports: [AuthorizationModule, DatabaseModule],

  controllers: [SitesController, SiteMonitoringController],

  providers: [SitesService, SiteMonitoringService],

  exports: [SitesService, SiteMonitoringService],
})
export class SitesModule {}
