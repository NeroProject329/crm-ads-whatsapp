export const roles = ['ADMIN', 'EMPLOYEE'] as const;

export type Role = (typeof roles)[number];

export type AuthenticatedPrincipal = Readonly<{
  organizationId: string;
  role: Role;
  userId: string;
}>;
