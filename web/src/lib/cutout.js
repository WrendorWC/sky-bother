// SkyCutoutClient: a DSS2 colour cutout from hips2fits, the mirror first and
// the primary as fallback. A server that fails to answer is skipped for three
// minutes, so that when the service is down every preview doesn't wait out
// its own timeout on each server in turn before saying there's no picture.
const endpoints = [
  'https://alaskybis.cds.unistra.fr/hips-image-services/hips2fits',
  'https://alasky.cds.unistra.fr/hips-image-services/hips2fits',
];
const cooldown = 180_000;
const downUntil = new Map();

// The picture as a blob, or null if neither server gave one.
export async function fetchCutout(query) {
  for (const endpoint of endpoints) {
    if ((downUntil.get(endpoint) ?? 0) > Date.now()) continue;
    try {
      const response = await fetch(`${endpoint}?${query}`, { signal: AbortSignal.timeout(30_000) });
      if (!response.ok) continue;
      return await response.blob();
    } catch {
      downUntil.set(endpoint, Date.now() + cooldown);
    }
  }
  return null;
}
