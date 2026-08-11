# Decisões da Etapa 1

## D1 — Node.js LTS fixado

A fundação usa Node.js 24.18.0 LTS, evitando a linha Current para produção.

## D2 — Dependências exatas

O `.npmrc` usa `save-exact=true`. Atualizações serão deliberadas e revisadas, não automáticas.

## D3 — TypeScript conservador

A fundação fixa TypeScript 5.9.3 para reduzir risco de incompatibilidade entre Next.js, NestJS, ESLint e ferramentas de teste. A atualização para uma major posterior exigirá ADR e validação completa.

## D4 — Cinco processos desde o começo

Mesmo vazios de regras reais, web, API, webhook ingress e os dois workers já possuem limites físicos e scripts independentes.

## D5 — Sem infraestrutura de dados nesta etapa

PostgreSQL, Prisma, Redis e BullMQ entram somente na Etapa 2. Isso mantém a Etapa 1 focada em toolchain, processos e qualidade.

## D6 — Sem design final

A tela inicial é apenas uma confirmação técnica da fundação. Ela não define a identidade visual do produto.

## D7 — Documento final consolidado

Os documentos das Etapas 1 a 13 serão preservados e, ao final, consolidados em `docs/DOCUMENTO_MESTRE_IMPLEMENTACAO_V1.md`.
