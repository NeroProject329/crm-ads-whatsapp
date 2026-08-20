# Decisoes - Etapa 6

SiteStatus e SiteMonitorStatus permanecem separados.

Todos os dominios ACTIVE com monitoringEnabled=true podem ser monitorados.

Somente o dominio primario DOWN bloqueia o scheduler.

UNKNOWN e DEGRADED nao bloqueiam distribuicao.

Failure threshold default: 3.

Recovery threshold default: 2.

Checks normais: 30 segundos.

Retry em estado nao saudavel: 5 segundos.

Timeout HTTPS: 5 segundos.

Lease: 15 segundos.

Concorrencia default: 5.

Retencao de SiteMonitorCheck: 14 dias.

SSRF e mitigado por resolucao DNS, validacao de IP publico e conexao ao IP validado com Host/SNI preservados.

Site monitor e separado do monitoramento futuro de qualidade/saude de numeros WhatsApp da Etapa 11.
