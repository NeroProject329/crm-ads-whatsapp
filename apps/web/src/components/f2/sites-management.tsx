'use client';

import { useEffect, useMemo, useState } from 'react';
import type { FormEvent } from 'react';

import { useSession } from '@/components/auth/session-provider';
import { crmFetch } from '@/lib/backend/client';
import type { ManagedEmployee, ManagedSite } from '@/lib/f2/types';

type SiteForm = { name: string; slug: string; description: string; ownerEmployeeId: string };
type DomainForm = { hostname: string; isPrimary: boolean; monitoringEnabled: boolean };

const emptySite: SiteForm = { name: '', slug: '', description: '', ownerEmployeeId: '' };
const emptyDomain: DomainForm = { hostname: '', isPrimary: false, monitoringEnabled: true };

function makeSlug(value: string): string {
  return value.toLowerCase().trim().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
}

export function SitesManagement() {
  const { user } = useSession();
  const isAdmin = Boolean(user?.roles.includes('ADMIN'));
  const [sites, setSites] = useState<readonly ManagedSite[]>([]);
  const [employees, setEmployees] = useState<readonly ManagedEmployee[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [siteModal, setSiteModal] = useState(false);
  const [domainSite, setDomainSite] = useState<ManagedSite | null>(null);
  const [siteForm, setSiteForm] = useState<SiteForm>(emptySite);
  const [domainForm, setDomainForm] = useState<DomainForm>(emptyDomain);

  async function load() {
    setLoading(true);
    setError(null);
    try {
      const siteData = await crmFetch<readonly ManagedSite[]>('/api/crm-sites');
      setSites(siteData);
      if (isAdmin) {
        setEmployees(await crmFetch<readonly ManagedEmployee[]>('/api/management/employees'));
      }
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Nao foi possivel carregar os sites.');
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => { if (user) void load(); }, [isAdmin, user]);

  const counts = useMemo(() => {
    const domains = sites.flatMap((site) => site.domains);
    return {
      sites: sites.length,
      activeSites: sites.filter((site) => site.status === 'ACTIVE').length,
      domains: domains.length,
      monitored: domains.filter((domain) => domain.monitoringEnabled && domain.status === 'ACTIVE').length,
    };
  }, [sites]);

  function openSiteModal() {
    const owner = employees.find((employee) => employee.status === 'ACTIVE' && employee.roles.includes('EMPLOYEE')) ?? employees.find((employee) => employee.status === 'ACTIVE');
    setSiteForm({ ...emptySite, ownerEmployeeId: owner?.id ?? '' });
    setError(null);
    setSiteModal(true);
  }

  async function createSite(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSaving(true);
    setError(null);
    try {
      await crmFetch('/api/crm-sites', {
        method: 'POST',
        body: JSON.stringify({
          name: siteForm.name,
          slug: siteForm.slug,
          description: siteForm.description.trim() || null,
          ownerEmployeeId: siteForm.ownerEmployeeId,
        }),
      });
      setSuccess('Site criado com sucesso.');
      setSiteModal(false);
      await load();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Nao foi possivel criar o site.');
    } finally {
      setSaving(false);
    }
  }

  async function createDomain(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!domainSite) return;
    setSaving(true);
    setError(null);
    try {
      await crmFetch(`/api/crm-sites/${domainSite.id}/domains`, {
        method: 'POST',
        body: JSON.stringify(domainForm),
      });
      setSuccess('Dominio adicionado com sucesso.');
      setDomainSite(null);
      setDomainForm(emptyDomain);
      await load();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Nao foi possivel adicionar o dominio.');
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="f2-page">
      <section className="f2-page-header">
        <div><span className="f2-kicker">PRESENCA DIGITAL</span><h1>Sites e dominios</h1><p>Centralize propriedades, responsaveis e dominios acompanhados pelo monitor de disponibilidade.</p></div>
        {isAdmin ? <button className="f2-primary-button" type="button" onClick={openSiteModal} disabled={employees.length === 0}>+ Novo site</button> : null}
      </section>

      <section className="f2-stat-strip four"><article><span>Sites</span><strong>{counts.sites}</strong></article><article><span>Sites ativos</span><strong>{counts.activeSites}</strong></article><article><span>Dominios</span><strong>{counts.domains}</strong></article><article><span>Monitorados</span><strong>{counts.monitored}</strong></article></section>
      {success ? <div className="f2-alert success">{success}</div> : null}
      {error && !siteModal && !domainSite ? <div className="f2-alert error">{error}</div> : null}

      <section className="f2-sites-grid">
        {loading ? <div className="f2-panel f2-empty">Carregando sites...</div> : null}
        {!loading && sites.length === 0 ? <div className="f2-panel f2-empty">Nenhum site disponivel para este acesso.</div> : null}
        {sites.map((site) => (
          <article className="f2-site-card" key={site.id}>
            <div className="f2-site-head"><div><span className="f2-kicker">{site.slug}</span><h2>{site.name}</h2></div><span className={`f2-status ${site.status.toLowerCase()}`}>{site.status}</span></div>
            <p>{site.description || 'Sem descricao cadastrada.'}</p>
            <div className="f2-site-owner"><span>Responsavel</span><strong>{site.owner.displayName}</strong><small>{site.owner.employeeCode}</small></div>
            <div className="f2-domain-list">
              {site.domains.length === 0 ? <span className="f2-domain-empty">Nenhum dominio cadastrado</span> : site.domains.map((domain) => (
                <div className="f2-domain-row" key={domain.id}><span className={`f2-domain-dot ${domain.status.toLowerCase()}`} /><div><strong>{domain.hostname}</strong><small>{domain.isPrimary ? 'Principal' : 'Secundario'} · {domain.monitoringEnabled ? 'Monitorado' : 'Monitor desligado'}</small></div></div>
              ))}
            </div>
            {isAdmin ? <button className="f2-secondary-button" type="button" onClick={() => { setDomainSite(site); setDomainForm(emptyDomain); setError(null); }}>+ Adicionar dominio</button> : null}
          </article>
        ))}
      </section>

      {siteModal ? <div className="f2-modal-backdrop"><section className="f2-modal"><div className="f2-modal-header"><div><span className="f2-kicker">NOVO SITE</span><h2>Cadastrar propriedade</h2></div><button type="button" onClick={() => setSiteModal(false)}>×</button></div>{error ? <div className="f2-modal-error">{error}</div> : null}<form className="f2-form" onSubmit={createSite}><div className="f2-form-grid"><label><span>Nome</span><input required value={siteForm.name} onChange={(event) => setSiteForm((current) => ({ ...current, name: event.target.value, slug: makeSlug(event.target.value) }))} /></label><label><span>Slug</span><input required value={siteForm.slug} onChange={(event) => setSiteForm((current) => ({ ...current, slug: makeSlug(event.target.value) }))} /></label><label className="full"><span>Responsavel</span><select required value={siteForm.ownerEmployeeId} onChange={(event) => setSiteForm((current) => ({ ...current, ownerEmployeeId: event.target.value }))}>{employees.filter((employee) => employee.status === 'ACTIVE').map((employee) => <option key={employee.id} value={employee.id}>{employee.user.displayName} · {employee.employeeCode}</option>)}</select></label><label className="full"><span>Descricao</span><textarea value={siteForm.description} onChange={(event) => setSiteForm((current) => ({ ...current, description: event.target.value }))} /></label></div><div className="f2-modal-actions"><button className="f2-secondary-button" type="button" onClick={() => setSiteModal(false)}>Cancelar</button><button className="f2-primary-button" type="submit" disabled={saving || !siteForm.ownerEmployeeId}>{saving ? 'Salvando...' : 'Criar site'}</button></div></form></section></div> : null}

      {domainSite ? <div className="f2-modal-backdrop"><section className="f2-modal"><div className="f2-modal-header"><div><span className="f2-kicker">DOMINIO</span><h2>{domainSite.name}</h2></div><button type="button" onClick={() => setDomainSite(null)}>×</button></div>{error ? <div className="f2-modal-error">{error}</div> : null}<form className="f2-form" onSubmit={createDomain}><div className="f2-form-grid"><label className="full"><span>Hostname</span><input required placeholder="www.exemplo.com.br" value={domainForm.hostname} onChange={(event) => setDomainForm((current) => ({ ...current, hostname: event.target.value.toLowerCase().trim() }))} /></label><label className="f2-check"><input type="checkbox" checked={domainForm.isPrimary} onChange={(event) => setDomainForm((current) => ({ ...current, isPrimary: event.target.checked }))} /><span>Dominio principal</span></label><label className="f2-check"><input type="checkbox" checked={domainForm.monitoringEnabled} onChange={(event) => setDomainForm((current) => ({ ...current, monitoringEnabled: event.target.checked }))} /><span>Monitorar disponibilidade</span></label></div><div className="f2-modal-actions"><button className="f2-secondary-button" type="button" onClick={() => setDomainSite(null)}>Cancelar</button><button className="f2-primary-button" type="submit" disabled={saving}>{saving ? 'Salvando...' : 'Adicionar dominio'}</button></div></form></section></div> : null}
    </div>
  );
}
