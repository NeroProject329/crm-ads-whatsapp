# Decisoes - Etapa 8

A integracao utiliza a Meta WhatsApp Cloud API oficial.

Graph API version deve ser configurada por ambiente.

Nao existe versao Graph hardcoded no codigo.

Access Token, App Secret e Verify Token permanecem fora do banco.

Meta Phone Number ID e o identificador tecnico principal para resolver WhatsAppNumber no webhook.

WABA ID tambem e validado quando presente.

Webhook POST exige HMAC SHA-256 sobre raw body.

Webhook ingress deve responder rapidamente e persistir o envelope antes do processamento de dominio.

Processamento pesado fica fora da request do webhook.

Payload SHA-256 e usado para deduplicacao de retries identicos.

Webhook desconhecido nao e atribuido a nenhum tenant.

UNKNOWN number gera UNMATCHED.

Objeto que nao seja whatsapp_business_account gera IGNORED.

MetaWebhookEnvelope ja contem claim e lease para a Etapa 9.

Nenhum tenant ID enviado pela Meta substitui a resolucao interna do CRM.
