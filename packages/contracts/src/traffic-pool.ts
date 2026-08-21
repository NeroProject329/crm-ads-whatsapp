export type TrafficPoolStatus = 'ACTIVE' | 'PAUSED' | 'ARCHIVED';

export type TrafficPoolMemberStatus = 'ACTIVE' | 'PAUSED';

export type TrafficPoolNumberResponse = Readonly<{
  id: string;
  displayName: string;
  e164: string;

  assignedEmployeeId: string | null;

  status: 'ACTIVE' | 'PAUSED' | 'DISABLED' | 'ARCHIVED';
}>;

export type TrafficPoolMemberResponse = Readonly<{
  id: string;

  organizationId: string;

  trafficPoolId: string;

  whatsAppNumberId: string;

  position: number;

  status: TrafficPoolMemberStatus;

  number: TrafficPoolNumberResponse;

  createdAt: string;

  updatedAt: string;
}>;

export type TrafficPoolSiteResponse = Readonly<{
  id: string;
  name: string;
  slug: string;
}>;

export type TrafficPoolResponse = Readonly<{
  id: string;

  organizationId: string;

  siteId: string;

  name: string;

  slug: string;

  description: string | null;

  status: TrafficPoolStatus;

  site: TrafficPoolSiteResponse;

  members: readonly TrafficPoolMemberResponse[];

  createdAt: string;

  updatedAt: string;
}>;

export type TrafficPoolListResponse = readonly TrafficPoolResponse[];

export type TrafficPoolMemberDeleteResponse = Readonly<{
  success: true;
}>;
