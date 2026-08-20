export type ConfigureWhatsAppMetaRequest = Readonly<{
  wabaId: string | null;
  phoneNumberId: string | null;
}>;

export type MetaConnectionResponse = Readonly<{
  wabaId: string | null;
  phoneNumberId: string | null;
  connectedAt: string | null;
  webhookLastSeenAt: string | null;
}>;
