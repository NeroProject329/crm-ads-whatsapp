import { z } from 'zod';

const rawHttpSecurityEnvironmentSchema = z.object({
  APP_ENV: z.enum(['development', 'test', 'staging', 'production']).default('development'),

  API_CORS_ALLOWED_ORIGINS: z.string().default(''),

  HTTP_TRUST_PROXY_HOPS: z.coerce.number().int().min(0).max(5).default(0),

  API_BODY_LIMIT_BYTES: z.coerce
    .number()
    .int()
    .min(1024)
    .max(5 * 1024 * 1024)
    .default(256 * 1024),

  WEBHOOK_BODY_LIMIT_BYTES: z.coerce
    .number()
    .int()
    .min(1024)
    .max(10 * 1024 * 1024)
    .default(1024 * 1024),

  HTTP_REQUEST_TIMEOUT_MS: z.coerce.number().int().min(5000).max(120000).default(30000),

  HTTP_HEADERS_TIMEOUT_MS: z.coerce.number().int().min(5000).max(60000).default(15000),

  HTTP_KEEP_ALIVE_TIMEOUT_MS: z.coerce.number().int().min(1000).max(120000).default(5000),

  HTTP_MAX_HEADERS_COUNT: z.coerce.number().int().min(20).max(500).default(100),

  API_RATE_LIMIT_TTL_MS: z.coerce.number().int().min(1000).max(3600000).default(60000),

  API_RATE_LIMIT_DEFAULT: z.coerce.number().int().min(10).max(10000).default(300),

  AUTH_LOGIN_RATE_LIMIT: z.coerce.number().int().min(1).max(100).default(10),

  AUTH_REFRESH_RATE_LIMIT: z.coerce.number().int().min(1).max(500).default(30),
});

export type HttpSecurityEnvironment = Readonly<{
  appEnvironment: 'development' | 'test' | 'staging' | 'production';

  corsAllowedOrigins: readonly string[];

  trustProxyHops: number;

  apiBodyLimitBytes: number;

  webhookBodyLimitBytes: number;

  requestTimeoutMs: number;

  headersTimeoutMs: number;

  keepAliveTimeoutMs: number;

  maxHeadersCount: number;

  apiRateLimitTtlMs: number;

  apiRateLimitDefault: number;

  authLoginRateLimit: number;

  authRefreshRateLimit: number;
}>;

function parseOrigins(
  raw: string,

  productionLike: boolean,
): readonly string[] {
  const values = raw
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);

  const effective =
    values.length > 0
      ? values
      : productionLike
        ? []
        : ['http://localhost:3000', 'http://127.0.0.1:3000'];

  if (productionLike && effective.length === 0) {
    throw new Error('API_CORS_ALLOWED_ORIGINS is required in staging and production.');
  }

  const normalized = effective.map((value) => {
    const url = new URL(value);

    if (url.origin !== value) {
      throw new Error(`CORS origin must not contain path/query/hash: ${value}`);
    }

    if (productionLike && url.protocol !== 'https:') {
      throw new Error(`CORS origin must use HTTPS in staging/production: ${value}`);
    }

    return url.origin;
  });

  return Array.from(new Set(normalized));
}

export function parseHttpSecurityEnvironment(
  environment: NodeJS.ProcessEnv = process.env,
): HttpSecurityEnvironment {
  const fallbackAppEnvironment =
    environment.NODE_ENV === 'test'
      ? 'test'
      : environment.NODE_ENV === 'production'
        ? 'production'
        : 'development';

  const parsed = rawHttpSecurityEnvironmentSchema.parse({
    ...environment,

    APP_ENV: environment.APP_ENV?.trim() || fallbackAppEnvironment,
  });

  const productionLike = parsed.APP_ENV === 'staging' || parsed.APP_ENV === 'production';

  if (parsed.HTTP_HEADERS_TIMEOUT_MS > parsed.HTTP_REQUEST_TIMEOUT_MS) {
    throw new Error('HTTP_HEADERS_TIMEOUT_MS must be <= HTTP_REQUEST_TIMEOUT_MS.');
  }

  return {
    appEnvironment: parsed.APP_ENV,

    corsAllowedOrigins: parseOrigins(parsed.API_CORS_ALLOWED_ORIGINS, productionLike),

    trustProxyHops: parsed.HTTP_TRUST_PROXY_HOPS,

    apiBodyLimitBytes: parsed.API_BODY_LIMIT_BYTES,

    webhookBodyLimitBytes: parsed.WEBHOOK_BODY_LIMIT_BYTES,

    requestTimeoutMs: parsed.HTTP_REQUEST_TIMEOUT_MS,

    headersTimeoutMs: parsed.HTTP_HEADERS_TIMEOUT_MS,

    keepAliveTimeoutMs: parsed.HTTP_KEEP_ALIVE_TIMEOUT_MS,

    maxHeadersCount: parsed.HTTP_MAX_HEADERS_COUNT,

    apiRateLimitTtlMs: parsed.API_RATE_LIMIT_TTL_MS,

    apiRateLimitDefault: parsed.API_RATE_LIMIT_DEFAULT,

    authLoginRateLimit: parsed.AUTH_LOGIN_RATE_LIMIT,

    authRefreshRateLimit: parsed.AUTH_REFRESH_RATE_LIMIT,
  };
}
