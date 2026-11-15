// SkyCutoutClient: a colour Digitized Sky Survey picture of a patch of sky,
// drawn here from the survey's tiles (hips.js) rather than asked of CDS's
// hips2fits, which went down with the rest of CDS in November 2026.
//
// Tiles come from the first mirror that answers. One that fails to is
// skipped for three minutes, so that when a mirror is down every tile
// doesn't wait out its own timeout before the next one is tried. Finished
// pictures are kept, like the photos, so the ones you've looked at come back
// at once and work offline.
import { SURVEYS, renderCutout } from './hips.js';

const cooldown = 180_000;
const downUntil = new Map();
const isUp = base => (downUntil.get(base) ?? 0) <= Date.now();

// The survey address for Aladin: the first mirror whose description
// answers, else the first.
export async function pickSurvey() {
  for (const base of SURVEYS) {
    if (!isUp(base)) continue;
    try {
      const response = await fetch(`${base}/properties`, { signal: AbortSignal.timeout(8_000) });
      if (response.ok) return `${base}/`;
    } catch {}
    downUntil.set(base, Date.now() + cooldown);
  }
  return `${SURVEYS[0]}/`;
}

// Decoded tiles, the most recently used last. A tile is a megabyte decoded;
// forty is a few views' worth.
const tiles = new Map();
const MAX_TILES = 40;

async function getTile(order, npix) {
  const key = `${order}/${npix}`;
  if (tiles.has(key)) {
    const hit = tiles.get(key);
    tiles.delete(key);
    tiles.set(key, hit);
    return hit;
  }
  const pending = loadTile(order, npix);
  tiles.set(key, pending);
  const pixels = await pending;
  if (!pixels) tiles.delete(key);
  while (tiles.size > MAX_TILES) tiles.delete(tiles.keys().next().value);
  return pixels;
}

async function loadTile(order, npix) {
  const path = `Norder${order}/Dir${Math.floor(npix / 10000) * 10000}/Npix${npix}.jpg`;
  for (const base of SURVEYS) {
    if (!isUp(base)) continue;
    let response;
    try {
      response = await fetch(`${base}/${path}`, { signal: AbortSignal.timeout(20_000) });
    } catch {
      downUntil.set(base, Date.now() + cooldown);
      continue;
    }
    // A tile the survey doesn't have (off its edge) is a 404 from every
    // mirror; there's nothing to draw there.
    if (response.status === 404) return null;
    if (!response.ok) continue;
    try {
      const bitmap = await createImageBitmap(await response.blob());
      const canvas = new OffscreenCanvas(bitmap.width, bitmap.height);
      const context = canvas.getContext('2d', { willReadFrequently: true });
      context.drawImage(bitmap, 0, 0);
      bitmap.close();
      return context.getImageData(0, 0, canvas.width, canvas.height).data;
    } catch {
      return null;
    }
  }
  return null;
}

// Rounded so a view a pixel different, or a coordinate a hair off, is the
// same picture.
const round = (value, places) => Number(value.toFixed(places));

// The picture as a JPEG blob, or null if none could be had. `fov` is in
// degrees along the longer side; north is up and east left.
export async function fetchCutout({ ra, dec, fov, width, height }) {
  width = Math.max(16, Math.min(1600, Math.round(width)));
  height = Math.max(16, Math.min(1600, Math.round(height)));
  ra = round(ra, 3); dec = round(dec, 3); fov = round(fov, 4);
  const key = `${location.origin}/sky-cutout/dss2?ra=${ra}&dec=${dec}&fov=${fov}&w=${width}&h=${height}`;
  const store = await caches.open('skybother-images').catch(() => null);
  const kept = await store?.match(key).catch(() => null);
  if (kept) return kept.blob();

  try {
    let drawn = false, missing = false;
    const pixels = await renderCutout({
      ra, dec, fov, width, height,
      getTile: async (order, npix) => {
        const tile = await getTile(order, npix);
        if (tile) drawn = true; else missing = true;
        return tile;
      },
    });
    // Not one tile arrived: no mirror is answering. Say so rather than show
    // a black square.
    if (!drawn) return null;
    const canvas = new OffscreenCanvas(width, height);
    canvas.getContext('2d').putImageData(new ImageData(pixels, width, height), 0, 0);
    const blob = await canvas.convertToBlob({ type: 'image/jpeg', quality: 0.88 });
    // Kept only if whole: a gap left by a mirror that didn't answer would
    // otherwise stay there for good.
    if (!missing) store?.put(key, new Response(blob, { headers: { 'Content-Type': 'image/jpeg' } })).catch(() => {});
    return blob;
  } catch {
    return null;
  }
}
