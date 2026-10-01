// The site's Worker: static files (web/dist) for everything except /api/:
// the sync store at /api/sync/<id>, and MET Norway's forecast at /api/metno.
//
// Sync stores one encrypted blob per sync code, in a Durable Object of its
// own. The id is a hash of the code and the blob is AES-GCM encrypted on the
// device with a key derived from it, so this never sees a location, a rig or
// a plan — only scrambled bytes and a version number. Writes are
// compare-and-swap on that version: a device writing over a newer copy gets
// a 409 with the newer copy, merges, and tries again. A check-in that names
// the version it already has gets just { unchanged: true } back.
import { DurableObject } from 'cloudflare:workers';

const MAX_BYTES = 512 * 1024;
const ID = /^[0-9a-f]{64}$/;

export class SyncStore extends DurableObject {
  async fetch(request) {
    const stored = (await this.ctx.storage.get('doc')) ?? null;
    if (request.method === 'GET') {
      if (!stored) return Response.json({ error: 'No sync data for this code yet.' }, { status: 404 });
      // ?known=<version>: the device already has this version, so say so
      // without sending the blob again — most check-ins are this.
      const known = new URL(request.url).searchParams.get('known');
      if (known != null && Number(known) === stored.version) return Response.json({ version: stored.version, unchanged: true });
      return Response.json(stored);
    }
    if (request.method === 'PUT') {
      let body;
      try { body = await request.json(); } catch { return Response.json({ error: 'Bad request.' }, { status: 400 }); }
      if (typeof body.data !== 'string' || !Number.isInteger(body.baseVersion)) return Response.json({ error: 'Bad request.' }, { status: 400 });
      const current = stored?.version ?? 0;
      if (body.baseVersion !== current) return Response.json(stored, { status: 409 });
      const doc = { version: current + 1, data: body.data, updated: Date.now() };
      await this.ctx.storage.put('doc', doc);
      return Response.json({ version: doc.version });
    }
    if (request.method === 'DELETE') {
      await this.ctx.storage.deleteAll();
      return new Response(null, { status: 204 });
    }
    return new Response('Method not allowed', { status: 405 });
  }
}

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Cache-Control': 'no-store',
};

// MET Norway's forecast, the Mac app's backup when Open-Meteo fails
// (MetNorwayClient). Browsers can't call it themselves: MET Norway requires
// an identifying User-Agent, which a page can't set. Its terms also ask for
// coordinates to 4 decimals and for responses to be cached until they
// expire, which the Cache API does here for everyone at the same spot.
const MET_URL = 'https://api.met.no/weatherapi/locationforecast/2.0/complete';
const MET_AGENT = 'SkyBother/1.0 (https://skybother.com; weather fallback)';

async function metNorway(url, ctx) {
  const lat = Number(url.searchParams.get('lat')), lon = Number(url.searchParams.get('lon'));
  if (!Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) {
    return Response.json({ error: 'lat and lon, please.' }, { status: 400, headers: cors });
  }
  const upstream = `${MET_URL}?lat=${lat.toFixed(4)}&lon=${lon.toFixed(4)}`;
  const cache = caches.default;
  const key = new Request(upstream);
  let response = await cache.match(key);
  if (!response) {
    const fetched = await fetch(upstream, { headers: { 'User-Agent': MET_AGENT } });
    if (!fetched.ok) return Response.json({ error: `MET Norway returned HTTP ${fetched.status}.` }, { status: 502, headers: cors });
    const expires = Date.parse(fetched.headers.get('Expires') ?? '');
    const seconds = Number.isFinite(expires) ? Math.max(60, Math.round((expires - Date.now()) / 1000)) : 1800;
    response = new Response(fetched.body, {
      headers: { 'Content-Type': 'application/json', 'Cache-Control': `public, max-age=${seconds}` },
    });
    ctx.waitUntil(cache.put(key, response.clone()));
  }
  const headers = new Headers(response.headers);
  for (const [k, v] of Object.entries(cors)) if (k !== 'Cache-Control') headers.set(k, v);
  return new Response(response.body, { status: 200, headers });
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const match = /^\/api\/sync\/([^/]+)$/.exec(url.pathname);
    if (!url.pathname.startsWith('/api/')) return env.ASSETS.fetch(request);
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
    if (url.pathname === '/api/metno' && request.method === 'GET') return metNorway(url, ctx);
    if (!match || !ID.test(match[1])) return Response.json({ error: 'Not found.' }, { status: 404, headers: cors });
    if (Number(request.headers.get('Content-Length') ?? 0) > MAX_BYTES) return Response.json({ error: 'Too large.' }, { status: 413, headers: cors });
    const store = env.SYNC.get(env.SYNC.idFromName(match[1]));
    const response = await store.fetch(request);
    const headers = new Headers(response.headers);
    for (const [k, v] of Object.entries(cors)) headers.set(k, v);
    return new Response(response.body, { status: response.status, headers });
  },
};
