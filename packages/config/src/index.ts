export { authEnvironmentSchema, parseAuthEnvironment, type AuthEnvironment } from './auth.js';
export {
  databaseEnvironmentSchema,
  parseDatabaseEnvironment,
  type DatabaseEnvironment,
} from './database.js';

export const runtimeEnvironments = ['development', 'staging', 'production', 'test'] as const;
export type RuntimeEnvironment = (typeof runtimeEnvironments)[number];
export { parseHttpSecurityEnvironment, type HttpSecurityEnvironment } from './http-security.js';
export {
  assertServiceProductionReadiness,
  type ProductionService,
} from './production-readiness.js';
