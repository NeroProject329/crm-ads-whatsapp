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

const organizationName = process.env.SEED_ORGANIZATION_NAME?.trim() || 'CRM ADS WhatsApp';

const organizationSlug = process.env.SEED_ORGANIZATION_SLUG?.trim() || 'crm-ads-whatsapp';

const teamName = process.env.SEED_TEAM_NAME?.trim() || 'Equipe Principal';

const teamSlug = process.env.SEED_TEAM_SLUG?.trim() || 'equipe-principal';

const adminEmail = (process.env.SEED_ADMIN_EMAIL?.trim() || 'admin@example.com').toLowerCase();

const adminName = process.env.SEED_ADMIN_NAME?.trim() || 'Administrador';

const adminEmployeeCode = process.env.SEED_ADMIN_EMPLOYEE_CODE?.trim() || 'ADMIN001';

const permissionDefinitions = [
  ['organization.read', 'Visualizar a organizaÃ§Ã£o'],
  ['organization.manage', 'Gerenciar a organizaÃ§Ã£o'],
  ['team.read', 'Visualizar equipes'],
  ['team.manage', 'Gerenciar equipes'],
  ['user.read', 'Visualizar usuÃ¡rios'],
  ['user.manage', 'Gerenciar usuÃ¡rios'],
  ['employee.read', 'Visualizar funcionÃ¡rios'],
  ['employee.manage', 'Gerenciar funcionÃ¡rios'],
  ['audit.read', 'Visualizar auditoria'],
  ['profile.read', 'Visualizar o prÃ³prio perfil'],
  ['profile.update', 'Atualizar o prÃ³prio perfil'],

  ['site.read', 'Visualizar sites autorizados'],
  ['site.manage', 'Gerenciar sites'],
  ['domain.read', 'Visualizar domÃ­nios autorizados'],
  ['domain.manage', 'Gerenciar domÃ­nios'],
  ['whatsapp_number.read', 'Visualizar nÃºmeros WhatsApp autorizados'],
  ['whatsapp_number.manage', 'Gerenciar nÃºmeros WhatsApp'],
  ['traffic_pool.read', 'Visualizar Traffic Pools autorizados'],
  ['traffic_pool.manage', 'Gerenciar Traffic Pools'],
  ['ads_request.read', 'Visualizar pedidos de ADS autorizados'],
  ['ads_request.manage', 'Criar e gerenciar pedidos de ADS autorizados'],
  ['ads_queue.read', 'Visualizar fila de ADS autorizada'],
  ['ads_queue.manage', 'Gerenciar fila de ADS'],
  ['inbox.read', 'Visualizar caixa de atendimento WhatsApp'],
  ['inbox.manage', 'Responder e gerenciar conversas WhatsApp'],
  ['quick_reply.read', 'Visualizar respostas rapidas'],
  ['quick_reply.manage', 'Gerenciar respostas rapidas'],
] as const;

async function seed(): Promise<void> {
  const organization = await prisma.organization.upsert({
    where: {
      slug: organizationSlug,
    },

    create: {
      name: organizationName,
      slug: organizationSlug,
    },

    update: {
      name: organizationName,
      status: 'ACTIVE',
    },
  });

  const team = await prisma.team.upsert({
    where: {
      organizationId_slug: {
        organizationId: organization.id,

        slug: teamSlug,
      },
    },

    create: {
      organizationId: organization.id,

      name: teamName,

      slug: teamSlug,
    },

    update: {
      name: teamName,

      status: 'ACTIVE',
    },
  });

  const permissions = await Promise.all(
    permissionDefinitions.map(([code, description]) =>
      prisma.permission.upsert({
        where: {
          code,
        },

        create: {
          code,
          description,
        },

        update: {
          description,
        },
      }),
    ),
  );

  const adminRole = await prisma.role.upsert({
    where: {
      organizationId_code: {
        organizationId: organization.id,

        code: 'ADMIN',
      },
    },

    create: {
      organizationId: organization.id,

      code: 'ADMIN',

      name: 'Administrador',

      description: 'Acesso administrativo integral Ã  organizaÃ§Ã£o.',

      isSystem: true,
    },

    update: {
      name: 'Administrador',

      description: 'Acesso administrativo integral Ã  organizaÃ§Ã£o.',

      isSystem: true,
    },
  });

  const employeeRole = await prisma.role.upsert({
    where: {
      organizationId_code: {
        organizationId: organization.id,

        code: 'EMPLOYEE',
      },
    },

    create: {
      organizationId: organization.id,

      code: 'EMPLOYEE',

      name: 'FuncionÃ¡rio',

      description: 'Acesso operacional aos prÃ³prios recursos.',

      isSystem: true,
    },

    update: {
      name: 'FuncionÃ¡rio',

      description: 'Acesso operacional aos prÃ³prios recursos.',

      isSystem: true,
    },
  });

  await prisma.rolePermission.createMany({
    data: permissions.map((permission) => ({
      roleId: adminRole.id,

      permissionId: permission.id,
    })),

    skipDuplicates: true,
  });

  const employeePermissionCodes = new Set([
    'profile.read',
    'profile.update',
    'site.read',
    'domain.read',
    'whatsapp_number.read',
    'traffic_pool.read',
    'ads_request.read',
    'ads_request.manage',
    'ads_queue.read',
    'inbox.read',
    'inbox.manage',
    'quick_reply.read',
  ]);

  await prisma.rolePermission.createMany({
    data: permissions
      .filter((permission) => employeePermissionCodes.has(permission.code))
      .map((permission) => ({
        roleId: employeeRole.id,

        permissionId: permission.id,
      })),

    skipDuplicates: true,
  });

  const adminUser = await prisma.user.upsert({
    where: {
      organizationId_emailNormalized: {
        organizationId: organization.id,

        emailNormalized: adminEmail,
      },
    },

    create: {
      organizationId: organization.id,

      email: adminEmail,

      emailNormalized: adminEmail,

      displayName: adminName,

      status: 'INVITED',
    },

    update: {
      email: adminEmail,

      displayName: adminName,
    },
  });

  await prisma.employee.upsert({
    where: {
      organizationId_userId: {
        organizationId: organization.id,

        userId: adminUser.id,
      },
    },

    create: {
      organizationId: organization.id,

      teamId: team.id,

      userId: adminUser.id,

      employeeCode: adminEmployeeCode,

      status: 'ACTIVE',
    },

    update: {
      teamId: team.id,

      employeeCode: adminEmployeeCode,

      status: 'ACTIVE',
    },
  });

  await prisma.userRole.upsert({
    where: {
      userId_roleId: {
        userId: adminUser.id,

        roleId: adminRole.id,
      },
    },

    create: {
      organizationId: organization.id,

      userId: adminUser.id,

      roleId: adminRole.id,
    },

    update: {},
  });

  console.log(
    JSON.stringify({
      event: 'database.seed.completed',

      organizationId: organization.id,

      teamId: team.id,

      adminUserId: adminUser.id,

      adminStatus: adminUser.status,

      permissionCount: permissions.length,

      employeePermissionCount: employeePermissionCodes.size,
    }),
  );
}

try {
  await seed();
} finally {
  await prisma.$disconnect();
}
