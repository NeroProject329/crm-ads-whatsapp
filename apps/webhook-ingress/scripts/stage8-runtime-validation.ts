import '../src/load-environment.js';

import assert from 'node:assert/strict';
import { createHmac, randomUUID } from 'node:crypto';

type AuthenticatedPrincipal = Readonly<{
  organizationId: string;
  userId: string;
  sessionId: string;
  roles: readonly ('ADMIN' | 'EMPLOYEE')[];
}>;

import {
  MetaCloudApiClient,
  MetaCloudApiError,
  verifyMetaWebhookChallenge,
  verifyMetaWebhookSignature,
} from '@crm/meta-cloud-api';

import { DatabaseService as ApiDatabaseService } from '../../api/src/database/database.service.js';

import { WhatsAppNumbersService } from '../../api/src/whatsapp-numbers/whatsapp-numbers.service.js';

import { DatabaseService as WebhookDatabaseService } from '../src/database.service.js';

import { MetaWebhookService } from '../src/meta-webhook.service.js';

const apiDatabaseService = new ApiDatabaseService();

const webhookDatabaseService = new WebhookDatabaseService();

const database = webhookDatabaseService.client;

const whatsAppService = new WhatsAppNumbersService(apiDatabaseService);

const webhookService = new MetaWebhookService(webhookDatabaseService);

const organizationSlug = process.env.SEED_ORGANIZATION_SLUG?.trim() || 'crm-ads-whatsapp';

const unique = randomUUID().replaceAll('-', '').slice(0, 12);

const userEmailPrefix = 'stage8.runtime.';

const numberNamePrefix = 'Stage 8 Runtime';

const foreignOrganizationPrefix = 'stage8-runtime-tenant-';

const metaKnownPrefix = '880800';

const metaUnknownPrefix = '990800';

function event(name: string, extra: Record<string, unknown> = {}): void {
  console.log(
    JSON.stringify({
      event: name,
      timestamp: new Date().toISOString(),
      ...extra,
    }),
  );
}

function numericSuffix(suffix: number): string {
  return Date.now().toString().slice(-9) + suffix.toString();
}

async function cleanupMainFixtures(): Promise<void> {
  const organization = await database.organization.findUnique({
    where: {
      slug: organizationSlug,
    },
  });

  if (!organization) {
    return;
  }

  await database.metaWebhookEnvelope.deleteMany({
    where: {
      OR: [
        {
          metaPhoneNumberId: {
            startsWith: metaKnownPrefix,
          },
        },

        {
          metaPhoneNumberId: {
            startsWith: metaUnknownPrefix,
          },
        },
      ],
    },
  });

  const numbers = await database.whatsAppNumber.findMany({
    where: {
      organizationId: organization.id,

      displayName: {
        startsWith: numberNamePrefix,
      },
    },

    select: {
      id: true,
    },
  });

  const numberIds = numbers.map((number) => number.id);

  if (numberIds.length > 0) {
    await database.auditLog.deleteMany({
      where: {
        organizationId: organization.id,

        resourceId: {
          in: numberIds,
        },
      },
    });

    await database.whatsAppNumber.deleteMany({
      where: {
        id: {
          in: numberIds,
        },
      },
    });
  }

  const users = await database.user.findMany({
    where: {
      organizationId: organization.id,

      emailNormalized: {
        startsWith: userEmailPrefix,
      },
    },

    select: {
      id: true,
    },
  });

  for (const user of users) {
    await database.auditLog.deleteMany({
      where: {
        organizationId: organization.id,

        actorUserId: user.id,
      },
    });

    await database.session.deleteMany({
      where: {
        organizationId: organization.id,

        userId: user.id,
      },
    });

    await database.userRole.deleteMany({
      where: {
        organizationId: organization.id,

        userId: user.id,
      },
    });

    await database.user.delete({
      where: {
        id: user.id,
      },
    });
  }
}

