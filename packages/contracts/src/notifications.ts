export type PushProvider = 'ONESIGNAL';

export type PushDeviceStatus = 'ACTIVE' | 'INACTIVE' | 'REVOKED';

export type PushDeviceResponse = Readonly<{
  id: string;
  subscriptionId: string;
  oneSignalId: string | null;
  provider: PushProvider;
  status: PushDeviceStatus;
  optedIn: boolean;
  platform: string | null;
  browser: string | null;
  deviceLabel: string | null;
  subscribedAt: string;
  unsubscribedAt: string | null;
  lastSeenAt: string;
  createdAt: string;
  updatedAt: string;
}>;

export type PushDeviceListResponse = readonly PushDeviceResponse[];

export type RegisterPushDeviceRequest = Readonly<{
  subscriptionId: string;
  oneSignalId?: string | null;
  optedIn: boolean;
  platform?: string | null;
  browser?: string | null;
  deviceLabel?: string | null;
}>;

export type NotificationPreferenceResponse = Readonly<{
  pushEnabled: boolean;
  siteMonitoring: boolean;
  adsUpdates: boolean;
  whatsappInbox: boolean;
  createdAt: string;
  updatedAt: string;
}>;

export type UpdateNotificationPreferenceRequest = Readonly<{
  pushEnabled?: boolean;
  siteMonitoring?: boolean;
  adsUpdates?: boolean;
  whatsappInbox?: boolean;
}>;

export type NotificationStatus =
  'QUEUED' | 'PROCESSING' | 'SENT' | 'FAILED' | 'SKIPPED' | 'CANCELLED';

export type NotificationResponse = Readonly<{
  id: string;
  type: string;
  title: string;
  body: string;
  url: string | null;
  data: unknown;
  status: NotificationStatus;
  createdAt: string;
  processedAt: string | null;
}>;

export type NotificationListResponse = readonly NotificationResponse[];
