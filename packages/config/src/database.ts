import { z } from 'zod';

const postgresUrlSchema = z
  .string()
  .min(1)
  .refine(
    (value) => value.startsWith('postgresql://') || value.startsWith('postgres://'),
    'A URL deve usar postgresql:// ou postgres://',
  );

export const databaseEnvironmentSchema = z.object({
  DATABASE_CONNECTION_TIMEOUT_MS: z.coerce.number().int().positive().default(5_000),
  DATABASE_IDLE_TIMEOUT_MS: z.coerce.number().int().positive().default(300_000),
  DATABASE_MAX_CONNECTIONS: z.coerce.number().int().min(1).max(100).default(10),
  DATABASE_URL: postgresUrlSchema,
  NODE_ENV: z.enum(['development', 'staging', 'production', 'test']).default('development'),
});

export type DatabaseEnvironment = z.infer<typeof databaseEnvironmentSchema>;

export function parseDatabaseEnvironment(
  environment: NodeJS.ProcessEnv = process.env,
): DatabaseEnvironment {
  return databaseEnvironmentSchema.parse(environment);
}
