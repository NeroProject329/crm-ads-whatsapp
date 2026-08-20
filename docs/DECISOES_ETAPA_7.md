# Decisoes - Etapa 7

PWA sera utilizado para instalacao e push, nao para operacao offline.

Nao existe cache offline de respostas autenticadas.

OneSignal Web SDK v16 e o provider inicial.

User.id e o external_id do OneSignal.

PushDevice representa cada subscription individual.

OneSignal possui service worker separado em /push/onesignal/.

Notification e independente do provider.

NotificationDelivery controla a entrega persistente.

PostgreSQL continua sendo fonte de verdade do dispatcher.

Claim utiliza FOR UPDATE SKIP LOCKED.

Lease permite recovery.

Retry utiliza backoff exponencial.

Idempotency key e protegida por unique constraint e upsert.

A OneSignal API key nunca pode ser exposta no frontend.

Credenciais reais do OneSignal nao fazem parte dos testes deterministas locais.
