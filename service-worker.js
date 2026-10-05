// CodeKasa service worker: makes the site installable and lets it open offline.
const CACHE_NAME = "codekasa-cache-v9";
const ASSETS_TO_CACHE = [
  "./index.html", "./admin.html",
  "./manifest.json", "./manifest-admin.json",
  "./building.jpg", "./upi-qr.png", "./room-tour.mp4",
  "./icon-180.png", "./icon-192.png", "./icon-512.png",
  "./icon-maskable-192.png", "./icon-maskable-512.png",
  "./screenshot-home-narrow.jpg",
  "./qr-location.png", "./qr-app.png"
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

  // Installer downloads (APK, MSIX, EXE, DMG, IPA…) and the apps.json list go straight to the network:
  // large files must never be copied into the cache, and the list must always be fresh.
  const path = new URL(event.request.url).pathname;
  if (/\.(apk|aab|msix|msixbundle|appx|appxbundle|exe|msi|dmg|pkg|deb|rpm|appimage|ipa|zip)$/i.test(path) || /\/apps\.json$/i.test(path)) return;

  const isPage = event.request.mode === "navigate" || event.request.url.split("?")[0].endsWith(".html");
  if (isPage) {
    event.respondWith(
      fetch(event.request)
        .then((response) => {
          if (response.ok) {                      // never keep error pages (404 etc.) for offline use
            const copy = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
          }
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
