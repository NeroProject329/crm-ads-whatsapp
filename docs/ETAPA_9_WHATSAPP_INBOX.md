# Etapa 9 - WhatsApp Inbox

## Status

CONCLUIDA.

## Boundary

A Etapa 9 transforma os MetaWebhookEnvelope persistidos pela Etapa 8 em dados de dominio da caixa de atendimento.

## Entidades

- WhatsAppContact
- WhatsAppConversation
- WhatsAppMessage
- WhatsAppMessageStatusEvent
- WhatsAppQuickReply

## Inbound

MetaWebhookEnvelope e a fila persistente de entrada.

O worker utiliza claim atomico PostgreSQL, FOR UPDATE SKIP LOCKED, lease, recovery e retry.

A idempotencia HTTP da Etapa 8 continua baseada em payloadHash.

A idempotencia de negocio da Etapa 9 utiliza Meta message id / wamid.

Envelopes diferentes contendo o mesmo wamid nao criam uma segunda mensagem.

## Conversations

A conversa e unica por Organization + WhatsAppNumber + Contact.

Mensagens inbound reabrem a conversa e atualizam unreadCount.

Quando o numero possui Employee atribuido, novas conversas herdam essa atribuicao.

EMPLOYEE enxerga apenas conversas atribuidas ao proprio Employee.

ADMIN possui visibilidade organizacional.

## Customer service window

Cada mensagem inbound valida estende customerServiceWindowExpiresAt para 24 horas apos o timestamp da mensagem do cliente.

TEXT outbound e bloqueado fora da janela.

A regra e validada na API e novamente no dispatcher antes da chamada externa.

TEMPLATE outbound pode ser enfileirado fora da janela.

## Outbound

Mensagens outbound sao persistidas antes da chamada Meta.

clientMessageId e unique e fornece idempotencia para retries do cliente/API.

O dispatcher utiliza claim e lease PostgreSQL.

Envio utiliza Meta Phone Number ID /messages atraves de @crm/meta-cloud-api.

HTTP 429 e 5xx utilizam retry com exponential backoff.

Erro de rede com resultado externo incerto nao e reenviado cegamente.

Nessa situacao a mensagem termina FAILED com OUTBOUND_DELIVERY_UNKNOWN para evitar duplicacao ao cliente.

## Delivery status

Estados persistidos:

- SENT
- DELIVERED
- READ
- FAILED
- DELETED

Status que chega antes da persistencia do Meta message id fica em WhatsAppMessageStatusEvent e e reconciliado apos o envio.

Eventos atrasados nao rebaixam READ para DELIVERED ou SENT.

## Quick replies

Quick replies sao organizacionais, possuem shortcut unico por Organization e soft delete.

EMPLOYEE recebe quick_reply.read.

Gerenciamento de quick replies permanece administrativo.

## Permissions

- inbox.read
- inbox.manage
- quick_reply.read
- quick_reply.manage

ADMIN recebe todas.

EMPLOYEE recebe inbox.read, inbox.manage e quick_reply.read.

## Validation

O fechamento da Etapa 9 valida:

- migration e Prisma generate
- seed e permission catalog
- inbound webhook
- wamid idempotency
- concurrent inbox claim
- expired lease recovery
- employee isolation
- API clientMessageId idempotency
- 24h window na API
- 24h window no dispatcher
- text outbound mockado
- template outbound mockado
- status reconciliation
- status before send
- 429 retry
- unknown network outcome protection
- outbound lease recovery
- concurrent outbound claim
- quick replies
- tenant isolation
- audit
- worker process smoke
- global CI
- secret scan

## Proxima etapa

Etapa 10 - Leads unicos e atribuicao.
