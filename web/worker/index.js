// The site's Worker: static files (web/dist) for everything except /api/:
// the sync store at /api/sync/<id>, MET Norway's forecast at /api/metno, and
// byte ranges of ESA WorldCover's land-cover files at /api/worldcover/<file>,
// and OpenStreetMap parks and nature areas at /api/places.
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

// ESA WorldCover 2021, for Better Spot Nearby's open-horizon search
// (LandCoverClient on the Mac). Its public bucket on AWS answers range
// requests but sends no CORS headers, so a page can't read it directly. This
// passes one byte range of one WorldCover map file through — nothing else —
// and caches it, since tiles never change. A missing file (open ocean) is a 404.
const WORLDCOVER_URL = 'https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/';
const WORLDCOVER_FILE = /^ESA_WorldCover_10m_2021_v200_[NS]\d{2}[EW]\d{3}_Map\.tif$/;
const WORLDCOVER_MAX_BYTES = 4 * 1024 * 1024;

async function worldCover(name, url, ctx) {
  const offset = Number(url.searchParams.get('offset')), length = Number(url.searchParams.get('length'));
  if (!WORLDCOVER_FILE.test(name) || !Number.isInteger(offset) || !Number.isInteger(length)
      || offset < 0 || length <= 0 || length > WORLDCOVER_MAX_BYTES) {
    return Response.json({ error: 'Bad request.' }, { status: 400, headers: cors });
  }
  const cache = caches.default;
  const key = new Request(`https://skybother.com/worldcover-cache/${name}/${offset}/${length}`);
  let response = await cache.match(key);
  if (!response) {
    const fetched = await fetch(WORLDCOVER_URL + name, { headers: { Range: `bytes=${offset}-${offset + length - 1}` } });
    if (fetched.status === 404 || fetched.status === 403) return Response.json({ error: 'No such file.' }, { status: 404, headers: cors });
    // Insist on a partial answer: anything else would be the whole 60–100 MB file.
    if (fetched.status !== 206) return Response.json({ error: `WorldCover returned HTTP ${fetched.status}.` }, { status: 502, headers: cors });
    response = new Response(await fetched.arrayBuffer(), {
      headers: { 'Content-Type': 'application/octet-stream', 'Cache-Control': 'public, max-age=2592000' },
    });
    ctx.waitUntil(cache.put(key, response.clone()));
  }
  const headers = new Headers(response.headers);
  for (const [k, v] of Object.entries(cors)) if (k !== 'Cache-Control') headers.set(k, v);
  return new Response(response.body, { status: 200, headers });
}

// Parks and nature areas from OpenStreetMap, for Better Spot Nearby (where the
// Mac uses Apple Maps). The public Overpass servers are busy and often turn
// requests away, so this builds the query itself — only these kinds of place,
// only small boxes — tries a second server if the first is slow, and keeps
// each answer for a week (parks don't move).
const OVERPASS = ['https://maps.mail.ru/osm/tools/overpass/api/interpreter', 'https://overpass-api.de/api/interpreter'];
const PLACE_AGENT = 'SkyBother/1.0 (https://skybother.com; nearby spots)';
const NATURE = ['nwr["leisure"="nature_reserve"]["name"]', 'nwr["boundary"="protected_area"]["name"]', 'nwr["boundary"="national_park"]["name"]',
  'nwr["natural"="beach"]["name"]', 'nwr["tourism"~"^(camp_site|viewpoint)$"]["name"]'];
const PLACE_KINDS = {
  nature: NATURE,
  parks: [...NATURE, 'nwr["leisure"="park"]["name"]'],
  horizon: [...NATURE, 'nwr["leisure"="park"]["name"]', 'nwr["leisure"="slipway"]', 'nwr["leisure"="marina"]["name"]'],
};

async function places(url, ctx) {
  const kind = url.searchParams.get('kind');
  const boxes = (url.searchParams.get('bbox') ?? '').split(';').filter(Boolean).map(b => b.split(',').map(Number));
  const valid = PLACE_KINDS[kind] && boxes.length >= 1 && boxes.length <= 6 && boxes.every(b =>
    b.length === 4 && b.every(Number.isFinite) && b[0] < b[2] && b[1] < b[3] && b[2] - b[0] <= 1.2 && b[3] - b[1] <= 1.6
    && Math.abs(b[0]) <= 90 && Math.abs(b[2]) <= 90 && Math.abs(b[1]) <= 180 && Math.abs(b[3]) <= 180);
  if (!valid) return Response.json({ error: 'Bad request.' }, { status: 400, headers: cors });
  const rounded = boxes.map(b => [Math.floor(b[0] * 100) / 100, Math.floor(b[1] * 100) / 100, Math.ceil(b[2] * 100) / 100, Math.ceil(b[3] * 100) / 100]);
  const statements = rounded.flatMap(b => PLACE_KINDS[kind].map(q => `${q}(${b.join(',')});`)).join('');
  const query = `[out:json][timeout:50];(${statements});out tags center;`;
  const cache = caches.default;
  const key = new Request(`https://skybother.com/places-cache/${kind}/${rounded.map(b => b.join(',')).join(';')}`);
  let response = await cache.match(key);
  if (!response) {
    const ask = server => fetch(server, {
      method: 'POST', headers: { 'User-Agent': PLACE_AGENT, 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ data: query }),
    }).then(async r => {
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      const text = await r.text();
      if (!text.trimStart().startsWith('{')) throw new Error('not JSON');
      return text;
    });
    // The first server, with the second joining in if it hasn't answered in 8 s.
    const first = ask(OVERPASS[0]);
    const second = new Promise(resolve => setTimeout(resolve, 8000)).then(() => ask(OVERPASS[1]));
    // Whichever loses may fail later; that's expected, not an error.
    first.catch(() => {});
    second.catch(() => {});
    let text;
    try {
      text = await Promise.any([first, second]);
    } catch (e) {
      console.log('places failed:', e.errors?.map(x => x.message).join(' / '));
      return Response.json({ error: 'OpenStreetMap’s place search isn’t answering right now. Try again in a minute.' }, { status: 502, headers: cors });
    }
    response = new Response(text, { headers: { 'Content-Type': 'application/json', 'Cache-Control': 'public, max-age=604800' } });
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
    if (url.pathname === '/api/places' && request.method === 'GET') return places(url, ctx);
    const cover = /^\/api\/worldcover\/([^/]+)$/.exec(url.pathname);
    if (cover && request.method === 'GET') return worldCover(cover[1], url, ctx);
    if (!match || !ID.test(match[1])) return Response.json({ error: 'Not found.' }, { status: 404, headers: cors });
    if (Number(request.headers.get('Content-Length') ?? 0) > MAX_BYTES) return Response.json({ error: 'Too large.' }, { status: 413, headers: cors });
    const store = env.SYNC.get(env.SYNC.idFromName(match[1]));
    const response = await store.fetch(request);
    const headers = new Headers(response.headers);
    for (const [k, v] of Object.entries(cors)) headers.set(k, v);
    return new Response(response.body, { status: response.status, headers });
  },
};
