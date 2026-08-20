import { z } from 'zod';

const optionalLabelSchema = z.string().trim().min(1).max(120).nullable();

const optionalClientSchema = z.string().trim().min(1).max(80).nullable();

export const registerPushDeviceSchema = z
  .object({
    subscriptionId: z.string().uuid(),

    oneSignalId: z.string().uuid().nullable().optional(),

    optedIn: z.boolean(),

    platform: optionalClientSchema.optional(),

    browser: optionalClientSchema.optional(),

    deviceLabel: optionalLabelSchema.optional(),
  })
  .strict();

export const updateNotificationPreferenceSchema = z
  .object({
    pushEnabled: z.boolean().optional(),

    siteMonitoring: z.boolean().optional(),

    adsUpdates: z.boolean().optional(),

    whatsappInbox: z.boolean().optional(),
  })
  .strict()
  .refine((value) => Object.keys(value).length > 0, {
    message: 'At least one notification preference must be provided.',
  });

export type RegisterPushDeviceInput = z.infer<typeof registerPushDeviceSchema>;

export type UpdateNotificationPreferenceInput = z.infer<typeof updateNotificationPreferenceSchema>;
