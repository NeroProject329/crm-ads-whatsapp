export const whatsappIntegrationStates = [
  'NOT_CONFIGURED',
  'READY',
  'DEGRADED',
  'DISCONNECTED',
] as const;

export type WhatsAppIntegrationState = (typeof whatsappIntegrationStates)[number];

// Cliente real da Cloud API será criado somente na etapa aprovada para a Meta.
