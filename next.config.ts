import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  reactStrictMode: true,
  // postgres.js and exceljs must stay as native Node modules (no bundling).
  serverExternalPackages: ['postgres', 'exceljs'],
  experimental: {
    serverActions: {
      bodySizeLimit: '12mb',
    },
  },
};

export default nextConfig;
