import { describe, expect, it } from 'vitest';

import { MetaCloudApiClient, MetaCloudApiError } from './client.js';

import { parseMetaCloudApiConfig } from './config.js';

describe('parseMetaCloudApiConfig', () => {
  it('requires an explicit Graph API version', () => {
    expect(() =>
      parseMetaCloudApiConfig({
        META_ACCESS_TOKEN: 'stage8-test-token',
      }),
    ).toThrow('META_GRAPH_API_VERSION is required.');
  });

  it('accepts an explicit version and HTTPS base URL', () => {
    const config = parseMetaCloudApiConfig({
      META_GRAPH_API_VERSION: 'v99.0',

      META_ACCESS_TOKEN: 'stage8-test-token',

      META_GRAPH_BASE_URL: 'https://graph.example.test',

      META_HTTP_TIMEOUT_MS: '5000',
    });

    expect(config.graphApiVersion).toBe('v99.0');

    expect(config.timeoutMs).toBe(5000);
  });

  it('rejects non-HTTPS Graph base URLs', () => {
    expect(() =>
      parseMetaCloudApiConfig({
        META_GRAPH_API_VERSION: 'v99.0',

        META_ACCESS_TOKEN: 'stage8-test-token',

        META_GRAPH_BASE_URL: 'http://graph.example.test',
      }),
    ).toThrow('META_GRAPH_BASE_URL must use HTTPS.');
  });
});

describe('MetaCloudApiClient', () => {
  it('sends Bearer authentication and the configured version', async () => {
    let capturedUrl = '';

    let capturedAuthorization: string | null = null;

    const fetchMock: typeof fetch = async (input, init) => {
      capturedUrl = String(input);

      const headers = new Headers(init?.headers);

      capturedAuthorization = headers.get('authorization');

      return new Response(
        JSON.stringify({
          id: '9988776655',
        }),
        {
          status: 200,

          headers: {
            'content-type': 'application/json',
          },
        },
      );
    };

    const client = new MetaCloudApiClient(
      {
        graphBaseUrl: 'https://graph.example.test',

        graphApiVersion: 'v99.0',

        accessToken: 'stage8-test-access-token',

        timeoutMs: 5000,
      },
      fetchMock,
    );

    const result = await client.get<{
      id: string;
    }>('9988776655', {
      fields: 'id',
    });

    expect(result.id).toBe('9988776655');

    expect(capturedUrl).toContain('/v99.0/9988776655');

    expect(capturedUrl).toContain('fields=id');

    expect(capturedAuthorization).toBe('Bearer stage8-test-access-token');
  });

  it('normalizes Meta Graph API errors', async () => {
    const fetchMock: typeof fetch = async () =>
      new Response(
        JSON.stringify({
          error: {
            message: 'Invalid OAuth access token.',

            type: 'OAuthException',

            code: 190,

            error_subcode: 463,

            fbtrace_id: 'stage8-trace',
          },
        }),
        {
          status: 400,

          headers: {
            'content-type': 'application/json',

            'x-fb-request-id': 'stage8-request',
          },
        },
      );

    const client = new MetaCloudApiClient(
      {
        graphBaseUrl: 'https://graph.example.test',

        graphApiVersion: 'v99.0',

        accessToken: 'stage8-test-access-token',

        timeoutMs: 5000,
      },
      fetchMock,
    );

    try {
      await client.get('me');

      throw new Error('Expected MetaCloudApiError.');
    } catch (error) {
      expect(error).toBeInstanceOf(MetaCloudApiError);

      const metaError = error as MetaCloudApiError;

      expect(metaError.status).toBe(400);

      expect(metaError.code).toBe(190);

      expect(metaError.errorSubcode).toBe(463);

      expect(metaError.fbtraceId).toBe('stage8-trace');

      expect(metaError.requestId).toBe('stage8-request');

      expect(metaError.message).not.toContain('stage8-test-access-token');
    }
  });
});
