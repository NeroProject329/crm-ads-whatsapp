export type HealthStatus = 'ok' | 'degraded' | 'error';

export type HealthPayload = Readonly<{
  service: string;
  status: HealthStatus;
  timestamp: string;
  version: string;
}>;

export function createHealthPayload(service: string, version: string): HealthPayload {
  return {
    service,
    status: 'ok',
    timestamp: new Date().toISOString(),
    version,
  };
}
