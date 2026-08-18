import { Module } from '@nestjs/common';

import { DatabaseModule } from '../database/database.module.js';
import { AccessTokenGuard } from './access-token.guard.js';
import { AuthorizationGuard } from './authorization.guard.js';

@Module({
  imports: [DatabaseModule],

  providers: [AccessTokenGuard, AuthorizationGuard],

  exports: [AccessTokenGuard, AuthorizationGuard],
})
export class AuthorizationModule {}
