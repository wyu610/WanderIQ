// Minimal app-shell cache. Data is offline-first via IndexedDB (the sync engine),
// so the SW only needs to serve the built shell when offline.
const CACHE = "wanderiq-shell-v1";
self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(["/", "/index.html"])));
  self.skipWaiting();
});
self.addEventListener("activate", (e) => {
  e.waitUntil(caches.keys().then((ks) =>
    Promise.all(ks.filter((k) => k !== CACHE).map((k) => caches.delete(k)))));
});
self.addEventListener("fetch", (e) => {
  const url = new URL(e.request.url);
  // Never cache Supabase API/Realtime; network-only.
  if (url.hostname.endsWith("supabase.co")) return;
  e.respondWith(caches.match(e.request).then((r) => r ?? fetch(e.request)));
});
