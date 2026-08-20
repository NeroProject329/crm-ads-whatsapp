/* global self */
self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('message', (event) => {
  if (event.data === 'SKIP_WAITING') {
    self.skipWaiting();
  }
});

/*
 * IMPORTANT:
 *
 * This CRM is intentionally online-only.
 *
 * There is NO fetch handler and NO Cache API usage here.
 *
 * Authenticated API responses, ADS data, leads,
 * WhatsApp conversations, dashboards, receipts,
 * tokens and financial information must never be
 * cached for offline use by this service worker.
 */
