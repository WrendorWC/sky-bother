// The site's Worker: static files (web/dist) for everything except /api/,
// and the sync store at /api/sync/<id>.
//
// Sync stores one encrypted blob per sync code, in a Durable Object of its
// own. The id is a hash of the code and the blob is AES-GCM encrypted on the
// device with a key derived from it, so this never sees a location, a rig or
// a plan — only scrambled bytes and a version number. Writes are
// compare-and-swap on that version: a device writing over a newer copy gets
// a 409 with the newer copy, merges, and tries again.
import { DurableObject } from 'cloudflare:workers';

const MAX_BYTES = 512 * 1024;
const ID = /^[0-9a-f]{64}$/;

export class SyncStore extends DurableObject {
  async fetch(request) {
    const stored = (await this.ctx.storage.get('doc')) ?? null;
    if (request.method === 'GET') {
      return stored ? Response.json(stored) : Response.json({ error: 'No sync data for this code yet.' }, { status: 404 });
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

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const match = /^\/api\/sync\/([^/]+)$/.exec(url.pathname);
    if (!url.pathname.startsWith('/api/')) return env.ASSETS.fetch(request);
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
    if (!match || !ID.test(match[1])) return Response.json({ error: 'Not found.' }, { status: 404, headers: cors });
    if (Number(request.headers.get('Content-Length') ?? 0) > MAX_BYTES) return Response.json({ error: 'Too large.' }, { status: 413, headers: cors });
    const store = env.SYNC.get(env.SYNC.idFromName(match[1]));
    const response = await store.fetch(request);
    const headers = new Headers(response.headers);
    for (const [k, v] of Object.entries(cors)) headers.set(k, v);
    return new Response(response.body, { status: response.status, headers });
  },
};
