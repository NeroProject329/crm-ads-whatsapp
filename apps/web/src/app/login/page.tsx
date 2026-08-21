import { redirect } from 'next/navigation';

import { LoginForm } from '@/components/auth/login-form';
import { hasSessionCookie } from '@/lib/auth/server';

export default async function LoginPage() {
  if (await hasSessionCookie()) {
    redirect('/dashboard');
  }

  return (
    <main className="login-page">
      <section className="login-visual" aria-label="CRM ADS e WhatsApp">
        <div className="login-orb login-orb-one" />
        <div className="login-orb login-orb-two" />
        <div className="login-grid" />

        <div className="login-brand">
          <div className="brand-mark is-large" aria-hidden="true">
            <span />
            <span />
            <span />
          </div>
          <div>
            <strong>NERO CRM</strong>
            <span>ADS + WhatsApp</span>
          </div>
        </div>

        <div className="login-visual-copy">
          <span className="hero-pill"><i /> Operacao conectada</span>
          <h1>Controle a operacao.<br />Sem perder o ritmo.</h1>
          <p>
            Atendimento, distribuicao de leads, saude dos numeros e operacao de ADS em uma unica
            central.
          </p>

          <div className="login-metrics">
            <div>
              <strong>24/7</strong>
              <span>monitoramento operacional</span>
            </div>
            <div>
              <strong>Meta</strong>
              <span>Cloud API oficial</span>
            </div>
            <div>
              <strong>RBAC</strong>
              <span>acesso por funcao</span>
            </div>
          </div>
        </div>

        <div className="login-visual-footer">
          <span>CRM ADS/WhatsApp</span>
          <span>Staging seguro</span>
        </div>
      </section>

      <section className="login-panel">
        <div className="login-panel-inner">
          <div className="login-heading">
            <span className="eyebrow">ACESSO AO SISTEMA</span>
            <h2>Bem-vindo de volta</h2>
            <p>Entre com suas credenciais para acessar sua area de trabalho.</p>
          </div>

          <LoginForm />

          <div className="login-panel-footer">
            <span className="security-dot" />
            Conexao protegida e sessao isolada por organizacao.
          </div>
        </div>
      </section>
    </main>
  );
}
