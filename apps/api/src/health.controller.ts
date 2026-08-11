import { Controller, Get, Inject, ServiceUnavailableException } from '@nestjs/common';

import { DatabaseService } from './database/database.service.js';

type LivenessResponse = Readonly<{
  service: 'api';
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
  constructor(@Inject(DatabaseService) private readonly databaseService: DatabaseService) {}

  @Get('live')
  getLiveness(): LivenessResponse {
    return this.createLivenessResponse();
  }

  @Get()
  async getHealth(): Promise<ReadinessResponse> {
    return this.getReadiness();
  }

  @Get('ready')
  async getReadiness(): Promise<ReadinessResponse> {
    try {
      const ready = await this.databaseService.isReady();
      if (!ready) {
        throw new Error('Database returned an unexpected healthcheck result.');
      }

      return {
        ...this.createLivenessResponse(),
        database: 'connected',
      };
    } catch {
      throw new ServiceUnavailableException({
        database: 'unavailable',
        service: 'api',
        status: 'degraded',
        timestamp: new Date().toISOString(),
        version: '0.2.0',
      });
    }
  }

  private createLivenessResponse(): LivenessResponse {
    return {
      service: 'api',
      status: 'ok',
      timestamp: new Date().toISOString(),
      version: '0.2.0',
    };
  }
}
