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
  assertServiceProductionReadiness('webhook-ingress');

  const security = parseHttpSecurityEnvironment();

  const productionLike =
    security.appEnvironment === 'staging' || security.appEnvironment === 'production';

  const app = await NestFactory.create<NestExpressApplication>(AppModule, {
    abortOnError: true,

    rawBody: true,
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

  /*
   * Keep Nest's built-in parser enabled because rawBody is
   * required for Meta HMAC verification. useBodyParser()
   * preserves rawBody while applying an explicit size limit.
   */
  app.useBodyParser('json', {
    limit: `${security.webhookBodyLimitBytes}b`,
  });

  app.enableShutdownHooks();

  const server = app.getHttpServer() as Server;

  server.requestTimeout = security.requestTimeoutMs;

  server.headersTimeout = security.headersTimeoutMs;

  server.keepAliveTimeout = security.keepAliveTimeoutMs;

  server.maxHeadersCount = security.maxHeadersCount;

  const port = Number(process.env.PORT ?? 3002);

  await app.listen(port, '0.0.0.0');

  console.log(
    JSON.stringify({
      event: 'service.started',

      port,

      service: 'webhook-ingress',

      appEnvironment: security.appEnvironment,

      metaWebhookConfigured: Boolean(
        process.env.META_APP_SECRET?.trim() && process.env.META_WEBHOOK_VERIFY_TOKEN?.trim(),
      ),

      timestamp: new Date().toISOString(),
    }),
  );
}

void bootstrap();
