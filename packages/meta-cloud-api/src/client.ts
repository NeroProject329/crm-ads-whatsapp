import type { MetaCloudApiConfig } from './config.js';

type FetchImplementation = typeof fetch;

type MetaErrorShape = Readonly<{
  message: string | null;
  type: string | null;
  code: number | null;
  errorSubcode: number | null;
  fbtraceId: string | null;
}>;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function readString(value: unknown): string | null {
  return typeof value === 'string' ? value : null;
}

function readNumber(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

function parseMetaError(payload: unknown): MetaErrorShape {
  if (!isRecord(payload)) {
    return {
      message: null,
      type: null,
      code: null,
      errorSubcode: null,
      fbtraceId: null,
    };
  }

  const error = isRecord(payload.error) ? payload.error : null;

  if (!error) {
    return {
      message: null,
      type: null,
      code: null,
      errorSubcode: null,
      fbtraceId: null,
    };
  }

  return {
    message: readString(error.message),

    type: readString(error.type),

    code: readNumber(error.code),

    errorSubcode: readNumber(error.error_subcode),

    fbtraceId: readString(error.fbtrace_id),
  };
}

export class MetaCloudApiError extends Error {
  readonly status: number;

  readonly code: number | null;

  readonly errorSubcode: number | null;

  readonly metaType: string | null;

  readonly fbtraceId: string | null;

  readonly requestId: string | null;

  constructor(
    input: Readonly<{
      status: number;
      message: string;
      code: number | null;
      errorSubcode: number | null;
      metaType: string | null;
      fbtraceId: string | null;
      requestId: string | null;
    }>,
  ) {
    super(input.message);

    this.name = 'MetaCloudApiError';

    this.status = input.status;

    this.code = input.code;

    this.errorSubcode = input.errorSubcode;

    this.metaType = input.metaType;

    this.fbtraceId = input.fbtraceId;

    this.requestId = input.requestId;
  }
}

export class MetaCloudApiClient {
  constructor(
    private readonly config: MetaCloudApiConfig,

    private readonly fetchImplementation: FetchImplementation = fetch,
  ) {}

  async get<T>(path: string, query: Readonly<Record<string, string>> = {}): Promise<T> {
    return this.request<T>('GET', path, query, undefined);
  }

  async post<T>(path: string, body: Readonly<Record<string, unknown>>): Promise<T> {
    return this.request<T>('POST', path, {}, body);
  }

  private async request<T>(
    method: 'GET' | 'POST',
    path: string,
    query: Readonly<Record<string, string>>,
    body: Readonly<Record<string, unknown>> | undefined,
  ): Promise<T> {
    const normalizedPath = path.trim().replace(/^\/+/, '');

    if (!normalizedPath || normalizedPath.includes('..')) {
      throw new Error('Invalid Meta Graph API path.');
    }

    const url = new URL(
      `${this.config.graphBaseUrl}/${this.config.graphApiVersion}/${normalizedPath}`,
    );

    for (const [key, value] of Object.entries(query)) {
      url.searchParams.set(key, value);
    }

    const response = await this.fetchImplementation(url, {
      method,

      headers: {
        Authorization: `Bearer ${this.config.accessToken}`,

        Accept: 'application/json',

        ...(body
          ? {
              'Content-Type': 'application/json',
            }
          : {}),
      },

      ...(body
        ? {
            body: JSON.stringify(body),
          }
        : {}),

      signal: AbortSignal.timeout(this.config.timeoutMs),
    });

    const raw = await response.text();

    let payload: unknown = null;

    if (raw) {
      try {
        payload = JSON.parse(raw) as unknown;
      } catch {
        payload = null;
      }
    }

    if (!response.ok) {
      const metaError = parseMetaError(payload);

      throw new MetaCloudApiError({
        status: response.status,

        message: metaError.message ?? `Meta Graph API HTTP ${response.status}`,

        code: metaError.code,

        errorSubcode: metaError.errorSubcode,

        metaType: metaError.type,

        fbtraceId: metaError.fbtraceId,

        requestId: response.headers.get('x-fb-request-id'),
      });
    }

    return payload as T;
  }
}
