import type { NextConfig } from 'next';

const appEnvironment = process.env.APP_ENV?.trim() ?? 'development';
const productionLike = appEnvironment === 'staging' || appEnvironment === 'production';
const apiBaseUrl = process.env.CRM_API_BASE_URL?.trim();

if (productionLike && process.env.NODE_ENV !== 'production') {
  throw new Error('NODE_ENV must be production when APP_ENV is staging or production.');
}

if (productionLike && !process.env.NEXT_PUBLIC_ONESIGNAL_APP_ID?.trim()) {
  throw new Error('NEXT_PUBLIC_ONESIGNAL_APP_ID is required for staging/production web builds.');
}

if (productionLike && !apiBaseUrl) {
  throw new Error('CRM_API_BASE_URL is required for staging/production web builds.');
}

if (apiBaseUrl) {
  let parsed: URL;

  try {
    parsed = new URL(apiBaseUrl);
  } catch {
    throw new Error('CRM_API_BASE_URL must be a valid absolute URL.');
  }

  if (productionLike && parsed.protocol !== 'https:') {
    throw new Error('CRM_API_BASE_URL must use HTTPS in staging and production.');
  }
}

const securityHeaders = [
  {
    key: 'X-Content-Type-Options',
    value: 'nosniff',
  },
  {
    key: 'X-Frame-Options',
    value: 'DENY',
  },
  {
    key: 'Referrer-Policy',
    value: 'strict-origin-when-cross-origin',
  },
  {
    key: 'Permissions-Policy',
    value: 'camera=(), microphone=(), geolocation=(), payment=(), usb=()',
  },
  {
    key: 'X-Robots-Tag',
    value: 'noindex, nofollow',
  },
  ...(productionLike
    ? [
        {
          key: 'Strict-Transport-Security',
          value: 'max-age=31536000; includeSubDomains',
        },
      ]
    : []),
];

const noCacheHeaders = [
  {
    key: 'Cache-Control',
    value: 'no-cache, no-store, must-revalidate',
  },
];

const nextConfig: NextConfig = {
  output: process.env.CRM_STANDALONE === 'true' ? 'standalone' : undefined,
  poweredByHeader: false,
  reactStrictMode: true,

  async headers() {
    return [
      {
        source: '/:path*',
        headers: securityHeaders,
      },
      {
        source: '/sw.js',
        headers: noCacheHeaders,
      },
      {
        source: '/push/onesignal/OneSignalSDKWorker.js',
        headers: noCacheHeaders,
      },
    ];
  },
};

export default nextConfig;
