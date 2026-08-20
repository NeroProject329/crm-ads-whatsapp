# Decisoes - Etapa 9

Webhook HTTP e processamento de dominio permanecem desacoplados.

MetaWebhookEnvelope e a fonte persistente de ingestao.

wamid e a chave de idempotencia de negocio para mensagens Meta.

metaMessageId e optional @unique porque outbound ainda nao possui wamid antes da resposta Meta.

clientMessageId e optional @unique e identifica unicamente uma tentativa logica criada pelo frontend/API.

A conversa e unica por tenant, numero WhatsApp e contato.

A janela de 24 horas deriva exclusivamente de mensagem inbound do cliente.

TEXT exige janela aberta tanto no enqueue quanto imediatamente antes do envio.

TEMPLATE e a via permitida quando a janela de atendimento esta fechada.

Claim e lease continuam PostgreSQL-first.

O worker nao depende de Redis para garantir a integridade da fila da Inbox.

HTTP 429/5xx da Meta sao retryable com backoff.

Falha de transporte com outcome desconhecido nao e reenviada automaticamente para evitar mensagem duplicada.

Status da Meta pode chegar antes da resposta de envio; por isso existe WhatsAppMessageStatusEvent separado.

EMPLOYEE acessa somente conversas atribuidas ao proprio Employee.

Mudanca de assignee e restrita a ADMIN.

Quick reply pode ser lida pelo EMPLOYEE, mas gerenciada somente com quick_reply.manage.
