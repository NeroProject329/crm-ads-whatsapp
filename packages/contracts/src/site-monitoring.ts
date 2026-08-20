export type SiteMonitorStatus = 'UNKNOWN' | 'HEALTHY' | 'DEGRADED' | 'DOWN';

export type SiteMonitorIncidentStatus = 'OPEN' | 'RESOLVED';

export type SiteMonitorIncidentResponse = Readonly<{
  id: string;
  status: SiteMonitorIncidentStatus;
  openedAt: string;
  resolvedAt: string | null;
  openedAfterFailures: number;
  lastFailureCode: string | null;
  lastFailureMessage: string | null;
}>;

export type SiteMonitorDomainResponse = Readonly<{
  domainId: string;
  hostname: string;
  isPrimary: boolean;
  monitoringEnabled: boolean;
  status: SiteMonitorStatus;
  consecutiveFailures: number;
  consecutiveSuccesses: number;
  lastCheckedAt: string | null;
  lastSuccessAt: string | null;
  lastFailureAt: string | null;
  lastHttpStatus: number | null;
  lastLatencyMs: number | null;
  lastResolvedAddress: string | null;
  lastFailureCode: string | null;
  lastFailureMessage: string | null;
  downSince: string | null;
  recoveredAt: string | null;
  nextCheckAt: string | null;
  openIncident: SiteMonitorIncidentResponse | null;
}>;

export type SiteMonitoringResponse = Readonly<{
  siteId: string;
  status: SiteMonitorStatus;
  primaryDomainId: string | null;
  domains: readonly SiteMonitorDomainResponse[];
}>;

export type SiteMonitorCheckResponse = Readonly<{
  id: string;
  siteId: string;
  siteDomainId: string;
  outcome: 'SUCCESS' | 'FAILURE';
  statusBefore: SiteMonitorStatus;
  statusAfter: SiteMonitorStatus;
  httpStatus: number | null;
  latencyMs: number | null;
  resolvedAddress: string | null;
  failureCode: string | null;
  failureMessage: string | null;
  checkedAt: string;
}>;

export type SiteMonitorCheckListResponse = readonly SiteMonitorCheckResponse[];
