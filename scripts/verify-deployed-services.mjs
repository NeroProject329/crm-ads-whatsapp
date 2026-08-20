const apiBase = process.env.DEPLOY_API_BASE_URL?.trim();

const webhookBase = process.env.DEPLOY_WEBHOOK_BASE_URL?.trim();

if (!apiBase || !webhookBase) {
  console.error('DEPLOY_API_BASE_URL and DEPLOY_WEBHOOK_BASE_URL are required.');

  process.exit(2);
}

function normalizeBase(raw, label) {
  const url = new URL(raw);

  if (url.protocol !== 'https:') {
    throw new Error(`${label} must use HTTPS.`);
  }

  return url.origin;
}

async function verify(url, expectedService) {
  const response = await fetch(url, {
    signal: AbortSignal.timeout(10000),
  });

  if (response.status !== 200) {
    throw new Error(`${url} returned ${response.status}.`);
  }

  const payload = await response.json();

  if (payload.service !== expectedService) {
    throw new Error(`${url} returned unexpected service identity.`);
  }

  const noSniff = response.headers.get('x-content-type-options');

  if (noSniff !== 'nosniff') {
    throw new Error(`${url} is missing X-Content-Type-Options: nosniff.`);
  }

  const cache = response.headers.get('cache-control');

  if (!cache?.includes('no-store')) {
    throw new Error(`${url} is missing Cache-Control: no-store.`);
  }

  return payload;
}

try {
  const api = normalizeBase(apiBase, 'DEPLOY_API_BASE_URL');

  const webhook = normalizeBase(webhookBase, 'DEPLOY_WEBHOOK_BASE_URL');

  await verify(`${api}/api/v1/health/live`, 'api');

  await verify(`${api}/api/v1/health/ready`, 'api');

  await verify(`${webhook}/health/live`, 'webhook-ingress');

  await verify(`${webhook}/health/ready`, 'webhook-ingress');

  console.log('[OK] Remote API and webhook health/security checks passed.');
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));

  process.exit(1);
}
