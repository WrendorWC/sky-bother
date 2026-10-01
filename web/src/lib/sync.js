// Sync between the Mac app and the web app, with no accounts: a sync code.
// The Mac app does the same in Support/SyncClient.swift — keep them in step.
//
// The code is 128 random bits, shown as 26 letters and digits in groups.
// From it come two things that can't be worked back to the code:
//   id  = hex(SHA-256("skybother-sync-id:" + code bytes))   — where it's stored
//   key = SHA-256("skybother-sync-key:" + code bytes)        — AES-256-GCM key
// The server (web/worker) keeps one encrypted blob per id, so it never sees
// what's in it. The blob is base64(12-byte IV + ciphertext) of JSON:
//   { v: 1, sections: { <name>: { modifiedAt: ms, value } } }
// Each section is merged on its own, newest change wins, so a plan edited on
// the phone and a rig changed on the Mac don't overwrite each other.

export const SECTIONS = ['site', 'rig', 'preferences', 'customTargets', 'savedSites', 'savedRigs', 'sessionPlans'];

// Crockford base32: no I, L, O or U to misread.
const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

export function newCode() {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  return format(encode(bytes));
}

function encode(bytes) {
  let bits = 0, value = 0, out = '';
  for (const b of bytes) {
    value = (value << 8) | b;
    bits += 8;
    while (bits >= 5) {
      out += ALPHABET[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) out += ALPHABET[(value << (5 - bits)) & 31];
  return out;
}

function decode(text) {
  const clean = normalize(text);
  if (clean.length !== 26) throw new Error('A sync code is 26 letters and digits.');
  let bits = 0, value = 0;
  const out = [];
  for (const ch of clean) {
    const v = ALPHABET.indexOf(ch);
    if (v < 0) throw new Error(`“${ch}” isn't in a sync code.`);
    value = (value << 5) | v;
    bits += 5;
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 255);
      bits -= 8;
    }
  }
  return new Uint8Array(out.slice(0, 16));
}

/** Upper case, no spaces or dashes, and the letters people mistake for digits. */
export function normalize(text) {
  return text.toUpperCase().replace(/[\s-]/g, '').replace(/[IL]/g, '1').replace(/O/g, '0');
}

export const format = code => normalize(code).match(/.{1,4}/g).join('-');

const utf8 = text => new TextEncoder().encode(text);
const concat = (a, b) => { const out = new Uint8Array(a.length + b.length); out.set(a); out.set(b, a.length); return out; };
const hex = buffer => [...new Uint8Array(buffer)].map(b => b.toString(16).padStart(2, '0')).join('');
const base64 = bytes => { let s = ''; bytes.forEach(b => (s += String.fromCharCode(b))); return btoa(s); };
const unbase64 = text => Uint8Array.from(atob(text), c => c.charCodeAt(0));

async function derive(code) {
  const secret = decode(code);
  const id = hex(await crypto.subtle.digest('SHA-256', concat(utf8('skybother-sync-id:'), secret)));
  const raw = await crypto.subtle.digest('SHA-256', concat(utf8('skybother-sync-key:'), secret));
  const key = await crypto.subtle.importKey('raw', raw, 'AES-GCM', false, ['encrypt', 'decrypt']);
  return { id, key };
}

async function seal(key, doc) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const sealed = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, utf8(JSON.stringify(doc)));
  return base64(concat(iv, new Uint8Array(sealed)));
}

async function open(key, data) {
  const bytes = unbase64(data);
  const plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: bytes.slice(0, 12) }, key, bytes.slice(12));
  return JSON.parse(new TextDecoder().decode(plain));
}

/** The newest of each section from two documents. */
export function merge(a, b) {
  const sections = {};
  for (const name of SECTIONS) {
    const x = a?.sections?.[name], y = b?.sections?.[name];
    sections[name] = !x ? y : !y ? x : (y.modifiedAt > x.modifiedAt ? y : x);
    if (!sections[name]) delete sections[name];
  }
  return { v: 1, sections };
}

const endpoint = id => `/api/sync/${id}`;

/**
 * One round: fetch what's stored, merge in `local`, write back if that
 * changed anything (retrying on a race). Returns { doc, version }.
 * `known` is the last version and document this device synced: when the
 * store still has that version, only "unchanged" comes back (no blob), and
 * if nothing changed here either, that's the whole round.
 */
export async function syncOnce(code, local, known = null) {
  const { id, key } = await derive(code);
  for (let attempt = 0; attempt < 4; attempt++) {
    const url = known && attempt === 0 ? `${endpoint(id)}?known=${known.version}` : endpoint(id);
    const response = await fetch(url, { cache: 'no-store' });
    let remote = null, version = 0;
    if (response.ok) {
      const stored = await response.json();
      version = stored.version;
      if (stored.unchanged) {
        remote = known.doc;
      } else {
        try {
          remote = await open(key, stored.data);
        } catch {
          throw new Error('This sync code doesn’t match what’s stored. Check the code.');
        }
      }
    } else if (response.status !== 404) {
      throw new Error(`Sync failed (HTTP ${response.status}).`);
    }
    if (!remote && !local) throw new Error('Nothing is synced with this code yet. Turn sync on from the device that has your settings.');
    const merged = merge(remote, local);
    if (remote && JSON.stringify(merged) === JSON.stringify(remote)) return { doc: merged, version };
    const put = await fetch(endpoint(id), {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ baseVersion: version, data: await seal(key, merged) }),
    });
    if (put.ok) return { doc: merged, version: (await put.json()).version };
    if (put.status !== 409) throw new Error(`Sync failed (HTTP ${put.status}).`);
  }
  throw new Error('Sync kept colliding with another device. It will try again.');
}

/** Stops syncing this code everywhere: the stored copy is deleted. */
export async function forget(code) {
  const { id } = await derive(code);
  await fetch(endpoint(id), { method: 'DELETE' });
}

/**
 * This device's document from its settings, stamping any section that changed
 * since `previous` (the last synced document) with now.
 */
export function documentFrom(settings, previous) {
  const now = Date.now();
  const sections = {};
  for (const name of SECTIONS) {
    const value = settings[name] ?? (name === 'sessionPlans' ? {} : name === 'customTargets' || name.startsWith('saved') ? [] : null);
    if (value == null) continue;
    const before = previous?.sections?.[name];
    const same = before && JSON.stringify(before.value) === JSON.stringify(value);
    sections[name] = same ? before : { modifiedAt: now, value };
  }
  return { v: 1, sections };
}

/** Settings with every section from the document. */
export function applyDocument(settings, doc) {
  const next = { ...settings };
  for (const [name, section] of Object.entries(doc.sections ?? {})) next[name] = section.value;
  return next;
}
