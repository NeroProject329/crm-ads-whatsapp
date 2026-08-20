import '../src/load-environment.js';

import assert from 'node:assert/strict';

import { createHash, createHmac, randomUUID } from 'node:crypto';

import { spawn, spawnSync } from 'node:child_process';

import { createServer } from 'node:net';

import { dirname, resolve } from 'node:path';

import { fileURLToPath } from 'node:url';

import { createDatabaseClient } from '@crm/database';

import { WhatsAppOutboundDispatcherService } from '../src/whatsapp-outbound-dispatcher.service.js';

import type { WhatsAppRuntimeConfig } from '../src/whatsapp-runtime.config.js';

const scriptDirectory = dirname(fileURLToPath(import.meta.url));

const repositoryRoot = resolve(scriptDirectory, '../../..');

const database = createDatabaseClient();

const unique = randomUUID().replaceAll('-', '').slice(0, 12);

const organizationSlug = `stage12-runtime-${unique}`;

const allowedOrigin = 'https://allowed.stage12.test';

const metaAppSecret = 'stage12-meta-secret-0123456789abcdef';

const verifyToken = 'stage12-verify-token-0123456789';

const accessSecret = 'stage12-access-secret-0123456789abcdef';

const refreshPepper = 'stage12-refresh-pepper-0123456789abcdef';

const outboundConfig: WhatsAppRuntimeConfig = {
  inboxIntervalMs: 1000,

  inboxLeaseMs: 30000,

  inboxMaxClaimsPerTick: 25,

  inboxMaxAttempts: 8,

  inboxRetryBaseMs: 1000,

  outboundIntervalMs: 1000,

  outboundLeaseMs: 30000,

  outboundMaxClaimsPerTick: 25,

  outboundMaxAttempts: 8,

  outboundRetryBaseMs: 2000,

  outboundDisabledRetryMs: 30000,
};

type ManagedProcess = Readonly<{
  child: ReturnType<typeof spawn>;

  getLogs: () => string;
}>;

function log(
  event: string,

  extra: Record<string, unknown> = {},
): void {
  console.log(
    JSON.stringify({
      event,

      timestamp: new Date().toISOString(),

      ...extra,
    }),
  );
}

function sleep(milliseconds: number): Promise<void> {
  return new Promise((resolvePromise) => {
    setTimeout(resolvePromise, milliseconds);
  });
}

async function getFreePort(): Promise<number> {
  const server = createServer();

  await new Promise<void>((resolvePromise, reject) => {
    server.once('error', reject);

    server.listen(0, '127.0.0.1', () => {
      resolvePromise();
    });
  });

  const address = server.address();

  assert.ok(address && typeof address !== 'string');

  const port = address.port;

  await new Promise<void>((resolvePromise, reject) => {
    server.close((error) => {
      if (error) {
        reject(error);

        return;
      }

      resolvePromise();
    });
  });

  return port;
}

function startService(
  entry: string,

  environment: NodeJS.ProcessEnv,
): ManagedProcess {
  const child = spawn(process.execPath, [entry], {
    cwd: repositoryRoot,

    env: {
      ...process.env,

      ...environment,
    },

    stdio: ['ignore', 'pipe', 'pipe'],
  });

  let logs = '';

  child.stdout?.on('data', (chunk: Buffer) => {
    logs += chunk.toString();
  });

  child.stderr?.on('data', (chunk: Buffer) => {
    logs += chunk.toString();
  });

  return {
    child,

    getLogs: () => logs,
  };
}

async function stopService(service: ManagedProcess): Promise<void> {
  if (service.child.exitCode !== null) {
    return;
  }

  service.child.kill('SIGTERM');

  for (let attempt = 0; attempt < 20; attempt += 1) {
    if (service.child.exitCode !== null) {
      return;
    }

    await sleep(100);
  }

  if (service.child.exitCode === null) {
    service.child.kill();
  }
}

async function waitForHttp(
  service: ManagedProcess,

  url: string,
): Promise<void> {
  for (let attempt = 0; attempt < 80; attempt += 1) {
    if (service.child.exitCode !== null) {
      throw new Error(`Service exited before becoming ready.` + `\n${service.getLogs()}`);
    }

    try {
      const response = await fetch(url, {
        signal: AbortSignal.timeout(1000),
      });

      if (response.status === 200) {
        return;
      }
    } catch {
      // startup retry
    }

    await sleep(125);
  }

  throw new Error(`Service did not become ready: ${url}` + `\n${service.getLogs()}`);
}

