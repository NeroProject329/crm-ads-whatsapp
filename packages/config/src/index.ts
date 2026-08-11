export {
  databaseEnvironmentSchema,
  parseDatabaseEnvironment,
  type DatabaseEnvironment,
} from './database.js';

export const runtimeEnvironments = ['development', 'staging', 'production', 'test'] as const;
export type RuntimeEnvironment = (typeof runtimeEnvironments)[number];
