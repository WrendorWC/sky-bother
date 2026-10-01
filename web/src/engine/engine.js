// Promise wrapper around the engine worker.
const worker = new Worker(new URL('./worker.js', import.meta.url), { type: 'module' });
const pending = new Map();
let nextID = 0;

worker.onmessage = ({ data: { id, result, error } }) => {
  const { resolve, reject } = pending.get(id);
  pending.delete(id);
  error ? reject(new Error(error)) : resolve(result);
};

function send(kind, request) {
  const id = nextID++;
  return new Promise((resolve, reject) => {
    pending.set(id, { resolve, reject });
    worker.postMessage({ id, kind, request });
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
