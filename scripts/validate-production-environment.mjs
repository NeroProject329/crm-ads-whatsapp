const service = process.argv[2];

const services = new Set(['api', 'webhook-ingress', 'worker', 'site-monitor-worker', 'web']);

if (!service || !services.has(service)) {
  console.error(
    'Usage: node scripts/validate-production-environment.mjs <api|webhook-ingress|worker|site-monitor-worker|web>',
  );

  process.exit(2);
}

const appEnvironment = process.env.APP_ENV?.trim();

if (appEnvironment !== 'staging' && appEnvironment !== 'production') {
  console.error('APP_ENV must be staging or production for this validator.');

  process.exit(1);
}

if (process.env.NODE_ENV !== 'production') {
  console.error('NODE_ENV must be production.');

  process.exit(1);
}

const errors = [];

function required(name, minimumLength = 1) {
  const value = process.env[name]?.trim();

  if (!value || value.length < minimumLength) {
    errors.push(`${name}: missing or too short`);

    return null;
  }

  const lower = value.toLowerCase();

  if (lower.includes('change_me') || lower.includes('placeholder')) {
    errors.push(`${name}: placeholder value`);
  }

  return value;
}

function database() {
  const raw = required('DATABASE_URL', 10);

  if (!raw) {
    return;
  }

  try {
    const url = new URL(raw);

    if (url.protocol !== 'postgresql:' && url.protocol !== 'postgres:') {
      errors.push('DATABASE_URL: must use PostgreSQL');
    }

    if (url.hostname === 'localhost' || url.hostname === '127.0.0.1') {
      errors.push('DATABASE_URL: localhost is forbidden');
    }
  } catch {
    errors.push('DATABASE_URL: invalid URL');
  }
}

if (service !== 'web') {
  database();
}

if (service === 'api') {
  const access = required('AUTH_ACCESS_TOKEN_SECRET', 32);

  const pepper = required('AUTH_REFRESH_TOKEN_PEPPER', 32);

  if (access && pepper && access === pepper) {
    errors.push('AUTH secrets must be different');
  }

  const origins = required('API_CORS_ALLOWED_ORIGINS', 8);

  if (origins) {
    for (const raw of origins
      .split(',')
      .map((value) => value.trim())
      .filter(Boolean)) {
      try {
        const url = new URL(raw);

        if (url.protocol !== 'https:') {
          errors.push(`CORS origin must use HTTPS: ${raw}`);
        }
      } catch {
        errors.push(`Invalid CORS origin: ${raw}`);
      }
    }
  }
}

if (service === 'webhook-ingress') {
  required('META_APP_SECRET', 32);

  required('META_WEBHOOK_VERIFY_TOKEN', 16);
}

if (service === 'worker') {
  const graph = required('META_GRAPH_API_VERSION', 4);

  if (graph && !/^v\d+\.\d+$/.test(graph)) {
    errors.push('META_GRAPH_API_VERSION: invalid format');
  }

  required('META_ACCESS_TOKEN', 20);

  required('ONESIGNAL_APP_ID', 8);

  required('ONESIGNAL_API_KEY', 20);
}

if (service === 'web') {
  required('NEXT_PUBLIC_ONESIGNAL_APP_ID', 8);
}

if (errors.length > 0) {
  for (const error of errors) {
    console.error(`[ERROR] ${error}`);
  }

  process.exit(1);
}

console.log(`[OK] ${service} production environment validated for ${appEnvironment}.`);
