# CRM de ADS/WhatsApp

Monorepo greenfield para gestão de ADS, números, leads e atendimento pelo WhatsApp.

## Estado atual

- Etapa 0: arquitetura V1 concluída.
- Etapa 1: fundação do monorepo concluída.
- Etapa 2A: PostgreSQL, Prisma e modelo organizacional concluídos.
- Integração real com a Meta: ainda não iniciada.
- PostgreSQL development: ativo no Railway; Redis entra em etapa posterior.

## Requisitos

- Node.js 24.18.0 LTS;
- Corepack habilitado;
- pnpm 11.15.1;
- PowerShell 7 recomendado no Windows.

## Instalação

```powershell
Set-Location "C:\Projetos\crm-ads-whatsapp"
corepack enable
corepack prepare pnpm@11.15.1 --activate
pnpm install
pnpm ci:check
```

O primeiro `pnpm install` cria o `pnpm-lock.yaml`. Esse arquivo deve ser versionado.

## Serviços

| Aplicação                  | Porta local | Função inicial                     |
| -------------------------- | ----------: | ---------------------------------- |
| `apps/web`                 |        3000 | Interface ADMIN/EMPLOYEE           |
| `apps/api`                 |        3001 | API administrativa e operacional   |
| `apps/webhook-ingress`     |        3002 | Entrada futura de webhooks da Meta |
| `apps/worker`              |    sem HTTP | Processamento assíncrono futuro    |
| `apps/site-monitor-worker` |    sem HTTP | Monitoramento futuro de sites      |

## Comandos principais

```powershell
pnpm dev
pnpm dev:web
pnpm dev:api
pnpm dev:webhook
pnpm dev:worker
pnpm dev:site-monitor
pnpm db:migrate:status
pnpm db:health
pnpm db:verify-seed
pnpm api:health:verify
pnpm ci:check
```

## Endpoints da fundação

- Web: `http://localhost:3000`
- Web health: `http://localhost:3000/api/health`
- API health: `http://localhost:3001/api/v1/health`
- Webhook ingress health: `http://localhost:3002/health`

## Regra de evolução

Cada etapa deve terminar com:

```text
documentação
→ implementação
→ lint
→ typecheck
→ testes
→ build
→ validação funcional
→ commit
```
