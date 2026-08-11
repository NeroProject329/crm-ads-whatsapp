import { PrismaPg } from '@prisma/adapter-pg';
import { parseDatabaseEnvironment, type DatabaseEnvironment } from '@crm/config';

import { PrismaClient } from './generated/prisma/client.js';

export type CrmDatabaseClient = PrismaClient;

export function createDatabaseClient(
  environment: DatabaseEnvironment = parseDatabaseEnvironment(),
): CrmDatabaseClient {
  const adapter = new PrismaPg({
    connectionString: environment.DATABASE_URL,
    connectionTimeoutMillis: environment.DATABASE_CONNECTION_TIMEOUT_MS,
    idleTimeoutMillis: environment.DATABASE_IDLE_TIMEOUT_MS,
    max: environment.DATABASE_MAX_CONNECTIONS,
  });

  return new PrismaClient({
    adapter,
    log: environment.NODE_ENV === 'development' ? ['warn', 'error'] : ['error'],
  });
}
