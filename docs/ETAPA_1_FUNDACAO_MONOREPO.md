# Etapa 1 — Fundação do monorepo

**Data:** 06 de agosto de 2026  
**Status inicial:** pronta para instalação e validação local  
**Abordagem:** greenfield completo

## 1. Objetivo

Criar a base técnica do novo CRM sem implementar ainda banco de dados, Redis, regras de ADS ou integração com a Meta.

Nenhum código, componente ou identidade visual do sistema anterior foi reutilizado.

## 2. Entregas

- pnpm workspace;
- Turborepo;
- TypeScript estrito;
- ESLint compartilhado;
- Prettier;
- Vitest;
- cinco aplicações independentes;
- treze packages compartilhados;
- healthchecks iniciais;
- logs JSON nos workers;
- CI do GitHub;
- scripts PowerShell;
- controle das 13 etapas.

## 3. Aplicações

```text
apps/web
apps/api
apps/webhook-ingress
apps/worker
apps/site-monitor-worker
```

A fundação não coloca a Meta API dentro de `apps/api`. O processo de webhook permanece separado desde o início.

## 4. Packages

```text
packages/auth
packages/config
packages/contracts
packages/database
packages/domain
packages/notifications
packages/observability
packages/queue
packages/realtime
packages/security
packages/testing
packages/validation
packages/whatsapp
```

Os packages possuem contratos mínimos para confirmar que os limites arquiteturais estão representados, mas ainda não contêm regras completas de negócio.

## 5. Portas locais

| Serviço         | Porta |
| --------------- | ----: |
| web             |  3000 |
| api             |  3001 |
| webhook-ingress |  3002 |

Workers não abrem portas HTTP nesta etapa. Eles emitem heartbeat em log estruturado.

## 6. Instalação no Windows

```powershell
$ErrorActionPreference = "Stop"
Set-Location "C:\Projetos\crm-ads-whatsapp"

.\scripts\Check-Environment.ps1
.\scripts\Install-Stage1.ps1
```

O primeiro `pnpm install` deve gerar:

```text
pnpm-lock.yaml
```

Esse arquivo deve ser commitado antes de o CI ser executado.

## 7. Validação automática

```powershell
pnpm structure:check
pnpm format:check
pnpm lint
pnpm typecheck
pnpm test
pnpm build
pnpm ci:check
```

## 8. Validação funcional

Terminal 1:

```powershell
pnpm dev:web
```

Terminal 2:

```powershell
pnpm dev:api
```

Terminal 3:

```powershell
pnpm dev:webhook
```

Terminal 4:

```powershell
pnpm dev:worker
```

Terminal 5:

```powershell
pnpm dev:site-monitor
```

Confirmar:

```text
http://localhost:3000
http://localhost:3000/api/health
http://localhost:3001/api/v1/health
http://localhost:3002/health
```

## 9. Critérios de aceite

- `pnpm install` concluído;
- `pnpm-lock.yaml` criado;
- `pnpm ci:check` aprovado;
- web abre na porta 3000;
- API retorna health na porta 3001;
- webhook-ingress retorna health na porta 3002;
- worker gera heartbeat;
- site-monitor-worker gera heartbeat;
- nenhum segredo versionado;
- nenhum `node_modules` ou ZIP dentro do repositório;
- GitHub Actions reconhece o workspace após o primeiro push.

## 10. O que não pertence à Etapa 1

- PostgreSQL e Prisma;
- Redis e BullMQ reais;
- autenticação;
- equipes e funcionários;
- sites e Traffic Pools;
- pedidos de ADS;
- Meta Cloud API;
- OneSignal;
- design final do CRM.

Esses itens serão adicionados nas etapas seguintes sem quebrar a fundação.

## 11. Encerramento

Depois que todos os critérios forem comprovados, alterar `docs/ETAPAS.md` de `EM ANDAMENTO` para `CONCLUÍDA` e registrar o commit de aceite da Etapa 1.
