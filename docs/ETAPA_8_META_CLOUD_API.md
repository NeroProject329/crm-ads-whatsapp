# Etapa 8 - Fundacao da Meta Cloud API

## Status

CONCLUIDA.

## Objetivo

Criar a fundacao segura para integrar numeros oficiais do WhatsApp com a Meta Cloud API e receber webhooks autenticados.

## Meta Cloud API package

Foi criado o pacote @crm/meta-cloud-api.

Responsabilidades:

- Graph API client
- Bearer authorization
- explicit Graph API version
- configurable Graph base URL
- request timeout
- normalized Meta errors
- webhook challenge verification
- webhook HMAC SHA-256 validation
- webhook metadata extraction

## Graph API version

Nenhuma versao da Graph API fica hardcoded no codigo.

Cada ambiente deve fornecer META_GRAPH_API_VERSION explicitamente.

Isso permite atualizar a versao da Graph API sem alterar a arquitetura da integracao.

## Segredos

META_ACCESS_TOKEN, META_APP_SECRET e META_WEBHOOK_VERIFY_TOKEN sao server-side only.

Esses segredos nao sao persistidos no PostgreSQL.

Nenhum deles utiliza prefixo NEXT_PUBLIC_.

## WhatsAppNumber

WhatsAppNumber agora pode armazenar:

- Meta WABA ID
- Meta Phone Number ID
- data de conexao
- ultimo webhook recebido

Meta Phone Number ID e globalmente unico no CRM.

## Webhook ingress

Endpoint:

GET /webhooks/meta/whatsapp

Usado para challenge de verificacao.

POST /webhooks/meta/whatsapp

Usado para eventos da Meta.

O POST exige x-hub-signature-256 valido calculado sobre o raw request body.

## Raw body

Nest rawBody fica habilitado no webhook-ingress.

A assinatura e calculada sobre os bytes originais recebidos, nao sobre JSON reserializado.

## MetaWebhookEnvelope

Cada payload aceito e persistido em MetaWebhookEnvelope.

Campos principais:

- payload hash SHA-256
- raw JSON normalizado
- WABA ID
- Meta Phone Number ID
- Organization resolvida
- WhatsAppNumber resolvido
- status
- receivedAt
- claim/lease foundation

## Deduplicacao

payloadHash possui unique constraint.

Retries da Meta com o mesmo raw payload nao criam um segundo envelope.

## Resolucao de tenant

O tenant nunca e aceito do payload como fonte de autoridade.

Organization e resolvida atraves do Meta Phone Number ID previamente conectado ao WhatsAppNumber.

Quando WABA ID e informado no webhook, ele tambem deve corresponder ao numero configurado.

Payload de numero desconhecido recebe status UNMATCHED.

Objetos fora de whatsapp_business_account recebem status IGNORED.

## Stage 9 readiness

MetaWebhookEnvelope ja possui status, availableAt, attempts, claim, lease e failureReason.

Na Etapa 9 a caixa de atendimento podera consumir os envelopes persistentes sem fazer processamento pesado dentro da request do webhook.

## Validacoes executadas

- Prisma format
- Prisma validate
- migration
- Prisma generate
- seed verification
- Meta package lint/typecheck/build
- webhook security tests
- payload extraction tests
- Graph client tests
- Graph error normalization
- validation tests
- API lint/typecheck/build
- webhook ingress lint/typecheck/build
- challenge valid/invalid
- signature valid/invalid
- Meta number connect
- global Meta Phone Number ID uniqueness
- number tenant isolation
- matched webhook
- webhook deduplication
- WABA mismatch
- unknown number
- ignored object
- envelope persistence
- connect/disconnect audit
- global CI
- webhook process smoke

## Proxima etapa

Etapa 9 - Inbox e processamento dos webhooks da Meta.
