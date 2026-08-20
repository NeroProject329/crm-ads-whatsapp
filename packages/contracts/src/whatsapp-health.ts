export type MetaPhoneQualityRating = 'UNKNOWN' | 'GREEN' | 'YELLOW' | 'RED' | 'NA';

export type WhatsAppNumberHealthStatus =
  'UNKNOWN' | 'HEALTHY' | 'DEGRADED' | 'CRITICAL' | 'RECOVERING' | 'DISABLED';

export type WhatsAppNumberHealthSource =
  'META_API' | 'META_WEBHOOK' | 'CRM_SIGNAL' | 'MANUAL' | 'SYSTEM';

export type WhatsAppNumberHealthResponse = Readonly<{
  whatsAppNumberId: string;
  status: WhatsAppNumberHealthStatus;
  schedulerEligible: boolean;
  manualPaused: boolean;

  metaQualityRating: MetaPhoneQualityRating;

  metaQualityEvent: string | null;

  messagingLimitTier: string | null;

  lastReasonCode: string | null;

  lastReasonMessage: string | null;

  lastMetaSyncAt: string | null;

  lastMetaWebhookAt: string | null;

  lastHealthyAt: string | null;

  degradedSinceAt: string | null;

  criticalSinceAt: string | null;

  recoveringSinceAt: string | null;

  consecutiveHealthyChecks: number;

  consecutiveSyncFailures: number;

  nextCheckAt: string;

  updatedAt: string;
}>;

export type WhatsAppNumberHealthEventResponse = Readonly<{
  id: string;
  source: WhatsAppNumberHealthSource;
  previousStatus: WhatsAppNumberHealthStatus;
  currentStatus: WhatsAppNumberHealthStatus;
  metaQualityRating: MetaPhoneQualityRating;
  metaQualityEvent: string | null;
  messagingLimitTier: string | null;
  schedulerEligible: boolean;
  reasonCode: string | null;
  reasonMessage: string | null;
  occurredAt: string;
}>;

export type WhatsAppNumberIncidentResponse = Readonly<{
  id: string;
  status: 'OPEN' | 'RESOLVED';
  type: string;
  severity: WhatsAppNumberHealthStatus;
  openedReasonCode: string | null;
  openedReason: string | null;
  openedAt: string;
  resolvedReason: string | null;
  resolvedAt: string | null;
}>;
