import '../src/load-environment.js';

import assert from 'node:assert/strict';

import { createHash, randomUUID } from 'node:crypto';

import { createDatabaseClient } from '@crm/database';

import { MetaCloudApiClient } from '@crm/meta-cloud-api';

import { WhatsAppInboxProcessorService } from '../src/whatsapp-inbox-processor.service.js';

import { WhatsAppOutboundDispatcherService } from '../src/whatsapp-outbound-dispatcher.service.js';

import type { WhatsAppRuntimeConfig } from '../src/whatsapp-runtime.config.js';

const database = createDatabaseClient();

const unique = randomUUID().replaceAll('-', '').slice(0, 12);

const organizationSlug = process.env.SEED_ORGANIZATION_SLUG?.trim() || 'crm-ads-whatsapp';

const numberPrefix = 'Stage 9 Runtime';

const employeeEmailPrefix = 'stage9.runtime.';

const foreignOrgPrefix = 'stage9-runtime-tenant-';

const metaPhonePrefix = '990900';

const contactPrefix = '55990900';

const quickReplyPrefix = `stage9_${unique}`;

const runtimeConfig: WhatsAppRuntimeConfig = {
  inboxIntervalMs: 1000,

  inboxLeaseMs: 30000,

  inboxMaxClaimsPerTick: 25,

  inboxMaxAttempts: 8,

  inboxRetryBaseMs: 100,

  outboundIntervalMs: 1000,

  outboundLeaseMs: 30000,

  outboundMaxClaimsPerTick: 25,

  outboundMaxAttempts: 8,

  outboundRetryBaseMs: 5000,

  outboundDisabledRetryMs: 1000,
};

function event(name: string, extra: Record<string, unknown> = {}): void {
  console.log(
    JSON.stringify({
      event: name,

      timestamp: new Date().toISOString(),

      ...extra,
    }),
  );
}

function numericSuffix(offset: number): string {
  return Date.now().toString().slice(-8) + offset.toString().padStart(2, '0');
}

function payloadHash(payload: unknown): string {
  return createHash('sha256').update(JSON.stringify(payload)).digest('hex');
}

