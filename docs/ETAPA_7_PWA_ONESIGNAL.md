# Etapa 7 - PWA e OneSignal

## Status

CONCLUIDA.

## PWA

O CRM e instalavel como PWA.

O PWA e intencionalmente 100% online.

O service worker raiz nao possui fetch handler e nao utiliza Cache API.

Dados autenticados, ADS, leads, WhatsApp, dashboards, tokens e demais respostas da API nao sao armazenados para uso offline.

## OneSignal

O frontend utiliza o Web SDK v16.

O User.id do CRM e utilizado como external_id no OneSignal.

Um mesmo usuario pode possuir multiplas subscriptions/dispositivos.

O service worker OneSignal utiliza escopo separado em /push/onesignal/.

## PushDevice

PushDevice registra cada subscription do navegador/dispositivo.

O registro e sincronizavel e suporta troca de conta no mesmo navegador.

Revogacao de um dispositivo nao remove os outros dispositivos do usuario.

## Preferencias

NotificationPreference armazena pushEnabled, siteMonitoring, adsUpdates e whatsappInbox.

## Notification

Notification representa o evento de notificacao independente do provider.

NotificationDelivery representa a entrega via provider.

A arquitetura permite adicionar outros canais futuramente sem acoplar eventos ao OneSignal.

## Idempotencia

idempotencyKey e unica dentro da Organization.

enqueuePush utiliza upsert para garantir idempotencia inclusive sob chamadas concorrentes.

## Dispatcher

NotificationDelivery usa PostgreSQL como fonte de verdade.

Claim utiliza FOR UPDATE SKIP LOCKED.

Lease permite recovery de workers interrompidos.

Retry utiliza backoff exponencial.

Depois do limite de tentativas a entrega e marcada FAILED.

Sem dispositivo ativo ou com push desabilitado a entrega e SKIPPED.

## Segredos

NEXT_PUBLIC_ONESIGNAL_APP_ID e publico e utilizado pelo frontend.

ONESIGNAL_API_KEY permanece apenas no backend/worker.

## API

GET /api/v1/push/devices

POST /api/v1/push/devices

DELETE /api/v1/push/devices/:subscriptionId

GET /api/v1/notifications/preferences

PATCH /api/v1/notifications/preferences

GET /api/v1/notifications

## Validacoes executadas

- Prisma format e validate
- migration
- Prisma generate
- seed verification
- validation tests
- API lint/typecheck/build
- Worker lint/typecheck/tests/build
- Web lint/typecheck/build
- manifest runtime validation
- service worker syntax
- zero offline cache
- device registration
- tenant isolation
- account switch
- unregister idempotente
- notification preferences
- concurrent enqueue idempotency
- notification tenant isolation
- SKIPPED sem dispositivo
- SKIPPED com push desabilitado
- mock OneSignal SENT
- retry e recovery
- permanent FAILED
- lease recovery
- multi-worker concurrent claim
- audit
- worker process smoke
- global ci:check

## OneSignal real

Credenciais reais nao sao necessarias para os testes locais da Etapa 7.

A configuracao real sera aplicada no ambiente apropriado usando ONESIGNAL_APP_ID, NEXT_PUBLIC_ONESIGNAL_APP_ID e ONESIGNAL_API_KEY.

## Proxima etapa

Etapa 8 - Fundacao da Meta Cloud API.
