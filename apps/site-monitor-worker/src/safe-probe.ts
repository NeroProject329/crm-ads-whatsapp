import { lookup } from 'node:dns/promises';

import { request as httpsRequest } from 'node:https';

import { isIP } from 'node:net';

export type SiteProbeResult = Readonly<{
  success: boolean;
  httpStatus: number | null;
  latencyMs: number | null;
  resolvedAddress: string | null;
  failureCode: string | null;
  failureMessage: string | null;
}>;

function isPublicIpv4(address: string): boolean {
  const values = address.split('.').map((value) => Number(value));

  if (
    values.length !== 4 ||
    values.some((value) => !Number.isInteger(value) || value < 0 || value > 255)
  ) {
    return false;
  }

  const first = values[0] ?? -1;
  const second = values[1] ?? -1;
  const third = values[2] ?? -1;

  if (first === 0) {
    return false;
  }

  if (first === 10) {
    return false;
  }

  if (first === 100 && second >= 64 && second <= 127) {
    return false;
  }

  if (first === 127) {
    return false;
  }

  if (first === 169 && second === 254) {
    return false;
  }

  if (first === 172 && second >= 16 && second <= 31) {
    return false;
  }

  if (first === 192 && second === 168) {
    return false;
  }

  if (first === 192 && second === 0 && third === 0) {
    return false;
  }

  if (first === 192 && second === 0 && third === 2) {
    return false;
  }

  if (first === 198 && (second === 18 || second === 19)) {
    return false;
  }

  if (first === 198 && second === 51 && third === 100) {
    return false;
  }

  if (first === 203 && second === 0 && third === 113) {
    return false;
  }

  if (first >= 224) {
    return false;
  }

  return true;
}

function isPublicIpv6(address: string): boolean {
  const normalized = address.toLowerCase();

  if (normalized === '::' || normalized === '::1') {
    return false;
  }

  if (normalized.startsWith('fc') || normalized.startsWith('fd')) {
    return false;
  }

  if (
    normalized.startsWith('fe8') ||
    normalized.startsWith('fe9') ||
    normalized.startsWith('fea') ||
    normalized.startsWith('feb')
  ) {
    return false;
  }

  if (normalized.startsWith('ff')) {
    return false;
  }

  if (normalized.startsWith('2001:db8')) {
    return false;
  }

  if (normalized.startsWith('::ffff:')) {
    const mapped = normalized.slice('::ffff:'.length);

    if (isIP(mapped) === 4) {
      return isPublicIpv4(mapped);
    }
  }

  return true;
}

export function isPublicIpAddress(address: string): boolean {
  const version = isIP(address);

  if (version === 4) {
    return isPublicIpv4(address);
  }

  if (version === 6) {
    return isPublicIpv6(address);
  }

  return false;
}

function classifyRequestError(error: NodeJS.ErrnoException): string {
  const code = error.code ?? '';

  if (code.includes('CERT') || code.includes('TLS') || code.includes('SSL')) {
    return 'TLS_ERROR';
  }

  if (
    code === 'ECONNREFUSED' ||
    code === 'ECONNRESET' ||
    code === 'EHOSTUNREACH' ||
    code === 'ENETUNREACH'
  ) {
    return 'CONNECTION_ERROR';
  }

  if (code === 'ETIMEDOUT') {
    return 'TIMEOUT';
  }

  return 'REQUEST_ERROR';
}

export async function probeHostname(hostname: string, timeoutMs: number): Promise<SiteProbeResult> {
  let addresses;

  try {
    addresses = await lookup(hostname, {
      all: true,
      verbatim: true,
    });
  } catch (error) {
    return {
      success: false,
      httpStatus: null,
      latencyMs: null,
      resolvedAddress: null,
      failureCode: 'DNS_ERROR',

      failureMessage:
        error instanceof Error ? error.message.slice(0, 500) : String(error).slice(0, 500),
    };
  }

  const publicAddress = addresses.find((entry) => isPublicIpAddress(entry.address));

  if (!publicAddress) {
    return {
      success: false,
      httpStatus: null,
      latencyMs: null,
      resolvedAddress: null,
      failureCode: 'SECURITY_BLOCKED_ADDRESS',

      failureMessage: 'Hostname resolved only to private, reserved, or unsupported addresses.',
    };
  }

  const startedAt = Date.now();

  return new Promise<SiteProbeResult>((resolve) => {
    let settled = false;
    let timedOut = false;

    const finish = (result: SiteProbeResult): void => {
      if (settled) {
        return;
      }

      settled = true;
      resolve(result);
    };

    const request = httpsRequest(
      {
        protocol: 'https:',
        hostname: publicAddress.address,
        port: 443,
        path: '/',
        method: 'GET',
        servername: hostname,
        rejectUnauthorized: true,

        headers: {
          Host: hostname,
          'User-Agent': 'CRM-ADS-WhatsApp-Site-Monitor/1.0',
          Accept: 'text/html,application/xhtml+xml,*/*;q=0.8',
        },
      },

      (response) => {
        const latencyMs = Date.now() - startedAt;

        const statusCode = response.statusCode ?? 0;

        response.destroy();

        if (statusCode >= 200 && statusCode < 400) {
          finish({
            success: true,
            httpStatus: statusCode,
            latencyMs,
            resolvedAddress: publicAddress.address,
            failureCode: null,
            failureMessage: null,
          });

          return;
        }

        finish({
          success: false,
          httpStatus: statusCode,
          latencyMs,
          resolvedAddress: publicAddress.address,
          failureCode: 'HTTP_STATUS',
          failureMessage: `HTTP ${statusCode}`,
        });
      },
    );

    request.setTimeout(timeoutMs, () => {
      timedOut = true;
      request.destroy();
    });

    request.on('error', (error: NodeJS.ErrnoException) => {
      finish({
        success: false,
        httpStatus: null,

        latencyMs: Date.now() - startedAt,

        resolvedAddress: publicAddress.address,

        failureCode: timedOut ? 'TIMEOUT' : classifyRequestError(error),

        failureMessage: timedOut ? `Request exceeded ${timeoutMs}ms.` : error.message.slice(0, 500),
      });
    });

    request.end();
  });
}
