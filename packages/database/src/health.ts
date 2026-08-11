import type { CrmDatabaseClient } from './client.js';

export async function checkDatabaseConnection(client: CrmDatabaseClient): Promise<boolean> {
  const rows = await client.$queryRaw<Array<{ value: number }>>`SELECT 1::int AS value`;
  return rows[0]?.value === 1;
}
