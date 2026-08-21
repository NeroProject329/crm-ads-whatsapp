'use client';

import { useEffect, useMemo, useState } from 'react';
import type { FormEvent } from 'react';

import { crmFetch } from '@/lib/backend/client';
import type { ManagedEmployee, ManagedTeam } from '@/lib/f2/types';

type EmployeeFormState = {
  displayName: string;
  email: string;
  employeeCode: string;
  teamId: string;
  password: string;
  employeeStatus: 'ACTIVE' | 'INACTIVE' | 'ON_LEAVE';
  userStatus: 'ACTIVE' | 'SUSPENDED' | 'DISABLED';
};

const emptyForm: EmployeeFormState = {
  displayName: '',
  email: '',
  employeeCode: '',
  teamId: '',
  password: '',
  employeeStatus: 'ACTIVE',
  userStatus: 'ACTIVE',
};

function initials(name: string): string {
  return name
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part.charAt(0).toUpperCase())
    .join('');
}

function statusLabel(employee: ManagedEmployee): string {
  if (employee.user.status !== 'ACTIVE') return employee.user.status;
  if (employee.status === 'ON_LEAVE') return 'AFASTADO';
  return employee.status;
}

export function EmployeesManagement() {
  const [employees, setEmployees] = useState<readonly ManagedEmployee[]>([]);
  const [teams, setTeams] = useState<readonly ManagedTeam[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [search, setSearch] = useState('');
  const [filter, setFilter] = useState<'ALL' | 'ACTIVE' | 'INACTIVE'>('ALL');
  const [editing, setEditing] = useState<ManagedEmployee | null>(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [form, setForm] = useState<EmployeeFormState>(emptyForm);

  async function load() {
    setLoading(true);
    setError(null);

    try {
      const [employeeData, teamData] = await Promise.all([
        crmFetch<readonly ManagedEmployee[]>('/api/management/employees'),
        crmFetch<readonly ManagedTeam[]>('/api/management/teams'),
      ]);
      setEmployees(employeeData);
      setTeams(teamData);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Nao foi possivel carregar os funcionarios.');
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void load();
  }, []);

  const filtered = useMemo(() => {
    const term = search.trim().toLowerCase();

    return employees.filter((employee) => {
      const active = employee.status === 'ACTIVE' && employee.user.status === 'ACTIVE';
      if (filter === 'ACTIVE' && !active) return false;
      if (filter === 'INACTIVE' && active) return false;
      if (!term) return true;

      return [
        employee.user.displayName,
        employee.user.email,
        employee.employeeCode,
        employee.team.name,
      ].some((value) => value.toLowerCase().includes(term));
    });
  }, [employees, filter, search]);

  const activeCount = employees.filter(
    (employee) => employee.status === 'ACTIVE' && employee.user.status === 'ACTIVE',
  ).length;

  function openCreate() {
    setEditing(null);
    setForm({ ...emptyForm, teamId: teams.find((team) => team.status === 'ACTIVE')?.id ?? '' });
    setError(null);
    setModalOpen(true);
  }

  function openEdit(employee: ManagedEmployee) {
    if (employee.roles.includes('ADMIN')) return;

    setEditing(employee);
    setForm({
      displayName: employee.user.displayName,
      email: employee.user.email,
      employeeCode: employee.employeeCode,
      teamId: employee.team.id,
      password: '',
      employeeStatus: employee.status,
      userStatus:
        employee.user.status === 'INVITED' ? 'ACTIVE' : employee.user.status,
    });
    setError(null);
    setModalOpen(true);
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSaving(true);
    setError(null);
    setSuccess(null);

    try {
      if (editing) {
        await crmFetch<ManagedEmployee>(`/api/management/employees/${editing.id}`, {
          method: 'PATCH',
          body: JSON.stringify({
            displayName: form.displayName,
            employeeCode: form.employeeCode,
            teamId: form.teamId,
            employeeStatus: form.employeeStatus,
            userStatus: form.userStatus,
            ...(form.password ? { password: form.password } : {}),
          }),
        });
        setSuccess('Funcionario atualizado com sucesso.');
      } else {
        await crmFetch<ManagedEmployee>('/api/management/employees', {
          method: 'POST',
          body: JSON.stringify({
            displayName: form.displayName,
            email: form.email,
            employeeCode: form.employeeCode,
            teamId: form.teamId,
            password: form.password,
          }),
        });
        setSuccess('Funcionario criado e pronto para acessar o CRM.');
      }

      setModalOpen(false);
      await load();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Nao foi possivel salvar o funcionario.');
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="f2-page">
      <section className="f2-page-header">
        <div>
          <span className="f2-kicker">GESTAO DE ACESSO</span>
          <h1>Funcionarios</h1>
          <p>Crie acessos, organize responsaveis por equipe e controle quem pode entrar na operacao.</p>
        </div>
        <button className="f2-primary-button" type="button" onClick={openCreate} disabled={teams.length === 0}>
          + Novo funcionario
        </button>
      </section>

      <section className="f2-stat-strip">
        <article><span>Total</span><strong>{employees.length}</strong></article>
        <article><span>Ativos</span><strong>{activeCount}</strong></article>
        <article><span>Fora da operacao</span><strong>{employees.length - activeCount}</strong></article>
      </section>

      {success ? <div className="f2-alert success">{success}</div> : null}
      {error && !modalOpen ? <div className="f2-alert error">{error}</div> : null}

      <section className="f2-panel">
        <div className="f2-toolbar">
          <label className="f2-search">
            <span>⌕</span>
            <input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Buscar nome, e-mail, codigo ou equipe" />
          </label>
          <div className="f2-segmented">
            {(['ALL', 'ACTIVE', 'INACTIVE'] as const).map((value) => (
              <button className={filter === value ? 'active' : ''} key={value} type="button" onClick={() => setFilter(value)}>
                {value === 'ALL' ? 'Todos' : value === 'ACTIVE' ? 'Ativos' : 'Inativos'}
              </button>
            ))}
          </div>
        </div>

        {loading ? (
          <div className="f2-empty">Carregando funcionarios...</div>
        ) : filtered.length === 0 ? (
          <div className="f2-empty">Nenhum funcionario encontrado.</div>
        ) : (
          <div className="f2-list">
            {filtered.map((employee) => {
              const protectedAdmin = employee.roles.includes('ADMIN');
              return (
                <article className="f2-person-card" key={employee.id}>
                  <div className="f2-avatar">{initials(employee.user.displayName)}</div>
                  <div className="f2-person-main">
                    <div className="f2-title-line">
                      <strong>{employee.user.displayName}</strong>
                      {protectedAdmin ? <span className="f2-role-badge">ADMIN</span> : null}
                    </div>
                    <span>{employee.user.email}</span>
                  </div>
                  <div className="f2-meta-cell"><span>Equipe</span><strong>{employee.team.name}</strong></div>
                  <div className="f2-meta-cell"><span>Codigo</span><strong>{employee.employeeCode}</strong></div>
                  <span className={`f2-status ${statusLabel(employee).toLowerCase()}`}>{statusLabel(employee)}</span>
                  <button className="f2-secondary-button" type="button" disabled={protectedAdmin} onClick={() => openEdit(employee)}>
                    {protectedAdmin ? 'Protegido' : 'Editar'}
                  </button>
                </article>
              );
            })}
          </div>
        )}
      </section>

      {modalOpen ? (
        <div className="f2-modal-backdrop" role="presentation" onMouseDown={() => !saving && setModalOpen(false)}>
          <section className="f2-modal" role="dialog" aria-modal="true" onMouseDown={(event) => event.stopPropagation()}>
            <div className="f2-modal-header">
              <div>
                <span className="f2-kicker">{editing ? 'EDITAR ACESSO' : 'NOVO ACESSO'}</span>
                <h2>{editing ? editing.user.displayName : 'Cadastrar funcionario'}</h2>
              </div>
              <button type="button" onClick={() => setModalOpen(false)} disabled={saving}>×</button>
            </div>
            {error ? <div className="f2-modal-error">{error}</div> : null}
            <form className="f2-form" onSubmit={submit}>
              <div className="f2-form-grid">
                <label><span>Nome</span><input required value={form.displayName} onChange={(event) => setForm((current) => ({ ...current, displayName: event.target.value }))} /></label>
                <label><span>Codigo</span><input required value={form.employeeCode} onChange={(event) => setForm((current) => ({ ...current, employeeCode: event.target.value }))} /></label>
                <label className="full"><span>E-mail</span><input required type="email" disabled={Boolean(editing)} value={form.email} onChange={(event) => setForm((current) => ({ ...current, email: event.target.value }))} /></label>
                <label><span>Equipe</span><select required value={form.teamId} onChange={(event) => setForm((current) => ({ ...current, teamId: event.target.value }))}>{teams.filter((team) => team.status === 'ACTIVE').map((team) => <option value={team.id} key={team.id}>{team.name}</option>)}</select></label>
                {editing ? <label><span>Status operacional</span><select value={form.employeeStatus} onChange={(event) => setForm((current) => ({ ...current, employeeStatus: event.target.value as EmployeeFormState['employeeStatus'] }))}><option value="ACTIVE">Ativo</option><option value="ON_LEAVE">Afastado</option><option value="INACTIVE">Inativo</option></select></label> : null}
                {editing ? <label><span>Status de acesso</span><select value={form.userStatus} onChange={(event) => setForm((current) => ({ ...current, userStatus: event.target.value as EmployeeFormState['userStatus'] }))}><option value="ACTIVE">Ativo</option><option value="SUSPENDED">Suspenso</option><option value="DISABLED">Desativado</option></select></label> : null}
                <label className={editing ? '' : 'full'}><span>{editing ? 'Nova senha (opcional)' : 'Senha inicial'}</span><input required={!editing} type="password" minLength={12} value={form.password} onChange={(event) => setForm((current) => ({ ...current, password: event.target.value }))} placeholder="Minimo 12 caracteres" /></label>
              </div>
              <div className="f2-modal-actions">
                <button className="f2-secondary-button" type="button" onClick={() => setModalOpen(false)} disabled={saving}>Cancelar</button>
                <button className="f2-primary-button" type="submit" disabled={saving || !form.teamId}>{saving ? 'Salvando...' : 'Salvar'}</button>
              </div>
            </form>
          </section>
        </div>
      ) : null}
    </div>
  );
}
