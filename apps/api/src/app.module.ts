import { Module } from '@nestjs/common';

import { AuthModule } from './auth/auth.module.js';

import { DatabaseModule } from './database/database.module.js';

import { HealthController } from './health.controller.js';

import { SecurityModule } from './security/security.module.js';

import { SitesModule } from './sites/sites.module.js';

import { WhatsAppNumbersModule } from './whatsapp-numbers/whatsapp-numbers.module.js';

import { TrafficPoolsModule } from './traffic-pools/traffic-pools.module.js';

import { AdsModule } from './ads/ads.module.js';

import { NotificationsModule } from './notifications/notifications.module.js';

import { InboxModule } from './inbox/inbox.module.js';

import { LeadsModule } from './leads/leads.module.js';

import { WhatsAppHealthModule } from './whatsapp-health/whatsapp-health.module.js';

@Module({
  controllers: [HealthController],

  imports: [
    SecurityModule,
    AuthModule,
    DatabaseModule,
    SitesModule,
    WhatsAppNumbersModule,
    TrafficPoolsModule,
    AdsModule,
    NotificationsModule,
    InboxModule,
    LeadsModule,
    WhatsAppHealthModule,
  ],
})
export class AppModule {}
