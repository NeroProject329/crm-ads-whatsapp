export type BatchSizeInput = Readonly<{
  requestedLeadCount: number;
  scheduledLeadCount: number;
  inflightLeadCount: number;
  maxInflightPerEmployee: number;
  microbatchSize: number;
}>;

export function computeBatchSize(input: BatchSizeInput): number {
  const remaining = Math.max(0, input.requestedLeadCount - input.scheduledLeadCount);

  const availableCapacity = Math.max(0, input.maxInflightPerEmployee - input.inflightLeadCount);

  return Math.min(remaining, availableCapacity, input.microbatchSize);
}

export type PositionedMember = Readonly<{
  position: number;
}>;

export type RoundRobinSelection<T extends PositionedMember> = Readonly<{
  member: T;
  nextPosition: number;
}>;

export function selectRoundRobinMember<T extends PositionedMember>(
  members: readonly T[],
  nextPosition: number,
): RoundRobinSelection<T> {
  if (members.length === 0) {
    throw new Error('Cannot select a member from an empty Traffic Pool.');
  }

  const ordered = [...members].sort((left, right) => left.position - right.position);

  const selectedIndex = ordered.findIndex((member) => member.position >= nextPosition);

  const normalizedIndex = selectedIndex >= 0 ? selectedIndex : 0;

  const member = ordered[normalizedIndex];

  if (!member) {
    throw new Error('Round-robin member selection failed.');
  }

  const followingMember = ordered[normalizedIndex + 1] ?? ordered[0];

  if (!followingMember) {
    throw new Error('Round-robin next member selection failed.');
  }

  return {
    member,
    nextPosition: followingMember.position,
  };
}
