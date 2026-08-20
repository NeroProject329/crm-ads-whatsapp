# Decisoes - Etapa 11

Qualidade oficial da Meta nao e inferida pelo tempo.

quality_rating da Meta e persistido separadamente do estado operacional do CRM.

Falha ao consultar a Meta nao significa automaticamente que o numero esta ruim.

YELLOW e DOWNGRADE bloqueiam novas reservas de ADS por estrategia conservadora.

RED e FLAGGED geram CRITICAL.

UNFLAGGED nao significa recuperacao completa; o numero entra em RECOVERING.

Dois GREEN consecutivos sao exigidos por padrao antes de reativar o scheduler.

Capacidade reservada ainda nao entregue e liberada quando o numero se torna inelegivel.

Leads ja entregues nunca sao removidos nem reatribuidos.

fulfilledLeadCount nunca e reduzido pela contingencia.

scheduledLeadCount e reduzido apenas pelo outstanding do microbatch cancelado.

O queue item volta para WAITING para permitir redistribuicao.

O scheduler escolhe somente numeros com schedulerEligible=true ou numeros sem HealthState legado.

Health domain e scheduler compartilham advisory lock por numero para eliminar race condition.

UNKNOWN e fail-open nesta etapa.

Pause/resume manual e separado do status base WhatsAppNumber.

Resume de numero conectado a Meta entra em RECOVERING antes de receber ADS novamente.
