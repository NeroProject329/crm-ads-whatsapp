import 'reflect-metadata';

import { NestFactory } from '@nestjs/core';

import { AppModule } from './app.module.js';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule, {
    abortOnError: true,
  });

  app.enableShutdownHooks();
  const port = Number(process.env.PORT ?? 3002);
  await app.listen(port, '0.0.0.0');

  console.log(
    JSON.stringify({
      event: 'service.started',
      port,
      service: 'webhook-ingress',
      timestamp: new Date().toISOString(),
    }),
  );
}

void bootstrap();
