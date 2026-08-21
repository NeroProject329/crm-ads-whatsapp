'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';

import { useSession } from '@/components/auth/session-provider';

export function AdminPageGuard({ children }: Readonly<{ children: React.ReactNode }>) {
  const router = useRouter();
  const { loading, user } = useSession();
  const isAdmin = Boolean(user?.roles.includes('ADMIN'));

  useEffect(() => {
    if (!loading && user && !isAdmin) {
      router.replace('/dashboard');
    }
  }, [isAdmin, loading, router, user]);

  if (loading || !user || !isAdmin) {
    return <div className="f2-panel f2-empty">Validando permissao administrativa...</div>;
  }

  return children;
}
