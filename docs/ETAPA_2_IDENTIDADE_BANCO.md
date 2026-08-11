# Etapa 2 — Identidade, organização e banco inicial

**Status:** 2A CONCLUÍDA  
**Início:** 06 de agosto de 2026  
**Conclusão da 2A:** 11 de agosto de 2026  
**Abordagem:** incremental, com validação por subetapa

## Subetapas

| Subetapa | Escopo                                                | Estado       |
| -------- | ----------------------------------------------------- | ------------ |
| 2A       | PostgreSQL, Prisma e modelo organizacional inicial    | CONCLUÍDA    |
| 2B       | Senhas, login, access token e refresh token rotativo  | NÃO INICIADA |
| 2C       | Sessões, logout, revogação e detecção de reutilização | NÃO INICIADA |
| 2D       | RBAC, autorização por organização/equipe/recurso      | NÃO INICIADA |
| 2E       | Testes integrados, seed definitivo e encerramento     | NÃO INICIADA |

## Objetivo da 2A

Criar uma fundação relacional nova para o CRM, sem reutilizar o MongoDB legado. A subetapa inclui:

- Prisma ORM 7;
- PostgreSQL;
- driver adapter `pg`;
- client gerado fora de `node_modules`;
- configuração por ambiente;
- modelo organizacional;
- sessões e refresh tokens preparados no schema;
- auditoria preparada no schema;
- seed inicial idempotente;
- healthcheck de banco na API;
- scripts de migration, seed e diagnóstico.

## Entidades iniciais

```text
Organization
Team
User
Employee
Role
Permission
RolePermission
UserRole
Session
RefreshToken
AuditLog
```

## Decisões da modelagem

- todos os dados operacionais pertencem a uma `Organization`;
- e-mail é único dentro da organização, usando `emailNormalized`;
- equipes são únicas por `organizationId + slug`;
- funcionários vinculam `User` e `Team` dentro da mesma organização;
- ADMIN e EMPLOYEE são registros de `Role`, não enum fixo no usuário;
- permissões são granulares e relacionadas às funções;
- sessões e refresh tokens serão persistidos e revogáveis;
- tokens serão armazenados somente em forma de hash na 2B;
- logs de auditoria não devem armazenar segredos ou conteúdo sensível;
- relações compostas ajudam a impedir vínculos acidentais entre organizações.

## Fluxo de validação da 2A

```text
aplicar arquivos
→ pnpm install
→ prisma format
→ prisma generate
→ prisma validate
→ format/lint/typecheck/test/build
→ configurar PostgreSQL development
→ criar migration
→ aplicar migration
→ executar seed
→ verificar conteúdo do seed
→ validar healthcheck
→ pnpm ci:check
```

## Estratégia de PostgreSQL development

- `DATABASE_URL` fica apenas em `.env` local ou nas variáveis do ambiente Railway.
- na máquina local, `DATABASE_URL` e `DATABASE_DIRECT_URL` usam a `DATABASE_PUBLIC_URL` do PostgreSQL de development.
- dentro do Railway, a API usa a referência privada `${{Postgres.DATABASE_URL}}`; a URL pública não é usada entre serviços.
- `SHADOW_DATABASE_URL` deve existir quando `prisma migrate dev` não puder criar automaticamente o shadow database.
- o proxy TCP público do PostgreSQL existe somente para migrations, seed, diagnóstico e desenvolvimento local.
- o repositório só recebe `.env.example`, nunca valores reais de conexão.

## Resultado confirmado da 2A

- schema formatado e validado;
- client Prisma gerado fora de `node_modules`;
- primeira migration versionada em `packages/database/prisma/migrations`;
- seed inicial idempotente aplicado com `Organization`, `Team`, `ADMIN`, `Role` e `Permission`;
- healthcheck da API validando PostgreSQL em `/api/v1/health/ready` e `/api/v1/health`;
- `pnpm ci:check` preservado como validação de base.

## Infraestrutura development

- projeto Railway: `crm-ads-whatsapp`;
- project ID: `350c4e0f-d027-4e0e-ad26-99fe14983fc4`;
- ambiente: `development`;
- PostgreSQL: serviço `Postgres`, com volume persistente e proxy TCP público;
- dashboard: `https://railway.com/project/350c4e0f-d027-4e0e-ad26-99fe14983fc4`;
- `.env` local: criado e protegido pelas regras de `.gitignore`;
- ambiente `production`: mantido vazio nesta subetapa.

## Migration e seed aplicados

- migration: `20260811171900_initial_identity_and_org`;
- estado Prisma: banco atualizado, sem migrations pendentes;
- organização: `CRM ADS WhatsApp` (`ACTIVE`);
- equipe: `Equipe Principal` (`ACTIVE`);
- ADMIN: `admin@example.com` (`INVITED`) e funcionário `ADMIN001` (`ACTIVE`);
- papéis: `ADMIN` com 11 permissões e `EMPLOYEE` com 2 permissões;
- catálogo: 11 permissões verificadas.

## Validação operacional

```powershell
pnpm db:migrate:status
pnpm db:health
pnpm db:verify-seed
pnpm api:health:verify
pnpm ci:check
```

Os endpoints `/api/v1/health/live`, `/api/v1/health/ready` e `/api/v1/health` retornaram HTTP 200. Os dois endpoints que dependem do banco confirmaram `database: connected`.

## Correções realizadas durante a validação real

- `prisma.config.ts` passou a carregar explicitamente o `.env` da raiz quando o comando roda no pacote `@crm/database`;
- `HealthController` passou a importar `DatabaseService` como referência de runtime, permitindo a injeção correta pelo Nest;
- `db:verify-seed` foi adicionado para conferir organização, equipe, ADMIN, papéis e permissões;
- `api:health:verify` foi adicionado para subir a API temporariamente, testar os três endpoints e encerrar o processo.

## Importante

O seed cria o usuário ADMIN como `INVITED`, sem senha. A ativação segura, o hash da senha e o login entram na Subetapa 2B.
