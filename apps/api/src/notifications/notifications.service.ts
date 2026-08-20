import { Inject, Injectable, NotFoundException } from '@nestjs/common';

import type { AuthenticatedPrincipal } from '@crm/auth';

import type {
  NotificationListResponse,
  NotificationPreferenceResponse,
  PushDeviceListResponse,
  PushDeviceResponse,
} from '@crm/contracts';

import type { RegisterPushDeviceInput, UpdateNotificationPreferenceInput } from '@crm/validation';

import { DatabaseService } from '../database/database.service.js';

export type EnqueuePushNotificationInput = Readonly<{
  organizationId: string;
  userId: string;
  type: string;
  title: string;
  body: string;
  url?: string | null;
  data?: Readonly<Record<string, string>>;
  idempotencyKey?: string | null;
}>;

@Injectable()
export class NotificationsService {
  constructor(
    @Inject(DatabaseService)
    private readonly database: DatabaseService,
  ) {}

  async listDevices(principal: AuthenticatedPrincipal): Promise<PushDeviceListResponse> {
    const devices = await this.database.client.pushDevice.findMany({
      where: {
        organizationId: principal.organizationId,

        userId: principal.userId,

        status: {
          not: 'REVOKED',
        },
      },

      orderBy: {
        lastSeenAt: 'desc',
      },
    });

    return devices.map((device) => this.mapDevice(device));
  }

  async registerDevice(
    principal: AuthenticatedPrincipal,
    input: RegisterPushDeviceInput,
    userAgent: string | null,
  ): Promise<PushDeviceResponse> {
    const now = new Date();

    const device = await this.database.client.$transaction(async (transaction) => {
      const existing = await transaction.pushDevice.findUnique({
        where: {
          subscriptionId: input.subscriptionId,
        },
      });

      const status = input.optedIn ? 'ACTIVE' : 'INACTIVE';

      const saved = existing
        ? await transaction.pushDevice.update({
            where: {
              id: existing.id,
            },

            data: {
              organizationId: principal.organizationId,

              userId: principal.userId,

              oneSignalId: input.oneSignalId ?? null,

              status,
              optedIn: input.optedIn,

              platform: input.platform ?? null,

              browser: input.browser ?? null,

              deviceLabel: input.deviceLabel ?? null,

              userAgent,

              lastSeenAt: now,

              ...(input.optedIn
                ? {
                    subscribedAt: now,

                    unsubscribedAt: null,

                    revokedAt: null,
                  }
                : {
                    unsubscribedAt: now,
                  }),
            },
          })
        : await transaction.pushDevice.create({
            data: {
              organizationId: principal.organizationId,

              userId: principal.userId,

              subscriptionId: input.subscriptionId,

              oneSignalId: input.oneSignalId ?? null,

              status,
              optedIn: input.optedIn,

              platform: input.platform ?? null,

              browser: input.browser ?? null,

              deviceLabel: input.deviceLabel ?? null,

              userAgent,

              subscribedAt: now,

              ...(input.optedIn
                ? {}
                : {
                    unsubscribedAt: now,
                  }),
            },
          });

      await transaction.auditLog.create({
        data: {
          organizationId: principal.organizationId,

          actorType: 'USER',

          actorUserId: principal.userId,

          action: existing ? 'push_device.synced' : 'push_device.registered',

          resourceType: 'push_device',

          resourceId: saved.id,

          outcome: 'SUCCESS',

          metadata: {
            provider: saved.provider,

            optedIn: saved.optedIn,
          },
        },
      });

      return saved;
    });

    return this.mapDevice(device);
  }

  async unregisterDevice(principal: AuthenticatedPrincipal, subscriptionId: string): Promise<void> {
    const device = await this.database.client.pushDevice.findFirst({
      where: {
        organizationId: principal.organizationId,

        userId: principal.userId,

        subscriptionId,
      },
    });

    if (!device) {
      throw new NotFoundException({
        code: 'PUSH_DEVICE_NOT_FOUND',

        message: 'Push device not found.',
      });
    }

    if (device.status === 'REVOKED') {
      return;
    }

    const now = new Date();

    await this.database.client.$transaction(async (transaction) => {
      await transaction.pushDevice.update({
        where: {
          id: device.id,
        },

        data: {
          status: 'REVOKED',

          optedIn: false,

          unsubscribedAt: device.unsubscribedAt ?? now,

          revokedAt: now,

          lastSeenAt: now,
        },
      });

      await transaction.auditLog.create({
        data: {
          organizationId: principal.organizationId,

          actorType: 'USER',

          actorUserId: principal.userId,

          action: 'push_device.revoked',

          resourceType: 'push_device',

          resourceId: device.id,

          outcome: 'SUCCESS',
        },
      });
    });
  }

  async getPreferences(principal: AuthenticatedPrincipal): Promise<NotificationPreferenceResponse> {
    const preferences = await this.database.client.notificationPreference.upsert({
      where: {
        organizationId_userId: {
          organizationId: principal.organizationId,

          userId: principal.userId,
        },
      },

      create: {
        organizationId: principal.organizationId,

        userId: principal.userId,
      },

      update: {},
    });

    return {
      pushEnabled: preferences.pushEnabled,

      siteMonitoring: preferences.siteMonitoring,

      adsUpdates: preferences.adsUpdates,

      whatsappInbox: preferences.whatsappInbox,

      createdAt: preferences.createdAt.toISOString(),

      updatedAt: preferences.updatedAt.toISOString(),
    };
  }

