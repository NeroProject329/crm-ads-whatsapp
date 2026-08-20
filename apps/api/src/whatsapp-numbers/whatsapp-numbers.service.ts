import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';

import type { AuthenticatedPrincipal } from '@crm/auth';

import type { EmployeeModel, UserModel, WhatsAppNumberModel } from '@crm/database';

import type { WhatsAppNumberListResponse, WhatsAppNumberResponse } from '@crm/contracts';

import type {
  ConfigureWhatsAppMetaInput,
  CreateWhatsAppNumberInput,
  UpdateWhatsAppNumberInput,
} from '@crm/validation';

import { DatabaseService } from '../database/database.service.js';

type LoadedWhatsAppNumber = WhatsAppNumberModel & {
  assignedEmployee:
    | (Pick<EmployeeModel, 'id' | 'employeeCode' | 'userId'> & {
        user: Pick<UserModel, 'displayName'>;
      })
    | null;
};

@Injectable()
export class WhatsAppNumbersService {
  constructor(
    @Inject(DatabaseService)
    private readonly database: DatabaseService,
  ) {}

  async list(principal: AuthenticatedPrincipal): Promise<WhatsAppNumberListResponse> {
    const employeeId = this.isAdmin(principal) ? null : await this.getCurrentEmployeeId(principal);

    const numbers = await this.database.client.whatsAppNumber.findMany({
      where: {
        organizationId: principal.organizationId,

        deletedAt: null,

        ...(employeeId
          ? {
              assignedEmployeeId: employeeId,
            }
          : {}),
      },

      include: {
        assignedEmployee: {
          include: {
            user: {
              select: {
                displayName: true,
              },
            },
          },
        },
      },

      orderBy: [
        {
          displayName: 'asc',
        },
        {
          e164: 'asc',
        },
      ],
    });

    return numbers.map((number) => this.mapNumber(number));
  }

  async getById(
    principal: AuthenticatedPrincipal,
    numberId: string,
  ): Promise<WhatsAppNumberResponse> {
    const number = await this.getAccessibleNumber(principal, numberId);

    return this.mapNumber(number);
  }

  async create(
    principal: AuthenticatedPrincipal,
    input: CreateWhatsAppNumberInput,
  ): Promise<WhatsAppNumberResponse> {
    if (input.assignedEmployeeId) {
      await this.assertActiveEmployee(principal.organizationId, input.assignedEmployeeId);
    }

    try {
      const number = await this.database.client.$transaction(async (transaction) => {
        const created = await transaction.whatsAppNumber.create({
          data: {
            organizationId: principal.organizationId,

            assignedEmployeeId: input.assignedEmployeeId ?? null,

            displayName: input.displayName,

            e164: input.e164,

            notes: input.notes ?? null,
          },

          include: {
            assignedEmployee: {
              include: {
                user: {
                  select: {
                    displayName: true,
                  },
                },
              },
            },
          },
        });

        await transaction.auditLog.create({
          data: {
            organizationId: principal.organizationId,

            actorType: 'USER',

            actorUserId: principal.userId,

            action: 'whatsapp_number.created',

            resourceType: 'whatsapp_number',

            resourceId: created.id,

            outcome: 'SUCCESS',

            metadata: {
              e164: created.e164,

              assignedEmployeeId: created.assignedEmployeeId,
            },
          },
        });

        return created;
      });

      return this.mapNumber(number);
    } catch (error) {
      if (this.isUniqueConstraintError(error)) {
        throw new ConflictException({
          code: 'WHATSAPP_NUMBER_ALREADY_EXISTS',

          message: 'This WhatsApp number is already registered.',
        });
      }

      throw error;
    }
  }

  async update(
    principal: AuthenticatedPrincipal,
    numberId: string,
    input: UpdateWhatsAppNumberInput,
  ): Promise<WhatsAppNumberResponse> {
    await this.getOrganizationNumber(principal.organizationId, numberId);

    if (input.assignedEmployeeId) {
      await this.assertActiveEmployee(principal.organizationId, input.assignedEmployeeId);
    }

    try {
      const number = await this.database.client.$transaction(async (transaction) => {
        const updated = await transaction.whatsAppNumber.update({
          where: {
            id: numberId,
          },

          data: {
            ...(input.displayName !== undefined
              ? {
                  displayName: input.displayName,
                }
              : {}),

            ...(input.e164 !== undefined
              ? {
                  e164: input.e164,
                }
              : {}),

            ...(input.assignedEmployeeId !== undefined
              ? {
                  assignedEmployeeId: input.assignedEmployeeId,
                }
              : {}),

            ...(input.notes !== undefined
              ? {
                  notes: input.notes,
                }
              : {}),

            ...(input.status !== undefined
              ? {
                  status: input.status,
                }
              : {}),
          },

          include: {
            assignedEmployee: {
              include: {
                user: {
                  select: {
                    displayName: true,
                  },
                },
              },
            },
          },
        });

        await transaction.auditLog.create({
          data: {
            organizationId: principal.organizationId,

            actorType: 'USER',

            actorUserId: principal.userId,

            action: 'whatsapp_number.updated',

            resourceType: 'whatsapp_number',

            resourceId: updated.id,

            outcome: 'SUCCESS',

            metadata: {
              assignedEmployeeId: updated.assignedEmployeeId,

              status: updated.status,
            },
          },
        });

        return updated;
      });

      return this.mapNumber(number);
    } catch (error) {
      if (this.isUniqueConstraintError(error)) {
        throw new ConflictException({
          code: 'WHATSAPP_NUMBER_ALREADY_EXISTS',

          message: 'This WhatsApp number is already registered.',
        });
      }

      throw error;
    }
  }

