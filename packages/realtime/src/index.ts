export type RealtimeEnvelope<TPayload> = Readonly<{
  eventId: string;
  eventType: string;
  occurredAt: string;
  payload: TPayload;
}>;
