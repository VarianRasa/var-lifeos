// One-time cleanup for Var's former root-scoped Flutter web app.
self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(
      keys
        .filter(key => key.startsWith('flutter-'))
        .map(key => caches.delete(key)),
    );

    await self.clients.claim();
    const clients = await self.clients.matchAll({ type: 'window' });
    await self.registration.unregister();

    for (const client of clients) {
      const url = new URL(client.url);
      if (url.origin === self.location.origin && !url.pathname.startsWith('/app/')) {
        url.searchParams.set('landing-refresh', '1');
        client.navigate(url.href);
      }
    }
  })());
});
