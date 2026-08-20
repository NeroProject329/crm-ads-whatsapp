# Staging e Production Runbook

## Objetivo

Checklist operacional para publicar CRM ADS WhatsApp sem misturar credenciais, bancos ou callbacks entre ambientes.

## Regra central

Staging e production devem possuir configuracoes e credenciais independentes sempre que o provedor permitir.

Nunca reutilizar banco de production em staging.

Nunca versionar secrets.

## API

Required:

- NODE_ENV=production
- APP_ENV=staging ou production
- DATABASE_URL
- AUTH_ACCESS_TOKEN_SECRET
- AUTH_REFRESH_TOKEN_PEPPER
- API_CORS_ALLOWED_ORIGINS
- HTTP_TRUST_PROXY_HOPS configurado para a topologia real

AUTH_ACCESS_TOKEN_SECRET e AUTH_REFRESH_TOKEN_PEPPER devem ser diferentes.

CORS em staging/producao aceita apenas origins HTTPS explicitas.

Health:

- /api/v1/health/live
- /api/v1/health/ready

## Meta webhook ingress

Required:

- NODE_ENV=production
- APP_ENV=staging ou production
- DATABASE_URL
- META_APP_SECRET
- META_WEBHOOK_VERIFY_TOKEN

Health:

- /health/live
- /health/ready

Callback Meta:

- HTTPS obrigatorio
- X-Hub-Signature-256 obrigatoria para POST
- raw body preservado
- payload limitado

Nao usar um rate limit humano agressivo por IP no callback da Meta.

## Worker

Required:

- NODE_ENV=production
- APP_ENV=staging ou production
- DATABASE_URL
- META_GRAPH_API_VERSION
- META_ACCESS_TOKEN
- ONESIGNAL_APP_ID
- ONESIGNAL_API_KEY

Apenas uma configuracao de ambiente deve ser utilizada por processo.

Nunca compartilhar DATABASE_URL de production com worker staging.

## Site monitor worker

Required:

- NODE_ENV=production
- APP_ENV=staging ou production
- DATABASE_URL

## Web

Required em staging/producao:

- NODE_ENV=production
- APP_ENV=staging ou production
- NEXT_PUBLIC_ONESIGNAL_APP_ID

## PostgreSQL

- nao expor credenciais no repositorio
- staging e production separados
- migrations executadas com prisma migrate deploy
- nunca executar prisma migrate dev em production
- backup habilitado no provedor
- acesso publico desabilitado quando a plataforma permitir rede privada entre servicos

## Seed

Seed em staging/producao exige explicitamente:

- SEED_ORGANIZATION_NAME
- SEED_ORGANIZATION_SLUG
- SEED_TEAM_NAME
- SEED_TEAM_SLUG
- SEED_ADMIN_EMAIL
- SEED_ADMIN_NAME
- SEED_ADMIN_EMPLOYEE_CODE

admin@example.com e proibido em staging/producao.

Seed deve ser uma operacao de release explicita, nunca um comando automatico em todo restart.

## Edge / WAF

A API possui rate limiting por processo como defense in depth.

Em staging/producao deve existir tambem rate limiting distribuido no edge/WAF.

Aplicar politica mais restritiva em login e refresh.

Nao aplicar bloqueio agressivo de callback Meta baseado apenas em IP.

TLS deve ser obrigatorio.

## Outbound WhatsApp

SENDING com lease expirado e outcome desconhecido nunca e reenviado automaticamente.

O registro passa para FAILED / OUTBOUND_DELIVERY_UNKNOWN_AFTER_LEASE.

Reconciliar manualmente antes de qualquer reenvio.

## Deploy order

1. Provisionar PostgreSQL staging.
2. Configurar secrets staging.
3. Executar validate-production-environment para cada servico.
4. Executar prisma migrate deploy.
5. Executar seed explicitamente com valores staging.
6. Subir webhook ingress.
7. Validar /health/live e /health/ready.
8. Configurar callback Meta staging.
9. Subir API.
10. Validar API live/ready e CORS.
11. Subir worker.
12. Subir site monitor worker.
13. Subir web quando a integracao frontend estiver pronta.
14. Executar verify-deployed-services.mjs.
15. Executar smoke funcional.

## Remote verification

Configure:

DEPLOY_API_BASE_URL=https://...
DEPLOY_WEBHOOK_BASE_URL=https://...

Depois execute:

node scripts/verify-deployed-services.mjs

## Production promotion

Somente promover depois de:

- CI verde
- pnpm audit sem high/critical
- migrations up-to-date
- staging smoke verde
- webhook HMAC validado
- health/readiness verde
- secrets separados
- rollback definido

## Rollback

Rollback de aplicacao deve preferir redeploy da ultima versao conhecida como boa.

Nao reverter migration destrutivamente sem plano especifico.

Mantenha migrations forward-compatible sempre que possivel.

## CSP

Content-Security-Policy final sera definida junto ao frontend real.

Nao foi aplicada uma CSP ficticia agora porque OneSignal, assets e chamadas reais do frontend ainda precisam ser conhecidos.
