import { redirect } from 'next/navigation';

import { SessionProvider } from '@/components/auth/session-provider';
import { AppShell } from '@/components/shell/app-shell';
import { hasSessionCookie } from '@/lib/auth/server';

export default async function ProtectedLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  if (!(await hasSessionCookie())) {
    redirect('/login');
  }

  return (
    <SessionProvider>
      <AppShell>{children}</AppShell>
    </SessionProvider>
  );
}
