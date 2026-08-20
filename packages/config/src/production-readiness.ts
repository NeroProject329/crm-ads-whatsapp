import { parseAuthEnvironment } from './auth.js';

import { parseHttpSecurityEnvironment } from './http-security.js';

export type ProductionService =
  'api' | 'webhook-ingress' | 'worker' | 'site-monitor-worker' | 'web';

function required(
  environment: NodeJS.ProcessEnv,

  name: string,

  minimumLength: number = 1,
): string {
  const value = environment[name]?.trim();

  if (!value || value.length < minimumLength) {
    throw new Error(`${name} is required for staging/production.`);
  }

  const lowered = value.toLowerCase();

  if (
    lowered.includes('change_me') ||
    lowered.includes('placeholder') ||
    lowered.includes('example-secret') ||
    lowered === 'test'
  ) {
    throw new Error(`${name} contains a placeholder value.`);
  }

  return value;
}

function requireDatabaseUrl(environment: NodeJS.ProcessEnv): void {
  const raw = required(environment, 'DATABASE_URL', 10);

  const url = new URL(raw);

  if (url.protocol !== 'postgresql:' && url.protocol !== 'postgres:') {
    throw new Error('DATABASE_URL must use PostgreSQL.');
  }

  if (url.hostname === 'localhost' || url.hostname === '127.0.0.1') {
    throw new Error('DATABASE_URL cannot use localhost in staging/production.');
  }
}

function assertGraphVersion(environment: NodeJS.ProcessEnv): void {
  const version = required(environment, 'META_GRAPH_API_VERSION');

  if (!/^v\d+\.\d+$/.test(version)) {
    throw new Error('META_GRAPH_API_VERSION must look like vXX.X.');
  }
}

export function assertServiceProductionReadiness(
  service: ProductionService,

  environment: NodeJS.ProcessEnv = process.env,
): void {
  const http = parseHttpSecurityEnvironment(environment);

  const productionLike = http.appEnvironment === 'staging' || http.appEnvironment === 'production';

  if (!productionLike) {
    return;
  }

  if (environment.NODE_ENV !== 'production') {
    throw new Error('NODE_ENV must be production when APP_ENV is staging or production.');
  }

  if (service !== 'web') {
    requireDatabaseUrl(environment);
  }

  if (service === 'api') {
    const auth = parseAuthEnvironment(environment);

    if (auth.AUTH_ACCESS_TOKEN_SECRET === auth.AUTH_REFRESH_TOKEN_PEPPER) {
      throw new Error('AUTH_ACCESS_TOKEN_SECRET and AUTH_REFRESH_TOKEN_PEPPER must be different.');
    }

    if (http.corsAllowedOrigins.length === 0) {
      throw new Error('API requires at least one CORS origin.');
    }
  }

  if (service === 'webhook-ingress') {
    required(environment, 'META_APP_SECRET', 32);

    required(environment, 'META_WEBHOOK_VERIFY_TOKEN', 16);
  }

  if (service === 'worker') {
    assertGraphVersion(environment);

    required(environment, 'META_ACCESS_TOKEN', 20);

    required(environment, 'ONESIGNAL_APP_ID', 8);

    required(environment, 'ONESIGNAL_API_KEY', 20);
  }

  if (service === 'web') {
    required(environment, 'NEXT_PUBLIC_ONESIGNAL_APP_ID', 8);
  }
}
