# Etapa 5 - Scheduler, Microbatches e Backpressure

## Status

CONCLUIDA.

## Objetivo

Transformar a fila persistente da Etapa 4 em um scheduler concorrente e recuperavel.

## Componentes

- AdsMicrobatch
- TrafficPoolSchedulerState
- AdsSchedulerService
- worker scheduler

## Contadores do AdsRequest

- requestedLeadCount: quantidade solicitada
- scheduledLeadCount: quantidade reservada em microbatches
- fulfilledLeadCount: quantidade efetivamente entregue

## Claim

O scheduler usa PostgreSQL FOR UPDATE SKIP LOCKED para claim atomico.

AdsQueueItem passa de WAITING para CLAIMED.

## Lease

O claim grava claimedByWorkerId e leaseExpiresAt.

CLAIMED com lease expirado pode ser recuperado por outro worker.

## Concorrencia

Advisory locks transacionais protegem Employee e Traffic Pool.

O lock de Employee protege backpressure.

O lock de Traffic Pool protege o cursor round-robin.

## Round-robin

TrafficPoolSchedulerState.nextPosition persiste a proxima posicao.

O cursor continua corretamente apos reinicio do worker.

## Microbatches

O scheduler reserva apenas a quantidade configurada por microlote.

Microbatches nao representam leads entregues.

## Backpressure

A capacidade e calculada por Employee considerando PLANNED e DELIVERING.

Sem capacidade, o queue item retorna para WAITING com availableAt futuro.

## Overflow

Ausencia temporaria de capacidade, pool ou numero elegivel nao causa FAILED.

O pedido permanece recuperavel.

## Scheduling completion

Quando scheduledLeadCount atinge requestedLeadCount, AdsQueueItem vira COMPLETED.

AdsRequest permanece PROCESSING ate que leads reais sejam entregues.

## Cancelamento

QUEUED, PROCESSING e PARTIALLY_FULFILLED podem ser cancelados.

Microbatches PLANNED ou DELIVERING sao cancelados junto com o pedido.

## Validacoes executadas

- unit tests do scheduler engine
- Prisma migration e generate
- round-robin 1-2-3-1-2-3
- backpressure parcial
- recuperacao apos liberar capacidade
- dois workers concorrentes
- FOR UPDATE SKIP LOCKED
- lease expirado recuperado
- audit ads_microbatch.planned
- worker process smoke
- global ci:check

## Proxima etapa

Etapa 6 - Site Monitoring.
