const CACHE_NAME = 'zombie-survival-v1.0';
const urlsToCache = [
  'index.html',
  'manifest.json',
  'icon-192.png',
  'icon-512.png'
];

// Instalacja - cachowanie plików
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => {
        console.log('📦 Cachowanie plików gry');
        return cache.addAll(urlsToCache);
      })
  );
  self.skipWaiting();
});

// Aktywacja - czyszczenie starych cache
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((cacheName) => {
          if (cacheName !== CACHE_NAME) {
            console.log('🗑️ Usuwanie starego cache:', cacheName);
            return caches.delete(cacheName);
          }
        })
      );
    })
  );
  self.clients.claim();
});

// Fetch - obsługa requestów (offline first)
self.addEventListener('fetch', (event) => {
  event.respondWith(
    caches.match(event.request)
      .then((response) => {
        // Zwróć z cache jeśli istnieje
        if (response) {
          return response;
        }

        // Jeśli nie ma w cache, pobierz z sieci
        return fetch(event.request).then((response) => {
          // Nie cachuj jeśli nieprawidłowa odpowiedź
          if (!response || response.status !== 200 || response.type !== 'basic') {
            return response;
          }

          // Sklonuj odpowiedź
          const responseToCache = response.clone();

          caches.open(CACHE_NAME)
            .then((cache) => {
              cache.put(event.request, responseToCache);
            });

          return response;
        });
      })
      .catch(() => {
        // Offline fallback
        return caches.match('index.html');
      })
  );
});