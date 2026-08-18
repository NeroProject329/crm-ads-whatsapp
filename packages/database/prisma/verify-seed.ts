import { config } from 'dotenv';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDirectory = dirname(fileURLToPath(import.meta.url));

config({
  path: resolve(scriptDirectory, '../../../.env'),
  quiet: true,
});

const { createDatabaseClient } = await import('../src/index.js');

const prisma = createDatabaseClient();

const expectedPermissionCodes = [
  'audit.read',
  'employee.manage',
  'employee.read',
  'organization.manage',
  'organization.read',
  'profile.read',
  'profile.update',
  'team.manage',
  'team.read',
  'user.manage',
  'user.read',
] as const;

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) {
    throw new Error(message);
  }
}

async function verifySeed(): Promise<void> {
  const organizationSlug = process.env.SEED_ORGANIZATION_SLUG?.trim() || 'crm-ads-whatsapp';

  const teamSlug = process.env.SEED_TEAM_SLUG?.trim() || 'equipe-principal';

  const adminEmail = (process.env.SEED_ADMIN_EMAIL?.trim() || 'admin@example.com').toLowerCase();

  const organization = await prisma.organization.findUnique({
    where: {
      slug: organizationSlug,
    },

    select: {
      id: true,
      name: true,
      slug: true,
      status: true,

      teams: {
        where: {
          slug: teamSlug,
        },

        select: {
          id: true,
          name: true,
          slug: true,
          status: true,
        },
      },

      users: {
        where: {
          emailNormalized: adminEmail,
        },

        select: {
          id: true,
          email: true,
          displayName: true,
          status: true,
          passwordHash: true,
          passwordChangedAt: true,

          employee: {
            select: {
              employeeCode: true,
              status: true,
            },
          },

          userRoles: {
            select: {
              role: {
                select: {
                  code: true,
                },
              },
            },
          },
        },
      },

      roles: {
        orderBy: {
          code: 'asc',
        },

        select: {
          code: true,
          name: true,
          isSystem: true,

          rolePermissions: {
            select: {
              permission: {
                select: {
                  code: true,
                },
              },
            },
          },
        },
      },
    },
  });

  assert(organization, `Organization ${organizationSlug} was not found.`);

  assert(organization.status === 'ACTIVE', 'Organization must be ACTIVE.');

  assert(organization.teams.length === 1, `Team ${teamSlug} was not found.`);

  assert(organization.teams[0]?.status === 'ACTIVE', 'Seed team must be ACTIVE.');

  assert(organization.users.length === 1, `ADMIN ${adminEmail} was not found.`);

  const adminUser = organization.users[0];

  assert(adminUser, 'ADMIN user was not found.');

  assert(adminUser.status === 'ACTIVE', 'ADMIN must be ACTIVE after Stage 2B.');

  assert(Boolean(adminUser.passwordHash), 'ADMIN password hash must exist after Stage 2B.');

  assert(
    Boolean(adminUser.passwordChangedAt),
    'ADMIN passwordChangedAt must exist after Stage 2B.',
  );

  assert(adminUser.employee?.status === 'ACTIVE', 'ADMIN employee record must be ACTIVE.');

  assert(
    adminUser.userRoles.some(({ role }) => role.code === 'ADMIN'),
    'ADMIN role was not assigned.',
  );

  const adminRole = organization.roles.find(({ code }) => code === 'ADMIN');

  const employeeRole = organization.roles.find(({ code }) => code === 'EMPLOYEE');

  assert(adminRole?.isSystem, 'ADMIN system role was not found.');

  assert(employeeRole?.isSystem, 'EMPLOYEE system role was not found.');

  const permissionCodes = (
    await prisma.permission.findMany({
      orderBy: {
        code: 'asc',
      },

      select: {
        code: true,
      },
    })
  ).map(({ code }) => code);

  const adminPermissionCodes = adminRole.rolePermissions
    .map(({ permission }) => permission.code)
    .sort();

  const employeePermissionCodes = employeeRole.rolePermissions
    .map(({ permission }) => permission.code)
    .sort();

  assert(
    JSON.stringify(permissionCodes) === JSON.stringify(expectedPermissionCodes),
    'Permission catalog does not match the Stage 2 seed.',
  );

  assert(
    JSON.stringify(adminPermissionCodes) === JSON.stringify(expectedPermissionCodes),
    'ADMIN must receive every Stage 2 permission.',
  );

  assert(
    JSON.stringify(employeePermissionCodes) === JSON.stringify(['profile.read', 'profile.update']),
    'EMPLOYEE permissions do not match the Stage 2 seed.',
  );

  console.log(
    JSON.stringify({
      event: 'database.seed.verified',

      organization: {
        id: organization.id,

        name: organization.name,

        slug: organization.slug,

        status: organization.status,
      },

      team: organization.teams[0],

      admin: {
        id: adminUser.id,

        email: adminUser.email,

        displayName: adminUser.displayName,

        status: adminUser.status,

        passwordConfigured: Boolean(adminUser.passwordHash),

        passwordChangedAt: adminUser.passwordChangedAt,

        employee: adminUser.employee,

        roles: adminUser.userRoles.map(({ role }) => role.code).sort(),
      },

      roles: organization.roles.map((role) => ({
        code: role.code,

        name: role.name,

        permissionCount: role.rolePermissions.length,
      })),

      permissionCount: permissionCodes.length,
    }),
  );
}

try {
  await verifySeed();
} finally {
  await prisma.$disconnect();
}
