import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  output: process.env.CRM_STANDALONE === 'true' ? 'standalone' : undefined,
  poweredByHeader: false,
  reactStrictMode: true,
};

export default nextConfig;
