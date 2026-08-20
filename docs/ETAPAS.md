# Controle das 13 etapas

Ao final da Etapa 13, os documentos produzidos serão consolidados em um único documento mestre de implementação.

| Etapa | Escopo                                    | Estado       |
| ----: | ----------------------------------------- | ------------ |
|     1 | Fundação do monorepo                      | CONCLUIDA    |
|     2 | Identidade, organização e banco inicial   | CONCLUIDA    |
|     3 | Sites, domínios, números e Traffic Pools  | CONCLUIDA    |
|     4 | Pedidos e fila de ADS                     | CONCLUIDA    |
|     5 | Scheduler, microlotes e backpressure      | CONCLUIDA    |
|     6 | Monitoramento de sites                    | CONCLUIDA    |
|     7 | PWA e OneSignal                           | CONCLUIDA    |
|     8 | Fundação da Meta Cloud API                | CONCLUIDA    |
|     9 | Caixa de atendimento                      | CONCLUIDA    |
|    10 | Leads únicos e atribuição                 | CONCLUIDA    |
|    11 | Saúde, incidentes e contingência          | CONCLUIDA    |
|    12 | Segurança, staging e produção             | CONCLUIDA    |
|    13 | Corte operacional e desativação do legado | NÃO INICIADA |

## Histórico

### Etapa 1 — concluída em 06/08/2026

- monorepo criado;
- dependências instaladas;
- Node e pnpm alinhados;
- builds de `esbuild` e `sharp` aprovados explicitamente;
- scripts PowerShell corrigidos para fail-fast;
- estrutura, formatação, lint, typecheck, testes e builds aprovados;
- `pnpm ci:check` concluído.

### Etapa 2 — iniciada em 06/08/2026

- Subetapa 2A concluída em 11/08/2026;
- projeto Railway `crm-ads-whatsapp` criado com ambiente `development`;
- PostgreSQL provisionado com rede privada para serviços e proxy público para desenvolvimento local;
- migration inicial aplicada e seed validado;
- healthchecks da API validados contra o banco real;
- próxima subetapa: 2B, autenticação e ativação segura do ADMIN.

## Documento final planejado

```text
docs/DOCUMENTO_MESTRE_IMPLEMENTACAO_V1.md
```

## Etapa 4 - ADS Requests + Queue

Status: CONCLUIDA.

Implementado: AdsRequest, AdsQueueItem, fila persistente PostgreSQL, criacao e cancelamento transacionais, eligibility, isolamento ADMIN/EMPLOYEE, 23 permissions, EMPLOYEE com 9 permissions, runtime smoke, tenant audit e CI global.

Documentacao: docs/ETAPA_4_ADS_REQUESTS_QUEUE.md e docs/DECISOES_ETAPA_4.md.

Proxima: Etapa 5 - Scheduler, microlotes, round-robin e backpressure.

## Etapa 5 - Scheduler + Microbatches

Status: CONCLUIDA.

Implementado:

- claim atomico
- worker lease
- lease recovery
- AdsMicrobatch
- TrafficPoolSchedulerState
- round-robin persistente
- backpressure por Employee
- overflow recuperavel
- multi-worker concurrency
- scheduledLeadCount
- cancellation lifecycle Stage 5

Documentacao:

- docs/ETAPA_5_SCHEDULER_MICROBATCHES.md
- docs/DECISOES_ETAPA_5.md

Proxima: Etapa 6 - Site Monitoring.

## Etapa 6 - Site Monitoring

Status: CONCLUIDA.

Implementado:

- SiteMonitorState
- SiteMonitorCheck
- SiteMonitorIncident
- UNKNOWN / HEALTHY / DEGRADED / DOWN
- HTTPS monitoring
- SSRF protection
- failure and recovery thresholds
- incident lifecycle
- historical checks
- claim and lease
- multi-worker safety
- scheduler DOWN gate
- automatic scheduler recovery
- monitoring API

Documentacao:

- docs/ETAPA_6_SITE_MONITORING.md
- docs/DECISOES_ETAPA_6.md

Proxima: Etapa 7 - PWA e OneSignal.

## Etapa 7 - PWA + OneSignal

Status: CONCLUIDA.

Implementado:

