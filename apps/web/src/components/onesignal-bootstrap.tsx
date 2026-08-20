'use client';

import Script from 'next/script';

import { initializeOneSignal } from '@/lib/push-client';

const appId = process.env.NEXT_PUBLIC_ONESIGNAL_APP_ID?.trim() ?? '';

export function OneSignalBootstrap() {
  if (!appId) {
    return null;
  }

  return (
    <Script
      id="onesignal-web-sdk"
      src="https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.page.js"
      strategy="afterInteractive"
      onLoad={() => {
        initializeOneSignal(appId);
      }}
    />
  );
}
