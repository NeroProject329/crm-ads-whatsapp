# Etapa 12 - Security Hardening, Staging e Production Readiness

## Status

CONCLUIDA NO REPOSITORIO.

O codigo, validadores e runbook para staging/producao estao prontos.

A ativacao de infraestrutura remota e uma operacao de deploy e deve usar docs/STAGING_PRODUCTION_RUNBOOK.md antes do cutover.

## API security

- Helmet
- explicit HTTPS CORS allowlist em production-like
- global process-local throttling
- stricter login throttling
- stricter refresh throttling
- explicit body limit
- request timeout
- headers timeout
- keep-alive timeout
- max incoming headers count
- explicit trusted proxy hops
- no-store
- noindex/nofollow
- fail-closed production environment validation

## Webhook security

- raw body preserved
- HMAC X-Hub-Signature-256 mandatory
- explicit body size limit
- Helmet
- no-store
- noindex/nofollow
- HTTP timeouts
- liveness
- database readiness
- fail-closed Meta secrets

## Authentication

- existing password hashing preserved
- failed-login lock preserved
- access token secret validation preserved
- opaque refresh token preserved
- refresh token hash preserved
- refresh token family rotation preserved
- reuse detection preserved
- live session lookup preserved
- login and refresh throttling added

## Outbound safety

Expired SENDING without Meta message id is never automatically reclaimed.

It transitions to FAILED with OUTBOUND_DELIVERY_UNKNOWN_AFTER_LEASE.

The transition generates an audit event.

This prevents blind duplicate customer messages after crash/lost lease.

## Environment hardening

APP_ENV differentiates development/test/staging/production.

Staging and production require NODE_ENV=production.

Server-side PostgreSQL cannot point to localhost in production-like environments.

API CORS requires explicit HTTPS origins.

Service-specific provider secrets are validated before production-like boot.

## Seed hardening

Production-like seed requires explicit organization/team/admin values.

admin@example.com is rejected.

## Web security

- poweredByHeader disabled
- X-Content-Type-Options
- X-Frame-Options
- Referrer-Policy
- Permissions-Policy
- X-Robots-Tag
- HSTS in staging/production
- production-like OneSignal public app id validation

CSP final is intentionally deferred until the real frontend integration exists.

## Supply-chain security

CI executes pnpm audit against production dependencies and blocks high/critical advisories.

Existing pnpm lockfile supply-chain policies remain active.

## Runtime validation

Validated:

- production environment validators
- API process boot
- API liveness
- API database readiness
- Helmet headers
- no-store
- CORS allowed origin
- CORS denied origin
- API oversized payload -> 413
- login throttling -> 429
- webhook process boot
- webhook liveness
- webhook database readiness
- Meta verification token
- invalid Meta signature -> 401
- valid Meta HMAC
- webhook oversized payload -> 413
- no arbitrary webhook CORS
- expired SENDING -> FAILED
- no automatic resend
- active SENDING lease preserved
- outbound unknown-outcome audit
- dependency audit
- complete monorepo build
- global CI
- secret scan
- git checks

## Deployment

Use docs/STAGING_PRODUCTION_RUNBOOK.md.

After remote staging is provisioned, run scripts/verify-deployed-services.mjs.

## Proxima etapa

Etapa 13 - Cutover, release e substituicao controlada dos sistemas antigos.
