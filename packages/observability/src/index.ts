export type LogContext = Readonly<Record<string, unknown>>;

export function logInfo(event: string, context: LogContext = {}): void {
  console.log(
    JSON.stringify({
      event,
      level: 'info',
      timestamp: new Date().toISOString(),
      ...context,
    }),
  );
}
