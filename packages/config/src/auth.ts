import { z } from 'zod';

const secretSchema = z.string().min(32);

export const authEnvironmentSchema = z.object({
  AUTH_ACCESS_TOKEN_AUDIENCE: z.string().trim().min(1).default('crm-ads-whatsapp'),
  AUTH_ACCESS_TOKEN_ISSUER: z.string().trim().min(1).default('crm-ads-whatsapp-api'),
  AUTH_ACCESS_TOKEN_SECRET: secretSchema,
  AUTH_ACCESS_TOKEN_TTL_SECONDS: z.coerce.number().int().min(60).max(3600).default(900),
  AUTH_LOGIN_LOCK_SECONDS: z.coerce.number().int().min(60).max(86400).default(900),
  AUTH_MAX_FAILED_LOGIN_ATTEMPTS: z.coerce.number().int().min(3).max(20).default(5),
  AUTH_REFRESH_TOKEN_PEPPER: secretSchema,
  AUTH_REFRESH_TOKEN_TTL_SECONDS: z.coerce
    .number()
    .int()
    .min(3600)
    .max(60 * 60 * 24 * 90)
    .default(60 * 60 * 24 * 30),
});

export type AuthEnvironment = z.infer<typeof authEnvironmentSchema>;

export function parseAuthEnvironment(
  environment: NodeJS.ProcessEnv = process.env,
): AuthEnvironment {
  return authEnvironmentSchema.parse(environment);
}
