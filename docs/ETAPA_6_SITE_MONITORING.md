# Etapa 6 - Site Monitoring

## Status

CONCLUIDA.

## Objetivo

Monitorar a disponibilidade dos dominios dos Sites e impedir novos microlotes quando o dominio primario estiver confirmado como DOWN.

## Entidades

- SiteMonitorState
- SiteMonitorCheck
- SiteMonitorIncident

## Estados

- UNKNOWN
- HEALTHY
- DEGRADED
- DOWN

## Threshold de falha

Uma falha isolada nao derruba o Site.

Com o default atual, tres falhas consecutivas alteram o dominio para DOWN e abrem um incidente.

## Recovery

Com o default atual, dois sucessos consecutivos resolvem o incidente e restauram HEALTHY.

## Scheduler

Somente o dominio primario e usado como gate operacional do scheduler.

UNKNOWN nao bloqueia.
HEALTHY nao bloqueia.
DEGRADED nao bloqueia.
DOWN bloqueia novos microlotes.

A recuperacao para HEALTHY permite que o scheduler continue automaticamente.

## Seguranca

O monitor resolve DNS antes da conexao.

Enderecos privados, loopback, link-local, metadata cloud, multicast e ranges reservados sao bloqueados.

HTTPS usa validacao TLS.

O probe conecta diretamente ao IP publico validado e preserva Host/SNI para reduzir risco de DNS rebinding.

## Concorrencia

SiteMonitorState possui claim e lease.

FOR UPDATE SKIP LOCKED evita normalmente que dois workers processem o mesmo dominio simultaneamente.

Lease expirado permite recovery por outra instancia.

## Historico

Cada probe gera SiteMonitorCheck.

O default de retencao e 14 dias.

## API

GET /api/v1/sites/:siteId/monitoring

GET /api/v1/sites/:siteId/domains/:domainId/monitoring/checks

As rotas reutilizam site.read e domain.read e respeitam o tenant e ownership ja existentes.

## Separacao de estados

SiteStatus continua representando decisao administrativa.

SiteMonitorStatus representa telemetria operacional.

Uma queda nao altera automaticamente SiteStatus.

## Validacoes executadas

- Prisma format e validate
- migration
- generate
- seed verification
- state engine unit tests
- SSRF unit tests
- failure 1 -> DEGRADED
- failure 3 -> DOWN
- incidente OPEN
- primeiro success -> DEGRADED
- segundo success -> HEALTHY
- incidente RESOLVED
- check history
- localhost SSRF blocked
- lease recovery
- two-worker concurrent claim
- scheduler blocked while DOWN
- scheduler resumes on HEALTHY
- worker process smoke
- global ci:check

## Proxima etapa

Etapa 7 - PWA e OneSignal.
