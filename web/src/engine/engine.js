// Promise wrapper around the engine worker.
const worker = new Worker(new URL('./worker.js', import.meta.url), { type: 'module' });
const pending = new Map();
let nextID = 0;

worker.onmessage = ({ data: { id, result, error } }) => {
  const entry = pending.get(id);
  if (!entry) return; // already timed out
  const { resolve, reject } = entry;
  pending.delete(id);
  error ? reject(new Error(error)) : resolve(result);
};

// A worker that fails to load or crashes never answers; fail what's waiting
// rather than leave the page hanging without a word.
function failAll(message) {
  for (const { reject } of pending.values()) reject(new Error(message));
  pending.clear();
}
worker.onerror = event => failAll(`The planning engine failed to load${event.message ? `: ${event.message}` : '.'}`);
worker.onmessageerror = () => failAll('The planning engine sent back something unreadable.');

function send(kind, request) {
  const id = nextID++;
  return new Promise((resolve, reject) => {
    pending.set(id, { resolve, reject });
    worker.postMessage({ id, kind, request });
    // The first call waits for the engine to download and start; give a slow
    // phone connection a minute, then say so.
    setTimeout(() => {
      if (!pending.has(id)) return;
      pending.delete(id);
      reject(new Error('The planning engine is taking too long to start. Check your connection and reload.'));
    }, 60_000);
  });
}

/** Starting rig, rig presets and preferences — the Mac app's own. */
export const defaults = () => send('defaults');

/**
 * A week of night plans. `request` is { site, rig, preferences, customTargets,
 * openMeteoResponse, cometElements, now } — see EngineAPI.PlanRequest.
 */
export const planNights = request => send('planNights', request);

/** One target on one night of the last week planned: { planKey, targetID }. */
export const targetDetail = request => send('targetDetail', request);

/** Every target the last week was planned from (catalogue, custom, comets). */
export const catalogEntries = () => send('catalog');

/** Sky View's Sun, Moon, wind, horizon and signpost stars for a night: { planKey }. */
export const skyTrack = request => send('skyTrack', request);
