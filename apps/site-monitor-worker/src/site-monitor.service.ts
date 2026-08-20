import type { CrmDatabaseClient } from '@crm/database';

import { computeMonitorTransition } from './site-monitor-engine.js';

import type { SiteMonitorConfig } from './site-monitor.config.js';

import { probeHostname, type SiteProbeResult } from './safe-probe.js';

export type SiteProbe = (hostname: string, timeoutMs: number) => Promise<SiteProbeResult>;

type ClaimedMonitorState = Readonly<{
  id: string;
  organizationId: string;
  siteId: string;
  siteDomainId: string;
}>;

type ProcessResult = Readonly<{
  checked: boolean;
  success: boolean;
  openedIncident: boolean;
  resolvedIncident: boolean;
  lostLease: boolean;
}>;

export type SiteMonitorTickSummary = Readonly<{
  claimed: number;
  checked: number;
  successes: number;
  failures: number;
  openedIncidents: number;
  resolvedIncidents: number;
  lostLeases: number;
}>;

function addMilliseconds(value: Date, milliseconds: number): Date {
  return new Date(value.getTime() + milliseconds);
}

function subtractDays(value: Date, days: number): Date {
  return new Date(value.getTime() - days * 24 * 60 * 60 * 1000);
}

export class SiteMonitorService {
  private nextStateSyncAt = 0;
  private nextCleanupAt = 0;

  constructor(
    private readonly database: CrmDatabaseClient,

    private readonly workerId: string,

    private readonly config: SiteMonitorConfig,

    private readonly probe: SiteProbe = probeHostname,

    private readonly scopeSiteDomainId: string | null = null,
  ) {}

  async runTick(): Promise<SiteMonitorTickSummary> {
    const now = Date.now();

    if (now >= this.nextStateSyncAt) {
      await this.ensureMonitorStates();

      this.nextStateSyncAt = now + this.config.stateSyncIntervalMs;
    }

    if (now >= this.nextCleanupAt) {
      await this.cleanupOldChecks();

      this.nextCleanupAt = now + this.config.cleanupIntervalMs;
    }

    let claimedCount = 0;
    let checkedCount = 0;
    let successes = 0;
    let failures = 0;
    let openedIncidents = 0;
    let resolvedIncidents = 0;
    let lostLeases = 0;

    while (claimedCount < this.config.maxClaimsPerTick) {
      const remaining = this.config.maxClaimsPerTick - claimedCount;

      const batchSize = Math.min(this.config.concurrency, remaining);

      const claims: ClaimedMonitorState[] = [];

      for (let index = 0; index < batchSize; index += 1) {
        const claimed = await this.claimNextState();

        if (!claimed) {
          break;
        }

        claims.push(claimed);
      }

      if (claims.length === 0) {
        break;
      }

      claimedCount += claims.length;

      const results = await Promise.all(
        claims.map(async (claim) => {
          try {
            return await this.processClaim(claim);
          } catch (error) {
            await this.handleProcessingError(claim);

            console.error(
              JSON.stringify({
                event: 'site_monitor.processing_error',
                siteDomainId: claim.siteDomainId,
                message: error instanceof Error ? error.message : String(error),
              }),
            );

            return {
              checked: false,
              success: false,
              openedIncident: false,
              resolvedIncident: false,
              lostLease: false,
            } satisfies ProcessResult;
          }
        }),
      );

      for (const result of results) {
        if (result.checked) {
          checkedCount += 1;

          if (result.success) {
            successes += 1;
          } else {
            failures += 1;
          }
        }

        if (result.openedIncident) {
          openedIncidents += 1;
        }

        if (result.resolvedIncident) {
          resolvedIncidents += 1;
        }

        if (result.lostLease) {
          lostLeases += 1;
        }
      }

      if (claims.length < batchSize) {
        break;
      }
    }

    return {
      claimed: claimedCount,
      checked: checkedCount,
      successes,
      failures,
      openedIncidents,
      resolvedIncidents,
      lostLeases,
    };
  }

  private async ensureMonitorStates(): Promise<void> {
    const domains = await this.database.siteDomain.findMany({
      where: {
        monitoringEnabled: true,

        ...(this.scopeSiteDomainId
          ? {
              id: this.scopeSiteDomainId,
            }
          : {}),
        status: 'ACTIVE',
        deletedAt: null,

        site: {
          status: 'ACTIVE',
          deletedAt: null,
        },
      },

      select: {
        organizationId: true,
        siteId: true,
        id: true,
      },
    });

    if (domains.length === 0) {
      return;
    }

    await this.database.siteMonitorState.createMany({
      data: domains.map((domain) => ({
        organizationId: domain.organizationId,

        siteId: domain.siteId,

        siteDomainId: domain.id,
      })),

      skipDuplicates: true,
    });
  }

