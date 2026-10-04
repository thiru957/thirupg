// CodeKasa service worker: makes the site installable and lets it open offline.
const CACHE_NAME = "codekasa-cache-v7";
const ASSETS_TO_CACHE = [
  "./index.html", "./admin.html",
  "./manifest.json", "./manifest-admin.json",
  "./building.jpg", "./upi-qr.png", "./room-tour.mp4",
  "./icon-180.png", "./icon-192.png", "./icon-512.png",
  "./icon-maskable-192.png", "./icon-maskable-512.png"
];

self.addEventListener("install", (event) => {
  // Add files one by one so a single missing file can never stop the app from installing.
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) =>
      Promise.all(ASSETS_TO_CACHE.map((url) => cache.add(url).catch(() => {})))
    )
  );
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key)))
    )
  );
  self.clients.claim();
});

// Pages: network first (so updates show immediately), cached copy when offline.
// Everything else on our own site: cached first, for speed.
// Anything on other sites (Firebase, payments, email form, fonts) is never touched.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET" || new URL(event.request.url).origin !== self.location.origin) return;

  const isPage = event.request.mode === "navigate" || event.request.url.split("?")[0].endsWith(".html");
  if (isPage) {
    event.respondWith(
      fetch(event.request)
        .then((response) => {
          const copy = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
          return response;
        })
        .catch(() =>
          caches.match(event.request, { ignoreSearch: true }).then((hit) =>
            hit || caches.match(event.request.url.includes("admin.html") ? "./admin.html" : "./index.html"))
        )
    );
    return;
  }
  event.respondWith(caches.match(event.request).then((cached) => cached || fetch(event.request)));
});
