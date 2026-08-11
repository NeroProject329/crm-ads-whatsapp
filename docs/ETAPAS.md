# Controle das 13 etapas

Ao final da Etapa 13, os documentos produzidos serão consolidados em um único documento mestre de implementação.

| Etapa | Escopo                                    | Estado                      |
| ----: | ----------------------------------------- | --------------------------- |
|     1 | Fundação do monorepo                      | CONCLUÍDA                   |
|     2 | Identidade, organização e banco inicial   | EM ANDAMENTO — 2A concluída |
|     3 | Sites, domínios, números e Traffic Pools  | NÃO INICIADA                |
|     4 | Pedidos e fila de ADS                     | NÃO INICIADA                |
|     5 | Scheduler, microlotes e backpressure      | NÃO INICIADA                |
|     6 | Monitoramento de sites                    | NÃO INICIADA                |
|     7 | PWA e OneSignal                           | NÃO INICIADA                |
|     8 | Fundação da Meta Cloud API                | NÃO INICIADA                |
|     9 | Caixa de atendimento                      | NÃO INICIADA                |
|    10 | Leads únicos e atribuição                 | NÃO INICIADA                |
|    11 | Saúde, incidentes e contingência          | NÃO INICIADA                |
|    12 | Segurança, staging e produção             | NÃO INICIADA                |
|    13 | Corte operacional e desativação do legado | NÃO INICIADA                |

## Histórico

### Etapa 1 — concluída em 06/08/2026

- monorepo criado;
- dependências instaladas;
- Node e pnpm alinhados;
- builds de `esbuild` e `sharp` aprovados explicitamente;
- scripts PowerShell corrigidos para fail-fast;
- estrutura, formatação, lint, typecheck, testes e builds aprovados;
- `pnpm ci:check` concluído.

### Etapa 2 — iniciada em 06/08/2026

- Subetapa 2A concluída em 11/08/2026;
- projeto Railway `crm-ads-whatsapp` criado com ambiente `development`;
- PostgreSQL provisionado com rede privada para serviços e proxy público para desenvolvimento local;
- migration inicial aplicada e seed validado;
- healthchecks da API validados contra o banco real;
- próxima subetapa: 2B, autenticação e ativação segura do ADMIN.

## Documento final planejado

```text
docs/DOCUMENTO_MESTRE_IMPLEMENTACAO_V1.md
```