  async configureMetaCloud(
    principal: AuthenticatedPrincipal,
    numberId: string,
    input: ConfigureWhatsAppMetaInput,
  ): Promise<WhatsAppNumberResponse> {
    await this.getOrganizationNumber(principal.organizationId, numberId);

    const connected = input.wabaId !== null && input.phoneNumberId !== null;

    try {
      const number = await this.database.client.$transaction(async (transaction) => {
        const updated = await transaction.whatsAppNumber.update({
          where: {
            id: numberId,
          },

          data: {
            metaWabaId: input.wabaId,

            metaPhoneNumberId: input.phoneNumberId,

            metaConnectedAt: connected ? new Date() : null,

            ...(!connected
              ? {
                  metaWebhookLastSeenAt: null,
                }
              : {}),
          },

          include: {
            assignedEmployee: {
              include: {
                user: {
                  select: {
                    displayName: true,
                  },
                },
              },
            },
          },
        });

        await transaction.auditLog.create({
          data: {
            organizationId: principal.organizationId,

            actorType: 'USER',

            actorUserId: principal.userId,

            action: connected
              ? 'whatsapp_number.meta_connected'
              : 'whatsapp_number.meta_disconnected',

            resourceType: 'whatsapp_number',

            resourceId: updated.id,

            outcome: 'SUCCESS',

            metadata: {
              wabaId: updated.metaWabaId,

              metaPhoneNumberId: updated.metaPhoneNumberId,
            },
          },
        });

        return updated;
      });

      return this.mapNumber(number);
    } catch (error) {
      if (this.isUniqueConstraintError(error)) {
        throw new ConflictException({
          code: 'META_PHONE_NUMBER_ALREADY_CONNECTED',

          message: 'This Meta phone number ID is already connected to another WhatsApp number.',
        });
      }

      throw error;
    }
  }
  private async getAccessibleNumber(
    principal: AuthenticatedPrincipal,
    numberId: string,
  ): Promise<LoadedWhatsAppNumber> {
    const employeeId = this.isAdmin(principal) ? null : await this.getCurrentEmployeeId(principal);

    const number = await this.database.client.whatsAppNumber.findFirst({
      where: {
        id: numberId,

        organizationId: principal.organizationId,

        deletedAt: null,

        ...(employeeId
          ? {
              assignedEmployeeId: employeeId,
            }
          : {}),
      },

      include: {
        assignedEmployee: {
          include: {
            user: {
              select: {
                displayName: true,
              },
            },
          },
        },
      },
    });

    if (!number) {
      throw new NotFoundException({
        code: 'WHATSAPP_NUMBER_NOT_FOUND',

        message: 'WhatsApp number not found.',
      });
    }

    return number;
  }

  private async getOrganizationNumber(
    organizationId: string,
    numberId: string,
  ): Promise<WhatsAppNumberModel> {
    const number = await this.database.client.whatsAppNumber.findFirst({
      where: {
        id: numberId,

        organizationId,

        deletedAt: null,
      },
    });

    if (!number) {
      throw new NotFoundException({
        code: 'WHATSAPP_NUMBER_NOT_FOUND',

        message: 'WhatsApp number not found.',
      });
    }

    return number;
  }

  private async assertActiveEmployee(organizationId: string, employeeId: string): Promise<void> {
    const employee = await this.database.client.employee.findFirst({
      where: {
        id: employeeId,

        organizationId,

        status: 'ACTIVE',

        deletedAt: null,
      },

      select: {
        id: true,
      },
    });

    if (!employee) {
      throw new BadRequestException({
        code: 'WHATSAPP_NUMBER_EMPLOYEE_INVALID',

        message: 'The selected employee is not active in this organization.',
      });
    }
  }

  private async getCurrentEmployeeId(principal: AuthenticatedPrincipal): Promise<string> {
    const employee = await this.database.client.employee.findFirst({
      where: {
        organizationId: principal.organizationId,

        userId: principal.userId,

        status: 'ACTIVE',

        deletedAt: null,
      },

      select: {
        id: true,
      },
    });

    if (!employee) {
      throw new ForbiddenException({
        code: 'EMPLOYEE_PROFILE_REQUIRED',

        message: 'An active employee profile is required.',
      });
    }

    return employee.id;
  }

  private isAdmin(principal: AuthenticatedPrincipal): boolean {
    return principal.roles.includes('ADMIN');
  }

  private mapNumber(number: LoadedWhatsAppNumber): WhatsAppNumberResponse {
    return {
      id: number.id,

      organizationId: number.organizationId,

      assignedEmployeeId: number.assignedEmployeeId,

      displayName: number.displayName,

      e164: number.e164,

      status: number.status,

      notes: number.notes,

      metaWabaId: number.metaWabaId,

      metaPhoneNumberId: number.metaPhoneNumberId,

      metaConnectedAt: number.metaConnectedAt?.toISOString() ?? null,

      metaWebhookLastSeenAt: number.metaWebhookLastSeenAt?.toISOString() ?? null,

      assignedEmployee: number.assignedEmployee
        ? {
            employeeId: number.assignedEmployee.id,

            employeeCode: number.assignedEmployee.employeeCode,

            userId: number.assignedEmployee.userId,

            displayName: number.assignedEmployee.user.displayName,
          }
        : null,

      createdAt: number.createdAt.toISOString(),

      updatedAt: number.updatedAt.toISOString(),
    };
  }

  private isUniqueConstraintError(error: unknown): boolean {
    if (typeof error !== 'object' || error === null) {
      return false;
    }

    return (
      'code' in error &&
      (
        error as {
          code?: unknown;
        }
      ).code === 'P2002'
    );
  }
}
