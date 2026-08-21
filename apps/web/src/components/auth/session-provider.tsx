'use client';

import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';

import { useRouter } from 'next/navigation';

import type { AuthUser } from '@/lib/auth/types';

type SessionContextValue = Readonly<{
  loading: boolean;
  user: AuthUser | null;
  refresh: () => Promise<AuthUser | null>;
  logout: () => Promise<void>;
}>;

const SessionContext = createContext<SessionContextValue | null>(null);

export function SessionProvider({ children }: Readonly<{ children: React.ReactNode }>) {
  const router = useRouter();
  const [user, setUser] = useState<AuthUser | null>(null);
  const [loading, setLoading] = useState(true);

  const refresh = useCallback(async (): Promise<AuthUser | null> => {
    try {
      const response = await fetch('/api/auth/session', {
        method: 'GET',
        cache: 'no-store',
        credentials: 'same-origin',
      });

      if (!response.ok) {
        setUser(null);
        return null;
      }

      const payload = (await response.json()) as { user: AuthUser };
      setUser(payload.user);
      return payload.user;
    } catch {
      setUser(null);
      return null;
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void refresh().then((resolved) => {
      if (!resolved) {
        router.replace('/login');
      }
    });
  }, [refresh, router]);

  const logout = useCallback(async (): Promise<void> => {
    try {
      await fetch('/api/auth/logout', {
        method: 'POST',
        credentials: 'same-origin',
      });
    } finally {
      setUser(null);
      router.replace('/login');
      router.refresh();
    }
  }, [router]);

  const value = useMemo<SessionContextValue>(
    () => ({
      loading,
      user,
      refresh,
      logout,
    }),
    [loading, logout, refresh, user],
  );

  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>;
}

export function useSession(): SessionContextValue {
  const context = useContext(SessionContext);

  if (!context) {
    throw new Error('useSession must be used inside SessionProvider.');
  }

  return context;
}
