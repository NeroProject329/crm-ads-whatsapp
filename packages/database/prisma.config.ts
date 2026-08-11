import { config } from 'dotenv';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'prisma/config';

const packageDirectory = dirname(fileURLToPath(import.meta.url));
config({ path: resolve(packageDirectory, '../../.env'), quiet: true });

const defaultDatabaseUrl = 'postgresql://localhost:5432/crm_ads_whatsapp';
const defaultShadowDatabaseUrl = 'postgresql://localhost:5432/crm_ads_whatsapp_shadow';

export default defineConfig({
  schema: 'prisma/schema.prisma',

  migrations: {
    path: 'prisma/migrations',
    seed: 'tsx prisma/seed.ts',
  },

  datasource: {
    url: process.env.DATABASE_URL ?? defaultDatabaseUrl,
    shadowDatabaseUrl: process.env.SHADOW_DATABASE_URL ?? defaultShadowDatabaseUrl,
  },
});
