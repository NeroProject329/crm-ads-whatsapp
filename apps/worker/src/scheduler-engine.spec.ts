import { describe, expect, it } from 'vitest';

import { computeBatchSize, selectRoundRobinMember } from './scheduler-engine.js';

describe('computeBatchSize', () => {
  it('limits the batch to the configured microbatch size', () => {
    expect(
      computeBatchSize({
        requestedLeadCount: 100,
        scheduledLeadCount: 0,
        inflightLeadCount: 0,
        maxInflightPerEmployee: 100,
        microbatchSize: 10,
      }),
    ).toBe(10);
  });

  it('respects employee backpressure', () => {
    expect(
      computeBatchSize({
        requestedLeadCount: 100,
        scheduledLeadCount: 30,
        inflightLeadCount: 95,
        maxInflightPerEmployee: 100,
        microbatchSize: 10,
      }),
    ).toBe(5);
  });

  it('does not schedule beyond the remaining request', () => {
    expect(
      computeBatchSize({
        requestedLeadCount: 100,
        scheduledLeadCount: 97,
        inflightLeadCount: 0,
        maxInflightPerEmployee: 100,
        microbatchSize: 10,
      }),
    ).toBe(3);
  });

  it('returns zero when there is no capacity', () => {
    expect(
      computeBatchSize({
        requestedLeadCount: 100,
        scheduledLeadCount: 30,
        inflightLeadCount: 100,
        maxInflightPerEmployee: 100,
        microbatchSize: 10,
      }),
    ).toBe(0);
  });
});

describe('selectRoundRobinMember', () => {
  const members = [
    { id: 'a', position: 1 },
    { id: 'b', position: 2 },
    { id: 'c', position: 3 },
  ];

  it('selects the requested position and advances the cursor', () => {
    const result = selectRoundRobinMember(members, 2);

    expect(result.member.id).toBe('b');
    expect(result.nextPosition).toBe(3);
  });

  it('wraps back to the first member', () => {
    const result = selectRoundRobinMember(members, 3);

    expect(result.member.id).toBe('c');
    expect(result.nextPosition).toBe(1);
  });

  it('recovers when positions contain gaps', () => {
    const result = selectRoundRobinMember(
      [
        { id: 'a', position: 1 },
        { id: 'c', position: 5 },
      ],
      2,
    );

    expect(result.member.id).toBe('c');
    expect(result.nextPosition).toBe(1);
  });
});