function runProductionValidators(): void {
  const common = {
    ...process.env,

    NODE_ENV: 'production',

    APP_ENV: 'staging',

    DATABASE_URL: 'postgresql://crm:password@postgres.internal:5432/crm',

    API_CORS_ALLOWED_ORIGINS: 'https://crm.stage12.test',

    AUTH_ACCESS_TOKEN_SECRET: accessSecret,

    AUTH_REFRESH_TOKEN_PEPPER: refreshPepper,

    META_APP_SECRET: metaAppSecret,

    META_WEBHOOK_VERIFY_TOKEN: verifyToken,

    META_GRAPH_API_VERSION: 'v99.0',

    META_ACCESS_TOKEN: 'stage12-meta-access-token-0123456789abcdef',

    ONESIGNAL_APP_ID: 'stage12-onesignal-app',

    ONESIGNAL_API_KEY: 'stage12-onesignal-key-0123456789abcdef',

    NEXT_PUBLIC_ONESIGNAL_APP_ID: 'stage12-public-onesignal-app',
  };

  for (const service of ['api', 'webhook-ingress', 'worker', 'site-monitor-worker', 'web']) {
    const result = spawnSync(
      process.execPath,
      ['scripts/validate-production-environment.mjs', service],
      {
        cwd: repositoryRoot,

        env: common,

        encoding: 'utf8',
      },
    );

    assert.equal(
      result.status,
      0,
      `${service} validator failed:\n${result.stdout}\n${result.stderr}`,
    );
  }

  const invalid = spawnSync(
    process.execPath,
    ['scripts/validate-production-environment.mjs', 'api'],
    {
      cwd: repositoryRoot,

      env: {
        ...common,

        AUTH_REFRESH_TOKEN_PEPPER: accessSecret,
      },

      encoding: 'utf8',
    },
  );

  assert.notEqual(invalid.status, 0);

  log('stage12.production_environment_validation.passed');
}

async function verifyApiSecurity(): Promise<void> {
  const databaseUrl = process.env.DATABASE_URL?.trim();

  assert.ok(databaseUrl, 'DATABASE_URL is required for Stage 12 runtime.');

  const port = await getFreePort();

  const service = startService('apps/api/dist/main.js', {
    NODE_ENV: 'test',

    APP_ENV: 'test',

    PORT: String(port),

    DATABASE_URL: databaseUrl,

    AUTH_ACCESS_TOKEN_SECRET: accessSecret,

    AUTH_REFRESH_TOKEN_PEPPER: refreshPepper,

    API_CORS_ALLOWED_ORIGINS: allowedOrigin,

    HTTP_TRUST_PROXY_HOPS: '0',

    API_BODY_LIMIT_BYTES: '1024',

    HTTP_REQUEST_TIMEOUT_MS: '10000',

    HTTP_HEADERS_TIMEOUT_MS: '5000',

    HTTP_KEEP_ALIVE_TIMEOUT_MS: '2000',

    HTTP_MAX_HEADERS_COUNT: '50',

    API_RATE_LIMIT_TTL_MS: '60000',

    API_RATE_LIMIT_DEFAULT: '100',

    AUTH_LOGIN_RATE_LIMIT: '2',

    AUTH_REFRESH_RATE_LIMIT: '3',
  });

  try {
    const base = `http://127.0.0.1:${port}`;

    await waitForHttp(service, `${base}/api/v1/health/live`);

    const live = await fetch(`${base}/api/v1/health/live`, {
      headers: {
        Origin: allowedOrigin,
      },
    });

    assert.equal(live.status, 200);

    assert.equal(live.headers.get('access-control-allow-origin'), allowedOrigin);

    assert.equal(live.headers.get('x-content-type-options'), 'nosniff');

    assert.equal(live.headers.get('x-frame-options'), 'SAMEORIGIN');

    assert.equal(live.headers.get('x-robots-tag'), 'noindex, nofollow');

    assert.ok(live.headers.get('cache-control')?.includes('no-store'));

    assert.equal(live.headers.get('x-powered-by'), null);

    const ready = await fetch(`${base}/api/v1/health/ready`);

    assert.equal(ready.status, 200);

    const disallowed = await fetch(`${base}/api/v1/health/live`, {
      headers: {
        Origin: 'https://evil.stage12.test',
      },
    });

    assert.equal(disallowed.status, 200);

    assert.equal(disallowed.headers.get('access-control-allow-origin'), null);

    const oversized = await fetch(`${base}/api/v1/auth/login`, {
      method: 'POST',

      headers: {
        'content-type': 'application/json',
      },

      body: JSON.stringify({
        padding: 'x'.repeat(4096),
      }),
    });

    assert.equal(oversized.status, 413);

    const rateStatuses: number[] = [];

    for (let index = 0; index < 3; index += 1) {
      const response = await fetch(`${base}/api/v1/auth/login`, {
        method: 'POST',

        headers: {
          'content-type': 'application/json',
        },

        body: '{}',
      });

      rateStatuses.push(response.status);
    }

    assert.deepEqual(rateStatuses, [400, 400, 429]);

    log('stage12.api_http_security.passed');
  } finally {
    await stopService(service);
  }
}

