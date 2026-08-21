'use client';

import { useEffect, useState } from 'react';
import type { FormEvent } from 'react';

import { crmFetch } from '@/lib/backend/client';
import type { ManagedOrganization } from '@/lib/f2/types';

export function SettingsManagement() {
  const [organization, setOrganization] = useState<ManagedOrganization | null>(null);
  const [name, setName] = useState('');
  const [timezone, setTimezone] = useState('America/Sao_Paulo');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  async function load() {
    setLoading(true);
    try {
      const data = await crmFetch<ManagedOrganization>('/api/management/organization');
      setOrganization(data);
      setName(data.name);
      setTimezone(data.timezone);
      setError(null);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Nao foi possivel carregar as configuracoes.');
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => { void load(); }, []);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSaving(true);
    setError(null);
    setSuccess(null);
    try {
      const updated = await crmFetch<ManagedOrganization>('/api/management/organization', {
        method: 'PATCH',
        body: JSON.stringify({ name, timezone }),
      });
      setOrganization(updated);
      setSuccess('Configuracoes atualizadas com sucesso.');
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Nao foi possivel salvar as configuracoes.');
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="f2-page">
      <section className="f2-page-header">
        <div><span className="f2-kicker">ADMINISTRACAO</span><h1>Configuracoes</h1><p>Dados centrais da organizacao usados em todo o CRM.</p></div>
      </section>
      {success ? <div className="f2-alert success">{success}</div> : null}
      {error ? <div className="f2-alert error">{error}</div> : null}
      <section className="f2-settings-grid">
        <article className="f2-panel f2-settings-summary">
          <span className="f2-kicker">ORGANIZACAO</span>
          <h2>{organization?.name ?? 'Carregando...'}</h2>
          <dl>
            <div><dt>Slug</dt><dd>{organization?.slug ?? '—'}</dd></div>
            <div><dt>Status</dt><dd>{organization?.status ?? '—'}</dd></div>
            <div><dt>Fuso horario</dt><dd>{organization?.timezone ?? '—'}</dd></div>
          </dl>
        </article>
        <form className="f2-panel f2-settings-form" onSubmit={submit}>
          <div><span className="f2-kicker">DADOS GERAIS</span><h2>Identidade da operacao</h2><p>Esses dados ficam no backend e sao aplicados a toda a organizacao.</p></div>
          <label><span>Nome da organizacao</span><input disabled={loading} required value={name} onChange={(event) => setName(event.target.value)} /></label>
          <label><span>Fuso horario</span><select disabled={loading} value={timezone} onChange={(event) => setTimezone(event.target.value)}><option value="America/Sao_Paulo">America/Sao_Paulo</option><option value="America/Manaus">America/Manaus</option><option value="America/Recife">America/Recife</option><option value="UTC">UTC</option></select></label>
          <button className="f2-primary-button" type="submit" disabled={loading || saving}>{saving ? 'Salvando...' : 'Salvar configuracoes'}</button>
        </form>
      </section>
    </div>
  );
}
