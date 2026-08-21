import { NextResponse } from 'next/server';

import { resolveSession } from '@/lib/auth/server';

export const dynamic = 'force-dynamic';

export async function GET(): Promise<NextResponse> {
  const user = await resolveSession();

  if (!user) {
    return NextResponse.json(
      { code: 'WEB_SESSION_UNAUTHENTICATED', message: 'Sessao nao autenticada.' },
      { status: 401 },
    );
  }

  return NextResponse.json({ user }, { status: 200 });
}
