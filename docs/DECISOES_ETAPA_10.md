# Decisoes - Etapa 10

Lead unico e definido por Organization + WhatsAppContact.

Como WhatsAppContact e unico por Organization + waId, o mesmo cliente nao consome capacidade ADS novamente ao enviar novas mensagens.

LeadAttribution e a prova persistente da entrega de um lead real.

scheduledLeadCount continua representando capacidade reservada.

fulfilledLeadCount passa a representar apenas LeadAttribution efetivamente persistida.

deliveredLeadCount passa a representar apenas LeadAttribution efetivamente persistida no AdsMicrobatch.

Microbatch e consumido somente pelo WhatsAppNumber para o qual foi reservado.

Selecao de capacidade e FIFO.

Lead recebido sem capacidade vira EXCESS e nao altera os contadores ADS.

A primeira implementacao nao reatribui automaticamente leads EXCESS antigos quando nova capacidade aparece.

Essa escolha evita atribuir retroativamente trafego recebido fora da janela operacional do microlote sem uma politica explicita.

Advisory lock por Contact protege unique lead.

Advisory lock por WhatsAppNumber protege slots locais.

FOR UPDATE em AdsMicrobatch e AdsRequest protege o contador global do pedido entre numeros diferentes.

AdsRequest FULFILLED significa requestedLeadCount leads unicos efetivamente atribuidos.

Mensagens repetidas de um lead existente continuam normalmente na Inbox.
