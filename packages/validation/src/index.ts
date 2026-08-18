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

export type LoginInput = z.infer<typeof loginSchema>;

export type RefreshTokenInput = z.infer<typeof refreshTokenSchema>;
