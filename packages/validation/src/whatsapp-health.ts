import { z } from 'zod';

export const whatsAppHealthHistoryQuerySchema = z
  .object({
    limit: z.coerce.number().int().min(1).max(200).default(50),
  })
  .strict();

export type WhatsAppHealthHistoryQuery = z.infer<typeof whatsAppHealthHistoryQuerySchema>;
