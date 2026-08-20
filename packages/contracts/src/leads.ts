export type LeadStatus = 'ATTRIBUTED' | 'EXCESS';

export type LeadContactResponse = Readonly<{
  id: string;
  waId: string;
  profileName: string | null;
}>;

export type LeadEmployeeResponse = Readonly<{
  employeeId: string;
  employeeCode: string;
  userId: string;
  displayName: string;
}>;

export type LeadWhatsAppNumberResponse = Readonly<{
  id: string;
  displayName: string;
  e164: string;
}>;

export type LeadAdsRequestResponse = Readonly<{
  id: string;
  requestedLeadCount: number;
  scheduledLeadCount: number;
  fulfilledLeadCount: number;
  status: 'QUEUED' | 'PROCESSING' | 'PARTIALLY_FULFILLED' | 'FULFILLED' | 'CANCELLED' | 'FAILED';
}>;

export type LeadMicrobatchResponse = Readonly<{
  id: string;
  sequence: number;
  reservedLeadCount: number;
  deliveredLeadCount: number;
  status: 'PLANNED' | 'DELIVERING' | 'COMPLETED' | 'CANCELLED' | 'FAILED';
}>;

export type LeadAttributionResponse = Readonly<{
  id: string;
  adsRequestId: string;
  adsMicrobatchId: string;
  employeeId: string;
  whatsAppNumberId: string;
  inboundMessageId: string;
  attributedAt: string;

  adsRequest: LeadAdsRequestResponse;
  microbatch: LeadMicrobatchResponse;
}>;

export type LeadResponse = Readonly<{
  id: string;
  organizationId: string;

  contact: LeadContactResponse;

  firstInboundMessageId: string;

  firstWhatsAppNumber: LeadWhatsAppNumberResponse;

  ownerEmployee: LeadEmployeeResponse | null;

  waIdSnapshot: string;
  profileNameSnapshot: string | null;

  status: LeadStatus;

  excessReason: string | null;

  firstSeenAt: string;
  lastSeenAt: string;

  inboundMessageCount: number;

  attributedAt: string | null;

  attribution: LeadAttributionResponse | null;

  createdAt: string;
  updatedAt: string;
}>;

export type LeadListResponse = Readonly<{
  items: readonly LeadResponse[];
  nextCursor: string | null;
}>;

export type LeadSummaryResponse = Readonly<{
  totalUniqueLeads: number;
  attributedLeads: number;
  excessLeads: number;
}>;
