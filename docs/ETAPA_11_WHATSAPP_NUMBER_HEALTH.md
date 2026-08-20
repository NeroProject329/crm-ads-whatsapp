# Etapa 11 - Saude, contingencia e recuperacao dos numeros WhatsApp

## Status

CONCLUIDA.

## Separacao de conceitos

A Etapa 11 separa qualidade oficial Meta, saude operacional do CRM e elegibilidade do scheduler.

Qualidade Meta:

- GREEN
- YELLOW
- RED
- NA
- UNKNOWN

Saude operacional:

- UNKNOWN
- HEALTHY
- DEGRADED
- CRITICAL
- RECOVERING
- DISABLED

## Scheduler

schedulerEligible e a fonte operacional usada pelo ADS scheduler.

HEALTHY pode receber novos microbatches.

DEGRADED, CRITICAL, RECOVERING e DISABLED nao recebem novos microbatches.

UNKNOWN permanece fail-open para preservar numeros ainda sem sinal Meta suficiente.

## Contingencia

Quando um numero elegivel passa para estado nao elegivel, a capacidade reservada ainda nao entregue e liberada.

Microbatches afetados sao CANCELLED.

Leads ja entregues permanecem intactos.

fulfilledLeadCount nunca e reduzido.

scheduledLeadCount e reduzido apenas pela capacidade ainda nao entregue.

AdsQueueItem volta para WAITING.

O scheduler redistribui a capacidade para outro numero elegivel do Traffic Pool.

## Recuperacao

UNFLAGGED inicia RECOVERING.

Um unico GREEN nao reativa imediatamente um numero que estava degradado ou critico.

Por padrao sao exigidos dois GREEN consecutivos.

Depois da confirmacao o estado volta a HEALTHY e schedulerEligible=true.

## Incidentes

DEGRADED e CRITICAL abrem ou atualizam incidente META_QUALITY.

HEALTHY confirmado resolve o incidente.

Pause manual abre incidente MANUAL_PAUSE.

Resume manual resolve o incidente de pause.

## Meta sync

O worker consulta o phone number profile usando Graph API.

Falha de polling nao transforma automaticamente o numero em CRITICAL.

Falhas de sync sao registradas separadamente para evitar contingencias falsas por instabilidade da Meta.

## Concorrencia

Health transitions usam advisory lock por Organization + WhatsAppNumber.

O scheduler usa o mesmo advisory lock antes de criar um novo microbatch.

Isso fecha a corrida entre degradacao do numero e nova reserva ADS.

## API

GET /whatsapp-numbers/:id/health

GET /whatsapp-numbers/:id/health/events

GET /whatsapp-numbers/:id/health/incidents

POST /whatsapp-numbers/:id/health/pause

POST /whatsapp-numbers/:id/health/resume

POST /whatsapp-numbers/:id/health/sync

EMPLOYEE possui leitura apenas dos proprios numeros.

Alteracoes de contingencia exigem ADMIN.

## Validacao

Validado:

- Meta phone quality parser
- Meta quality profile polling
- quality webhook
- DOWNGRADE -> DEGRADED
- FLAGGED -> CRITICAL
- UNFLAGGED -> RECOVERING
- GREEN confirmation
- incident open/update/resolve
- capacity release
- scheduledLeadCount rollback
- fulfilledLeadCount preservation
- queue reopen
- scheduler reroute
- manual pause/resume
- Employee isolation
- audit
- worker process smoke
- global CI

## Proxima etapa

Etapa 12 - Security hardening, staging e production readiness.