async function cleanupForeignFixtures(): Promise<void> {
  const organizations = await database.organization.findMany({
    where: {
      slug: {
        startsWith: foreignOrganizationPrefix,
      },
    },

    select: {
      id: true,
    },
  });

  for (const organization of organizations) {
    await database.metaWebhookEnvelope.deleteMany({
      where: {
        organizationId: organization.id,
      },
    });

    await database.auditLog.deleteMany({
      where: {
        organizationId: organization.id,
      },
    });

    await database.whatsAppNumber.deleteMany({
      where: {
        organizationId: organization.id,
      },
    });

    await database.session.deleteMany({
      where: {
        organizationId: organization.id,
      },
    });

    await database.userRole.deleteMany({
      where: {
        organizationId: organization.id,
      },
    });

    await database.user.deleteMany({
      where: {
        organizationId: organization.id,
      },
    });

    await database.rolePermission.deleteMany({
      where: {
        role: {
          organizationId: organization.id,
        },
      },
    });

    await database.role.deleteMany({
      where: {
        organizationId: organization.id,
      },
    });

    await database.organization.delete({
      where: {
        id: organization.id,
      },
    });
  }
}

async function cleanupFixtures(): Promise<void> {
  await cleanupMainFixtures();
  await cleanupForeignFixtures();
}

