# Etapa 10 - Leads unicos e atribuicao

## Status

CONCLUIDA.

## Objetivo

Conectar leads reais recebidos pelo WhatsApp aos slots reservados pelo scheduler de ADS.

## Identidade de lead

A identidade de negocio e WhatsAppContact.

WhatsAppContact ja e unico por Organization + waId.

Por isso cada contato WhatsApp gera no maximo um Lead por Organization.

Mensagens inbound posteriores incrementam inboundMessageCount, mas nao fulfilledLeadCount.

## Lead

Lead preserva:

- contato
- waId snapshot
- profile name snapshot
- primeira mensagem inbound
- primeiro numero WhatsApp
- funcionario proprietario
- firstSeenAt
- lastSeenAt
- inboundMessageCount
- status ATTRIBUTED ou EXCESS

## LeadAttribution

LeadAttribution registra de forma imutavel qual lead consumiu qual slot ADS.

A atribuicao registra:

- Lead
- AdsRequest
- AdsMicrobatch
- Employee
- WhatsAppNumber
- inbound WhatsAppMessage
- attributedAt

## Consumo de microbatch

Somente microbatches PLANNED ou DELIVERING com capacidade restante podem receber lead.

A selecao e FIFO por plannedAt, sequence e id.

O lead somente pode consumir capacidade do mesmo WhatsAppNumber e Employee.

PLANNED passa a DELIVERING na primeira entrega.

Quando deliveredLeadCount atinge reservedLeadCount, o microbatch vira COMPLETED.

## AdsRequest

Cada LeadAttribution incrementa fulfilledLeadCount exatamente uma vez.

Com entrega parcial o pedido vira PARTIALLY_FULFILLED.

Quando fulfilledLeadCount atinge requestedLeadCount, o pedido vira FULFILLED e completedAt e gravado.

## Excess

Lead sem slot reservado permanece EXCESS.

Motivos iniciais:

- NUMBER_UNASSIGNED
- NO_RESERVED_CAPACITY

Lead EXCESS nao incrementa deliveredLeadCount nem fulfilledLeadCount.

## Concorrencia

Advisory lock por Organization + Contact serializa a decisao de lead unico.

Advisory lock por Organization + WhatsAppNumber serializa o consumo de capacidade daquele numero.

A query de selecao tambem bloqueia AdsMicrobatch e AdsRequest com FOR UPDATE.

Isso protege fulfilledLeadCount mesmo quando numeros diferentes entregam simultaneamente para o mesmo AdsRequest.

## API

GET /leads

GET /leads/summary

GET /leads/:leadId

ADMIN possui visibilidade organizacional.

EMPLOYEE visualiza apenas leads cujo ownerEmployeeId corresponde ao proprio Employee.

## Permission

lead.read

ADMIN e EMPLOYEE recebem lead.read.

## Validacao

O runtime Stage 10 valida:

- webhook -> Inbox -> Lead -> LeadAttribution
- deduplicacao por waId
- inboundMessageCount
- FIFO de microbatch
- completion de microbatch
- lead excess sem capacidade
- concorrencia de consumo
- no overfill de microbatch
- no overfill de AdsRequest
- concorrencia do mesmo contato
- numero sem Employee
- Employee isolation
- tenant isolation
- audit
- worker process smoke
- global CI

## Proxima etapa

Etapa 11 - Saude, contingencia e recuperacao dos numeros WhatsApp.
