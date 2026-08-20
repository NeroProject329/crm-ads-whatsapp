import { z } from 'zod';

const metaNumericIdSchema = z.string().trim().min(5).max(64).regex(/^\d+$/);

export const configureWhatsAppMetaSchema = z
  .object({
    wabaId: metaNumericIdSchema.nullable(),

    phoneNumberId: metaNumericIdSchema.nullable(),
  })
  .strict()
  .refine(
    (value) =>
      (value.wabaId === null && value.phoneNumberId === null) ||
      (value.wabaId !== null && value.phoneNumberId !== null),
    {
      message: 'wabaId and phoneNumberId must both be provided or both be null.',
    },
  );

export type ConfigureWhatsAppMetaInput = z.infer<typeof configureWhatsAppMetaSchema>;