async function verifyWebhookSecurity(): Promise<void> {
  const databaseUrl = process.env.DATABASE_URL?.trim();

  assert.ok(databaseUrl);

  const port = await getFreePort();

  const service = startService('apps/webhook-ingress/dist/main.js', {
    NODE_ENV: 'test',

    APP_ENV: 'test',

    PORT: String(port),

    DATABASE_URL: databaseUrl,

    META_APP_SECRET: metaAppSecret,

    META_WEBHOOK_VERIFY_TOKEN: verifyToken,

    WEBHOOK_BODY_LIMIT_BYTES: '1024',

    HTTP_REQUEST_TIMEOUT_MS: '10000',

    HTTP_HEADERS_TIMEOUT_MS: '5000',

    HTTP_KEEP_ALIVE_TIMEOUT_MS: '2000',

    HTTP_MAX_HEADERS_COUNT: '50',
  });

  let webhookPayloadHash: string | null = null;

  try {
    const base = `http://127.0.0.1:${port}`;

    await waitForHttp(service, `${base}/health/live`);

    const live = await fetch(`${base}/health/live`);

    assert.equal(live.status, 200);

    assert.equal(live.headers.get('x-content-type-options'), 'nosniff');

    assert.ok(live.headers.get('cache-control')?.includes('no-store'));

    const ready = await fetch(`${base}/health/ready`);

    assert.equal(ready.status, 200);

    const challenge = `stage12-${unique}`;

    const verification = await fetch(
      `${base}/webhooks/meta/whatsapp` +
        `?hub.mode=subscribe` +
        `&hub.verify_token=${encodeURIComponent(verifyToken)}` +
        `&hub.challenge=${encodeURIComponent(challenge)}`,
    );

    assert.equal(verification.status, 200);

    assert.equal(await verification.text(), challenge);

    const denied = await fetch(
      `${base}/webhooks/meta/whatsapp` +
        `?hub.mode=subscribe` +
        `&hub.verify_token=wrong-token` +
        `&hub.challenge=${encodeURIComponent(challenge)}`,
    );

    assert.equal(denied.status, 403);

    const raw = JSON.stringify({
      object: 'stage12_security_test',

      nonce: unique,
    });

    const invalidSignature = await fetch(`${base}/webhooks/meta/whatsapp`, {
      method: 'POST',

      headers: {
        'content-type': 'application/json',

        'x-hub-signature-256': 'sha256=deadbeef',
      },

      body: raw,
    });

    assert.equal(invalidSignature.status, 401);

    const signature = 'sha256=' + createHmac('sha256', metaAppSecret).update(raw).digest('hex');

    webhookPayloadHash = createHash('sha256').update(raw).digest('hex');

    const valid = await fetch(`${base}/webhooks/meta/whatsapp`, {
      method: 'POST',

      headers: {
        'content-type': 'application/json',

        'x-hub-signature-256': signature,
      },

      body: raw,
    });

    assert.equal(valid.status, 200);

    assert.equal(await valid.text(), 'EVENT_RECEIVED');

    const oversizedRaw = JSON.stringify({
      padding: 'x'.repeat(4096),
    });

    const oversized = await fetch(`${base}/webhooks/meta/whatsapp`, {
      method: 'POST',

      headers: {
        'content-type': 'application/json',
      },

      body: oversizedRaw,
    });

    assert.equal(oversized.status, 413);

    const originTest = await fetch(`${base}/health/live`, {
      headers: {
        Origin: 'https://arbitrary.stage12.test',
      },
    });

    assert.equal(originTest.headers.get('access-control-allow-origin'), null);

    log('stage12.webhook_http_security.passed');
  } finally {
    await stopService(service);

    if (webhookPayloadHash) {
      await database.metaWebhookEnvelope.deleteMany({
        where: {
          payloadHash: webhookPayloadHash,
        },
      });
    }
  }
}

