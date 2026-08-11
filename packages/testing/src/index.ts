export const fixedTestDate = new Date('2026-08-06T00:00:00.000Z');

export function createTestId(prefix: string, sequence = 1): string {
  return `${prefix}-${sequence}`;
}
