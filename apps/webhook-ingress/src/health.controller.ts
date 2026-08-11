import { Controller, Get } from '@nestjs/common';

type HealthResponse = Readonly<{
  service: 'webhook-ingress';
  status: 'ok';
  timestamp: string;
  version: '0.1.0';
}>;

@Controller('health')
export class HealthController {
  @Get()
  getHealth(): HealthResponse {
    return {
      service: 'webhook-ingress',
      status: 'ok',
      timestamp: new Date().toISOString(),
      version: '0.1.0',
    };
  }
}