async function cleanupOutboundFixture(): Promise<void> {
  const organization = await database.organization.findUnique({
    where: {
      slug: organizationSlug,
    },

    select: {
      id: true,
    },
  });

  if (!organization) {
    return;
  }

  const organizationId = organization.id;

  await database.auditLog.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.whatsAppMessageStatusEvent.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.whatsAppMessage.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.whatsAppConversation.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.whatsAppContact.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.whatsAppNumberHealthEvent.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.whatsAppNumberIncident.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.whatsAppNumberHealthState.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.metaWebhookEnvelope.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.whatsAppNumber.deleteMany({
    where: {
      organizationId,
    },
  });

  await database.organization.delete({
    where: {
      id: organizationId,
    },
  });
}

async function verifyOutboundLeaseSafety(): Promise<void> {
  await cleanupOutboundFixture();

  const organization = await database.organization.create({
    data: {
      name: 'Stage 12 Runtime',

      slug: organizationSlug,

      status: 'ACTIVE',
    },
  });

  const number = await database.whatsAppNumber.create({
    data: {
      organizationId: organization.id,

      displayName: 'Stage 12 Number',

      e164: `+1555${Date.now().toString().slice(-7)}`,

      status: 'ACTIVE',
    },
  });

  const contact = await database.whatsAppContact.create({
    data: {
      organizationId: organization.id,

      waId: `551198${Date.now().toString().slice(-6)}`,

      profileName: 'Stage 12 Contact',
    },
  });

  const conversation = await database.whatsAppConversation.create({
    data: {
      organizationId: organization.id,

      whatsAppNumberId: number.id,

      contactId: contact.id,

      status: 'OPEN',

      lastMessageAt: new Date(),
    },
  });

  const expired = await database.whatsAppMessage.create({
    data: {
      organizationId: organization.id,

      conversationId: conversation.id,

      whatsAppNumberId: number.id,

      contactId: contact.id,

      direction: 'OUTBOUND',

      type: 'TEXT',

      status: 'SENDING',

      clientMessageId: randomUUID(),

      textBody: 'Do not resend me',

      content: {
        stage12: true,
      },

      attempts: 1,

      availableAt: new Date(0),

      lastAttemptAt: new Date(Date.now() - 60000),

      claimedAt: new Date(Date.now() - 60000),

      claimedByWorkerId: 'stage12-dead-worker',

      leaseExpiresAt: new Date(Date.now() - 5000),
    },
  });

  const active = await database.whatsAppMessage.create({
    data: {
      organizationId: organization.id,

      conversationId: conversation.id,

      whatsAppNumberId: number.id,

      contactId: contact.id,

      direction: 'OUTBOUND',

      type: 'TEXT',

      status: 'SENDING',

      clientMessageId: randomUUID(),

      textBody: 'Active lease',

      content: {
        stage12: true,
      },

      attempts: 1,

      availableAt: new Date(0),

      lastAttemptAt: new Date(),

      claimedAt: new Date(),

      claimedByWorkerId: 'stage12-live-worker',

      leaseExpiresAt: new Date(Date.now() + 60000),
    },
  });

  const dispatcher = new WhatsAppOutboundDispatcherService(
    database,
    `stage12-worker-${unique}`,
    outboundConfig,
    null,
  );

  const summary = await dispatcher.runTick();

  assert.equal(summary.claimed, 0);

  const expiredAfter = await database.whatsAppMessage.findUniqueOrThrow({
    where: {
      id: expired.id,
    },
  });

  assert.equal(expiredAfter.status, 'FAILED');

  assert.equal(expiredAfter.errorCode, 'OUTBOUND_DELIVERY_UNKNOWN_AFTER_LEASE');

  assert.equal(expiredAfter.claimedByWorkerId, null);

  assert.equal(expiredAfter.leaseExpiresAt, null);

  const activeAfter = await database.whatsAppMessage.findUniqueOrThrow({
    where: {
      id: active.id,
    },
  });

  assert.equal(activeAfter.status, 'SENDING');

  assert.equal(activeAfter.claimedByWorkerId, 'stage12-live-worker');

  const audit = await database.auditLog.findFirstOrThrow({
    where: {
      organizationId: organization.id,

      action: 'whatsapp.outbound.delivery_unknown_after_lease',

      resourceId: expired.id,
    },
  });

  assert.equal(audit.outcome, 'FAILURE');

  log('stage12.outbound_expired_lease_safety.passed');

  await cleanupOutboundFixture();
}

async function main(): Promise<void> {
  log('stage12.validation.started');

  runProductionValidators();

  await verifyApiSecurity();

  await verifyWebhookSecurity();

  await verifyOutboundLeaseSafety();

  log('stage12.validation.completed');
}

try {
  await main();
} finally {
  try {
    await cleanupOutboundFixture();
  } finally {
    await database.$disconnect();
  }
}
