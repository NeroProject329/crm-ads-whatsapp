import { config } from 'dotenv';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
config({ path: resolve(scriptDirectory, '../../../.env'), quiet: true });

const { checkDatabaseConnection, createDatabaseClient } = await import('../src/index.js');
const client = createDatabaseClient();

try {
  const healthy = await checkDatabaseConnection(client);
  if (!healthy) {
    throw new Error('SELECT 1 did not return the expected value.');
  }

  console.log(
    JSON.stringify({
      event: 'database.healthcheck.succeeded',
      timestamp: new Date().toISOString(),
    }),
  );
} finally {
  await client.$disconnect();
}
