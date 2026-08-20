import { Module } from '@nestjs/common';

import { APP_GUARD } from '@nestjs/core';

import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';

import { parseHttpSecurityEnvironment } from '@crm/config';

const security = parseHttpSecurityEnvironment();

@Module({
  imports: [
    ThrottlerModule.forRoot([
      {
        name: 'default',

        ttl: security.apiRateLimitTtlMs,

        limit: security.apiRateLimitDefault,
      },
    ]),
  ],

  providers: [
    {
      provide: APP_GUARD,

      useClass: ThrottlerGuard,
    },
  ],
})
export class SecurityModule {}