async function main(): Promise<void> {
  try {
    event('stage8.validation.started');

    await cleanupFixtures();

    const organization = await database.organization.findUniqueOrThrow({
      where: {
        slug: organizationSlug,
      },
    });

    const user = await database.user.create({
      data: {
        organizationId: organization.id,

        email: `${userEmailPrefix}${unique}@example.com`,

        emailNormalized: `${userEmailPrefix}${unique}@example.com`,

        displayName: 'Stage 8 Runtime User',

        status: 'ACTIVE',
      },
    });

    const principal: AuthenticatedPrincipal = {
      organizationId: organization.id,

      userId: user.id,

      sessionId: randomUUID(),

      roles: ['ADMIN'],
    };

    const verification = verifyMetaWebhookChallenge({
      mode: 'subscribe',

      providedToken: 'stage8-verify',

      expectedToken: 'stage8-verify',

      challenge: 'stage8-challenge',
    });

    assert.equal(verification, 'stage8-challenge');

    assert.equal(
      verifyMetaWebhookChallenge({
        mode: 'subscribe',

        providedToken: 'wrong',

        expectedToken: 'stage8-verify',

        challenge: 'stage8-challenge',
      }),
      null,
    );

    event('stage8.challenge.passed');

    const signatureSecret = 'stage8-app-secret';

    const signatureBody = Buffer.from(
      JSON.stringify({
        object: 'whatsapp_business_account',
      }),
    );

    const signature = createHmac('sha256', signatureSecret).update(signatureBody).digest('hex');

    assert.equal(
      verifyMetaWebhookSignature(signatureSecret, signatureBody, `sha256=${signature}`),
      true,
    );

    assert.equal(
      verifyMetaWebhookSignature(signatureSecret, signatureBody, `sha256=${'0'.repeat(64)}`),
      false,
    );

    event('stage8.signature.passed');

    let graphAuthorization: string | null = null;

    let graphUrl = '';

    const graphSuccessFetch: typeof fetch = async (input, init) => {
      graphUrl = String(input);

      graphAuthorization = new Headers(init?.headers).get('authorization');

      return new Response(
        JSON.stringify({
          id: '88080012345',

          display_phone_number: '+15551234567',
        }),
        {
          status: 200,

          headers: {
            'content-type': 'application/json',
          },
        },
      );
    };

    const graphClient = new MetaCloudApiClient(
      {
        graphBaseUrl: 'https://graph.example.test',

        graphApiVersion: 'v99.0',

        accessToken: 'stage8-runtime-token',

        timeoutMs: 5000,
      },
      graphSuccessFetch,
    );

    const graphResult = await graphClient.get<{
      id: string;
    }>('88080012345', {
      fields: 'id,display_phone_number',
    });

    assert.equal(graphResult.id, '88080012345');

    assert.ok(graphUrl.includes('/v99.0/88080012345'));

    assert.equal(graphAuthorization, 'Bearer stage8-runtime-token');

    event('stage8.graph_client.passed');

    const graphErrorClient = new MetaCloudApiClient(
      {
        graphBaseUrl: 'https://graph.example.test',

        graphApiVersion: 'v99.0',

        accessToken: 'stage8-runtime-token',

        timeoutMs: 5000,
      },

      async () =>
        new Response(
          JSON.stringify({
            error: {
              message: 'Simulated Meta error',

              type: 'OAuthException',

              code: 190,

              error_subcode: 463,

              fbtrace_id: 'stage8-runtime-trace',
            },
          }),
          {
            status: 400,

            headers: {
              'x-fb-request-id': 'stage8-runtime-request',
            },
          },
        ),
    );

    try {
      await graphErrorClient.get('me');

      assert.fail('MetaCloudApiError expected.');
    } catch (error) {
      assert.ok(error instanceof MetaCloudApiError);

      assert.equal(error.code, 190);

      assert.equal(error.errorSubcode, 463);

      assert.equal(error.requestId, 'stage8-runtime-request');

      assert.equal(error.message.includes('stage8-runtime-token'), false);
    }

    event('stage8.graph_error_normalization.passed');

    const knownWabaId = `${metaKnownPrefix}${numericSuffix(1)}`;

    const knownPhoneId = `${metaKnownPrefix}${numericSuffix(2)}`;

    const knownNumber = await database.whatsAppNumber.create({
      data: {
        organizationId: organization.id,

        displayName: `${numberNamePrefix} Known`,

        e164: `+1555${numericSuffix(3)}`,

        status: 'ACTIVE',
      },
    });

    const connected = await whatsAppService.configureMetaCloud(principal, knownNumber.id, {
      wabaId: knownWabaId,

      phoneNumberId: knownPhoneId,
    });

    assert.equal(connected.metaWabaId, knownWabaId);

    assert.equal(connected.metaPhoneNumberId, knownPhoneId);

    assert.ok(connected.metaConnectedAt);

    event('stage8.number_connect.passed');

    const duplicateNumber = await database.whatsAppNumber.create({
      data: {
        organizationId: organization.id,

        displayName: `${numberNamePrefix} Duplicate`,

        e164: `+1555${numericSuffix(4)}`,

        status: 'ACTIVE',
      },
    });

    await assert.rejects(() =>
      whatsAppService.configureMetaCloud(principal, duplicateNumber.id, {
        wabaId: knownWabaId,

        phoneNumberId: knownPhoneId,
      }),
    );

    event('stage8.phone_id_uniqueness.passed');

    const foreignOrganization = await database.organization.create({
      data: {
        name: 'Stage 8 Foreign Tenant',

        slug: `${foreignOrganizationPrefix}${unique}`,

        status: 'ACTIVE',
      },
    });

    const foreignUser = await database.user.create({
      data: {
        organizationId: foreignOrganization.id,

        email: `stage8.foreign.${unique}@example.com`,

        emailNormalized: `stage8.foreign.${unique}@example.com`,

        displayName: 'Stage 8 Foreign User',

        status: 'ACTIVE',
      },
    });

    const foreignNumber = await database.whatsAppNumber.create({
      data: {
        organizationId: foreignOrganization.id,

        displayName: `${numberNamePrefix} Foreign`,

        e164: `+1555${numericSuffix(5)}`,

        status: 'ACTIVE',
      },
    });

    void foreignUser;

    await assert.rejects(() =>
      whatsAppService.configureMetaCloud(principal, foreignNumber.id, {
        wabaId: `${metaKnownPrefix}${numericSuffix(6)}`,

        phoneNumberId: `${metaKnownPrefix}${numericSuffix(7)}`,
      }),
    );

    event('stage8.number_tenant_isolation.passed');

    const knownPayload = {
      object: 'whatsapp_business_account',

      entry: [
        {
          id: knownWabaId,

          changes: [
            {
              field: 'messages',

              value: {
                metadata: {
                  display_phone_number: knownNumber.e164,

                  phone_number_id: knownPhoneId,
                },

                messages: [
                  {
                    id: `wamid.stage8.${unique}`,

                    from: '15550001111',

                    timestamp: '1700000000',

                    type: 'text',

                    text: {
                      body: 'Stage 8 webhook',
                    },
                  },
                ],
              },
            },
          ],
        },
      ],
    };

    const knownRawBody = Buffer.from(JSON.stringify(knownPayload));

    const firstWebhook = await webhookService.ingest(knownPayload, knownRawBody);

    assert.equal(firstWebhook.status, 'RECEIVED');

    assert.equal(firstWebhook.organizationId, organization.id);

    assert.equal(firstWebhook.whatsAppNumberId, knownNumber.id);

    const connectedAfterWebhook = await database.whatsAppNumber.findUniqueOrThrow({
      where: {
        id: knownNumber.id,
      },
    });

    assert.ok(connectedAfterWebhook.metaWebhookLastSeenAt);

    event('stage8.matched_webhook.passed');

    const secondWebhook = await webhookService.ingest(knownPayload, knownRawBody);

    assert.equal(secondWebhook.envelopeId, firstWebhook.envelopeId);

    assert.equal(
      await database.metaWebhookEnvelope.count({
        where: {
          id: firstWebhook.envelopeId,
        },
      }),
      1,
    );

    event('stage8.webhook_deduplication.passed');

    const wrongWabaPayload = {
      object: 'whatsapp_business_account',

      entry: [
        {
          id: `${metaUnknownPrefix}${numericSuffix(8)}`,

          changes: [
            {
              field: 'messages',

              value: {
                metadata: {
                  phone_number_id: knownPhoneId,
                },
              },
            },
          ],
        },
      ],
    };

    const wrongWabaResult = await webhookService.ingest(
      wrongWabaPayload,
      Buffer.from(JSON.stringify(wrongWabaPayload)),
    );

    assert.equal(wrongWabaResult.status, 'UNMATCHED');

    assert.equal(wrongWabaResult.organizationId, null);

    event('stage8.waba_mismatch.passed');

    const unknownPhoneId = `${metaUnknownPrefix}${numericSuffix(9)}`;

    const unknownPayload = {
      object: 'whatsapp_business_account',

      entry: [
        {
          id: `${metaUnknownPrefix}${numericSuffix(10)}`,

          changes: [
            {
              field: 'messages',

              value: {
                metadata: {
                  phone_number_id: unknownPhoneId,
                },
              },
            },
          ],
        },
      ],
    };

    const unknownResult = await webhookService.ingest(
      unknownPayload,
      Buffer.from(JSON.stringify(unknownPayload)),
    );

    assert.equal(unknownResult.status, 'UNMATCHED');

    assert.equal(unknownResult.whatsAppNumberId, null);

    event('stage8.unknown_number.passed');

    const ignoredPayload = {
      object: 'instagram',
      entry: [],
    };

    const ignoredResult = await webhookService.ingest(
      ignoredPayload,
      Buffer.from(JSON.stringify(ignoredPayload)),
    );

    assert.equal(ignoredResult.status, 'IGNORED');

    assert.equal(ignoredResult.organizationId, null);

    event('stage8.ignored_object.passed');

    const persistedEnvelope = await database.metaWebhookEnvelope.findUniqueOrThrow({
      where: {
        id: firstWebhook.envelopeId,
      },
    });

    assert.equal(persistedEnvelope.status, 'RECEIVED');

    assert.equal(persistedEnvelope.wabaId, knownWabaId);

    assert.equal(persistedEnvelope.metaPhoneNumberId, knownPhoneId);

    assert.ok(persistedEnvelope.payloadHash.length === 64);

    event('stage8.envelope_persistence.passed');

    const connectAudit = await database.auditLog.count({
      where: {
        organizationId: organization.id,

        action: 'whatsapp_number.meta_connected',

        resourceId: knownNumber.id,
      },
    });

    assert.ok(connectAudit >= 1);

    const disconnected = await whatsAppService.configureMetaCloud(principal, knownNumber.id, {
      wabaId: null,

      phoneNumberId: null,
    });

    assert.equal(disconnected.metaWabaId, null);

    assert.equal(disconnected.metaPhoneNumberId, null);

    assert.equal(disconnected.metaConnectedAt, null);

    assert.equal(disconnected.metaWebhookLastSeenAt, null);

    const disconnectAudit = await database.auditLog.count({
      where: {
        organizationId: organization.id,

        action: 'whatsapp_number.meta_disconnected',

        resourceId: knownNumber.id,
      },
    });

    assert.ok(disconnectAudit >= 1);

    event('stage8.number_disconnect.passed');

    event('stage8.audit.passed', {
      connectAudit,
      disconnectAudit,
    });

    event('stage8.validation.completed');
  } finally {
    try {
      await cleanupFixtures();
    } finally {
      await Promise.all([
        apiDatabaseService.onApplicationShutdown(),
        webhookDatabaseService.onApplicationShutdown(),
      ]);
    }
  }
}

void main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
