import { config } from 'dotenv';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const appDirectory = resolve(dirname(fileURLToPath(import.meta.url)), '..');

config({
  path: resolve(appDirectory, '../../.env'),

  quiet: true,
});
