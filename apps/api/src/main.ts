import './load-environment.js';
import 'reflect-metadata';

import type { Server } from 'node:http';

import helmet from 'helmet';

import { NestFactory } from '@nestjs/core';

import type { NestExpressApplication } from '@nestjs/platform-express';

import { assertServiceProductionReadiness, parseHttpSecurityEnvironment } from '@crm/config';

import { AppModule } from './app.module.js';

type HeaderResponse = Readonly<{
  setHeader(
    name: string,

    value: string,
  ): void;
}>;

async function bootstrap(): Promise<void> {
  assertServiceProductionReadiness('api');

  const security = parseHttpSecurityEnvironment();

  const productionLike =
    security.appEnvironment === 'staging' || security.appEnvironment === 'production';

  const app = await NestFactory.create<NestExpressApplication>(AppModule, {
    abortOnError: true,
  });

  app.set('trust proxy', security.trustProxyHops);

  app.use(
    helmet({
      contentSecurityPolicy: false,

      crossOriginEmbedderPolicy: false,

      strictTransportSecurity: productionLike
        ? {
            maxAge: 31536000,

            includeSubDomains: true,
          }
        : false,
    }),
  );

  app.use(
    (
      _request: unknown,

      response: HeaderResponse,

      next: () => void,
    ) => {
      response.setHeader('Cache-Control', 'no-store');

      response.setHeader('X-Robots-Tag', 'noindex, nofollow');

      next();
    },
  );

  app.enableCors({
    origin: [...security.corsAllowedOrigins],

    credentials: false,

    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],

    allowedHeaders: ['Authorization', 'Content-Type', 'Idempotency-Key'],

    maxAge: 600,
  });

  app.useBodyParser('json', {
    limit: `${security.apiBodyLimitBytes}b`,
  });

  app.useBodyParser('urlencoded', {
    limit: `${security.apiBodyLimitBytes}b`,

    extended: false,
  });

  app.enableShutdownHooks();

  app.setGlobalPrefix('api/v1');

  const server = app.getHttpServer() as Server;

  server.requestTimeout = security.requestTimeoutMs;

  server.headersTimeout = security.headersTimeoutMs;

  server.keepAliveTimeout = security.keepAliveTimeoutMs;

  server.maxHeadersCount = security.maxHeadersCount;

  const port = Number(process.env.PORT ?? 3001);

  await app.listen(port, '0.0.0.0');

  console.log(
    JSON.stringify({
      event: 'service.started',

      port,

      service: 'api',

      appEnvironment: security.appEnvironment,

      trustProxyHops: security.trustProxyHops,

      corsOriginCount: security.corsAllowedOrigins.length,

      timestamp: new Date().toISOString(),
    }),
  );
}

void bootstrap();
