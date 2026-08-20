import { describe, expect, it } from 'vitest';

import { computeMonitorTransition } from './site-monitor-engine.js';

describe('computeMonitorTransition', () => {
  it('marks the first failure as DEGRADED', () => {
    const result = computeMonitorTransition({
      previousStatus: 'HEALTHY',
      consecutiveFailures: 0,
      consecutiveSuccesses: 10,
      hasOpenIncident: false,
      success: false,
      failureThreshold: 3,
      recoveryThreshold: 2,
    });

    expect(result.status).toBe('DEGRADED');
    expect(result.consecutiveFailures).toBe(1);
    expect(result.openIncident).toBe(false);
  });

  it('opens an incident at the failure threshold', () => {
    const result = computeMonitorTransition({
      previousStatus: 'DEGRADED',
      consecutiveFailures: 2,
      consecutiveSuccesses: 0,
      hasOpenIncident: false,
      success: false,
      failureThreshold: 3,
      recoveryThreshold: 2,
    });

    expect(result.status).toBe('DOWN');
    expect(result.consecutiveFailures).toBe(3);
    expect(result.openIncident).toBe(true);
  });

  it('requires consecutive successes to recover an incident', () => {
    const firstSuccess = computeMonitorTransition({
      previousStatus: 'DOWN',
      consecutiveFailures: 3,
      consecutiveSuccesses: 0,
      hasOpenIncident: true,
      success: true,
      failureThreshold: 3,
      recoveryThreshold: 2,
    });

    expect(firstSuccess.status).toBe('DEGRADED');
    expect(firstSuccess.resolveIncident).toBe(false);

    const secondSuccess = computeMonitorTransition({
      previousStatus: firstSuccess.status,
      consecutiveFailures: firstSuccess.consecutiveFailures,
      consecutiveSuccesses: firstSuccess.consecutiveSuccesses,
      hasOpenIncident: true,
      success: true,
      failureThreshold: 3,
      recoveryThreshold: 2,
    });

    expect(secondSuccess.status).toBe('HEALTHY');
    expect(secondSuccess.resolveIncident).toBe(true);
  });

  it('marks an unknown successful domain as HEALTHY', () => {
    const result = computeMonitorTransition({
      previousStatus: 'UNKNOWN',
      consecutiveFailures: 0,
      consecutiveSuccesses: 0,
      hasOpenIncident: false,
      success: true,
      failureThreshold: 3,
      recoveryThreshold: 2,
    });

    expect(result.status).toBe('HEALTHY');
  });
});
