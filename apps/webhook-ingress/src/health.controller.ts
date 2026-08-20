import { Controller, Get, Inject, ServiceUnavailableException } from '@nestjs/common';

import { DatabaseService } from './database.service.js';

type LivenessResponse = Readonly<{
  service: 'webhook-ingress';

  status: 'ok';

  timestamp: string;

  version: '0.2.0';
}>;

type ReadinessResponse = LivenessResponse &
  Readonly<{
    database: 'connected';
  }>;

@Controller('health')
export class HealthController {
  constructor(
    @Inject(DatabaseService)
    private readonly database: DatabaseService,
  ) {}

  @Get('live')
  getLiveness(): LivenessResponse {
    return this.createLiveness();
  }

  @Get()
  async getHealth(): Promise<ReadinessResponse> {
    return this.getReadiness();
  }

  @Get('ready')
  async getReadiness(): Promise<ReadinessResponse> {
    try {
      const ready = await this.database.isReady();

      if (!ready) {
        throw new Error('Database readiness failed.');
      }

      return {
        ...this.createLiveness(),

        database: 'connected',
      };
    } catch {
      throw new ServiceUnavailableException({
        service: 'webhook-ingress',

        status: 'degraded',

        database: 'unavailable',

        timestamp: new Date().toISOString(),

        version: '0.2.0',
      });
    }
  }

  private createLiveness(): LivenessResponse {
    return {
      service: 'webhook-ingress',

      status: 'ok',

      timestamp: new Date().toISOString(),

      version: '0.2.0',
    };
  }
}
