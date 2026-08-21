export type ManagementOverview = Readonly<{
  employees: Readonly<{ total: number; active: number; inactive: number; onLeave: number }>;
  teams: Readonly<{ total: number; active: number }>;
  sites: Readonly<{ total: number; active: number }>;
  domains: Readonly<{ total: number; active: number }>;
  whatsAppNumbers: Readonly<{ total: number; active: number }>;
  leads: Readonly<{ total: number; attributed: number; excess: number }>;
}>;

export type ManagedTeam = Readonly<{
  id: string;
  organizationId: string;
  name: string;
  slug: string;
  description: string | null;
  status: 'ACTIVE' | 'INACTIVE';
  employeeCount: number;
  createdAt: string;
  updatedAt: string;
}>;

export type ManagedEmployee = Readonly<{
  id: string;
  organizationId: string;
  employeeCode: string;
  status: 'ACTIVE' | 'INACTIVE' | 'ON_LEAVE';
  team: Readonly<{
    id: string;
    name: string;
    slug: string;
    status: 'ACTIVE' | 'INACTIVE';
  }>;
  user: Readonly<{
    id: string;
    email: string;
    displayName: string;
    status: 'INVITED' | 'ACTIVE' | 'SUSPENDED' | 'DISABLED';
    lastLoginAt: string | null;
    createdAt: string;
  }>;
  roles: readonly 'EMPLOYEE'[];
  createdAt: string;
  updatedAt: string;
}>;

export type ManagedOrganization = Readonly<{
  id: string;
  name: string;
  slug: string;
  status: 'ACTIVE' | 'SUSPENDED' | 'ARCHIVED';
  timezone: string;
  createdAt: string;
  updatedAt: string;
}>;

export type ManagedSiteDomain = Readonly<{
  id: string;
  organizationId: string;
  siteId: string;
  hostname: string;
  isPrimary: boolean;
  status: 'ACTIVE' | 'PAUSED' | 'ARCHIVED';
  monitoringEnabled: boolean;
  createdAt: string;
  updatedAt: string;
}>;

export type ManagedSite = Readonly<{
  id: string;
  organizationId: string;
  name: string;
  slug: string;
  description: string | null;
  status: 'ACTIVE' | 'PAUSED' | 'ARCHIVED';
  domains: readonly ManagedSiteDomain[];
  createdAt: string;
  updatedAt: string;
}>;
