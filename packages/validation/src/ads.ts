import { z } from 'zod';

const uuidSchema = z.string().uuid();

const requestedLeadCountSchema = z.number().int().min(1).max(100_000);

const adsRequestNotesSchema = z.string().trim().max(500).nullable();

export const createAdsRequestSchema = z
  .object({
    siteId: uuidSchema,
    trafficPoolId: uuidSchema,
    requestedLeadCount: requestedLeadCountSchema,
    notes: adsRequestNotesSchema.optional(),
  })
  .strict();

export type CreateAdsRequestInput = z.infer<typeof createAdsRequestSchema>;
