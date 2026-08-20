export type MetaWebhookConfig = Readonly<{
  verifyToken: string | null;
  appSecret: string | null;
}>;

function optionalEnvironment(name: string): string | null {
  const value = process.env[name]?.trim();

  return value ? value : null;
}

export function parseMetaWebhookConfig(): MetaWebhookConfig {
  return {
    verifyToken: optionalEnvironment('META_WEBHOOK_VERIFY_TOKEN'),

    appSecret: optionalEnvironment('META_APP_SECRET'),
  };
}
