# Decisoes - Etapa 12

HTTP security, provider security e infrastructure security sao camadas independentes.

Helmet e security headers sao baseline, nao substituem WAF/TLS.

CORS e allowlist explicita em staging/producao.

Authentication permanece bearer-token based; CORS credentials permanece false.

Login e refresh possuem throttling mais restritivo que a API geral.

O throttler da aplicacao e process-local e serve como defense in depth.

Rate limiting distribuido deve existir no edge quando houver mais de uma instancia.

Meta webhook nao recebe o mesmo throttling agressivo de usuario humano.

Autenticidade do callback Meta depende principalmente de HMAC sobre raw body.

Payloads API e webhook possuem limites distintos.

Request timeout e headers timeout sao explicitamente configurados.

Trust proxy nunca e habilitado como boolean true; o numero de hops deve corresponder a topologia real.

Staging e production usam NODE_ENV=production; APP_ENV diferencia os dois ambientes.

Production-like boot e fail-closed quando secrets obrigatorios estao ausentes.

Seed production-like nao aceita valores default ou admin@example.com.

SENDING expirado sem wamid e tratado como outcome desconhecido.

Automatic resend e proibido nesse estado para evitar duplicidade de mensagem ao cliente.

CSP final foi adiada ate o frontend real para nao criar uma politica incorreta.

CI bloqueia dependencias de producao com vulnerabilidades high ou critical.

Deploy remoto nao e realizado pelo finalizador local.

O repositorio gera runbook e verifier remoto; a ativacao do ambiente remoto ocorre como operacao de deploy antes do cutover.
