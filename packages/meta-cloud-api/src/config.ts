export type MetaCloudApiConfig = Readonly<{
  graphBaseUrl: string;
  graphApiVersion: string;
  accessToken: string;
  timeoutMs: number;
}>;

function readRequired(environment: NodeJS.ProcessEnv, name: string): string {
  const value = environment[name]?.trim();

  if (!value) {
    throw new Error(`${name} is required.`);
  }

  return value;
}

function readTimeout(environment: NodeJS.ProcessEnv): number {
  const raw = environment.META_HTTP_TIMEOUT_MS?.trim();

  if (!raw) {
    return 10_000;
  }

  const value = Number(raw);

  if (!Number.isInteger(value) || value < 500 || value > 120_000) {
    throw new Error('META_HTTP_TIMEOUT_MS must be an integer between 500 and 120000.');
  }

  return value;
}

export function parseMetaCloudApiConfig(
  environment: NodeJS.ProcessEnv = process.env,
): MetaCloudApiConfig {
  const graphApiVersion = readRequired(environment, 'META_GRAPH_API_VERSION');

  if (!/^v\d+\.\d+$/.test(graphApiVersion)) {
    throw new Error('META_GRAPH_API_VERSION must look like vXX.X.');
  }

  const accessToken = readRequired(environment, 'META_ACCESS_TOKEN');

  const graphBaseUrl = (
    environment.META_GRAPH_BASE_URL?.trim() || 'https://graph.facebook.com'
  ).replace(/\/+$/, '');

  const parsedBaseUrl = new URL(graphBaseUrl);

  if (parsedBaseUrl.protocol !== 'https:') {
    throw new Error('META_GRAPH_BASE_URL must use HTTPS.');
  }

  return {
    graphBaseUrl,
    graphApiVersion,
    accessToken,
    timeoutMs: readTimeout(environment),
  };
}