  private async cleanupOldChecks(): Promise<void> {
    const cutoff = subtractDays(new Date(), this.config.checkRetentionDays);

    await this.database.siteMonitorCheck.deleteMany({
      where: {
        checkedAt: {
          lt: cutoff,
        },
      },
    });
  }

  private async claimNextState(): Promise<ClaimedMonitorState | null> {
    const rows = await this.database.$queryRawUnsafe<ClaimedMonitorState[]>(
      `
          WITH candidate AS (
            SELECT
              state."id"
            FROM
              "site_monitor_states" state
            INNER JOIN
              "site_domains" domain
                ON domain."id" = state."siteDomainId"
                AND domain."organizationId" = state."organizationId"
            INNER JOIN
              "sites" site
                ON site."id" = state."siteId"
                AND site."organizationId" = state."organizationId"
            WHERE
              domain."monitoringEnabled" = TRUE
              AND (
                $3::uuid IS NULL
                OR state."siteDomainId" = $3::uuid
              )
              AND domain."status" = 'ACTIVE'
              AND domain."deletedAt" IS NULL
              AND site."status" = 'ACTIVE'
              AND site."deletedAt" IS NULL
              AND (
                (
                  state."claimedByWorkerId" IS NULL
                  AND state."nextCheckAt" <= NOW()
                )
                OR
                (
                  state."leaseExpiresAt" IS NOT NULL
                  AND state."leaseExpiresAt" <= NOW()
                )
              )
            ORDER BY
              state."nextCheckAt" ASC,
              state."id" ASC
            FOR UPDATE OF state SKIP LOCKED
            LIMIT 1
          )
          UPDATE
            "site_monitor_states" AS state
          SET
            "claimedAt" = NOW(),
            "claimedByWorkerId" = $1,
            "leaseExpiresAt" =
              NOW() + ($2::int * INTERVAL '1 millisecond'),
            "updatedAt" = NOW()
          FROM
            candidate
          WHERE
            state."id" = candidate."id"
          RETURNING
            state."id",
            state."organizationId",
            state."siteId",
            state."siteDomainId"
        `,
      this.workerId,
      this.config.leaseMs,
      this.scopeSiteDomainId,
    );

    return rows[0] ?? null;
  }

