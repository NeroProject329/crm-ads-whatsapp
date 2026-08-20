import { Injectable, type OnApplicationShutdown } from '@nestjs/common';

import {
  checkDatabaseConnection,
  createDatabaseClient,
  type CrmDatabaseClient,
} from '@crm/database';

@Injectable()
export class DatabaseService implements OnApplicationShutdown {
  readonly client: CrmDatabaseClient = createDatabaseClient();

  async isReady(): Promise<boolean> {
    return checkDatabaseConnection(this.client);
  }

  async onApplicationShutdown(): Promise<void> {
    await this.client.$disconnect();
  }
}
