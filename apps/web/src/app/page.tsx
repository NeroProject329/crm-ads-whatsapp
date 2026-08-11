const services = ['web', 'api', 'webhook-ingress', 'worker', 'site-monitor-worker'] as const;

export default function HomePage() {
  return (
    <main className="foundation-page">
      <section className="foundation-card">
        <p className="eyebrow">ETAPA 1 · FUNDAÇÃO</p>
        <h1>CRM ADS/WhatsApp</h1>
        <p className="lead">
          Monorepo greenfield criado. Nenhum código, componente ou identidade visual do sistema
          anterior foi reaproveitado.
        </p>

        <div className="status">
          <span aria-hidden="true" />
          Fundação pronta para validação local
        </div>

        <h2>Serviços previstos</h2>
        <ul>
          {services.map((service) => (
            <li key={service}>{service}</li>
          ))}
        </ul>
      </section>
    </main>
  );
}
