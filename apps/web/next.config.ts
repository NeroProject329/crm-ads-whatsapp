import type { NextConfig } from 'next';

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
