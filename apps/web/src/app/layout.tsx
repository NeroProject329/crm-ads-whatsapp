import type { Metadata, Viewport } from 'next';

import type { ReactNode } from 'react';

import { OneSignalBootstrap } from '@/components/onesignal-bootstrap';
import { PwaBootstrap } from '@/components/pwa-bootstrap';

import './globals.css';
import './management-blue-theme.css';
import './f2-management.css';
import './f3-inbox.css';

export const metadata: Metadata = {
  title: 'CRM ADS/WhatsApp',
  description: 'CRM greenfield para ADS, numeros, leads e atendimento WhatsApp.',
  applicationName: 'CRM ADS WhatsApp',
  appleWebApp: {
    capable: true,
    title: 'CRM',
    statusBarStyle: 'black-translucent',
  },
};

export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
  viewportFit: 'cover',
  themeColor: '#dfe5ee',
};

type RootLayoutProps = Readonly<{ children: ReactNode }>;

export default function RootLayout({ children }: RootLayoutProps) {
  return (
    <html lang="pt-BR">
      <body>
        <PwaBootstrap />
        <OneSignalBootstrap />
        {children}
      </body>
    </html>
  );
}
