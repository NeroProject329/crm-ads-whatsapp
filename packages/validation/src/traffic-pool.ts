import { z } from 'zod';

const uuidSchema = z.string().uuid();

const poolNameSchema = z.string().trim().min(2).max(160);

const poolSlugSchema = z
  .string()
  .trim()
  .toLowerCase()
  .min(2)
  .max(100)
  .regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/);

const descriptionSchema = z.string().trim().max(500).nullable();

const trafficPoolStatusSchema = z.enum(['ACTIVE', 'PAUSED', 'ARCHIVED']);

const memberStatusSchema = z.enum(['ACTIVE', 'PAUSED']);

export const createTrafficPoolSchema = z.object({
  siteId: uuidSchema,

  name: poolNameSchema,

  slug: poolSlugSchema,

  description: descriptionSchema.optional(),
});

export const updateTrafficPoolSchema = z
  .object({
    name: poolNameSchema.optional(),

    slug: poolSlugSchema.optional(),

    description: descriptionSchema.optional(),

    status: trafficPoolStatusSchema.optional(),
  })
  .refine((value) => Object.keys(value).length > 0, {
    message: 'At least one traffic pool field must be provided.',
  });

export const addTrafficPoolMemberSchema = z.object({
  whatsAppNumberId: uuidSchema,
});

export const updateTrafficPoolMemberSchema = z.object({
  status: memberStatusSchema,
});

export const reorderTrafficPoolMembersSchema = z
  .object({
    memberIds: z.array(uuidSchema).min(1).max(500),
  })
  .superRefine((value, context) => {
    const unique = new Set(value.memberIds);

    if (unique.size !== value.memberIds.length) {
      context.addIssue({
        code: 'custom',

        path: ['memberIds'],

        message: 'memberIds must not contain duplicates.',
      });
    }
  });

export type CreateTrafficPoolInput = z.infer<typeof createTrafficPoolSchema>;

export type UpdateTrafficPoolInput = z.infer<typeof updateTrafficPoolSchema>;

export type AddTrafficPoolMemberInput = z.infer<typeof addTrafficPoolMemberSchema>;

export type UpdateTrafficPoolMemberInput = z.infer<typeof updateTrafficPoolMemberSchema>;

export type ReorderTrafficPoolMembersInput = z.infer<typeof reorderTrafficPoolMembersSchema>;
