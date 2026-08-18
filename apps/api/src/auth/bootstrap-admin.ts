import '../load-environment.js';

import { hashPassword } from '@crm/security';
import { createDatabaseClient } from '@crm/database';

const organizationSlug =
  process.env.SEED_ORGANIZATION_SLUG?.trim().toLowerCase() || 'crm-ads-whatsapp';
const adminEmail = process.env.SEED_ADMIN_EMAIL?.trim().toLowerCase() || 'admin@example.com';
const password = process.env.BOOTSTRAP_ADMIN_PASSWORD;

if (!password) {
  throw new Error('BOOTSTRAP_ADMIN_PASSWORD is required.');
}

if (password.length < 12 || password.length > 256) {
  throw new Error('ADMIN password must contain between 12 and 256 characters.');
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

  const user = await prisma.user.findUnique({
    where: {
      organizationId_emailNormalized: {
        organizationId: organization.id,
        emailNormalized: adminEmail,
      },
    },
  });

  if (!user) {
    throw new Error(`Seeded ADMIN user not found: ${adminEmail}`);
  }

  const passwordHash = await hashPassword(password);
  const now = new Date();

  await prisma.$transaction([
    prisma.user.update({
      where: {
        id: user.id,
      },
      data: {
        passwordHash,
        passwordChangedAt: now,
        status: 'ACTIVE',
        failedLoginAttempts: 0,
        lockedUntil: null,
      },
    }),
    prisma.auditLog.create({
      data: {
        organizationId: organization.id,
        actorType: 'SYSTEM',
        action: 'auth.admin.bootstrap',
        resourceType: 'user',
        resourceId: user.id,
        outcome: 'SUCCESS',
        metadata: {
          emailNormalized: adminEmail,
        },
      },
    }),
  ]);

  console.log(
    JSON.stringify({
      event: 'auth.admin.bootstrap.completed',
      organizationId: organization.id,
      userId: user.id,
      userStatus: 'ACTIVE',
    }),
  );
} finally {
  await prisma.$disconnect();
}
