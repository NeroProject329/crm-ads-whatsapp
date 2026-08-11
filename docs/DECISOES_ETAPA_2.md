# Decisões da Etapa 2

## D2.1 — PostgreSQL como fonte principal

O novo CRM usará PostgreSQL. O MongoDB do sistema antigo não será migrado nem usado como base da nova arquitetura.

## D2.2 — Prisma ORM 7 com adapter `pg`

A conexão de runtime usa `@prisma/adapter-pg`. O client é gerado em `packages/database/src/generated/prisma` e não é versionado.

## D2.3 — URLs de runtime e migration separáveis

- `DATABASE_URL`: conexão usada pelos serviços em runtime;
- `DATABASE_DIRECT_URL`: conexão direta opcional usada pelo Prisma CLI;
- `SHADOW_DATABASE_URL`: conexão opcional para o shadow database durante `migrate dev`.

## D2.4 — Organização como raiz de isolamento

Mesmo começando com uma única empresa, as entidades possuem `organizationId` para evitar uma reestruturação futura e para permitir autorização consistente.

## D2.5 — Papéis persistidos

ADMIN e EMPLOYEE serão papéis persistidos no banco. Permissões granulares serão verificadas pelo backend.

## D2.6 — Usuário ADMIN inicialmente convidado

A 2A não define senha em texto nem senha padrão. O seed cria o ADMIN como `INVITED`; a ativação segura acontece na 2B.

## D2.7 — API com liveness e readiness separados

- `/api/v1/health/live`: confirma que o processo está vivo;
- `/api/v1/health/ready`: confirma também a conexão com PostgreSQL;
- `/api/v1/health`: mantém o endpoint consolidado e exige banco disponível.

## D2.8 — Rede do PostgreSQL no Railway

- serviços executados no Railway usam a URL privada do PostgreSQL;
- migrations, seed e diagnósticos locais usam a URL pública do ambiente `development`;
- a URL pública é mantida apenas no `.env` local ignorado pelo Git;
- nenhum segredo real é incluído em documentação, `.env.example` ou migration.

## D2.9 — Validação funcional reproduzível

- `pnpm db:verify-seed` valida o conteúdo obrigatório da 2A;
- `pnpm api:health:verify` inicia a API temporariamente e testa liveness, readiness e health consolidado;
- os verificadores funcionais ficam fora do CI porque dependem de um PostgreSQL acessível.
