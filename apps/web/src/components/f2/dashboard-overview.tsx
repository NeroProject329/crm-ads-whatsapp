'use client';

import { useEffect, useMemo, useState } from 'react';

import { useSession } from '@/components/auth/session-provider';
import { crmFetch } from '@/lib/backend/client';
import type { ManagedSite, ManagementOverview } from '@/lib/f2/types';

type Metric = Readonly<{
  label: string;
  value: number;
  detail: string;
  tone?: 'dark' | 'blue';
}>;

export function DashboardOverview() {
  const { loading: sessionLoading, user } = useSession();
  const [overview, setOverview] = useState<ManagementOverview | null>(null);
  const [sites, setSites] = useState<readonly ManagedSite[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const isAdmin = Boolean(user?.roles.includes('ADMIN'));

  useEffect(() => {
    if (sessionLoading || !user) {
      return;
    }

    let active = true;

    async function load() {
      setLoading(true);
      setError(null);

      try {
        if (isAdmin) {
          const data = await crmFetch<ManagementOverview>('/api/management/overview');
          if (active) setOverview(data);
        } else {
          const data = await crmFetch<readonly ManagedSite[]>('/api/crm-sites');
          if (active) setSites(data);
        }
      } catch (caught) {
        if (active) {
          setError(caught instanceof Error ? caught.message : 'Nao foi possivel carregar o dashboard.');
        }
      } finally {
        if (active) setLoading(false);
      }
    }

    void load();
    return () => {
      active = false;
    };
  }, [isAdmin, sessionLoading, user]);

  const metrics = useMemo<readonly Metric[]>(() => {
    if (!isAdmin) {
      const activeSites = sites.filter((site) => site.status === 'ACTIVE').length;
      const domains = sites.flatMap((site) => site.domains);
      const activeDomains = domains.filter((domain) => domain.status === 'ACTIVE').length;

      return [
        { label: 'Sites sob sua gestao', value: sites.length, detail: `${activeSites} ativos`, tone: 'blue' },
        { label: 'Dominios', value: domains.length, detail: `${activeDomains} ativos` },
        { label: 'Perfil operacional', value: 1, detail: 'Acesso EMPLOYEE' },
      ];
    }

    if (!overview) return [];

    return [
      {
        label: 'Funcionarios',
        value: overview.employees.total,
        detail: `${overview.employees.active} ativos`,
        tone: 'blue',
      },
      {
        label: 'Equipes',
        value: overview.teams.total,
        detail: `${overview.teams.active} ativas`,
      },
      {
        label: 'Sites',
        value: overview.sites.total,
        detail: `${overview.sites.active} ativos`,
      },
      {
        label: 'Dominios',
        value: overview.domains.total,
        detail: `${overview.domains.active} ativos`,
      },
      {
        label: 'Numeros WhatsApp',
        value: overview.whatsAppNumbers.total,
        detail: `${overview.whatsAppNumbers.active} ativos`,
      },
      {
        label: 'Leads unicos',
        value: overview.leads.total,
        detail: `${overview.leads.attributed} atribuidos · ${overview.leads.excess} excedentes`,
        tone: 'dark',
      },
    ];
  }, [isAdmin, overview, sites]);

  return (
    <div className="f2-page f2-dashboard">
      <section className="f2-hero f2-dashboard-hero">
        <div className="f2-hero-copy">
          <span className="f2-kicker">CENTRAL DE OPERACAO</span>
          <h1>{isAdmin ? 'Visao geral da operacao.' : 'Sua operacao em um so lugar.'}</h1>
          <p>
            {isAdmin
              ? 'Acompanhe pessoas, equipes, sites, numeros e leads antes de entrar nos modulos operacionais.'
              : 'Acompanhe os recursos vinculados ao seu acesso e entre rapidamente na operacao.'}
          </p>
        </div>
        <div className="f2-hero-status">
          <span className="f2-status-dot" />
          <div>
            <small>Ambiente</small>
            <strong>Staging conectado</strong>
          </div>
        </div>
      </section>

      {error ? <div className="f2-alert error">{error}</div> : null}

      <section className="f2-metrics-grid" aria-busy={loading}>
        {loading
          ? Array.from({ length: isAdmin ? 6 : 3 }, (_, index) => (
              <div className="f2-metric-card is-loading" key={index} />
            ))
          : metrics.map((metric) => (
              <article className={`f2-metric-card${metric.tone ? ` ${metric.tone}` : ''}`} key={metric.label}>
                <span>{metric.label}</span>
                <strong>{metric.value.toLocaleString('pt-BR')}</strong>
                <small>{metric.detail}</small>
              </article>
            ))}
      </section>

      <section className="f2-panel f2-next-panel">
        <div>
          <span className="f2-kicker">ESTRUTURA OPERACIONAL</span>
          <h2>{isAdmin ? 'Gestao pronta para o dia a dia' : 'Seu acesso esta preparado'}</h2>
          <p>
            {isAdmin
              ? 'Use Funcionarios e Equipes para organizar a operacao. Sites concentra dominios e responsaveis.'
              : 'Os proximos modulos vao usar esta mesma sessao para WhatsApp, ADS, leads e numeros.'}
          </p>
        </div>
        <div className="f2-flow-list">
          <span><b>01</b> Pessoas e equipes</span>
          <span><b>02</b> Sites e dominios</span>
          <span><b>03</b> WhatsApp + ADS</span>
        </div>
      </section>
    </div>
  );
}
