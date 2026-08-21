import { NextResponse } from 'next/server';

import { loginWithPassword, setAuthCookies } from '@/lib/auth/server';
import type { ApiErrorPayload, AuthTokenResponse } from '@/lib/auth/types';

export const dynamic = 'force-dynamic';

export async function POST(request: Request): Promise<NextResponse> {
  let body: unknown;

  try {
    body = await request.json();
  } catch {
    return NextResponse.json(
      { code: 'WEB_LOGIN_INVALID_JSON', message: 'Dados de login invalidos.' },
      { status: 400 },
    );
  }

  if (!body || typeof body !== 'object') {
    return NextResponse.json(
      { code: 'WEB_LOGIN_INVALID_PAYLOAD', message: 'Dados de login invalidos.' },
      { status: 400 },
    );
  }

  const input = body as Record<string, unknown>;
  const email = typeof input.email === 'string' ? input.email.trim().toLowerCase() : '';
  const organizationSlug =
    typeof input.organizationSlug === 'string' ? input.organizationSlug.trim().toLowerCase() : '';
  const password = typeof input.password === 'string' ? input.password : '';

  if (!email || !organizationSlug || !password) {
    return NextResponse.json(
      { code: 'WEB_LOGIN_REQUIRED_FIELDS', message: 'Preencha e-mail e senha.' },
      { status: 400 },
    );
  }

  const response = await loginWithPassword({ email, organizationSlug, password });

  if (!response.ok) {
    let error: ApiErrorPayload = { message: 'Nao foi possivel entrar.' };

    try {
      error = (await response.json()) as ApiErrorPayload;
    } catch {
      // Keep the safe fallback above.
    }

    return NextResponse.json(
      {
        code: error.code ?? 'WEB_LOGIN_FAILED',
        message:
          error.code === 'AUTH_INVALID_CREDENTIALS'
            ? 'E-mail ou senha invalidos.'
            : (error.message ?? 'Nao foi possivel entrar.'),
      },
      { status: response.status },
    );
  }

  const tokens = (await response.json()) as AuthTokenResponse;
  await setAuthCookies(tokens);

  return NextResponse.json({ user: tokens.user }, { status: 200 });
}
