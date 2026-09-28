const CACHE_NAME = "codekasa-cache-v5";
const ASSETS_TO_CACHE = [
  "./index.html",
  "./admin.html",
  "./manifest.json",
  "./manifest-admin.json",
  "./building.jpg",
  "./room-tour.mp4",
  "./icon-192.png",
  "./icon-512.png",
  "./icon-180.png"
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(ASSETS_TO_CACHE))
  );
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key))
      )
    )
  );
  self.clients.claim();
});

// Network-first for pages (HTML), so edits/updates are picked up immediately.
// Cache-first for everything else (images, icons, manifests), for speed.
self.addEventListener("fetch", (event) => {
  // Only handle GET requests for our own files. Anything else (Firebase, form service, fonts) goes straight to the network.
  if (event.request.method !== "GET" || new URL(event.request.url).origin !== self.location.origin) return;

  const isHTML = event.request.mode === "navigate" || event.request.url.endsWith(".html");

  if (isHTML) {
    event.respondWith(
      fetch(event.request)
        .then((response) => {
          const clone = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
          return response;
        })
        .catch(() => {
          const fallback = event.request.url.includes("admin.html") ? "./admin.html" : "./index.html";
          return caches.match(fallback);
        })
    );
    return;
  }

  event.respondWith(
    caches.match(event.request).then((cached) => cached || fetch(event.request))
  );
});
