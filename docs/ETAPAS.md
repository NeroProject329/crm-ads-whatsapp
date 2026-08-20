# Controle das 13 etapas

Ao final da Etapa 13, os documentos produzidos serão consolidados em um único documento mestre de implementação.

| Etapa | Escopo                                    | Estado                      |
| ----: | ----------------------------------------- | --------------------------- |
|     1 | Fundação do monorepo                      | CONCLUÍDA                   |
|     2 | Identidade, organização e banco inicial   | EM ANDAMENTO — 2A concluída |
|     3 | Sites, domínios, números e Traffic Pools  | NÃO INICIADA                |
|     4 | Pedidos e fila de ADS                     | CONCLUÃDA                   |
|     5 | Scheduler, microlotes e backpressure      | CONCLUÃDA                   |
|     6 | Monitoramento de sites                    | CONCLUÃDA                   |
|     7 | PWA e OneSignal                           | CONCLUÃDA                   |
|     8 | Fundação da Meta Cloud API                | NÃO INICIADA                |
|     9 | Caixa de atendimento                      | NÃO INICIADA                |
|    10 | Leads únicos e atribuição                 | NÃO INICIADA                |
|    11 | Saúde, incidentes e contingência          | NÃO INICIADA                |
|    12 | Segurança, staging e produção             | NÃO INICIADA                |
|    13 | Corte operacional e desativação do legado | NÃO INICIADA                |

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