- PWA instalavel
- zero cache offline autenticado
- OneSignal Web SDK v16
- dedicated OneSignal service worker
- external_id por User.id
- PushDevice multi-device
- NotificationPreference
- Notification
- NotificationDelivery
- register/unregister device
- persistent dispatcher
- claim e lease
- exponential retry
- concurrent idempotency
- tenant isolation
- provider mock validation

Documentacao:

- docs/ETAPA_7_PWA_ONESIGNAL.md
- docs/DECISOES_ETAPA_7.md

Proxima: Etapa 8 - Fundacao da Meta Cloud API.

## Etapa 8 - Meta Cloud API

Status: CONCLUIDA.

Implementado:

- @crm/meta-cloud-api
- Graph API client
- explicit Graph API version
- Meta normalized errors
- webhook verification challenge
- HMAC SHA-256 raw-body validation
- MetaWebhookEnvelope
- SHA-256 webhook deduplication
- WABA mapping
- Meta Phone Number ID mapping
- tenant-safe webhook resolution
- UNMATCHED and IGNORED handling
- connect/disconnect API
- claim/lease foundation for Stage 9

Documentacao:

- docs/ETAPA_8_META_CLOUD_API.md
- docs/DECISOES_ETAPA_8.md

Proxima: Etapa 9 - Inbox.

## Etapa 9 - Inbox

Status: CONCLUIDA.

Implementado:

- WhatsAppContact
- WhatsAppConversation
- WhatsAppMessage
- WhatsAppMessageStatusEvent
- WhatsAppQuickReply
- inbound webhook processor
- wamid idempotency
- customer service window 24h
- employee assignment
- persistent outbound queue
- Meta text/template outbound
- status reconciliation
- quick replies
- claim/lease/recovery
- retry protection
- tenant isolation

Documentacao:

- docs/ETAPA_9_WHATSAPP_INBOX.md
- docs/DECISOES_ETAPA_9.md

Proxima: Etapa 10 - Leads unicos e atribuicao.

## Etapa 10 - Leads unicos e atribuicao

Status: CONCLUIDA.

Implementado:

- Lead
- LeadAttribution
- Organization + waId unique lead identity
- inboundMessageCount
- WhatsApp -> ADS attribution
- FIFO microbatch consumption
- deliveredLeadCount real
- fulfilledLeadCount real
- ATTRIBUTED / EXCESS
- NUMBER_UNASSIGNED
- NO_RESERVED_CAPACITY
- concurrent contact deduplication
- concurrent slot protection
- AdsRequest fulfillment
- lead.read
- Leads API
- Employee isolation
- tenant isolation

Documentacao:

- docs/ETAPA_10_LEADS_ATRIBUICAO.md
- docs/DECISOES_ETAPA_10.md

Proxima: Etapa 11 - Saude, contingencia e recuperacao dos numeros WhatsApp.

## Etapa 11 - Saude e contingencia dos numeros WhatsApp

Status: CONCLUIDA.

Implementado:

- Meta quality rating
- phone_number_quality_update
- WhatsAppNumberHealthState
- WhatsAppNumberHealthEvent
- WhatsAppNumberIncident
- schedulerEligible
- Meta API polling
- polling claim/lease
- DEGRADED / CRITICAL / RECOVERING / DISABLED
- contingency capacity release
- AdsQueueItem reopen
- scheduler reroute
- recovery confirmation
- manual pause/resume
- health events
- incidents
- Employee isolation
- audit

Documentacao:

- docs/ETAPA_11_WHATSAPP_NUMBER_HEALTH.md
- docs/DECISOES_ETAPA_11.md

Proxima: Etapa 12 - Security hardening, staging e production readiness.

## Etapa 12 - Security Hardening, Staging e Production Readiness

Status: CONCLUIDA.

Implementado:

- HTTP security
- Helmet
- strict CORS
- API throttling
- auth throttling
- request size limits
- request/header timeouts
- trusted proxy policy
- API readiness
- webhook readiness
- Meta HMAC protection
- production environment fail-closed
- production seed fail-closed
- outbound unknown-outcome safety
- Next.js baseline headers
- dependency audit
- remote deployment verifier
- staging/production runbook

Documentacao:

- docs/ETAPA_12_SECURITY_HARDENING.md
- docs/DECISOES_ETAPA_12.md
- docs/STAGING_PRODUCTION_RUNBOOK.md

Proxima: Etapa 13 - Cutover, release e substituicao controlada.
