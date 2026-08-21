export class CrmApiError extends Error {
  readonly status: number;
  readonly code: string | null;

  constructor(message: string, status: number, code: string | null = null) {
    super(message);
    this.name = 'CrmApiError';
    this.status = status;
    this.code = code;
  }
}

export async function crmFetch<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(path, {
    ...init,
    cache: 'no-store',
    credentials: 'same-origin',
    headers: {
      Accept: 'application/json',
      ...(init?.body !== undefined ? { 'Content-Type': 'application/json' } : {}),
      ...init?.headers,
    },
  });

  if (!response.ok) {
    const payload = (await response.json().catch(() => null)) as
      | { code?: string; message?: string }
      | null;

    throw new CrmApiError(
      payload?.message ?? 'Nao foi possivel concluir a operacao.',
      response.status,
      payload?.code ?? null,
    );
  }

  return (await response.json()) as T;
}
