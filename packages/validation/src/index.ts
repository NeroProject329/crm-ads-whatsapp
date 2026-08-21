import { z } from 'zod';

export const nonEmptyIdSchema = z.string().trim().min(1);

export const isoDateTimeSchema = z.iso.datetime();

export const loginSchema = z.object({
  email: z.string().trim().toLowerCase().pipe(z.email().max(254)),

  organizationSlug: z
    .string()
    .trim()
    .toLowerCase()
    .min(1)
    .max(80)
    .regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/),

  password: z.string().min(1).max(256),
});

export const refreshTokenSchema = z.object({
  refreshToken: z.string().trim().min(32).max(256),
});

const uuidSchema = z.string().uuid();

const siteNameSchema = z.string().trim().min(2).max(160);

const siteSlugSchema = z
  .string()
  .trim()
  .toLowerCase()
  .min(2)
  .max(100)
  .regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/);

const siteDescriptionSchema = z.string().trim().max(500).nullable();

const siteStatusSchema = z.enum(['ACTIVE', 'PAUSED', 'ARCHIVED']);

const domainStatusSchema = z.enum(['ACTIVE', 'PAUSED', 'ARCHIVED']);

const hostnameSchema = z
  .string()
  .trim()
  .toLowerCase()
  .min(4)
  .max(253)
  .regex(/^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/);

const whatsAppNumberStatusSchema = z.enum(['ACTIVE', 'PAUSED', 'DISABLED', 'ARCHIVED']);

export function normalizeWhatsAppPhone(value: string): string {
  const original = value.trim();

  if (!original) {
    return '';
  }

  const compact = original.replace(/\s/g, '');

  let digits = original.replace(/\D/g, '');

  if (!digits) {
    return '';
  }

  if (
    original.startsWith('+') &&
    digits.length >= 8 &&
    digits.length <= 15 &&
    /^[1-9]\d+$/.test(digits)
  ) {
    return `+${digits}`;
  }

  if (compact.startsWith('00')) {
    digits = digits.slice(2);

    if (digits.length >= 8 && digits.length <= 15 && /^[1-9]\d+$/.test(digits)) {
      return `+${digits}`;
    }

    return '';
  }

  if (digits.startsWith('55') && (digits.length === 12 || digits.length === 13)) {
    return `+${digits}`;
  }

  if (digits.startsWith('0') && (digits.length === 11 || digits.length === 12)) {
    digits = digits.slice(1);
  }

  if ((digits.length === 10 || digits.length === 11) && /^[1-9]\d+$/.test(digits)) {
    return `+55${digits}`;
  }

  return '';
}

const e164Schema = z
  .string()
  .trim()
  .min(1)
  .max(64)
  .transform(normalizeWhatsAppPhone)
  .refine((value) => /^\+[1-9]\d{7,14}$/.test(value), {
    message: 'Invalid phone number.',
  });

const whatsAppDisplayNameSchema = z.string().trim().min(2).max(120);

const whatsAppNotesSchema = z.string().trim().max(500).nullable();

export const createSiteSchema = z.object({
  ownerEmployeeId: uuidSchema,
  name: siteNameSchema,
  slug: siteSlugSchema,
  description: siteDescriptionSchema.optional(),
});

export const updateSiteSchema = z
  .object({
    ownerEmployeeId: uuidSchema.optional(),
    name: siteNameSchema.optional(),
    slug: siteSlugSchema.optional(),
    description: siteDescriptionSchema.optional(),
    status: siteStatusSchema.optional(),
  })
  .refine((value) => Object.keys(value).length > 0, {
    message: 'At least one site field must be provided.',
  });

export const createSiteDomainSchema = z.object({
  hostname: hostnameSchema,
  isPrimary: z.boolean().default(false),
  monitoringEnabled: z.boolean().default(true),
});

export const updateSiteDomainSchema = z
  .object({
    hostname: hostnameSchema.optional(),
    isPrimary: z.boolean().optional(),
    monitoringEnabled: z.boolean().optional(),
    status: domainStatusSchema.optional(),
  })
  .refine((value) => Object.keys(value).length > 0, {
    message: 'At least one domain field must be provided.',
  });

export const createWhatsAppNumberSchema = z.object({
  displayName: whatsAppDisplayNameSchema,
  e164: e164Schema,
  assignedEmployeeId: uuidSchema.nullable().optional(),
  notes: whatsAppNotesSchema.optional(),
});

export const updateWhatsAppNumberSchema = z
  .object({
    displayName: whatsAppDisplayNameSchema.optional(),
    e164: e164Schema.optional(),
    assignedEmployeeId: uuidSchema.nullable().optional(),
    notes: whatsAppNotesSchema.optional(),
    status: whatsAppNumberStatusSchema.optional(),
  })
  .refine((value) => Object.keys(value).length > 0, {
    message: 'At least one WhatsApp number field must be provided.',
  });

export type LoginInput = z.infer<typeof loginSchema>;
export type RefreshTokenInput = z.infer<typeof refreshTokenSchema>;
export type CreateSiteInput = z.infer<typeof createSiteSchema>;
export type UpdateSiteInput = z.infer<typeof updateSiteSchema>;
export type CreateSiteDomainInput = z.infer<typeof createSiteDomainSchema>;
export type UpdateSiteDomainInput = z.infer<typeof updateSiteDomainSchema>;
export type CreateWhatsAppNumberInput = z.infer<typeof createWhatsAppNumberSchema>;
export type UpdateWhatsAppNumberInput = z.infer<typeof updateWhatsAppNumberSchema>;

export * from './management.js';
export * from './traffic-pool.js';
export * from './ads.js';
export * from './notifications.js';
export * from './meta-cloud.js';
export * from './inbox.js';
export * from './leads.js';
export * from './whatsapp-health.js';
