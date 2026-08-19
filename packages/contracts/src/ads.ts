export type AdsRequestStatus =
  'QUEUED' | 'PROCESSING' | 'PARTIALLY_FULFILLED' | 'FULFILLED' | 'CANCELLED' | 'FAILED';

export type AdsQueueItemStatus = 'WAITING' | 'CLAIMED' | 'COMPLETED' | 'CANCELLED' | 'FAILED';

export type AdsRequestSiteResponse = Readonly<{
  id: string;
  name: string;
  slug: string;
}>;

export type AdsRequestTrafficPoolResponse = Readonly<{
  id: string;
  name: string;
  slug: string;
}>;

export type AdsRequestEmployeeResponse = Readonly<{
  id: string;
  employeeCode: string;
}>;

export type AdsQueueItemSummaryResponse = Readonly<{
  id: string;
  status: AdsQueueItemStatus;
  priority: number;
  attempts: number;
  enqueuedAt: string;
  availableAt: string;
  claimedAt: string | null;
  completedAt: string | null;
  cancelledAt: string | null;
}>;

export type AdsRequestResponse = Readonly<{
  id: string;
  organizationId: string;
  employeeId: string;
  siteId: string;
  trafficPoolId: string;
  requestedByUserId: string;
  requestedLeadCount: number;
  fulfilledLeadCount: number;
  status: AdsRequestStatus;
  notes: string | null;
  queuedAt: string;
  startedAt: string | null;
  completedAt: string | null;
  cancelledAt: string | null;
  failureReason: string | null;
  site: AdsRequestSiteResponse;
  trafficPool: AdsRequestTrafficPoolResponse;
  employee: AdsRequestEmployeeResponse;
  queueItem: AdsQueueItemSummaryResponse | null;
  createdAt: string;
  updatedAt: string;
}>;

export type AdsRequestListResponse = readonly AdsRequestResponse[];

export type CreateAdsRequestRequest = Readonly<{
  siteId: string;
  trafficPoolId: string;
  requestedLeadCount: number;
  notes?: string | null;
}>;

export type AdsQueueRequestSummaryResponse = Readonly<{
  id: string;
  status: AdsRequestStatus;
  requestedLeadCount: number;
  fulfilledLeadCount: number;
}>;

export type AdsQueueItemResponse = Readonly<{
  id: string;
  organizationId: string;
  adsRequestId: string;
  employeeId: string;
  trafficPoolId: string;
  status: AdsQueueItemStatus;
  priority: number;
  attempts: number;
  enqueuedAt: string;
  availableAt: string;
  claimedAt: string | null;
  completedAt: string | null;
  cancelledAt: string | null;
  adsRequest: AdsQueueRequestSummaryResponse;
  createdAt: string;
  updatedAt: string;
}>;

export type AdsQueueListResponse = readonly AdsQueueItemResponse[];
