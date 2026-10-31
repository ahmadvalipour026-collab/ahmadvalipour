/* Mobile web push service worker */
self.addEventListener('push', event => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; }
  catch (_) { data = { body: event.data ? event.data.text() : '' }; }

  const title = String(data.title || 'اعلان ساختمان');
  const options = {
    body: String(data.body || 'یک اعلان جدید دریافت کردید.'),
    icon: '/icon.svg',
    badge: '/icon.svg',
    dir: 'rtl',
    lang: 'fa',
    data: { url: data.url || '/' },
    tag: data.tag || 'building-notification',
    renotify: false
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', event => {
  event.notification.close();
  const target = new URL(event.notification.data?.url || '/', self.location.origin).href;
  event.waitUntil((async () => {
    const windows = await clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const client of windows) {
      if (client.url.startsWith(self.location.origin) && 'focus' in client) {
        await client.focus();
        if ('navigate' in client) await client.navigate(target);
        return;
      }
    }
    if (clients.openWindow) await clients.openWindow(target);
  })());
});
