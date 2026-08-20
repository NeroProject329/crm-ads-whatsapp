export type MonitorStatus = 'UNKNOWN' | 'HEALTHY' | 'DEGRADED' | 'DOWN';

export type MonitorTransitionInput = Readonly<{
  previousStatus: MonitorStatus;
  consecutiveFailures: number;
  consecutiveSuccesses: number;
  hasOpenIncident: boolean;
  success: boolean;
  failureThreshold: number;
  recoveryThreshold: number;
}>;

export type MonitorTransition = Readonly<{
  status: MonitorStatus;
  consecutiveFailures: number;
  consecutiveSuccesses: number;
  openIncident: boolean;
  resolveIncident: boolean;
}>;

export function computeMonitorTransition(input: MonitorTransitionInput): MonitorTransition {
  if (input.success) {
    const consecutiveSuccesses = input.consecutiveSuccesses + 1;

    if (input.hasOpenIncident && consecutiveSuccesses < input.recoveryThreshold) {
      return {
        status: 'DEGRADED',
        consecutiveFailures: 0,
        consecutiveSuccesses,
        openIncident: false,
        resolveIncident: false,
      };
    }

    return {
      status: 'HEALTHY',
      consecutiveFailures: 0,
      consecutiveSuccesses,
      openIncident: false,

      resolveIncident: input.hasOpenIncident && consecutiveSuccesses >= input.recoveryThreshold,
    };
  }

  const consecutiveFailures = input.consecutiveFailures + 1;

  const status: MonitorStatus = consecutiveFailures >= input.failureThreshold ? 'DOWN' : 'DEGRADED';

  return {
    status,
    consecutiveFailures,
    consecutiveSuccesses: 0,

    openIncident: status === 'DOWN' && !input.hasOpenIncident,

    resolveIncident: false,
  };
}
