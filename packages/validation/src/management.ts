import { z } from 'zod';

const uuidSchema = z.string().uuid();
const slugSchema = z.string().trim().toLowerCase().min(2).max(80).regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/);
const nullableDescriptionSchema = z.string().trim().max(500).nullable();

export const updateOrganizationManagementSchema = z
  .object({
    name: z.string().trim().min(2).max(160).optional(),
    timezone: z.string().trim().min(3).max(64).optional(),
  })
  .refine((value) => Object.keys(value).length > 0, {
    message: 'At least one organization field must be provided.',
  });

export const createTeamManagementSchema = z.object({
  name: z.string().trim().min(2).max(120),
  slug: slugSchema,
  description: nullableDescriptionSchema.optional(),
});

export const updateTeamManagementSchema = z
  .object({
    name: z.string().trim().min(2).max(120).optional(),
    slug: slugSchema.optional(),
    description: nullableDescriptionSchema.optional(),
    status: z.enum(['ACTIVE', 'INACTIVE']).optional(),
  })
  .refine((value) => Object.keys(value).length > 0, {
    message: 'At least one team field must be provided.',
  });

export const createManagedEmployeeSchema = z.object({
  email: z.string().trim().toLowerCase().pipe(z.email().max(254)),
  displayName: z.string().trim().min(2).max(160),
  employeeCode: z.string().trim().min(2).max(40),
  teamId: uuidSchema,
  password: z.string().min(12).max(256),
});

export const updateManagedEmployeeSchema = z
  .object({
    displayName: z.string().trim().min(2).max(160).optional(),
    employeeCode: z.string().trim().min(2).max(40).optional(),
    teamId: uuidSchema.optional(),
    employeeStatus: z.enum(['ACTIVE', 'INACTIVE', 'ON_LEAVE']).optional(),
    userStatus: z.enum(['ACTIVE', 'SUSPENDED', 'DISABLED']).optional(),
    password: z.string().min(12).max(256).optional(),
  })
  .refine((value) => Object.keys(value).length > 0, {
    message: 'At least one employee field must be provided.',
  });

export type UpdateOrganizationManagementInput = z.infer<typeof updateOrganizationManagementSchema>;
export type CreateTeamManagementInput = z.infer<typeof createTeamManagementSchema>;
export type UpdateTeamManagementInput = z.infer<typeof updateTeamManagementSchema>;
export type CreateManagedEmployeeInput = z.infer<typeof createManagedEmployeeSchema>;
export type UpdateManagedEmployeeInput = z.infer<typeof updateManagedEmployeeSchema>;
