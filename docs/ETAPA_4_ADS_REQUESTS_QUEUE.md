# Etapa 4 - ADS Requests + Persistent Queue

## Status

CONCLUIDA.

## Objetivo

Implementar pedidos persistentes de ADS e sua entrada em uma fila de dominio recuperavel.

A Etapa 4 cria e cancela trabalho; a execucao da fila pertence a Etapa 5.

## Entidades

### AdsRequest

Status preparados: QUEUED, PROCESSING, PARTIALLY_FULFILLED, FULFILLED, CANCELLED e FAILED.

### AdsQueueItem

Status preparados: WAITING, CLAIMED, COMPLETED, CANCELLED e FAILED.

## Fonte de verdade

PostgreSQL e a fonte persistente de verdade da fila. BullMQ podera ser usado como mecanismo de execucao na Etapa 5.

## Criacao transacional

A mesma transacao cria AdsRequest QUEUED, AdsQueueItem WAITING e os AuditLogs ads_request.created e ads_queue.enqueued.

## Eligibility

O Site precisa estar ACTIVE, o Traffic Pool precisa estar ACTIVE e pertencer ao Site, deve existir TrafficPoolMember ACTIVE e o WhatsAppNumber precisa estar ACTIVE e atribuido ao owner do Site.

## Permissions

Catalogo total: 23 permissions.

EMPLOYEE: 9 permissions.

EMPLOYEE recebe ads_request.read, ads_request.manage e ads_queue.read. EMPLOYEE nao recebe ads_queue.manage.

## Endpoints

GET /api/v1/ads-requests
GET /api/v1/ads-requests/:requestId
POST /api/v1/ads-requests
POST /api/v1/ads-requests/:requestId/cancel
GET /api/v1/ads-queue
GET /api/v1/ads-queue/:queueItemId

## Cancelamento

AdsRequest: QUEUED -> CANCELLED.
AdsQueueItem: WAITING -> CANCELLED.
O cancelamento repetido e idempotente.

## Queue ordering

priority -> availableAt -> enqueuedAt -> id

## Runtime smoke validado

Rotas sem token retornam 401.
Payload invalido retorna 400.
Tenant injection retorna 400.
Pool sem numero elegivel retorna 409.
EMPLOYEE cria e le pedido proprio.
AdsRequest inicia QUEUED.
AdsQueueItem inicia WAITING.
ADMIN possui leitura organizacional.
Cancelamento atualiza request e queue.
cancelledAt e persistido.
Cancelamento e idempotente.

## Fora do escopo

Scheduler, claim, lease, microbatches, round-robin, backpressure, overflow, lead delivery e Meta transport ficam para etapas posteriores.

## Proxima etapa

Etapa 5 - Scheduler, microlotes, round-robin e backpressure.
