// Service worker Zombie 2.0 - pełny tryb offline (Three.js jest w vendor/, bez CDN)
// Podbij wersję przy każdej zmianie gry - inaczej gracze dostaną starą wersję z cache.
const CACHE = 'zombie2-v2';
const FILES = [
  './',
  'css/style.css',
  'icon-192.png',
  'icon-512.png',
  'index.html',
  'js/audio.js',
  'js/buildings.js',
  'js/config.js',
  'js/effects.js',
  'js/game.js',
  'js/input.js',
  'js/main.js',
  'js/render.js',
  'js/rig.js',
  'js/ui.js',
  'js/utils.js',
  'js/world.js',
  'manifest.json',
  'vendor/three/build/three.module.min.js',
  'vendor/three/examples/jsm/postprocessing/EffectComposer.js',
  'vendor/three/examples/jsm/postprocessing/MaskPass.js',
  'vendor/three/examples/jsm/postprocessing/OutputPass.js',
  'vendor/three/examples/jsm/postprocessing/Pass.js',
  'vendor/three/examples/jsm/postprocessing/RenderPass.js',
  'vendor/three/examples/jsm/postprocessing/ShaderPass.js',
  'vendor/three/examples/jsm/postprocessing/UnrealBloomPass.js',
  'vendor/three/examples/jsm/shaders/CopyShader.js',
  'vendor/three/examples/jsm/shaders/LuminosityHighPassShader.js',
  'vendor/three/examples/jsm/shaders/OutputShader.js',
  'vendor/three/examples/jsm/utils/BufferGeometryUtils.js',
];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(FILES)));
  self.skipWaiting();
});

self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys().then((keys) => Promise.all(
    keys.filter((k) => k.startsWith('zombie2-') && k !== CACHE).map((k) => caches.delete(k)))));
  self.clients.claim();
});

self.addEventListener('fetch', (e) => {
  if (e.request.method !== 'GET') return;
  e.respondWith(
    caches.match(e.request, { ignoreSearch: true }).then((hit) => hit || fetch(e.request).then((res) => {
      if (res && res.status === 200 && res.type === 'basic') {
        const copy = res.clone();
        caches.open(CACHE).then((c) => c.put(e.request, copy));
      }
      return res;
    })).catch(() => (e.request.mode === 'navigate' ? caches.match('./index.html') : undefined))
  );
});
