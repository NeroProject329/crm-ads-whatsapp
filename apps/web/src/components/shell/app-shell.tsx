'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useMemo, useState } from 'react';

import { useSession } from '@/components/auth/session-provider';

type NavigationIconName =
  | 'dashboard'
  | 'employees'
  | 'teams'
  | 'inbox'
  | 'ads'
  | 'leads'
  | 'numbers'
  | 'sites'
  | 'settings';

type NavigationItem = Readonly<{
  label: string;
  href: string;
  icon: NavigationIconName;
  adminOnly?: boolean;
  comingSoon?: boolean;
}>;

const navigation: readonly NavigationItem[] = [
  { label: 'Visao geral', href: '/dashboard', icon: 'dashboard' },
  { label: 'Funcionarios', href: '/employees', icon: 'employees', adminOnly: true },
  { label: 'Equipes', href: '/teams', icon: 'teams', adminOnly: true },
  { label: 'Sites', href: '/sites', icon: 'sites' },
  { label: 'WhatsApp', href: '/inbox', icon: 'inbox', comingSoon: true },
  { label: 'ADS e filas', href: '/ads', icon: 'ads', comingSoon: true },
  { label: 'Leads', href: '/leads', icon: 'leads', comingSoon: true },
  { label: 'Numeros', href: '/numbers', icon: 'numbers', comingSoon: true },
  { label: 'Configuracoes', href: '/settings', icon: 'settings', adminOnly: true },
];

function NavigationIcon({ name }: Readonly<{ name: NavigationIconName }>) {
  const paths: Record<NavigationIconName, React.ReactNode> = {
    dashboard: <><rect x="4" y="4" width="6" height="6" rx="1.5" /><rect x="14" y="4" width="6" height="6" rx="1.5" /><rect x="4" y="14" width="6" height="6" rx="1.5" /><rect x="14" y="14" width="6" height="6" rx="1.5" /></>,
    employees: <><circle cx="9" cy="8" r="3" /><path d="M4 19c0-3 2.2-5 5-5s5 2 5 5" /><circle cx="17" cy="9" r="2.2" /><path d="M15 15c2.8-.3 5 1.3 5 4" /></>,
    teams: <><circle cx="8" cy="8" r="2.7" /><circle cx="16" cy="8" r="2.7" /><path d="M3.5 19c0-3 2-5 4.5-5s4.5 2 4.5 5M11.5 19c0-3 2-5 4.5-5s4.5 2 4.5 5" /></>,
    inbox: <><path d="M4 5h16v12H8l-4 3V5Z" /><path d="M8 9h8M8 13h5" /></>,
    ads: <><path d="M5 7h14M5 12h14M5 17h14" /><circle cx="9" cy="7" r="2" /><circle cx="15" cy="12" r="2" /><circle cx="11" cy="17" r="2" /></>,
    leads: <><circle cx="9" cy="8" r="3" /><path d="M4 19c0-3 2.2-5 5-5s5 2 5 5" /><path d="M17 8v6M14 11h6" /></>,
    numbers: <><rect x="6" y="3" width="12" height="18" rx="3" /><path d="M9 7h6M10 17h4" /></>,
    sites: <><circle cx="12" cy="12" r="9" /><path d="M3 12h18M12 3a15 15 0 0 1 0 18M12 3a15 15 0 0 0 0 18" /></>,
    settings: <><circle cx="12" cy="12" r="3" /><path d="M19 12a7 7 0 0 0-.1-1l2-1.5-2-3.4-2.4 1a7 7 0 0 0-1.7-1L14.5 3h-5l-.4 3.1a7 7 0 0 0-1.7 1L5 6.1 3 9.5 5 11a7 7 0 0 0 0 2l-2 1.5 2 3.4 2.4-1a7 7 0 0 0 1.7 1l.4 3.1h5l.4-3.1a7 7 0 0 0 1.7-1l2.4 1 2-3.4L19 13a7 7 0 0 0 .1-1Z" /></>,
  };

  return <svg className="nav-icon" aria-hidden="true" viewBox="0 0 24 24">{paths[name]}</svg>;
}

function initials(name: string | undefined): string {
  if (!name) return 'CRM';
  return name.trim().split(/\s+/).slice(0, 2).map((part) => part.charAt(0).toUpperCase()).join('');
}

export function AppShell({ children }: Readonly<{ children: React.ReactNode }>) {
  const pathname = usePathname();
  const { loading, user, logout } = useSession();
  const [mobileOpen, setMobileOpen] = useState(false);
  const isAdmin = Boolean(user?.roles.includes('ADMIN'));
  const visibleNavigation = useMemo(() => navigation.filter((item) => !item.adminOnly || isAdmin), [isAdmin]);

  return (
    <div className="app-frame">
      <button className={`sidebar-scrim${mobileOpen ? ' is-visible' : ''}`} aria-label="Fechar menu" type="button" onClick={() => setMobileOpen(false)} />
      <aside className={`app-sidebar${mobileOpen ? ' is-open' : ''}`}>
        <div className="brand-lockup"><div className="brand-mark" aria-hidden="true"><span /><span /><span /></div><div><strong>NERO CRM</strong><span>ADS + WhatsApp</span></div></div>
        <div className="workspace-chip"><span className="workspace-dot" aria-hidden="true" /><div><strong>Operacao principal</strong><span>{loading ? 'Validando acesso...' : isAdmin ? 'Administrador' : 'Atendimento'}</span></div></div>
        <nav className="sidebar-nav" aria-label="Navegacao principal">
          <span className="nav-section-label">Operacao</span>
          {visibleNavigation.map((item) => {
            const active = pathname === item.href || pathname.startsWith(`${item.href}/`);
            if (item.comingSoon) return <div className="nav-item is-disabled" key={item.href} aria-disabled="true"><NavigationIcon name={item.icon} /><span>{item.label}</span><span className="soon-badge">Em breve</span></div>;
            return <Link className={`nav-item${active ? ' is-active' : ''}`} href={item.href} key={item.href} onClick={() => setMobileOpen(false)}><NavigationIcon name={item.icon} /><span>{item.label}</span></Link>;
          })}
        </nav>
        <div className="sidebar-footer"><div className="environment-status"><span /><div><strong>Staging conectado</strong><small>Backend operacional</small></div></div><button className="sidebar-logout" type="button" onClick={() => void logout()}>Sair da conta</button></div>
      </aside>
      <div className="app-content-column">
        <header className="app-topbar">
          <button className="mobile-menu-button" type="button" aria-label="Abrir menu" onClick={() => setMobileOpen(true)}><span /><span /></button>
          <div className="topbar-context"><span className="topbar-kicker">CRM ADS / WHATSAPP</span><strong>Central de operacao</strong></div>
          <div className="topbar-actions"><button className="icon-button" type="button" aria-label="Notificacoes" disabled><svg aria-hidden="true" viewBox="0 0 24 24"><path d="M6 17h12l-1.5-2.5V10a4.5 4.5 0 0 0-9 0v4.5L6 17Z" /><path d="M10 20h4" /></svg></button><div className="user-chip"><span className="user-avatar">{initials(user?.displayName)}</span><div><strong>{loading ? 'Carregando...' : (user?.displayName ?? 'Usuario')}</strong><span>{isAdmin ? 'ADMIN' : 'EMPLOYEE'}</span></div></div></div>
        </header>
        <main className="app-main">{children}</main>
      </div>
    </div>
  );
}
