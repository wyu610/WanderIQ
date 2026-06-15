// App-shell cache. Navigations are NETWORK-FIRST so a new deploy reaches
// returning users immediately (a cached index.html would point at an old,
// now-404 asset hash). Hashed assets are immutable, so they're cache-first.
// Data is offline-first via IndexedDB, so Supabase requests are never cached.
const CACHE = "wanderiq-shell-v2";

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(["/", "/index.html"])));
  self.skipWaiting();
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys()
      .then((ks) => Promise.all(ks.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener("fetch", (e) => {
  const { request } = e;
  const url = new URL(request.url);

  // Never cache Supabase API/Realtime; let it hit the network directly.
  if (url.hostname.endsWith("supabase.co")) return;

  // Navigations: network-first; fall back to the cached shell only offline.
  if (request.mode === "navigate") {
    e.respondWith(
      fetch(request)
        .then((res) => {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put("/index.html", copy));
          return res;
        })
        .catch(() => caches.match(request).then((r) => r ?? caches.match("/index.html"))),
    );
    return;
  }

  // Other same-origin GETs (hashed assets are immutable): cache-first, then
  // network, caching what we fetch for offline use.
  e.respondWith(
    caches.match(request).then((cached) =>
      cached ??
      fetch(request).then((res) => {
        if (request.method === "GET" && res.ok && url.origin === self.location.origin) {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(request, copy));
        }
        return res;
      }),
    ),
  );
});
