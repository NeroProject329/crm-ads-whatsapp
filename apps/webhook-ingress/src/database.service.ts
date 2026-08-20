import { Injectable, type OnApplicationShutdown } from '@nestjs/common';

import { createDatabaseClient, type CrmDatabaseClient } from '@crm/database';

@Injectable()
export class DatabaseService implements OnApplicationShutdown {
  readonly client: CrmDatabaseClient = createDatabaseClient();

  async onApplicationShutdown(): Promise<void> {
    await this.client.$disconnect();
  }
}
