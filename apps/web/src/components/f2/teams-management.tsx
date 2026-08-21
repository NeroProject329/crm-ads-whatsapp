'use client';

import { useEffect, useState } from 'react';
import type { FormEvent } from 'react';

import { crmFetch } from '@/lib/backend/client';
import type { ManagedTeam } from '@/lib/f2/types';

type FormState = { name: string; slug: string; description: string; status: 'ACTIVE' | 'INACTIVE' };
const emptyForm: FormState = { name: '', slug: '', description: '', status: 'ACTIVE' };

function makeSlug(value: string): string {
  return value.toLowerCase().trim().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
}

export function TeamsManagement() {
  const [teams, setTeams] = useState<readonly ManagedTeam[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState<ManagedTeam | null>(null);
  const [open, setOpen] = useState(false);
  const [form, setForm] = useState<FormState>(emptyForm);

  async function load() {
    setLoading(true);
    try {
      setTeams(await crmFetch<readonly ManagedTeam[]>('/api/management/teams'));
      setError(null);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Nao foi possivel carregar as equipes.');
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => { void load(); }, []);

  function createTeam() {
    setEditing(null);
    setForm(emptyForm);
    setError(null);
    setOpen(true);
  }

  function editTeam(team: ManagedTeam) {
    setEditing(team);
    setForm({ name: team.name, slug: team.slug, description: team.description ?? '', status: team.status });
    setError(null);
    setOpen(true);
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSaving(true);
    setError(null);
    setMessage(null);
    try {
      const body = JSON.stringify({
        name: form.name,
        slug: form.slug,
        description: form.description.trim() || null,
        ...(editing ? { status: form.status } : {}),
      });
      await crmFetch(editing ? `/api/management/teams/${editing.id}` : '/api/management/teams', {
        method: editing ? 'PATCH' : 'POST',
        body,
      });
      setMessage(editing ? 'Equipe atualizada.' : 'Equipe criada.');
      setOpen(false);
      await load();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Nao foi possivel salvar a equipe.');
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="f2-page">
      <section className="f2-page-header">
        <div><span className="f2-kicker">ESTRUTURA</span><h1>Equipes</h1><p>Organize os funcionarios em equipes e acompanhe a distribuicao da estrutura.</p></div>
        <button className="f2-primary-button" type="button" onClick={createTeam}>+ Nova equipe</button>
      </section>
      {message ? <div className="f2-alert success">{message}</div> : null}
      {error && !open ? <div className="f2-alert error">{error}</div> : null}
      <section className="f2-team-grid">
        {loading ? <div className="f2-panel f2-empty">Carregando equipes...</div> : null}
        {!loading && teams.length === 0 ? <div className="f2-panel f2-empty">Nenhuma equipe cadastrada.</div> : null}
        {teams.map((team) => (
          <article className="f2-team-card" key={team.id}>
            <div className="f2-team-top"><span className="f2-team-icon">{team.name.charAt(0).toUpperCase()}</span><span className={`f2-status ${team.status.toLowerCase()}`}>{team.status === 'ACTIVE' ? 'ATIVA' : 'INATIVA'}</span></div>
            <h2>{team.name}</h2><p>{team.description || 'Sem descricao.'}</p>
            <div className="f2-team-meta"><div><span>Funcionarios</span><strong>{team.employeeCount}</strong></div><div><span>Slug</span><strong>{team.slug}</strong></div></div>
            <button className="f2-secondary-button" type="button" onClick={() => editTeam(team)}>Editar</button>
          </article>
        ))}
      </section>
      {open ? <div className="f2-modal-backdrop"><section className="f2-modal"><div className="f2-modal-header"><div><span className="f2-kicker">{editing ? 'EDITAR' : 'NOVA EQUIPE'}</span><h2>{editing?.name ?? 'Criar equipe'}</h2></div><button type="button" onClick={() => setOpen(false)}>×</button></div>{error ? <div className="f2-modal-error">{error}</div> : null}<form className="f2-form" onSubmit={submit}><div className="f2-form-grid"><label><span>Nome</span><input required value={form.name} onChange={(event) => setForm((current) => ({ ...current, name: event.target.value, ...(!editing ? { slug: makeSlug(event.target.value) } : {}) }))} /></label><label><span>Slug</span><input required value={form.slug} onChange={(event) => setForm((current) => ({ ...current, slug: makeSlug(event.target.value) }))} /></label><label className="full"><span>Descricao</span><textarea value={form.description} onChange={(event) => setForm((current) => ({ ...current, description: event.target.value }))} /></label>{editing ? <label><span>Status</span><select value={form.status} onChange={(event) => setForm((current) => ({ ...current, status: event.target.value as FormState['status'] }))}><option value="ACTIVE">Ativa</option><option value="INACTIVE">Inativa</option></select></label> : null}</div><div className="f2-modal-actions"><button className="f2-secondary-button" type="button" onClick={() => setOpen(false)}>Cancelar</button><button className="f2-primary-button" type="submit" disabled={saving}>{saving ? 'Salvando...' : 'Salvar'}</button></div></form></section></div> : null}
    </div>
  );
}
