import { z } from 'zod';

const uuidSchema = z.string().uuid();

const leadStatusSchema = z.enum(['ATTRIBUTED', 'EXCESS']);

export const leadListQuerySchema = z
  .object({
    cursor: uuidSchema.optional(),

    limit: z.coerce.number().int().min(1).max(100).default(30),

    status: leadStatusSchema.optional(),

    whatsAppNumberId: uuidSchema.optional(),

    adsRequestId: uuidSchema.optional(),

    search: z.string().trim().min(1).max(120).optional(),
  })
  .strict();

export type LeadListQuery = z.infer<typeof leadListQuerySchema>;
