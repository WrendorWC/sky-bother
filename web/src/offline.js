// The last forecast and comet orbits, kept on this device so the week can
// still be planned with no signal — at a dark site, say. Kept in the Cache
// API rather than localStorage: a forecast is a few hundred kilobytes.
const STORE = 'skybother-data';
const FORECAST = '/offline/forecast';
const COMETS = '/offline/comets';

async function put(key, value) {
  try {
    const cache = await caches.open(STORE);
    await cache.put(key, new Response(JSON.stringify(value), { headers: { 'Content-Type': 'application/json' } }));
  } catch {}
}

async function get(key) {
  try {
    const hit = await (await caches.open(STORE)).match(key);
    return hit ? await hit.json() : null;
  } catch {
    return null;
  }
}

/** Keeps a forecast fetched for a site (`{ source, body }`). */
export const saveForecast = (latitude, longitude, forecast) =>
  put(FORECAST, { latitude, longitude, forecast, fetchedAt: Date.now() });

/** The kept forecast, if it's for this site (within about a kilometre). */
export async function savedForecast(latitude, longitude) {
  const saved = await get(FORECAST);
  if (!saved || Math.abs(saved.latitude - latitude) > 0.01 || Math.abs(saved.longitude - longitude) > 0.01) return null;
  return saved;
}

export const saveComets = text => put(COMETS, { text, fetchedAt: Date.now() });
export const savedComets = async () => (await get(COMETS))?.text;
