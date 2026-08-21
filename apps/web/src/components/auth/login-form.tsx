'use client';

import { FormEvent, useState } from 'react';

import { useRouter } from 'next/navigation';

const organizationSlug =
  process.env.NEXT_PUBLIC_CRM_ORGANIZATION_SLUG?.trim() || 'crm-ads-whatsapp';

type LoginError = Readonly<{
  message?: string;
}>;

export function LoginForm() {
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (loading) {
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const response = await fetch('/api/auth/login', {
        method: 'POST',
        credentials: 'same-origin',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          email,
          organizationSlug,
          password,
        }),
      });

      if (!response.ok) {
        const payload = (await response.json().catch(() => ({}))) as LoginError;
        setError(payload.message ?? 'Nao foi possivel entrar. Tente novamente.');
        return;
      }

      router.replace('/dashboard');
      router.refresh();
    } catch {
      setError('Nao foi possivel conectar ao CRM. Verifique sua conexao e tente novamente.');
    } finally {
      setLoading(false);
    }
  }

  return (
    <form className="login-form" onSubmit={handleSubmit} noValidate>
      <div className="field-group">
        <label htmlFor="email">E-mail</label>
        <div className="field-shell">
          <svg aria-hidden="true" viewBox="0 0 24 24">
            <path d="M4 6.5h16v11H4z" />
            <path d="m4.5 7 7.5 6 7.5-6" />
          </svg>
          <input
            id="email"
            name="email"
            type="email"
            autoComplete="email"
            inputMode="email"
            placeholder="voce@empresa.com"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            required
          />
        </div>
      </div>

      <div className="field-group">
        <div className="field-label-row">
          <label htmlFor="password">Senha</label>
          <span>Ambiente seguro</span>
        </div>
        <div className="field-shell">
          <svg aria-hidden="true" viewBox="0 0 24 24">
            <rect x="5" y="10" width="14" height="10" rx="2" />
            <path d="M8 10V7.5a4 4 0 0 1 8 0V10" />
          </svg>
          <input
            id="password"
            name="password"
            type={showPassword ? 'text' : 'password'}
            autoComplete="current-password"
            placeholder="Digite sua senha"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            required
          />
          <button
            className="password-toggle"
            type="button"
            aria-label={showPassword ? 'Ocultar senha' : 'Mostrar senha'}
            onClick={() => setShowPassword((current) => !current)}
          >
            {showPassword ? 'Ocultar' : 'Mostrar'}
          </button>
        </div>
      </div>

      {error ? (
        <div className="form-error" role="alert">
          <span aria-hidden="true">!</span>
          {error}
        </div>
      ) : null}

      <button className="primary-button login-submit" type="submit" disabled={loading}>
        <span>{loading ? 'Entrando...' : 'Entrar no CRM'}</span>
        <svg aria-hidden="true" viewBox="0 0 24 24">
          <path d="M5 12h14M14 7l5 5-5 5" />
        </svg>
      </button>

      <p className="login-security-note">
        Seus tokens de sessao ficam protegidos em cookies HttpOnly e nao sao expostos ao navegador.
      </p>
    </form>
  );
}
