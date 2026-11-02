/* Mobile web push service worker */
self.addEventListener('push', event => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; }
  catch (_) { data = { body: event.data ? event.data.text() : '' }; }

  const title = String(data.title || 'اعلان ساختمان').slice(0, 120);
  const options = {
    body: String(data.body || 'یک اعلان جدید دریافت کردید.').slice(0, 500),
    icon: '/icon.svg',
    badge: '/icon.svg',
    dir: 'rtl',
    lang: 'fa',
    data: { path: safeAppPath(data.url) },
    tag: String(data.tag || 'building-notification').slice(0, 100),
    renotify: false
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

function safeAppPath(value) {
  if (typeof value !== 'string' || !value) return '/';
  try {
    const parsed = new URL(value, self.location.origin);
    if (parsed.origin !== self.location.origin) return '/';
    return parsed.pathname + parsed.search + parsed.hash;
  } catch (_) {
    return '/';
  }
}

self.addEventListener('notificationclick', event => {
  event.notification.close();
  const target = new URL(safeAppPath(event.notification.data?.path), self.location.origin).href;
  event.waitUntil((async () => {
    const windows = await clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const client of windows) {
      if (new URL(client.url).origin === self.location.origin && 'focus' in client) {
        await client.focus();
        if ('navigate' in client) await client.navigate(target);
        return;
      }
    }
    if (clients.openWindow) await clients.openWindow(target);
  })());
});

// Keep GET requests network-only; the app does not cache private account data.
self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;
  event.respondWith(fetch(event.request));
});
