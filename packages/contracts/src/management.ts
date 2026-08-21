export type OrganizationManagementResponse = Readonly<{
  id: string;
  name: string;
  slug: string;
  status: 'ACTIVE' | 'SUSPENDED' | 'ARCHIVED';
  timezone: string;
  createdAt: string;
  updatedAt: string;
}>;

export type UpdateOrganizationManagementRequest = Readonly<{
  name?: string;
  timezone?: string;
}>;

export type TeamManagementStatus = 'ACTIVE' | 'INACTIVE';

export type TeamManagementResponse = Readonly<{
  id: string;
  organizationId: string;
  name: string;
  slug: string;
  description: string | null;
  status: TeamManagementStatus;
  employeeCount: number;
  createdAt: string;
  updatedAt: string;
}>;

export type TeamManagementListResponse = readonly TeamManagementResponse[];

export type CreateTeamManagementRequest = Readonly<{
  name: string;
  slug: string;
  description?: string | null;
}>;

export type UpdateTeamManagementRequest = Readonly<{
  name?: string;
  slug?: string;
  description?: string | null;
  status?: TeamManagementStatus;
}>;

export type ManagedEmployeeStatus = 'ACTIVE' | 'INACTIVE' | 'ON_LEAVE';
export type ManagedUserStatus = 'ACTIVE' | 'SUSPENDED' | 'DISABLED';

export type ManagedEmployeeTeamResponse = Readonly<{
  id: string;
  name: string;
  slug: string;
  status: TeamManagementStatus;
}>;

export type ManagedEmployeeUserResponse = Readonly<{
  id: string;
  email: string;
  displayName: string;
  status: 'INVITED' | ManagedUserStatus;
  lastLoginAt: string | null;
  createdAt: string;
}>;

export type ManagedEmployeeResponse = Readonly<{
  id: string;
  organizationId: string;
  employeeCode: string;
  status: ManagedEmployeeStatus;
  team: ManagedEmployeeTeamResponse;
  user: ManagedEmployeeUserResponse;
  roles: readonly ('ADMIN' | 'EMPLOYEE')[];
  createdAt: string;
  updatedAt: string;
}>;

export type ManagedEmployeeListResponse = readonly ManagedEmployeeResponse[];

export type CreateManagedEmployeeRequest = Readonly<{
  email: string;
  displayName: string;
  employeeCode: string;
  teamId: string;
  password: string;
}>;

export type UpdateManagedEmployeeRequest = Readonly<{
  displayName?: string;
  employeeCode?: string;
  teamId?: string;
  employeeStatus?: ManagedEmployeeStatus;
  userStatus?: ManagedUserStatus;
  password?: string;
}>;

export type ManagementOverviewResponse = Readonly<{
  employees: Readonly<{
    total: number;
    active: number;
    inactive: number;
    onLeave: number;
  }>;
  teams: Readonly<{
    total: number;
    active: number;
  }>;
  sites: Readonly<{
    total: number;
    active: number;
  }>;
  domains: Readonly<{
    total: number;
    active: number;
  }>;
  whatsAppNumbers: Readonly<{
    total: number;
    active: number;
  }>;
  leads: Readonly<{
    total: number;
    attributed: number;
    excess: number;
  }>;
}>;
