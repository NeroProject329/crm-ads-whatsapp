export const queueNames = {
  adsReconciliation: 'ads-reconciliation',
  adsRotation: 'ads-rotation',
  deadLetterReprocessing: 'dead-letter-reprocessing',
  leadAttribution: 'lead-attribution',
  messageOutbound: 'message-outbound',
  metaWebhookProcessing: 'meta-webhook-processing',
  numberHealthSync: 'number-health-sync',
  numberIncidentAnalysis: 'number-incident-analysis',
  oneSignalNotifications: 'onesignal-notifications',
  siteMonitoring: 'site-monitoring',
} as const;

export type QueueName = (typeof queueNames)[keyof typeof queueNames];
