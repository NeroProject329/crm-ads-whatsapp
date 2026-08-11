import { Module } from '@nestjs/common';

import { DatabaseModule } from './database/database.module.js';
import { HealthController } from './health.controller.js';

@Module({
  controllers: [HealthController],
  imports: [DatabaseModule],
})
export class AppModule {}