  private async processClaim(claimed: ClaimedMonitorState): Promise<ProcessResult> {
    const now = new Date();

    const state = await this.database.siteMonitorState.findFirst({
      where: {
        id: claimed.id,
        claimedByWorkerId: this.workerId,

        leaseExpiresAt: {
          gt: now,
        },
      },

      include: {
        siteDomain: {
          include: {
            site: true,
          },
        },
      },
    });

    if (!state) {
      return {
        checked: false,
        success: false,
        openedIncident: false,
        resolvedIncident: false,
        lostLease: true,
      };
    }

    if (
      state.siteDomain.monitoringEnabled !== true ||
      state.siteDomain.status !== 'ACTIVE' ||
      state.siteDomain.deletedAt !== null ||
      state.siteDomain.site.status !== 'ACTIVE' ||
      state.siteDomain.site.deletedAt !== null
    ) {
      await this.database.siteMonitorState.updateMany({
        where: {
          id: state.id,
          claimedByWorkerId: this.workerId,
        },

        data: {
          claimedAt: null,
          claimedByWorkerId: null,
          leaseExpiresAt: null,

          nextCheckAt: addMilliseconds(now, this.config.checkIntervalMs),
        },
      });

      return {
        checked: false,
        success: false,
        openedIncident: false,
        resolvedIncident: false,
        lostLease: false,
      };
    }

    const probe = await this.probe(state.siteDomain.hostname, this.config.timeoutMs);

    return this.database.$transaction(async (transaction) => {
      await transaction.$queryRawUnsafe(
        `
            WITH lock_guard AS MATERIALIZED (
              SELECT
                pg_advisory_xact_lock(
                  hashtextextended($1, 0)
                )
            )
            SELECT TRUE AS locked
            FROM lock_guard
          `,
        `site-domain:${state.siteDomainId}`,
      );

      const current = await transaction.siteMonitorState.findFirst({
        where: {
          id: state.id,

          claimedByWorkerId: this.workerId,

          leaseExpiresAt: {
            gt: new Date(),
          },
        },

        include: {
          siteDomain: true,
        },
      });

      if (!current) {
        return {
          checked: false,
          success: false,
          openedIncident: false,
          resolvedIncident: false,
          lostLease: true,
        };
      }

      const openIncident = await transaction.siteMonitorIncident.findFirst({
        where: {
          organizationId: current.organizationId,

          siteDomainId: current.siteDomainId,

          status: 'OPEN',
        },

        orderBy: {
          openedAt: 'desc',
        },
      });

      const transition = computeMonitorTransition({
        previousStatus: current.status,

        consecutiveFailures: current.consecutiveFailures,

        consecutiveSuccesses: current.consecutiveSuccesses,

        hasOpenIncident: Boolean(openIncident),

        success: probe.success,

        failureThreshold: this.config.failureThreshold,

        recoveryThreshold: this.config.recoveryThreshold,
      });

      const checkedAt = new Date();

      await transaction.siteMonitorCheck.create({
        data: {
          organizationId: current.organizationId,

          siteId: current.siteId,

          siteDomainId: current.siteDomainId,

          outcome: probe.success ? 'SUCCESS' : 'FAILURE',

          statusBefore: current.status,

          statusAfter: transition.status,

          httpStatus: probe.httpStatus,

          latencyMs: probe.latencyMs,

          resolvedAddress: probe.resolvedAddress,

          failureCode: probe.failureCode,

          failureMessage: probe.failureMessage,

          checkedAt,
        },
      });

      const nextDelayMs =
        transition.status === 'HEALTHY' ? this.config.checkIntervalMs : this.config.retryDelayMs;

      await transaction.siteMonitorState.update({
        where: {
          id: current.id,
        },

        data: {
          status: transition.status,

          consecutiveFailures: transition.consecutiveFailures,

          consecutiveSuccesses: transition.consecutiveSuccesses,

          lastCheckedAt: checkedAt,

          lastSuccessAt: probe.success ? checkedAt : current.lastSuccessAt,

          lastFailureAt: probe.success ? current.lastFailureAt : checkedAt,

          lastHttpStatus: probe.httpStatus,

          lastLatencyMs: probe.latencyMs,

          lastResolvedAddress: probe.resolvedAddress,

          lastFailureCode: probe.success ? null : probe.failureCode,

          lastFailureMessage: probe.success ? null : probe.failureMessage,

          downSince:
            transition.status === 'DOWN'
              ? (current.downSince ?? checkedAt)
              : transition.resolveIncident
                ? null
                : current.downSince,

          recoveredAt: transition.resolveIncident ? checkedAt : current.recoveredAt,

          nextCheckAt: addMilliseconds(checkedAt, nextDelayMs),

          claimedAt: null,
          claimedByWorkerId: null,
          leaseExpiresAt: null,
        },
      });

      if (transition.openIncident) {
        await transaction.siteMonitorIncident.create({
          data: {
            organizationId: current.organizationId,

            siteId: current.siteId,

            siteDomainId: current.siteDomainId,

            status: 'OPEN',

            openedAfterFailures: transition.consecutiveFailures,

            lastFailureCode: probe.failureCode,

            lastFailureMessage: probe.failureMessage,
          },
        });

        await transaction.auditLog.create({
          data: {
            organizationId: current.organizationId,

            actorType: 'SYSTEM',

            action: 'site_monitor.down',

            resourceType: 'site_domain',

            resourceId: current.siteDomainId,

            outcome: 'SUCCESS',

            metadata: {
              siteId: current.siteId,

              hostname: current.siteDomain.hostname,

              consecutiveFailures: transition.consecutiveFailures,

              failureCode: probe.failureCode,

              httpStatus: probe.httpStatus,
            },
          },
        });
      } else if (!probe.success && openIncident) {
        await transaction.siteMonitorIncident.update({
          where: {
            id: openIncident.id,
          },

          data: {
            lastFailureCode: probe.failureCode,

            lastFailureMessage: probe.failureMessage,
          },
        });
      }

      if (transition.resolveIncident && openIncident) {
        await transaction.siteMonitorIncident.update({
          where: {
            id: openIncident.id,
          },

          data: {
            status: 'RESOLVED',
            resolvedAt: checkedAt,
          },
        });

        await transaction.auditLog.create({
          data: {
            organizationId: current.organizationId,

            actorType: 'SYSTEM',

            action: 'site_monitor.recovered',

            resourceType: 'site_domain',

            resourceId: current.siteDomainId,

            outcome: 'SUCCESS',

            metadata: {
              siteId: current.siteId,

              hostname: current.siteDomain.hostname,

              recoverySuccesses: transition.consecutiveSuccesses,

              httpStatus: probe.httpStatus,

              latencyMs: probe.latencyMs,
            },
          },
        });
      }

      return {
        checked: true,
        success: probe.success,
        openedIncident: transition.openIncident,
        resolvedIncident: transition.resolveIncident,
        lostLease: false,
      };
    });
  }

  private async handleProcessingError(claimed: ClaimedMonitorState): Promise<void> {
    await this.database.siteMonitorState.updateMany({
      where: {
        id: claimed.id,

        claimedByWorkerId: this.workerId,
      },

      data: {
        claimedAt: null,
        claimedByWorkerId: null,
        leaseExpiresAt: null,

        nextCheckAt: addMilliseconds(new Date(), this.config.retryDelayMs),
      },
    });
  }
}
