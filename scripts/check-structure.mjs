import { access } from 'node:fs/promises';

const requiredPaths = [
  'apps/web/package.json',
  'apps/api/package.json',
  'apps/webhook-ingress/package.json',
  'apps/worker/package.json',
  'apps/site-monitor-worker/package.json',
  'packages/contracts/package.json',
  'packages/database/package.json',
  'packages/queue/package.json',
  'packages/whatsapp/package.json',
  'pnpm-workspace.yaml',
  'turbo.json',
];

for (const path of requiredPaths) {
  await access(path);
}

console.log(
  JSON.stringify({
    checkedPaths: requiredPaths.length,
    event: 'monorepo.structure-valid',
    status: 'ok',
  }),
);
