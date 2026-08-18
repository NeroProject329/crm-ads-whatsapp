import { Module } from '@nestjs/common';

import { AuthorizationModule } from '../authorization/authorization.module.js';
import { DatabaseModule } from '../database/database.module.js';
import { AuthController } from './auth.controller.js';
import { AuthService } from './auth.service.js';
import { ProfileController } from './profile.controller.js';
import { SessionService } from './session.service.js';

@Module({
  controllers: [AuthController, ProfileController],

  imports: [AuthorizationModule, DatabaseModule],

  providers: [AuthService, SessionService],
})
export class AuthModule {}
