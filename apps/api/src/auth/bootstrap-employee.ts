import '../load-environment.js';

import { createDatabaseClient } from '@crm/database';
import { hashPassword } from '@crm/security';

const organizationSlug =
  process.env.SEED_ORGANIZATION_SLUG?.trim().toLowerCase() || 'crm-ads-whatsapp';

const employeeEmail =
  process.env.BOOTSTRAP_EMPLOYEE_EMAIL?.trim().toLowerCase() || 'employee@example.com';

const employeeName = process.env.BOOTSTRAP_EMPLOYEE_NAME?.trim() || 'Funcionário de Teste';

const employeeCode = process.env.BOOTSTRAP_EMPLOYEE_CODE?.trim() || 'EMP001';

const password = process.env.BOOTSTRAP_EMPLOYEE_PASSWORD;

if (!password) {
  throw new Error('BOOTSTRAP_EMPLOYEE_PASSWORD is required.');
}

if (password.length < 12 || password.length > 256) {
  throw new Error('EMPLOYEE password must contain between 12 and 256 characters.');
}

const prisma = createDatabaseClient();

try {
  const organization = await prisma.organization.findUnique({
    where: {
      slug: organizationSlug,
    },
  });

  if (!organization) {
    throw new Error(`Organization not found: ${organizationSlug}`);
  }

  const team = await prisma.team.findFirst({
    where: {
      organizationId: organization.id,
      status: 'ACTIVE',
    },
    orderBy: {
      createdAt: 'asc',
    },
  });

  if (!team) {
    throw new Error('No active team found for organization.');
  }

  const employeeRole = await prisma.role.findUnique({
    where: {
      organizationId_code: {
        organizationId: organization.id,
        code: 'EMPLOYEE',
      },
    },
  });

  if (!employeeRole) {
    throw new Error('EMPLOYEE role was not found.');
  }

  const passwordHash = await hashPassword(password);

  const now = new Date();

  const user = await prisma.user.upsert({
    where: {
      organizationId_emailNormalized: {
        organizationId: organization.id,
        emailNormalized: employeeEmail,
      },
    },

    create: {
      organizationId: organization.id,
      email: employeeEmail,
      emailNormalized: employeeEmail,
      displayName: employeeName,
      passwordHash,
      passwordChangedAt: now,
      status: 'ACTIVE',
      failedLoginAttempts: 0,
    },

    update: {
      email: employeeEmail,
      displayName: employeeName,
      passwordHash,
      passwordChangedAt: now,
      status: 'ACTIVE',
      failedLoginAttempts: 0,
      lockedUntil: null,
    },
  });

  const employee = await prisma.employee.upsert({
    where: {
      organizationId_userId: {
        organizationId: organization.id,
        userId: user.id,
      },
    },

    create: {
      organizationId: organization.id,
      teamId: team.id,
      userId: user.id,
      employeeCode,
      status: 'ACTIVE',
    },

    update: {
      teamId: team.id,
      employeeCode,
      status: 'ACTIVE',
    },
  });

  await prisma.userRole.upsert({
    where: {
      userId_roleId: {
        userId: user.id,
        roleId: employeeRole.id,
      },
    },

    create: {
      organizationId: organization.id,
      userId: user.id,
      roleId: employeeRole.id,
    },

    update: {},
  });

  await prisma.auditLog.create({
    data: {
      organizationId: organization.id,
      actorType: 'SYSTEM',
      action: 'auth.employee.bootstrap',
      resourceType: 'user',
      resourceId: user.id,
      outcome: 'SUCCESS',
      metadata: {
        emailNormalized: employeeEmail,
        employeeCode,
      },
    },
  });

  console.log(
    JSON.stringify({
      event: 'auth.employee.bootstrap.completed',
      organizationId: organization.id,
      userId: user.id,
      employeeId: employee.id,
      employeeCode,
      role: 'EMPLOYEE',
      userStatus: 'ACTIVE',
    }),
  );
} finally {
  await prisma.$disconnect();
}