async function cleanupFixtures(): Promise<void> {
  const organization = await database.organization.findUnique({
    where: {
      slug: organizationSlug,
    },

    select: {
      id: true,
    },
  });

  if (organization) {
    const numbers = await database.whatsAppNumber.findMany({
      where: {
        organizationId: organization.id,

        displayName: {
          startsWith: numberPrefix,
        },
      },

      select: {
        id: true,
      },
    });

    const numberIds = numbers.map((item) => item.id);

    const quickReplies = await database.whatsAppQuickReply.findMany({
      where: {
        organizationId: organization.id,

        shortcut: {
          startsWith: 'stage9_',
        },
      },

      select: {
        id: true,
      },
    });

    const conversations =
      numberIds.length > 0
        ? await database.whatsAppConversation.findMany({
            where: {
              organizationId: organization.id,

              whatsAppNumberId: {
                in: numberIds,
              },
            },

            select: {
              id: true,
            },
          })
        : [];

    const messages =
      numberIds.length > 0
        ? await database.whatsAppMessage.findMany({
            where: {
              organizationId: organization.id,

              whatsAppNumberId: {
                in: numberIds,
              },
            },

            select: {
              id: true,
            },
          })
        : [];

    const resourceIds = [
      ...numberIds,

      ...quickReplies.map((item) => item.id),

      ...conversations.map((item) => item.id),

      ...messages.map((item) => item.id),
    ];

    if (resourceIds.length > 0) {
      await database.auditLog.deleteMany({
        where: {
          organizationId: organization.id,

          resourceId: {
            in: resourceIds,
          },
        },
      });
    }

    if (numberIds.length > 0) {
      await database.whatsAppMessageStatusEvent.deleteMany({
        where: {
          organizationId: organization.id,

          whatsAppNumberId: {
            in: numberIds,
          },
        },
      });

      await database.whatsAppMessage.deleteMany({
        where: {
          organizationId: organization.id,

          whatsAppNumberId: {
            in: numberIds,
          },
        },
      });

      await database.whatsAppConversation.deleteMany({
        where: {
          organizationId: organization.id,

          whatsAppNumberId: {
            in: numberIds,
          },
        },
      });

      await database.whatsAppContact.deleteMany({
        where: {
          organizationId: organization.id,

          waId: {
            startsWith: contactPrefix,
          },
        },
      });

      await database.metaWebhookEnvelope.deleteMany({
        where: {
          OR: [
            {
              whatsAppNumberId: {
                in: numberIds,
              },
            },

            {
              metaPhoneNumberId: {
                startsWith: metaPhonePrefix,
              },
            },
          ],
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

    await database.whatsAppQuickReply.deleteMany({
      where: {
        organizationId: organization.id,

        shortcut: {
          startsWith: 'stage9_',
        },
      },
    });

    const users = await database.user.findMany({
      where: {
        organizationId: organization.id,

        emailNormalized: {
          startsWith: employeeEmailPrefix,
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

      await database.employee.deleteMany({
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

  const foreignOrganizations = await database.organization.findMany({
    where: {
      slug: {
        startsWith: foreignOrgPrefix,
      },
    },

    select: {
      id: true,
    },
  });

  for (const organization of foreignOrganizations) {
    await database.whatsAppMessageStatusEvent.deleteMany({
      where: {
        organizationId: organization.id,
      },
    });

    await database.whatsAppMessage.deleteMany({
      where: {
        organizationId: organization.id,
      },
    });

    await database.whatsAppConversation.deleteMany({
      where: {
        organizationId: organization.id,
      },
    });

    await database.whatsAppContact.deleteMany({
      where: {
        organizationId: organization.id,
      },
    });

    await database.metaWebhookEnvelope.deleteMany({
      where: {
        organizationId: organization.id,
      },
    });

    await database.whatsAppNumber.deleteMany({
      where: {
        organizationId: organization.id,
      },
    });

    await database.whatsAppQuickReply.deleteMany({
      where: {
        organizationId: organization.id,
      },
    });

    await database.auditLog.deleteMany({
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

    await database.employee.deleteMany({
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

    await database.team.deleteMany({
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

async function createEnvelope(
  organizationId: string,
  whatsAppNumberId: string,
  wabaId: string,
  phoneNumberId: string,
  payload: Record<string, unknown>,
  override: Readonly<{
    status?: 'RECEIVED' | 'CLAIMED';

    claimedByWorkerId?: string | null;

    leaseExpiresAt?: Date | null;
  }> = {},
) {
  return database.metaWebhookEnvelope.create({
    data: {
      organizationId,

      whatsAppNumberId,

      object: 'whatsapp_business_account',

      field: 'messages',

      wabaId,

      metaPhoneNumberId: phoneNumberId,

      payloadHash: payloadHash(payload),

      payload,

      status: override.status ?? 'RECEIVED',

      ...(override.claimedByWorkerId !== undefined
        ? {
            claimedByWorkerId: override.claimedByWorkerId,
          }
        : {}),

      ...(override.status === 'CLAIMED'
        ? {
            claimedAt: new Date(Date.now() - 60000),
          }
        : {}),

      ...(override.leaseExpiresAt !== undefined
        ? {
            leaseExpiresAt: override.leaseExpiresAt,
          }
        : {}),
    },
  });
}

function inboundPayload(
  input: Readonly<{
    nonce: string;

    wabaId: string;

    phoneNumberId: string;

    waId: string;

    messageId: string;

    profileName: string;

    timestamp: number;
  }>,
): Record<string, unknown> {
  return {
    stage9RuntimeNonce: input.nonce,

    object: 'whatsapp_business_account',

    entry: [
      {
        id: input.wabaId,

        changes: [
          {
            field: 'messages',

            value: {
              metadata: {
                phone_number_id: input.phoneNumberId,
              },

              contacts: [
                {
                  wa_id: input.waId,

                  profile: {
                    name: input.profileName,
                  },
                },
              ],

              messages: [
                {
                  id: input.messageId,

                  from: input.waId,

                  timestamp: String(input.timestamp),

                  type: 'text',

                  text: {
                    body: 'Mensagem Stage 9',
                  },
                },
              ],
            },
          },
        ],
      },
    ],
  };
}

function statusPayload(
  input: Readonly<{
    nonce: string;

    wabaId: string;

    phoneNumberId: string;

    messageId: string;

    recipientId: string;

    statuses: readonly Readonly<{
      status: string;

      timestamp: number;
    }>[];
  }>,
): Record<string, unknown> {
  return {
    stage9RuntimeNonce: input.nonce,

    object: 'whatsapp_business_account',

    entry: [
      {
        id: input.wabaId,

        changes: [
          {
            field: 'messages',

            value: {
              metadata: {
                phone_number_id: input.phoneNumberId,
              },

              statuses: input.statuses.map((status) => ({
                id: input.messageId,

                recipient_id: input.recipientId,

                status: status.status,

                timestamp: String(status.timestamp),
              })),
            },
          },
        ],
      },
    ],
  };
}

function createMetaClient(
  handler: (body: Record<string, unknown>, url: string) => Promise<Response>,
): MetaCloudApiClient {
  return new MetaCloudApiClient(
    {
      graphBaseUrl: 'https://graph.example.test',

      graphApiVersion: 'v99.0',

      accessToken: 'stage9-runtime-token',

      timeoutMs: 5000,
    },

    async (input, init) => {
      const raw = typeof init?.body === 'string' ? init.body : '{}';

      return handler(
        JSON.parse(raw) as Record<string, unknown>,

        String(input),
      );
    },
  );
}

async function main(): Promise<void> {
  event('stage9.validation.started');

  await cleanupFixtures();

  const pendingEnvelopeCount = await database.metaWebhookEnvelope.count({
    where: {
      status: {
        in: ['RECEIVED', 'CLAIMED'],
      },
    },
  });

  assert.equal(
    pendingEnvelopeCount,
    0,
    'Stage 9 runtime refuses to consume pre-existing pending webhook envelopes.',
  );

  const pendingOutboundCount = await database.whatsAppMessage.count({
    where: {
      direction: 'OUTBOUND',

      status: {
        in: ['QUEUED', 'SENDING'],
      },
    },
  });

  assert.equal(
    pendingOutboundCount,
    0,
    'Stage 9 runtime refuses to touch pre-existing outbound queue items.',
  );

  const organization = await database.organization.findUniqueOrThrow({
    where: {
      slug: organizationSlug,
    },

    include: {
      teams: {
        where: {
          status: 'ACTIVE',
        },

        take: 1,
      },

      users: {
        where: {
          employee: {
            isNot: null,
          },
        },

        include: {
          employee: true,
        },

        take: 1,
      },
    },
  });

  const team = organization.teams[0];

  const adminUser = organization.users[0];

  assert.ok(team, 'Seed team missing.');

  assert.ok(adminUser?.employee, 'Seed employee missing.');

  const primaryEmployee = adminUser.employee;

  const secondaryUser = await database.user.create({
    data: {
      organizationId: organization.id,

      email: `${employeeEmailPrefix}${unique}@example.com`,

      emailNormalized: `${employeeEmailPrefix}${unique}@example.com`,

      displayName: 'Stage 9 Secondary Employee',

      status: 'ACTIVE',
    },
  });

  const secondaryEmployee = await database.employee.create({
    data: {
      organizationId: organization.id,

      teamId: team.id,

      userId: secondaryUser.id,

      employeeCode: `S9${unique}`,

      status: 'ACTIVE',
    },
  });

  const phoneA = `${metaPhonePrefix}${numericSuffix(1)}`;

  const phoneB = `${metaPhonePrefix}${numericSuffix(2)}`;

  const wabaA = `${metaPhonePrefix}${numericSuffix(3)}`;

  const wabaB = `${metaPhonePrefix}${numericSuffix(4)}`;

  const numberA = await database.whatsAppNumber.create({
    data: {
      organizationId: organization.id,

      assignedEmployeeId: primaryEmployee.id,

      displayName: `${numberPrefix} A`,

      e164: `+1555${numericSuffix(5)}`,

      status: 'ACTIVE',

      metaWabaId: wabaA,

      metaPhoneNumberId: phoneA,

      metaConnectedAt: new Date(),
    },
  });

  const numberB = await database.whatsAppNumber.create({
    data: {
      organizationId: organization.id,

      assignedEmployeeId: secondaryEmployee.id,

      displayName: `${numberPrefix} B`,

      e164: `+1555${numericSuffix(6)}`,

      status: 'ACTIVE',

      metaWabaId: wabaB,

      metaPhoneNumberId: phoneB,

      metaConnectedAt: new Date(),
    },
  });

  const processorA = new WhatsAppInboxProcessorService(
    database,
    `stage9-inbox-a-${unique}`,
    runtimeConfig,
  );

  const processorB = new WhatsAppInboxProcessorService(
    database,
    `stage9-inbox-b-${unique}`,
    runtimeConfig,
  );

  const nowSeconds = Math.floor(Date.now() / 1000);

  const waIdA = `${contactPrefix}${numericSuffix(7)}`;

  const inboundMessageId = `wamid.stage9.inbound.${unique}`;

  await createEnvelope(
    organization.id,
    numberA.id,
    wabaA,
    phoneA,
    inboundPayload({
      nonce: `first-${unique}`,

      wabaId: wabaA,

      phoneNumberId: phoneA,

      waId: waIdA,

      messageId: inboundMessageId,

      profileName: 'Cliente Runtime A',

      timestamp: nowSeconds,
    }),
  );

  const firstTick = await processorA.runTick();

  assert.equal(firstTick.messages, 1);

  const inboundMessage = await database.whatsAppMessage.findUniqueOrThrow({
    where: {
      metaMessageId: inboundMessageId,
    },
  });

  assert.equal(inboundMessage.direction, 'INBOUND');

  assert.equal(inboundMessage.status, 'RECEIVED');

  const conversationA = await database.whatsAppConversation.findUniqueOrThrow({
    where: {
      id: inboundMessage.conversationId,
    },
  });

  assert.equal(conversationA.assignedEmployeeId, primaryEmployee.id);

  assert.equal(conversationA.unreadCount, 1);

  assert.ok(conversationA.customerServiceWindowExpiresAt);

  const expectedWindow = new Date(nowSeconds * 1000 + 24 * 60 * 60 * 1000);

  assert.equal(conversationA.customerServiceWindowExpiresAt?.getTime(), expectedWindow.getTime());

  event('stage9.inbound_message.passed');

  await createEnvelope(
    organization.id,
    numberA.id,
    wabaA,
    phoneA,
    inboundPayload({
      nonce: `duplicate-${unique}`,

      wabaId: wabaA,

      phoneNumberId: phoneA,

      waId: waIdA,

      messageId: inboundMessageId,

      profileName: 'Cliente Runtime A',

      timestamp: nowSeconds,
    }),
  );

  await processorA.runTick();

  assert.equal(
    await database.whatsAppMessage.count({
      where: {
        metaMessageId: inboundMessageId,
      },
    }),
    1,
  );

  const conversationAfterDuplicate = await database.whatsAppConversation.findUniqueOrThrow({
    where: {
      id: conversationA.id,
    },
  });

  assert.equal(conversationAfterDuplicate.unreadCount, 1);

  event('stage9.wamid_idempotency.passed');

  const concurrentMessageId = `wamid.stage9.concurrent.${unique}`;

  const waIdB = `${contactPrefix}${numericSuffix(8)}`;

  const concurrentEnvelope = await createEnvelope(
    organization.id,
    numberB.id,
    wabaB,
    phoneB,
    inboundPayload({
      nonce: `concurrent-${unique}`,

      wabaId: wabaB,

      phoneNumberId: phoneB,

      waId: waIdB,

      messageId: concurrentMessageId,

      profileName: 'Cliente Runtime B',

      timestamp: nowSeconds,
    }),
  );

  await Promise.all([processorA.runTick(), processorB.runTick()]);

  assert.equal(
    await database.whatsAppMessage.count({
      where: {
        metaMessageId: concurrentMessageId,
      },
    }),
    1,
  );

  const concurrentEnvelopeAfter = await database.metaWebhookEnvelope.findUniqueOrThrow({
    where: {
      id: concurrentEnvelope.id,
    },
  });

  assert.equal(concurrentEnvelopeAfter.status, 'PROCESSED');

  event('stage9.concurrent_inbox_claim.passed');

  const recoveredMessageId = `wamid.stage9.recovered.${unique}`;

  const recoveredEnvelope = await createEnvelope(
    organization.id,
    numberA.id,
    wabaA,
    phoneA,
    inboundPayload({
      nonce: `lease-${unique}`,

      wabaId: wabaA,

      phoneNumberId: phoneA,

      waId: waIdA,

      messageId: recoveredMessageId,

      profileName: 'Cliente Runtime A',

      timestamp: nowSeconds,
    }),
    {
      status: 'CLAIMED',

      claimedByWorkerId: 'dead-worker',

      leaseExpiresAt: new Date(Date.now() - 60000),
    },
  );

  await processorA.runTick();

  assert.equal(
    (
      await database.metaWebhookEnvelope.findUniqueOrThrow({
        where: {
          id: recoveredEnvelope.id,
        },
      })
    ).status,
    'PROCESSED',
  );

  assert.ok(
    await database.whatsAppMessage.findUnique({
      where: {
        metaMessageId: recoveredMessageId,
      },
    }),
  );

  event('stage9.inbox_lease_recovery.passed');

  const apiModule = await import('../../api/dist/inbox/inbox.service.js');

  const inboxService = new apiModule.InboxService({
    client: database,
  } as never);

  const adminPrincipal = {
    organizationId: organization.id,

    userId: adminUser.id,

    sessionId: randomUUID(),

    roles: ['ADMIN'] as const,
  };

  const employeePrincipal = {
    organizationId: organization.id,

    userId: adminUser.id,

    sessionId: randomUUID(),

    roles: ['EMPLOYEE'] as const,
  };

  const employeeList = await inboxService.listConversations(employeePrincipal, {
    limit: 30,

    whatsAppNumberId: numberA.id,
  });

  assert.ok(employeeList.items.some((item) => item.id === conversationA.id));

  const conversationB = await database.whatsAppConversation.findFirstOrThrow({
    where: {
      organizationId: organization.id,

      whatsAppNumberId: numberB.id,
    },
  });

  await assert.rejects(() => inboxService.getConversation(employeePrincipal, conversationB.id));

  event('stage9.employee_isolation.passed');

  const clientTextId = randomUUID();

  const queuedText = await inboxService.sendMessage(adminPrincipal, conversationA.id, {
    clientMessageId: clientTextId,

    type: 'TEXT',

    text: 'Resposta Stage 9',
  });

  const sameQueuedText = await inboxService.sendMessage(adminPrincipal, conversationA.id, {
    clientMessageId: clientTextId,

    type: 'TEXT',

    text: 'Resposta Stage 9',
  });

  assert.equal(sameQueuedText.id, queuedText.id);

  event('stage9.client_idempotency.passed');

  let textRequestCount = 0;

  const textMetaId = `wamid.stage9.outbound.text.${unique}`;

  const textClient = createMetaClient(async (body, url) => {
    textRequestCount += 1;

    assert.ok(url.includes(`/${phoneA}/messages`));

    assert.equal(body.type, 'text');

    return new Response(
      JSON.stringify({
        messages: [
          {
            id: textMetaId,
          },
        ],
      }),
      {
        status: 200,
      },
    );
  });

  const textDispatcher = new WhatsAppOutboundDispatcherService(
    database,
    `stage9-outbound-text-${unique}`,
    runtimeConfig,
    textClient,
  );

  await textDispatcher.runTick();

  assert.equal(textRequestCount, 1);

  const sentText = await database.whatsAppMessage.findUniqueOrThrow({
    where: {
      id: queuedText.id,
    },
  });

  assert.equal(sentText.status, 'SENT');

  assert.equal(sentText.metaMessageId, textMetaId);

  event('stage9.outbound_text.passed');

  await database.whatsAppConversation.update({
    where: {
      id: conversationA.id,
    },

    data: {
      customerServiceWindowExpiresAt: new Date(Date.now() - 1000),
    },
  });

  await assert.rejects(() =>
    inboxService.sendMessage(adminPrincipal, conversationA.id, {
      clientMessageId: randomUUID(),

      type: 'TEXT',

      text: 'Janela fechada',
    }),
  );

  event('stage9.window_api_guard.passed');

  const templateQueued = await inboxService.sendMessage(adminPrincipal, conversationA.id, {
    clientMessageId: randomUUID(),

    type: 'TEMPLATE',

    templateName: 'stage9_template',

    languageCode: 'pt_BR',
  });

  const templateMetaId = `wamid.stage9.template.${unique}`;

  const templateClient = createMetaClient(async (body) => {
    assert.equal(body.type, 'template');

    return new Response(
      JSON.stringify({
        messages: [
          {
            id: templateMetaId,
          },
        ],
      }),
      {
        status: 200,
      },
    );
  });

  const templateDispatcher = new WhatsAppOutboundDispatcherService(
    database,
    `stage9-outbound-template-${unique}`,
    runtimeConfig,
    templateClient,
  );

  await templateDispatcher.runTick();

  assert.equal(
    (
      await database.whatsAppMessage.findUniqueOrThrow({
        where: {
          id: templateQueued.id,
        },
      })
    ).status,
    'SENT',
  );

  event('stage9.template_outside_window.passed');

  const blockedText = await database.whatsAppMessage.create({
    data: {
      organizationId: organization.id,

      conversationId: conversationA.id,

      whatsAppNumberId: numberA.id,

      contactId: inboundMessage.contactId,

      direction: 'OUTBOUND',

      type: 'TEXT',

      status: 'QUEUED',

      clientMessageId: randomUUID(),

      textBody: 'Nao pode sair',

      content: {
        type: 'text',

        text: {
          body: 'Nao pode sair',
        },
      },

      queuedAt: new Date(),
    },
  });

  let blockedNetworkCalls = 0;

  const blockedClient = createMetaClient(async () => {
    blockedNetworkCalls += 1;

    return new Response('{}', {
      status: 500,
    });
  });

  const blockedDispatcher = new WhatsAppOutboundDispatcherService(
    database,
    `stage9-outbound-blocked-${unique}`,
    runtimeConfig,
    blockedClient,
  );

  await blockedDispatcher.runTick();

  const blockedAfter = await database.whatsAppMessage.findUniqueOrThrow({
    where: {
      id: blockedText.id,
    },
  });

  assert.equal(blockedNetworkCalls, 0);

  assert.equal(blockedAfter.status, 'FAILED');

  assert.equal(blockedAfter.errorCode, 'WHATSAPP_CUSTOMER_SERVICE_WINDOW_CLOSED');

  event('stage9.window_worker_guard.passed');

  const statusNow = Math.floor(Date.now() / 1000);

  await createEnvelope(
    organization.id,
    numberA.id,
    wabaA,
    phoneA,
    statusPayload({
      nonce: `read-${unique}`,

      wabaId: wabaA,

      phoneNumberId: phoneA,

      messageId: textMetaId,

      recipientId: waIdA,

      statuses: [
        {
          status: 'delivered',

          timestamp: statusNow,
        },

        {
          status: 'read',

          timestamp: statusNow + 1,
        },
      ],
    }),
  );

  await processorA.runTick();

  const readText = await database.whatsAppMessage.findUniqueOrThrow({
    where: {
      id: sentText.id,
    },
  });

  assert.equal(readText.status, 'READ');

  assert.ok(readText.deliveredAt);

  assert.ok(readText.readAt);

  await createEnvelope(
    organization.id,
    numberA.id,
    wabaA,
    phoneA,
    statusPayload({
      nonce: `late-sent-${unique}`,

      wabaId: wabaA,

      phoneNumberId: phoneA,

      messageId: textMetaId,

      recipientId: waIdA,

      statuses: [
        {
          status: 'sent',

          timestamp: statusNow - 5,
        },
      ],
    }),
  );

  await processorA.runTick();

  assert.equal(
    (
      await database.whatsAppMessage.findUniqueOrThrow({
        where: {
          id: sentText.id,
        },
      })
    ).status,
    'READ',
  );

  event('stage9.status_reconciliation.passed');

  const pendingMetaId = `wamid.stage9.pending.${unique}`;

  await createEnvelope(
    organization.id,
    numberA.id,
    wabaA,
    phoneA,
    statusPayload({
      nonce: `before-send-${unique}`,

      wabaId: wabaA,

      phoneNumberId: phoneA,

      messageId: pendingMetaId,

      recipientId: waIdA,

      statuses: [
        {
          status: 'delivered',

          timestamp: statusNow + 2,
        },
      ],
    }),
  );

  await processorA.runTick();

  const pendingStatus = await database.whatsAppMessageStatusEvent.findFirstOrThrow({
    where: {
      organizationId: organization.id,

      metaMessageId: pendingMetaId,
    },
  });

  assert.equal(pendingStatus.appliedAt, null);

  const pendingMessage = await inboxService.sendMessage(adminPrincipal, conversationA.id, {
    clientMessageId: randomUUID(),

    type: 'TEMPLATE',

    templateName: 'stage9_pending',

    languageCode: 'pt_BR',
  });

  const pendingClient = createMetaClient(
    async () =>
      new Response(
        JSON.stringify({
          messages: [
            {
              id: pendingMetaId,
            },
          ],
        }),
        {
          status: 200,
        },
      ),
  );

  const pendingDispatcher = new WhatsAppOutboundDispatcherService(
    database,
    `stage9-outbound-pending-${unique}`,
    runtimeConfig,
    pendingClient,
  );

  await pendingDispatcher.runTick();

  assert.equal(
    (
      await database.whatsAppMessage.findUniqueOrThrow({
        where: {
          id: pendingMessage.id,
        },
      })
    ).status,
    'DELIVERED',
  );

  assert.ok(
    (
      await database.whatsAppMessageStatusEvent.findUniqueOrThrow({
        where: {
          id: pendingStatus.id,
        },
      })
    ).appliedAt,
  );

  event('stage9.status_before_send.passed');

  const retryMessage = await inboxService.sendMessage(adminPrincipal, conversationA.id, {
    clientMessageId: randomUUID(),

    type: 'TEMPLATE',

    templateName: 'stage9_retry',

    languageCode: 'pt_BR',
  });

  let retryCalls = 0;

  const retryMetaId = `wamid.stage9.retry.${unique}`;

  const retryClient = createMetaClient(async () => {
    retryCalls += 1;

    if (retryCalls === 1) {
      return new Response(
        JSON.stringify({
          error: {
            message: 'Rate limited',

            type: 'OAuthException',

            code: 4,
          },
        }),
        {
          status: 429,
        },
      );
    }

    return new Response(
      JSON.stringify({
        messages: [
          {
            id: retryMetaId,
          },
        ],
      }),
      {
        status: 200,
      },
    );
  });

  const retryDispatcher = new WhatsAppOutboundDispatcherService(
    database,
    `stage9-outbound-retry-${unique}`,
    runtimeConfig,
    retryClient,
  );

  await retryDispatcher.runTick();

  const afterRateLimit = await database.whatsAppMessage.findUniqueOrThrow({
    where: {
      id: retryMessage.id,
    },
  });

  assert.equal(afterRateLimit.status, 'QUEUED');

  await database.whatsAppMessage.update({
    where: {
      id: retryMessage.id,
    },

    data: {
      availableAt: new Date(),
    },
  });

  await retryDispatcher.runTick();

  const afterRetry = await database.whatsAppMessage.findUniqueOrThrow({
    where: {
      id: retryMessage.id,
    },
  });

  assert.equal(afterRetry.status, 'SENT');

  assert.equal(afterRetry.attempts, 2);

  assert.equal(retryCalls, 2);

  event('stage9.retry_backoff.passed');

  const uncertainMessage = await inboxService.sendMessage(adminPrincipal, conversationA.id, {
    clientMessageId: randomUUID(),

    type: 'TEMPLATE',

    templateName: 'stage9_uncertain',

    languageCode: 'pt_BR',
  });

  const uncertainClient = createMetaClient(async () => {
    throw new Error('Simulated socket reset');
  });

  const uncertainDispatcher = new WhatsAppOutboundDispatcherService(
    database,
    `stage9-outbound-uncertain-${unique}`,
    runtimeConfig,
    uncertainClient,
  );

  await uncertainDispatcher.runTick();

  const uncertainAfter = await database.whatsAppMessage.findUniqueOrThrow({
    where: {
      id: uncertainMessage.id,
    },
  });

  assert.equal(uncertainAfter.status, 'FAILED');

  assert.equal(uncertainAfter.errorCode, 'OUTBOUND_DELIVERY_UNKNOWN');

  event('stage9.uncertain_outcome_protection.passed');

  const leaseMessage = await inboxService.sendMessage(adminPrincipal, conversationA.id, {
    clientMessageId: randomUUID(),

    type: 'TEMPLATE',

    templateName: 'stage9_lease',

    languageCode: 'pt_BR',
  });

  await database.whatsAppMessage.update({
    where: {
      id: leaseMessage.id,
    },

    data: {
      status: 'SENDING',

      claimedAt: new Date(Date.now() - 60000),

      claimedByWorkerId: 'dead-outbound-worker',

      leaseExpiresAt: new Date(Date.now() - 30000),
    },
  });

  const leaseMetaId = `wamid.stage9.lease.${unique}`;

  const leaseDispatcher = new WhatsAppOutboundDispatcherService(
    database,
    `stage9-outbound-lease-${unique}`,
    runtimeConfig,
    createMetaClient(
      async () =>
        new Response(
          JSON.stringify({
            messages: [
              {
                id: leaseMetaId,
              },
            ],
          }),
          {
            status: 200,
          },
        ),
    ),
  );

  await leaseDispatcher.runTick();

  assert.equal(
    (
      await database.whatsAppMessage.findUniqueOrThrow({
        where: {
          id: leaseMessage.id,
        },
      })
    ).status,
    'SENT',
  );

  event('stage9.outbound_lease_recovery.passed');

  const concurrentOutbound = await inboxService.sendMessage(adminPrincipal, conversationA.id, {
    clientMessageId: randomUUID(),

    type: 'TEMPLATE',

    templateName: 'stage9_concurrent',

    languageCode: 'pt_BR',
  });

  let concurrentSendCalls = 0;

  const concurrentOutboundClient = createMetaClient(async () => {
    concurrentSendCalls += 1;

    return new Response(
      JSON.stringify({
        messages: [
          {
            id: `wamid.stage9.concurrent.out.${unique}`,
          },
        ],
      }),
      {
        status: 200,
      },
    );
  });

  const outboundA = new WhatsAppOutboundDispatcherService(
    database,
    `stage9-out-a-${unique}`,
    runtimeConfig,
    concurrentOutboundClient,
  );

  const outboundB = new WhatsAppOutboundDispatcherService(
    database,
    `stage9-out-b-${unique}`,
    runtimeConfig,
    concurrentOutboundClient,
  );

  await Promise.all([outboundA.runTick(), outboundB.runTick()]);

  assert.equal(concurrentSendCalls, 1);

  assert.equal(
    (
      await database.whatsAppMessage.findUniqueOrThrow({
        where: {
          id: concurrentOutbound.id,
        },
      })
    ).status,
    'SENT',
  );

  event('stage9.concurrent_outbound_claim.passed');

  const quickReply = await inboxService.createQuickReply(adminPrincipal, {
    title: 'Stage 9 Ola',

    shortcut: `${quickReplyPrefix}_ola`,

    body: 'Ola! Como posso ajudar?',
  });

  const quickReplies = await inboxService.listQuickReplies(adminPrincipal);

  assert.ok(quickReplies.some((item) => item.id === quickReply.id));

  await assert.rejects(() =>
    inboxService.createQuickReply(adminPrincipal, {
      title: 'Duplicada',

      shortcut: `${quickReplyPrefix}_ola`,

      body: 'Duplicada',
    }),
  );

  event('stage9.quick_replies.passed');

  const conversationRead = await inboxService.markConversationRead(
    adminPrincipal,
    conversationA.id,
  );

  assert.equal(conversationRead.unreadCount, 0);

  await assert.rejects(() =>
    inboxService.updateConversation(employeePrincipal, conversationA.id, {
      assignedEmployeeId: secondaryEmployee.id,
    }),
  );

  event('stage9.assignment_and_read.passed');

  const foreignOrganization = await database.organization.create({
    data: {
      name: 'Stage 9 Foreign Tenant',

      slug: `${foreignOrgPrefix}${unique}`,

      status: 'ACTIVE',
    },
  });

  const foreignNumber = await database.whatsAppNumber.create({
    data: {
      organizationId: foreignOrganization.id,

      displayName: `${numberPrefix} Foreign`,

      e164: `+1555${numericSuffix(20)}`,

      status: 'ACTIVE',

      metaWabaId: `${metaPhonePrefix}${numericSuffix(21)}`,

      metaPhoneNumberId: `${metaPhonePrefix}${numericSuffix(22)}`,

      metaConnectedAt: new Date(),
    },
  });

  const foreignContact = await database.whatsAppContact.create({
    data: {
      organizationId: foreignOrganization.id,

      waId: `${contactPrefix}${numericSuffix(23)}`,

      profileName: 'Foreign Contact',
    },
  });

  const foreignConversation = await database.whatsAppConversation.create({
    data: {
      organizationId: foreignOrganization.id,

      whatsAppNumberId: foreignNumber.id,

      contactId: foreignContact.id,

      status: 'OPEN',
    },
  });

  await assert.rejects(() => inboxService.getConversation(adminPrincipal, foreignConversation.id));

  event('stage9.tenant_isolation.passed');

  const auditCount = await database.auditLog.count({
    where: {
      organizationId: organization.id,

      resourceId: {
        in: [queuedText.id, quickReply.id, conversationA.id],
      },
    },
  });

  assert.ok(auditCount >= 3);

  event('stage9.audit.passed', {
    auditCount,
  });

  event('stage9.validation.completed');
}

try {
  await main();
} finally {
  try {
    await cleanupFixtures();
  } finally {
    await database.$disconnect();
  }
}