  async updatePreferences(
    principal: AuthenticatedPrincipal,
    input: UpdateNotificationPreferenceInput,
  ): Promise<NotificationPreferenceResponse> {
    const preferences = await this.database.client.notificationPreference.upsert({
      where: {
        organizationId_userId: {
          organizationId: principal.organizationId,

          userId: principal.userId,
        },
      },

      create: {
        organizationId: principal.organizationId,

        userId: principal.userId,

        ...(input.pushEnabled !== undefined
          ? {
              pushEnabled: input.pushEnabled === true,
            }
          : {}),

        ...(input.siteMonitoring !== undefined
          ? {
              siteMonitoring: input.siteMonitoring === true,
            }
          : {}),

        ...(input.adsUpdates !== undefined
          ? {
              adsUpdates: input.adsUpdates === true,
            }
          : {}),

        ...(input.whatsappInbox !== undefined
          ? {
              whatsappInbox: input.whatsappInbox === true,
            }
          : {}),
      },

      update: {
        ...(input.pushEnabled !== undefined
          ? {
              pushEnabled: input.pushEnabled === true,
            }
          : {}),

        ...(input.siteMonitoring !== undefined
          ? {
              siteMonitoring: input.siteMonitoring === true,
            }
          : {}),

        ...(input.adsUpdates !== undefined
          ? {
              adsUpdates: input.adsUpdates === true,
            }
          : {}),

        ...(input.whatsappInbox !== undefined
          ? {
              whatsappInbox: input.whatsappInbox === true,
            }
          : {}),
      },
    });

    return {
      pushEnabled: preferences.pushEnabled,

      siteMonitoring: preferences.siteMonitoring,

      adsUpdates: preferences.adsUpdates,

      whatsappInbox: preferences.whatsappInbox,

      createdAt: preferences.createdAt.toISOString(),

      updatedAt: preferences.updatedAt.toISOString(),
    };
  }

  async listNotifications(principal: AuthenticatedPrincipal): Promise<NotificationListResponse> {
    const notifications = await this.database.client.notification.findMany({
      where: {
        organizationId: principal.organizationId,

        userId: principal.userId,
      },

      orderBy: {
        createdAt: 'desc',
      },

      take: 100,
    });

    return notifications.map((notification) => ({
      id: notification.id,

      type: notification.type,

      title: notification.title,

      body: notification.body,

      url: notification.url,

      data: notification.data,

      status: notification.status,

      createdAt: notification.createdAt.toISOString(),

      processedAt: notification.processedAt?.toISOString() ?? null,
    }));
  }

  async enqueuePush(input: EnqueuePushNotificationInput): Promise<string> {
    if (input.idempotencyKey) {
      const notification = await this.database.client.notification.upsert({
        where: {
          organizationId_idempotencyKey: {
            organizationId: input.organizationId,

            idempotencyKey: input.idempotencyKey,
          },
        },

        create: {
          organizationId: input.organizationId,

          userId: input.userId,

          channel: 'PUSH',

          type: input.type,

          title: input.title,

          body: input.body,

          url: input.url ?? null,

          ...(input.data !== undefined
            ? {
                data: {
                  ...input.data,
                },
              }
            : {}),

          idempotencyKey: input.idempotencyKey,
        },

        update: {},
      });

      await this.database.client.notificationDelivery.upsert({
        where: {
          notificationId_provider: {
            notificationId: notification.id,

            provider: 'ONESIGNAL',
          },
        },

        create: {
          organizationId: notification.organizationId,

          notificationId: notification.id,

          userId: notification.userId,

          provider: 'ONESIGNAL',
        },

        update: {},
      });

      return notification.id;
    }

    const notification = await this.database.client.$transaction(async (transaction) => {
      const created = await transaction.notification.create({
        data: {
          organizationId: input.organizationId,

          userId: input.userId,

          channel: 'PUSH',

          type: input.type,

          title: input.title,

          body: input.body,

          url: input.url ?? null,

          ...(input.data !== undefined
            ? {
                data: {
                  ...input.data,
                },
              }
            : {}),
        },
      });

      await transaction.notificationDelivery.create({
        data: {
          organizationId: input.organizationId,

          notificationId: created.id,

          userId: input.userId,

          provider: 'ONESIGNAL',
        },
      });

      return created;
    });

    return notification.id;
  }
  private mapDevice(device: {
    id: string;
    subscriptionId: string;
    oneSignalId: string | null;
    provider: 'ONESIGNAL';
    status: 'ACTIVE' | 'INACTIVE' | 'REVOKED';
    optedIn: boolean;
    platform: string | null;
    browser: string | null;
    deviceLabel: string | null;
    subscribedAt: Date;
    unsubscribedAt: Date | null;
    lastSeenAt: Date;
    createdAt: Date;
    updatedAt: Date;
  }): PushDeviceResponse {
    return {
      id: device.id,

      subscriptionId: device.subscriptionId,

      oneSignalId: device.oneSignalId,

      provider: device.provider,

      status: device.status,

      optedIn: device.optedIn,

      platform: device.platform,

      browser: device.browser,

      deviceLabel: device.deviceLabel,

      subscribedAt: device.subscribedAt.toISOString(),

      unsubscribedAt: device.unsubscribedAt?.toISOString() ?? null,

      lastSeenAt: device.lastSeenAt.toISOString(),

      createdAt: device.createdAt.toISOString(),

      updatedAt: device.updatedAt.toISOString(),
    };
  }
}
