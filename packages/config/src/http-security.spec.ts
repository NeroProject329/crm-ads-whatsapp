import { describe, expect, it } from 'vitest';

import { parseHttpSecurityEnvironment } from './http-security.js';

import { assertServiceProductionReadiness } from './production-readiness.js';

const productionBase = {
  NODE_ENV: 'production',

  APP_ENV: 'production',

  DATABASE_URL: 'postgresql://crm:password@postgres.internal:5432/crm',

  API_CORS_ALLOWED_ORIGINS: 'https://crm.example.com',

  AUTH_ACCESS_TOKEN_SECRET: 'stage12-access-secret-0123456789abcdef',

  AUTH_REFRESH_TOKEN_PEPPER: 'stage12-refresh-pepper-0123456789abcdef',

  META_APP_SECRET: 'stage12-meta-secret-0123456789abcdef',

  META_WEBHOOK_VERIFY_TOKEN: 'stage12-webhook-token-0123456789',

  META_GRAPH_API_VERSION: 'v99.0',

  META_ACCESS_TOKEN: 'stage12-meta-token-0123456789abcdef',

  ONESIGNAL_APP_ID: 'stage12-onesignal-app',

  ONESIGNAL_API_KEY: 'stage12-onesignal-key-0123456789',

  NEXT_PUBLIC_ONESIGNAL_APP_ID: 'stage12-public-onesignal-app',
} satisfies NodeJS.ProcessEnv;

describe('Stage 12 production security', () => {
  it('uses local development CORS defaults', () => {
    const config = parseHttpSecurityEnvironment({
      NODE_ENV: 'development',

      APP_ENV: 'development',
    });

    expect(config.corsAllowedOrigins).toContain('http://localhost:3000');
  });

  it('requires explicit HTTPS CORS in production', () => {
    expect(() =>
      parseHttpSecurityEnvironment({
        NODE_ENV: 'production',

        APP_ENV: 'production',

        API_CORS_ALLOWED_ORIGINS: '',
      }),
    ).toThrow();
  });

  it('rejects HTTP origin in production', () => {
    expect(() =>
      parseHttpSecurityEnvironment({
        NODE_ENV: 'production',

        APP_ENV: 'production',

        API_CORS_ALLOWED_ORIGINS: 'http://crm.example.com',
      }),
    ).toThrow();
  });

  it('rejects CORS origins containing a path', () => {
    expect(() =>
      parseHttpSecurityEnvironment({
        NODE_ENV: 'production',

        APP_ENV: 'production',

        API_CORS_ALLOWED_ORIGINS: 'https://crm.example.com/app',
      }),
    ).toThrow();
  });

  it('rejects headers timeout above request timeout', () => {
    expect(() =>
      parseHttpSecurityEnvironment({
        NODE_ENV: 'development',

        HTTP_REQUEST_TIMEOUT_MS: '10000',

        HTTP_HEADERS_TIMEOUT_MS: '15000',
      }),
    ).toThrow();
  });

  it('accepts complete production API environment', () => {
    expect(() => assertServiceProductionReadiness('api', productionBase)).not.toThrow();
  });

  it('rejects equal access and refresh secrets', () => {
    expect(() =>
      assertServiceProductionReadiness('api', {
        ...productionBase,

        AUTH_REFRESH_TOKEN_PEPPER: productionBase.AUTH_ACCESS_TOKEN_SECRET,
      }),
    ).toThrow();
  });

  it('rejects localhost PostgreSQL in production', () => {
    expect(() =>
      assertServiceProductionReadiness('api', {
        ...productionBase,

        DATABASE_URL: 'postgresql://crm:password@localhost:5432/crm',
      }),
    ).toThrow();
  });

  it('requires Meta webhook secrets', () => {
    expect(() =>
      assertServiceProductionReadiness('webhook-ingress', {
        ...productionBase,

        META_APP_SECRET: '',
      }),
    ).toThrow();
  });

  it('requires provider configuration for worker', () => {
    expect(() => assertServiceProductionReadiness('worker', productionBase)).not.toThrow();

    expect(() =>
      assertServiceProductionReadiness('worker', {
        ...productionBase,

        META_ACCESS_TOKEN: '',
      }),
    ).toThrow();
  });

  it('requires production NODE_ENV for staging', () => {
    expect(() =>
      assertServiceProductionReadiness('site-monitor-worker', {
        ...productionBase,

        APP_ENV: 'staging',

        NODE_ENV: 'development',
      }),
    ).toThrow();
  });

  it('does not require production secrets during development', () => {
    expect(() =>
      assertServiceProductionReadiness('worker', {
        NODE_ENV: 'development',

        APP_ENV: 'development',
      }),
    ).not.toThrow();
  });
});
