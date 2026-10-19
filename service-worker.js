const CACHE_NAME = 'leasing-tracker-v2';
const urlsToCache = [
  './',
  './index.html',
  './manifest.json'
];

// Installation
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => {
        console.log('Cache geöffnet');
        return cache.addAll(urlsToCache);
      })
  );
  self.skipWaiting();
});

// Fetch - Cache-First Strategie
self.addEventListener('fetch', event => {
  event.respondWith(
    caches.match(event.request)
      .then(response => {
        // Cache hit - gib gecachte Version zurück
        if (response) {
          return response;
        }
        // Ansonsten vom Netzwerk laden
        return fetch(event.request).then(response => {
          // Prüfe ob valide Response
          if (!response || response.status !== 200 || response.type !== 'basic') {
            return response;
          }
          // Clone der Response für Cache
          const responseToCache = response.clone();
          caches.open(CACHE_NAME)
            .then(cache => {
              cache.put(event.request, responseToCache);
            });
          return response;
        });
      })
  );
});

// Aktivierung - Alte Caches löschen
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(cacheNames => {
      return Promise.all(
        cacheNames.map(cacheName => {
          if (cacheName !== CACHE_NAME) {
            console.log('Lösche alten Cache:', cacheName);
            return caches.delete(cacheName);
          }
        })
      );
    })
  );
  self.clients.claim();
});