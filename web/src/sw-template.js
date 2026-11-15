// Sky Bother's service worker: the app keeps working with no signal — at a
// dark site, say. Written into the build by vite.config.js, which fills in
// VERSION and PRECACHE (every file the app needs to start).
//
// - Files named by their contents (/assets/…) never change: from storage.
// - Everything else of the app's own (the page, the engine, the catalogue,
//   the star and Moon maps): from the network when there is one, so an
//   update is never mixed with an older engine, else from storage.
// - Target photos, sky thumbnails and sky-survey tiles: from storage
//   once seen, so the ones you've looked at work offline.
// - The API and weather: always the network; the page keeps its own copy of
//   the last forecast (src/offline.js).
const VERSION = '__VERSION__';
const PRECACHE = __PRECACHE__;
const APP = `skybother-app-${VERSION}`;
const IMAGES = 'skybother-images';
const MAX_IMAGES = 400;

self.addEventListener('install', event => {
  event.waitUntil(caches.open(APP).then(cache => cache.addAll(PRECACHE)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    for (const name of await caches.keys()) {
      if (name.startsWith('skybother-app-') && name !== APP) await caches.delete(name);
    }
    await self.clients.claim();
  })());
});

// The colour sky survey's tiles, from either mirror (src/lib/hips.js) — for
// Sky Browser and for the framing pictures drawn from them — kept once seen
// (as the Mac keeps its sky pictures), so going back to somewhere is instant
// and works offline. They never change. The framing pictures themselves are
// kept by src/lib/cutout.js.
const SKY = 'skybother-sky';
const MAX_SKY = 3000;
const isSurveyTile = url =>
  (url.hostname === 'irsa.ipac.caltech.edu' && /^\/data\/hips\/CDS\/DSS2\/color\/+Norder\d+\//.test(url.pathname)) ||
  (['alasky.cds.unistra.fr', 'alaskybis.cds.unistra.fr'].includes(url.hostname) && /^\/DSS\/DSSColor\/+Norder\d+\//.test(url.pathname));

self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  const own = url.origin === self.location.origin;

  if (own && url.pathname.startsWith('/api/')) return;

  // Pictures: from storage once seen.
  if (own && /^\/catalog\/(photos|sky)\//.test(url.pathname)) {
    event.respondWith(fromStorageFirst(request, IMAGES, true));
    return;
  }
  if (isSurveyTile(url)) {
    event.respondWith(fromStorageFirst(request, SKY, false).then(response => { trimLater(SKY, MAX_SKY); return response; }));
    return;
  }
  if (!own) return;

  if (request.mode === 'navigate') {
    event.respondWith(networkFirst(request, '/'));
    return;
  }
  if (url.pathname.startsWith('/assets/')) {
    event.respondWith(fromStorageFirst(request, APP, false));
    return;
  }
  event.respondWith(networkFirst(request));
});

async function fromStorageFirst(request, name, trim) {
  const cache = await caches.open(name);
  const hit = await cache.match(request);
  if (hit) return hit;
  const response = await fetch(request);
  if (response.ok || response.type === 'opaque') {
    // Stored alongside, not before, handing it over.
    const stored = cache.put(request, response.clone()).catch(() => {});
    if (!trim) return response;
    await stored;
    if (trim) {
      const keys = await cache.keys();
      for (const key of keys.slice(0, Math.max(0, keys.length - MAX_IMAGES))) await cache.delete(key);
    }
  }
  return response;
}

// Trimmed in the background, now and then, so a tile isn't kept waiting.
let trimming = false;
function trimLater(name, max) {
  if (trimming || Math.random() > 0.05) return;
  trimming = true;
  caches.open(name).then(async cache => {
    const keys = await cache.keys();
    for (const key of keys.slice(0, Math.max(0, keys.length - max))) await cache.delete(key);
  }).finally(() => (trimming = false));
}

async function networkFirst(request, fallbackPath = null) {
  const cache = await caches.open(APP);
  try {
    const response = await fetch(request);
    if (response.ok) cache.put(fallbackPath ?? request, response.clone());
    return response;
  } catch (error) {
    const hit = await cache.match(fallbackPath ?? request, { ignoreSearch: true });
    if (hit) return hit;
    throw error;
  }
}
