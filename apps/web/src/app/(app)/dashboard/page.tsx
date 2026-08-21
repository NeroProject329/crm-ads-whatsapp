const modules = [
  {
    title: 'WhatsApp',
    description: 'Conversas, mensagens, respostas rapidas e janela de atendimento.',
    status: 'F3',
  },
  {
    title: 'ADS e filas',
    description: 'Pedidos, filas, Traffic Pools, microlotes e distribuicao.',
    status: 'F4',
  },
  {
    title: 'Numeros',
    description: 'Saude, qualidade Meta, contingencia e recuperacao.',
    status: 'F5',
  },
] as const;

export default function DashboardPage() {
  return (
    <div className="dashboard-page">
      <section className="page-heading-row">
        <div>
          <span className="eyebrow">VISAO GERAL</span>
          <h1>Central de operacao</h1>
          <p>
            A fundacao do frontend esta conectada ao backend de staging e pronta para receber os
            modulos operacionais.
          </p>
        </div>
        <div className="release-chip">
          <span />
          Backend staging aprovado
        </div>
      </section>

      <section className="foundation-status-grid" aria-label="Status da fundacao">
        <article className="status-card is-primary">
          <div className="status-card-top">
            <span>Autenticacao</span>
            <strong>ONLINE</strong>
          </div>
          <h2>Login e sessao</h2>
          <p>Cookies HttpOnly, refresh automatico e logout seguro via BFF.</p>
          <div className="status-line"><span /><small>Conectado</small></div>
        </article>

        <article className="status-card">
          <div className="status-card-top">
            <span>Acesso</span>
            <strong>RBAC</strong>
          </div>
          <h2>ADMIN / EMPLOYEE</h2>
          <p>Navegacao e futuras acoes respeitam as roles emitidas pela API.</p>
          <div className="status-line"><span /><small>Protegido</small></div>
        </article>

        <article className="status-card">
          <div className="status-card-top">
            <span>Ambiente</span>
            <strong>STAGING</strong>
          </div>
          <h2>Backend validado</h2>
          <p>API, webhook, worker, Meta, OneSignal e monitoramento ja validados.</p>
          <div className="status-line"><span /><small>Operacional</small></div>
        </article>
      </section>

      <section className="dashboard-section">
        <div className="section-heading">
          <div>
            <span className="eyebrow">PROXIMOS MODULOS</span>
            <h2>Estrutura preparada para evoluir</h2>
          </div>
          <span className="subtle-label">Frontend F1</span>
        </div>

        <div className="module-grid">
          {modules.map((module) => (
            <article className="module-card" key={module.title}>
              <span className="module-index">{module.status}</span>
              <h3>{module.title}</h3>
              <p>{module.description}</p>
              <div className="module-card-footer">
                <span>Base pronta</span>
                <span aria-hidden="true">→</span>
              </div>
            </article>
          ))}
        </div>
      </section>
    </div>
  );
}
