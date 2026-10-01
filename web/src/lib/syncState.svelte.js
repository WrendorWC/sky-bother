// This browser's side of sync: its code, the last document it synced, and
// what's going on, kept apart from the settings themselves.
import { syncOnce, documentFrom, applyDocument, forget } from './sync.js';

const storageKey = 'skybother.sync.v1';

function load() {
  try { return JSON.parse(localStorage.getItem(storageKey)) ?? {}; } catch { return {}; }
}

const saved = load();
export const sync = $state({ code: saved.code ?? null, doc: saved.doc ?? null, at: saved.at ?? null, busy: false, error: '' });

function persist() {
  try { localStorage.setItem(storageKey, JSON.stringify({ code: sync.code, doc: $state.snapshot(sync.doc), at: sync.at })); } catch {}
}

/**
 * One round for these settings. Returns the settings to use afterwards (with
 * anything newer from other devices), or null when nothing changed here.
 * `joining`: take what's stored as it is — nothing local counts as newer.
 */
export async function runSync(settings, { joining = false } = {}) {
  if (!sync.code || sync.busy) return null;
  sync.busy = true;
  sync.error = '';
  try {
    const local = joining || !settings ? null : documentFrom(settings, sync.doc);
    const merged = await syncOnce(sync.code, local);
    if (!merged) return null;
    sync.doc = merged;
    sync.at = Date.now();
    persist();
    const next = applyDocument(settings ?? {}, merged);
    return JSON.stringify(next) === JSON.stringify(settings) ? null : next;
  } catch (e) {
    sync.error = e.message;
    return null;
  } finally {
    sync.busy = false;
  }
}

export function startSync(code) {
  sync.code = code;
  sync.doc = null;
  sync.at = null;
  persist();
}

export function stopSync() {
  sync.code = null;
  sync.doc = null;
  sync.at = null;
  sync.error = '';
  persist();
}

export async function stopSyncEverywhere() {
  if (sync.code) await forget(sync.code);
  stopSync();
}
