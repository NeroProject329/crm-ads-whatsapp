import type { MetadataRoute } from 'next';

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: 'CRM ADS WhatsApp',

    short_name: 'CRM',

    description: 'CRM para operacao de ADS e WhatsApp.',

    start_url: '/',

    display: 'standalone',

    orientation: 'any',

    background_color: '#0b0b0b',

    theme_color: '#0b0b0b',

    icons: [
      {
        src: '/icons/pwa-192.svg',

        sizes: '192x192',

        type: 'image/svg+xml',

        purpose: 'any',
      },

      {
        src: '/icons/pwa-512.svg',

        sizes: '512x512',

        type: 'image/svg+xml',

        purpose: 'any',
      },

      {
        src: '/icons/pwa-maskable.svg',

        sizes: '512x512',

        type: 'image/svg+xml',

        purpose: 'maskable',
      },
    ],
  };
}
