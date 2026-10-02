// Better Spot Nearby for the web — the Mac's SkyBother/DarkSky folder in one
// place. The model and every threshold are the Mac's (keep them in step):
//   SkyGlow.swift            sky glow from night lights, and the Bortle estimate
//   NightLightsClient.swift  NASA Black Marble radiance, median of six dates
//   DarkSkyFinder.swift      darker sky: dark patches, then real places in them
//   LandCoverClient.swift    ESA WorldCover land cover, read from the GeoTIFFs
//   OpenHorizonFinder.swift  open horizon: sight lines over land cover
//   NearbySpotSelection.swift which spots to suggest
//   ParkHours.swift          posted hours
// What differs: Apple Maps found the places on the Mac; here it's
// OpenStreetMap (through Nominatim), which also carries posted hours and
// websites, so there's no separate hours lookup. WorldCover is read through skybother.com
// (/api/worldcover), since its bucket sends no CORS headers.

const rad = Math.PI / 180;
const clamp = (x, lo, hi) => Math.min(hi, Math.max(lo, x));
const COMPASS8 = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];

// --- DarkSkyGeometry -------------------------------------------------------
export const KM_PER_DEGREE = 111.2;
export function distanceKm(lat1, lon1, lat2, lon2) {
  const dLat = (lat2 - lat1) * rad, dLon = (lon2 - lon1) * rad;
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(dLon / 2) ** 2;
  return 2 * 6371 * Math.asin(Math.min(1, Math.sqrt(a)));
}
export function compassDirection(lat1, lon1, lat2, lon2) {
  const d = (lon2 - lon1) * rad;
  const y = Math.sin(d) * Math.cos(lat2 * rad);
  const x = Math.cos(lat1 * rad) * Math.sin(lat2 * rad) - Math.sin(lat1 * rad) * Math.cos(lat2 * rad) * Math.cos(d);
  const bearing = ((Math.atan2(y, x) / rad) % 360 + 360) % 360;
  return COMPASS8[Math.floor((bearing + 22.5) / 45) % 8];
}

// --- DarkSkyEstimate ---------------------------------------------------------
const NATURAL_SKY = 22.0;
const GLOW_TO_ARTIFICIAL = 0.0366;
const BORTLE_BOUNDARIES = [21.8, 21.55, 21.15, 20.6, 19.8, 18.95, 18.3, 17.75];
export const zenithBrightness = glow => NATURAL_SKY - 2.5 * Math.log10(1 + Math.max(glow, 0) * GLOW_TO_ARTIFICIAL);
export const bortleForBrightness = b => 1 + BORTLE_BOUNDARIES.filter(x => b < x).length;

// --- SkyGlowField ------------------------------------------------------------
// Walker's law (d^-2.5), softened at 2 km, summed by 4×4 block beyond 5 km
// and pixel by pixel within it.
export class SkyGlowField {
  constructor(grid) {
    this.grid = grid;
    this.block = 4;
    this.blocksWide = Math.floor(grid.width / 4);
    this.blocksHigh = Math.floor(grid.height / 4);
    const sums = new Float64Array(this.blocksWide * this.blocksHigh);
    for (let br = 0; br < this.blocksHigh; br++) {
      for (let bc = 0; bc < this.blocksWide; bc++) {
        let sum = 0;
        for (let r = br * 4; r < br * 4 + 4; r++) {
          const start = r * grid.width;
          for (let c = bc * 4; c < bc * 4 + 4; c++) sum += grid.values[start + c];
        }
        sums[br * this.blocksWide + bc] = sum;
      }
    }
    this.blockSums = sums;
    const centre = (grid.south + grid.north) / 2;
    this.pixelHeight = (grid.north - grid.south) / grid.height * KM_PER_DEGREE;
    this.pixelWidth = (grid.east - grid.west) / grid.width * KM_PER_DEGREE * Math.max(Math.cos(centre * rad), 0.2);
  }
  contains(lat, lon) {
    const g = this.grid;
    return lat >= g.south && lat <= g.north && lon >= g.west && lon <= g.east;
  }
  glow(lat, lon) {
    const g = this.grid, ph = this.pixelHeight, pw = this.pixelWidth;
    const pointY = (g.north - lat) / (g.north - g.south) * g.height * ph;
    const pointX = (lon - g.west) / (g.east - g.west) * g.width * pw;
    const soft2 = 4, near2 = 25;
    const falloff = d2 => d2 * Math.sqrt(Math.sqrt(d2));
    let total = 0;
    for (let br = 0; br < this.blocksHigh; br++) {
      const blockY = (br + 0.5) * 4 * ph - pointY;
      for (let bc = 0; bc < this.blocksWide; bc++) {
        const blockSum = this.blockSums[br * this.blocksWide + bc];
        if (!(blockSum > 0)) continue;
        const blockX = (bc + 0.5) * 4 * pw - pointX;
        const d2 = blockX * blockX + blockY * blockY;
        if (d2 > near2) { total += blockSum / falloff(d2 + soft2); continue; }
        for (let r = br * 4; r < br * 4 + 4; r++) {
          const dy = (r + 0.5) * ph - pointY;
          const start = r * g.width;
          for (let c = bc * 4; c < bc * 4 + 4; c++) {
            const v = g.values[start + c];
            if (!(v > 0)) continue;
            const dx = (c + 0.5) * pw - pointX;
            total += v / falloff(dx * dx + dy * dy + soft2);
          }
        }
      }
    }
    return total;
  }
  brightness(lat, lon) {
    return zenithBrightness(this.glow(lat, lon));
  }
}

// --- NightLightsClient -------------------------------------------------------
const LAYER = 'VIIRS_SNPP_GapFilled_BRDF_Corrected_DayNightBand_Radiance';
const HALF_SPAN = 1.25;
const PIXELS = 640;
const DATES = 6, DAYS_BETWEEN = 61, NEWEST_AGE = 10, MIN_DATES = 2;
const NIGHT_CACHE_DAYS = 60;

// The colour map's grey levels and their radiance band midpoints, exactly as
// NightLightsClient has them. Grey 166 is 9.8–10: NASA's colour map gives its
// source range as "[9.8,100)", a typo, and both apps' tables once carried the
// resulting 54.9. Caches made with it are named differently (v2).
const GRAY = [7, 13, 19, 24, 29, 33, 37, 41, 45, 48, 52, 55, 58, 61, 64, 67, 69, 72, 74, 77, 79, 81, 83, 85, 87, 89, 91, 93, 95, 96, 98, 100,
  101, 103, 105, 106, 108, 109, 111, 112, 113, 115, 116, 117, 118, 120, 121, 122, 123, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139,
  140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171,
  172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203,
  204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235,
  236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255];
const MIDPOINTS = [0.05, 0.15, 0.25, 0.35, 0.45, 0.55, 0.65, 0.75, 0.85, 0.95, 1.05, 1.15, 1.25, 1.35, 1.45, 1.55, 1.65, 1.75, 1.85, 1.95,
  2.05, 2.15, 2.25, 2.35, 2.45, 2.55, 2.65, 2.75, 2.85, 2.95, 3.05, 3.15, 3.25, 3.35, 3.45, 3.55, 3.65, 3.75, 3.85, 3.95,
  4.05, 4.15, 4.25, 4.35, 4.45, 4.55, 4.65, 4.75, 4.85, 4.95, 5.05, 5.15, 5.25, 5.35, 5.45, 5.55, 5.65, 5.75, 5.85, 5.95,
  6.05, 6.15, 6.25, 6.35, 6.45, 6.55, 6.65, 6.75, 6.9, 7.05, 7.15, 7.25, 7.35, 7.5, 7.65, 7.75, 7.85, 8.0, 8.15, 8.25,
  8.4, 8.55, 8.7, 8.85, 8.95, 9.1, 9.25, 9.4, 9.55, 9.7, 9.9, 10.05, 10.2, 10.35, 10.5, 10.7, 10.9, 11.05, 11.2, 11.4,
  11.6, 11.75, 11.9, 12.1, 12.3, 12.5, 12.7, 12.9, 13.1, 13.3, 13.5, 13.75, 14.0, 14.2, 14.4, 14.6, 14.85, 15.1, 15.3, 15.55,
  15.8, 16.05, 16.3, 16.55, 16.8, 17.05, 17.35, 17.6, 17.85, 18.15, 18.45, 18.7, 18.95, 19.25, 19.55, 19.85, 20.15, 20.5, 20.85, 21.15,
  21.45, 21.75, 22.1, 22.45, 22.8, 23.15, 23.5, 23.85, 24.2, 24.6, 24.95, 25.3, 25.7, 26.1, 26.5, 26.9, 27.3, 27.7, 28.1, 28.55,
  29.0, 29.4, 29.85, 30.3, 30.75, 31.25, 31.7, 32.15, 32.65, 33.15, 33.65, 34.15, 34.65, 35.2, 35.75, 36.25, 36.8, 37.35, 37.9, 60.0];

const radianceTable = (() => {
  const table = new Float32Array(256);
  for (let gray = 0; gray < 256; gray++) {
    if (gray <= GRAY[0]) { table[gray] = MIDPOINTS[0] * gray / GRAY[0]; continue; }
    let low = 0, high = GRAY.length - 1;
    while (high - low > 1) { const m = (low + high) >> 1; if (GRAY[m] <= gray) low = m; else high = m; }
    if (GRAY[high] <= gray) { table[gray] = MIDPOINTS[high]; continue; }
    const t = (gray - GRAY[low]) / (GRAY[high] - GRAY[low]);
    table[gray] = MIDPOINTS[low] + t * (MIDPOINTS[high] - MIDPOINTS[low]);
  }
  return table;
})();

const isoDay = ms => new Date(ms).toISOString().slice(0, 10);

async function fetchFrame(date, south, west, north, east) {
  const params = new URLSearchParams({
    REQUEST: 'GetSnapshot', LAYERS: LAYER, CRS: 'EPSG:4326', TIME: date,
    BBOX: `${south},${west},${north},${east}`, FORMAT: 'image/png', WIDTH: PIXELS, HEIGHT: PIXELS,
  });
  try {
    const response = await fetch(`https://wvs.earthdata.nasa.gov/api/v1/snapshot?${params}`, { signal: timeout(30_000) });
    if (!response.ok) return null;
    const bitmap = await createImageBitmap(await response.blob(), { colorSpaceConversion: 'none', premultiplyAlpha: 'none' });
    if (bitmap.width < 2) return null;
    const canvas = document.createElement('canvas');
    canvas.width = PIXELS; canvas.height = PIXELS;
    const context = canvas.getContext('2d', { willReadFrequently: true });
    context.imageSmoothingEnabled = false;
    context.drawImage(bitmap, 0, 0, PIXELS, PIXELS);
    const rgba = context.getImageData(0, 0, PIXELS, PIXELS).data;
    const values = new Float32Array(PIXELS * PIXELS).fill(NaN);
    let opaque = 0;
    for (let i = 0; i < values.length; i++) {
      if (rgba[i * 4 + 3] <= 127) continue;
      opaque++;
      values[i] = radianceTable[rgba[i * 4]];
    }
    // Mostly no-data is a gap day, not an observation.
    return opaque > values.length / 4 ? values : null;
  } catch {
    return null;
  }
}

function timeout(ms) {
  const controller = new AbortController();
  setTimeout(() => controller.abort(), ms);
  return controller.signal;
}

/** The radiance grid around a site — the median of six dates over the past year — cached for 60 days. */
export async function nightLightsGrid(latitude, longitude) {
  const lat = Math.round(latitude * 10) / 10, lon = Math.round(longitude * 10) / 10;
  const cacheKey = `/nearby-cache/nightlights_v2_${lat.toFixed(1)}_${lon.toFixed(1)}`;
  const cache = await caches.open('skybother-nearby').catch(() => null);
  const hit = await cache?.match(cacheKey);
  if (hit && Date.now() - Number(hit.headers.get('X-Retrieved')) < NIGHT_CACHE_DAYS * 86_400_000) {
    const meta = JSON.parse(hit.headers.get('X-Grid'));
    return { ...meta, values: new Float32Array(await hit.arrayBuffer()) };
  }
  const lonSpan = HALF_SPAN / Math.max(Math.cos(lat * rad), 0.3);
  const south = Math.max(lat - HALF_SPAN, -90), north = Math.min(lat + HALF_SPAN, 90);
  const west = lon - lonSpan, east = lon + lonSpan;
  const now = Date.now();
  const dates = Array.from({ length: DATES }, (_, i) => isoDay(now - (NEWEST_AGE + i * DAYS_BETWEEN) * 86_400_000));
  const frames = (await Promise.all(dates.map(d => fetchFrame(d, south, west, north, east)))).filter(Boolean);
  if (frames.length < MIN_DATES) throw new Error('NASA’s night-lights imagery couldn’t be loaded for this area.');
  const values = new Float32Array(PIXELS * PIXELS);
  const samples = [];
  for (let i = 0; i < values.length; i++) {
    samples.length = 0;
    for (const frame of frames) if (!Number.isNaN(frame[i])) samples.push(frame[i]);
    if (!samples.length) { values[i] = 0; continue; }
    samples.sort((a, b) => a - b);
    const m = samples.length >> 1;
    values[i] = samples.length % 2 ? samples[m] : (samples[m - 1] + samples[m]) / 2;
  }
  const grid = { south, west, north, east, width: PIXELS, height: PIXELS, values };
  try {
    await cache?.put(cacheKey, new Response(values.buffer.slice(0), {
      headers: { 'X-Retrieved': String(now), 'X-Grid': JSON.stringify({ south, west, north, east, width: PIXELS, height: PIXELS }) },
    }));
  } catch {}
  return grid;
}

// --- Places (OpenStreetMap, in place of NearbyPlaceSearch) -------------------
// Small, usually lit, or nowhere to set up a tripod after dark.
const UNSUITABLE = ['dog park', 'playground', 'skate', 'splash', 'water park', 'rv park', 'ballpark', 'sports complex', 'athletic',
  'golf', 'cemetery', 'tennis', 'soccer', 'baseball', 'softball', 'pool'];
const GENERIC = new Set(['park', 'beach', 'marina', 'campground', 'boat ramp', 'boat launch', 'nature reserve', 'playground']);

// OpenStreetMap places through Nominatim, its own search, asked from this
// device. Like Apple Maps on the Mac it returns a limited number (40) per
// search, so — as on the Mac — several small searches are aimed where they
// matter: one per kind of place per area. Nominatim asks for no more than
// one request a second, so they run one after another. Each answer is kept
// on this device for a week. (The Overpass servers, tried first, were too
// busy to rely on, and turn away requests from skybother.com's server.)
const PHRASES = {
  nature: ['nature reserve', 'state park', 'beach'],
  parks: ['park', 'nature reserve'],
  horizon: ['park', 'slipway', 'marina', 'beach', 'nature reserve'],
};
// What counts as a place to set up — a phrase search also turns up paths,
// neighbourhoods and the like that merely share a word.
const PLACE_TYPES = new Set(['leisure=park', 'leisure=nature_reserve', 'leisure=slipway', 'leisure=marina',
  'boundary=protected_area', 'boundary=national_park', 'natural=beach', 'tourism=camp_site', 'tourism=viewpoint']);
const PLACE_CACHE_DAYS = 7;
const unavailable = () => new Error('OpenStreetMap’s place search isn’t answering right now. Try again in a minute.');
let lastAsked = 0;

async function nominatim(phrase, b) {
  const [south, west, north, east] = b.map(x => x.toFixed(3));
  const url = `https://nominatim.openstreetmap.org/search?${new URLSearchParams({
    q: phrase, format: 'jsonv2', viewbox: `${west},${north},${east},${south}`, bounded: '1', limit: '40', extratags: '1',
  })}`;
  const cache = await caches.open('skybother-nearby').catch(() => null);
  const hit = await cache?.match(url);
  if (hit && Date.now() - Number(hit.headers.get('X-Retrieved')) < PLACE_CACHE_DAYS * 86_400_000) return hit.json();
  const wait = lastAsked + 1100 - Date.now();
  if (wait > 0) await new Promise(resolve => setTimeout(resolve, wait));
  lastAsked = Date.now();
  const response = await fetch(url, { signal: timeout(20_000) });
  if (!response.ok) throw unavailable();
  const results = await response.json();
  try { await cache?.put(url, new Response(JSON.stringify(results), { headers: { 'X-Retrieved': String(Date.now()) } })); } catch {}
  return results;
}

/** Places of a kind in each box, as Overpass-style elements for toPlaces. */
async function places(kind, boxes) {
  const elements = [];
  let failures = 0, asked = 0;
  for (const b of boxes) {
    for (const phrase of PHRASES[kind]) {
      asked++;
      try {
        for (const r of await nominatim(phrase, b)) {
          if (!PLACE_TYPES.has(`${r.category}=${r.type}`)) continue;
          elements.push({ lat: Number(r.lat), lon: Number(r.lon), tags: { name: r.name, ...(r.extratags ?? {}) } });
        }
      } catch {
        failures++;
      }
    }
  }
  // One failed search doesn't sink the rest; all of them failing does.
  if (asked && failures === asked) throw unavailable();
  return elements;
}

/** A box `metres` around a point: [south, west, north, east]. */
function box(lat, lon, metres) {
  const dLat = metres / 111_200, dLon = metres / (111_200 * Math.max(Math.cos(lat * rad), 0.2));
  return [lat - dLat, lon - dLon, lat + dLat, lon + dLon];
}

function toPlaces(elements) {
  const places = [];
  for (const element of elements) {
    const tags = element.tags ?? {};
    const name = tags.name?.trim();
    const lat = element.lat ?? element.center?.lat, lon = element.lon ?? element.center?.lon;
    if (!name || lat == null || lon == null) continue;
    const lower = name.toLowerCase();
    if (GENERIC.has(lower) || UNSUITABLE.some(f => lower.includes(f))) continue;
    if (places.some(p => p.name === name && Math.abs(p.latitude - lat) < 0.01 && Math.abs(p.longitude - lon) < 0.01)) continue;
    places.push({
      name, latitude: lat, longitude: lon,
      website: tags.website ?? tags['contact:website'] ?? null,
      hours: tags.opening_hours ? postedHours(tags.opening_hours) : null,
    });
  }
  return places;
}

// --- ParkHours: PostedHours --------------------------------------------------
export function postedHours(text) {
  const value = text.trim().toLowerCase();
  if (['24/7', 'mo-su 00:00-24:00', '00:00-24:00'].includes(value)) return { closing: 'never', raw: text };
  if (value.includes(';') || value.includes(',') || value.includes('off')) return null;
  let times = value;
  for (const prefix of ['mo-su ', 'daily ']) if (times.startsWith(prefix)) times = times.slice(prefix.length);
  if (!/^\d/.test(times) && !times.startsWith('sunrise') && !times.startsWith('dawn')) return null;
  const dash = times.indexOf('-');
  if (dash < 0) return null;
  const start = times.slice(0, dash).trim(), end = times.slice(dash + 1).trim();
  if (end === 'sunset' || end === 'dusk') return { closing: 'sunset', raw: text };
  const clock = t => { const m = /^(\d{1,2}):(\d{2})$/.exec(t); if (!m) return null; const h = +m[1], mi = +m[2]; return h <= 24 && mi < 60 ? { h, mi } : null; };
  const e = clock(end);
  if (!e) return null;
  const s = clock(start);
  if (e.h === 24 && e.mi === 0 && s?.h === 0 && s?.mi === 0) return { closing: 'never', raw: text };
  const crossesMidnight = e.h === 24 || (s ? e.h * 60 + e.mi <= s.h * 60 + s.mi : false);
  return { closing: 'time', hour: e.h % 24, minute: e.mi, crossesMidnight, raw: text };
}

// --- DarkSkyFinder -------------------------------------------------------------
const MIN_IMPROVEMENT = 0.35;
const DISTANCE_PENALTY = 0.008;
const MAX_PATCHES = 5;

function spotFrom(place, site, field, extra = {}) {
  const at = extra.latitude != null ? extra : place;
  const distance = distanceKm(site.latitude, site.longitude, at.latitude, at.longitude);
  const brightness = field.brightness(at.latitude, at.longitude);
  return {
    name: place.name, latitude: at.latitude, longitude: at.longitude, distanceKilometers: distance,
    direction: compassDirection(site.latitude, site.longitude, at.latitude, at.longitude),
    zenithBrightness: brightness, estimatedBortleClass: bortleForBrightness(brightness),
    horizonAltitude: extra.horizon ?? null, clearestDirection: extra.clearestDirection ?? null,
    website: place.website, hours: place.hours,
  };
}

export async function findDarkerSky(site, radiusKm, onstage = () => {}) {
  onstage('Checking satellite night lights…');
  const grid = await nightLightsGrid(site.latitude, site.longitude);
  const field = new SkyGlowField(grid);
  const home = field.brightness(site.latitude, site.longitude);
  const result = candidates => ({ goal: 'darkerSky', radiusKilometers: radiusKm, siteZenithBrightness: home, siteEstimatedBortleClass: bortleForBrightness(home), candidates });

  // Stage one: the darkest, well-separated patches of the search area.
  const step = clamp(radiusKm / 8, 1, 5);
  const latStep = step / KM_PER_DEGREE;
  const lonStep = step / (KM_PER_DEGREE * Math.max(Math.cos(site.latitude * rad), 0.2));
  const out = Math.ceil(radiusKm / step);
  const points = [];
  for (let n = -out; n <= out; n++) {
    for (let e = -out; e <= out; e++) {
      const lat = site.latitude + n * latStep, lon = site.longitude + e * lonStep;
      const distance = distanceKm(site.latitude, site.longitude, lat, lon);
      if (distance > radiusKm || !field.contains(lat, lon)) continue;
      const b = field.brightness(lat, lon);
      if (b - home >= MIN_IMPROVEMENT) points.push({ lat, lon, rank: b - DISTANCE_PENALTY * distance });
    }
  }
  const separation = Math.max(3, radiusKm / 4);
  const patches = [];
  for (const p of points.sort((a, b) => b.rank - a.rank)) {
    if (patches.length >= MAX_PATCHES) break;
    if (patches.every(q => distanceKm(q.lat, q.lon, p.lat, p.lon) >= separation)) patches.push(p);
  }
  if (!patches.length) return result([]);

  // Stage two: real places — parks of every size around each dark patch,
  // larger nature areas across the whole search — each scored where it is.
  onstage('Looking for parks and nature areas…');
  // As DarkSkyFinder: around each dark patch, then the whole area (its
  // bigger nature areas), then the site's own surroundings, which a
  // whole-area search tends to crowd out.
  const elements = await places('parks', [
    ...patches.map(p => box(p.lat, p.lon, 4000)),
    box(site.latitude, site.longitude, Math.min(radiusKm * 1000, 8000)),
  ]);
  // A search returns at most 40, so a wide area is searched in quarters.
  const whole = box(site.latitude, site.longitude, radiusKm * 1000);
  const quarters = radiusKm > 20
    ? [[whole[0], whole[1], site.latitude, site.longitude], [whole[0], site.longitude, site.latitude, whole[3]],
       [site.latitude, whole[1], whole[2], site.longitude], [site.latitude, site.longitude, whole[2], whole[3]]]
    : [whole];
  elements.push(...await places('nature', quarters).catch(() => []));
  const candidates = toPlaces(elements).flatMap(place => {
    const distance = distanceKm(site.latitude, site.longitude, place.latitude, place.longitude);
    if (distance > radiusKm || !field.contains(place.latitude, place.longitude)) return [];
    const spot = spotFrom(place, site, field);
    return spot.zenithBrightness - home >= MIN_IMPROVEMENT ? [spot] : [];
  });
  return result(candidates);
}

// --- LandCoverClient -------------------------------------------------------------
const FILE_SPAN = 3, OVERVIEW = 1, HEADER_BYTES = 65_536;
const FILE_PIXELS = 36_000 >> OVERVIEW;
const PIXELS_PER_DEGREE = FILE_PIXELS / FILE_SPAN;
const layouts = new Map();
const tiles = new Map();

async function coverBytes(name, offset, length) {
  const response = await fetch(`/api/worldcover/${name}?offset=${offset}&length=${length}`, { signal: timeout(30_000) });
  if (response.status === 404) return null;
  if (!response.ok) throw new Error('Satellite land-cover data couldn’t be loaded for this area.');
  return new Uint8Array(await response.arrayBuffer());
}

function fileName(fileColumn, fileRow) {
  const west = fileColumn * FILE_SPAN - 180, south = 90 - (fileRow + 1) * FILE_SPAN;
  const latPart = `${south >= 0 ? 'N' : 'S'}${String(Math.abs(south)).padStart(2, '0')}`;
  const lonPart = `${west >= 0 ? 'E' : 'W'}${String(Math.abs(west)).padStart(3, '0')}`;
  return `ESA_WorldCover_10m_2021_v200_${latPart}${lonPart}_Map.tif`;
}

function parseLayout(data, level) {
  const u16 = o => data[o] | (data[o + 1] << 8);
  const u32 = o => (data[o] | (data[o + 1] << 8) | (data[o + 2] << 16) | (data[o + 3] << 24)) >>> 0;
  if (data.length < 8 || data[0] !== 0x49 || data[1] !== 0x49 || u16(2) !== 42) throw new Error('unreadable');
  let ifd = u32(4), current = 0;
  while (ifd > 0) {
    if (ifd + 2 > data.length) return { needs: ifd + 65_536 };
    const count = u16(ifd);
    const end = ifd + 2 + count * 12 + 4;
    if (end > data.length) return { needs: end + 65_536 };
    if (current === level) {
      let width = 0, tileSize = 0, compression = 0, bits = 0, predictor = 1, offsets = null, counts = null;
      for (let i = 0; i < count; i++) {
        const e = ifd + 2 + i * 12;
        const tag = u16(e), type = u16(e + 2), n = u32(e + 4);
        const inline = type === 3 ? u16(e + 8) : u32(e + 8);
        if (tag === 256) width = inline;
        else if (tag === 258) bits = inline;
        else if (tag === 259) compression = inline;
        else if (tag === 317) predictor = inline;
        else if (tag === 322) tileSize = inline;
        else if (tag === 324) offsets = { n, at: u32(e + 8) };
        else if (tag === 325) counts = { n, at: u32(e + 8) };
      }
      if (bits !== 8 || compression !== 8 || predictor !== 1 || !tileSize || !offsets || !counts) throw new Error('unreadable');
      const tableEnd = Math.max(offsets.at + offsets.n * 4, counts.at + counts.n * 4);
      if (tableEnd > data.length) return { needs: tableEnd };
      return {
        layout: {
          width, tileSize,
          offsets: Array.from({ length: offsets.n }, (_, i) => u32(offsets.at + i * 4)),
          counts: Array.from({ length: counts.n }, (_, i) => u32(counts.at + i * 4)),
        },
      };
    }
    ifd = u32(ifd + 2 + count * 12);
    current++;
  }
  throw new Error('unreadable');
}

async function layoutFor(name) {
  if (layouts.has(name)) return layouts.get(name);
  let header = await coverBytes(name, 0, HEADER_BYTES);
  if (!header) { layouts.set(name, null); return null; }
  let parsed = parseLayout(header, OVERVIEW);
  if (parsed.needs) parsed = parseLayout(await coverBytes(name, 0, parsed.needs), OVERVIEW);
  if (!parsed.layout) throw new Error('unreadable');
  layouts.set(name, parsed.layout);
  return parsed.layout;
}

// TIFF Deflate is a zlib stream, which DecompressionStream('deflate') reads.
async function inflate(bytes, expected) {
  const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('deflate'));
  const out = new Uint8Array(await new Response(stream).arrayBuffer());
  if (out.length < expected) throw new Error('unreadable');
  return out.subarray(0, expected);
}

async function tileFor(name, index, layout) {
  const key = `${name}#${index}`;
  if (tiles.has(key)) return tiles.get(key);
  const compressed = await coverBytes(name, layout.offsets[index], layout.counts[index]);
  const pixels = await inflate(compressed, layout.tileSize * layout.tileSize);
  if (tiles.size > 48) tiles.clear();
  tiles.set(key, pixels);
  return pixels;
}

export async function landCoverGrid(latitude, longitude, halfMetres) {
  const halfLat = halfMetres / 111_200;
  const halfLon = halfMetres / (111_200 * Math.max(Math.cos(latitude * rad), 0.2));
  const originColumn = Math.floor((longitude - halfLon + 180) * PIXELS_PER_DEGREE);
  const originRow = Math.floor((90 - (latitude + halfLat)) * PIXELS_PER_DEGREE);
  const endColumn = Math.ceil((longitude + halfLon + 180) * PIXELS_PER_DEGREE);
  const endRow = Math.ceil((90 - (latitude - halfLat)) * PIXELS_PER_DEGREE);
  const width = endColumn - originColumn, height = endRow - originRow;
  const classes = new Uint8Array(width * height);
  let anyData = false;
  for (let fileRow = Math.floor(originRow / FILE_PIXELS); fileRow <= Math.floor((endRow - 1) / FILE_PIXELS); fileRow++) {
    for (let fileColumn = Math.floor(originColumn / FILE_PIXELS); fileColumn <= Math.floor((endColumn - 1) / FILE_PIXELS); fileColumn++) {
      const name = fileName(fileColumn, fileRow);
      const layout = await layoutFor(name);
      const fileOriginColumn = fileColumn * FILE_PIXELS, fileOriginRow = fileRow * FILE_PIXELS;
      const startColumn = Math.max(originColumn - fileOriginColumn, 0), stopColumn = Math.min(endColumn - fileOriginColumn, FILE_PIXELS);
      const startRow = Math.max(originRow - fileOriginRow, 0), stopRow = Math.min(endRow - fileOriginRow, FILE_PIXELS);
      if (!layout) {
        // No file: open ocean. Water is the answer, not a gap.
        for (let r = startRow; r < stopRow; r++) for (let c = startColumn; c < stopColumn; c++) {
          classes[(fileOriginRow + r - originRow) * width + fileOriginColumn + c - originColumn] = 80;
        }
        anyData = true;
        continue;
      }
      if (layout.width !== FILE_PIXELS) throw new Error('Satellite land-cover data couldn’t be loaded for this area.');
      const size = layout.tileSize, across = Math.ceil(FILE_PIXELS / size);
      for (let tr = Math.floor(startRow / size); tr <= Math.floor((stopRow - 1) / size); tr++) {
        for (let tc = Math.floor(startColumn / size); tc <= Math.floor((stopColumn - 1) / size); tc++) {
          const pixels = await tileFor(name, tr * across + tc, layout);
          anyData = true;
          const tileRow0 = tr * size, tileColumn0 = tc * size;
          for (let r = Math.max(startRow, tileRow0); r < Math.min(stopRow, tileRow0 + size); r++) {
            const gridRow = fileOriginRow + r - originRow;
            const source = (r - tileRow0) * size;
            for (let c = Math.max(startColumn, tileColumn0); c < Math.min(stopColumn, tileColumn0 + size); c++) {
              classes[gridRow * width + fileOriginColumn + c - originColumn] = pixels[source + c - tileColumn0];
            }
          }
        }
      }
    }
  }
  if (!anyData) throw new Error('Satellite land-cover data couldn’t be loaded for this area.');
  return {
    originColumn, originRow, width, height, classes,
    pixelHeight: 111_200 / PIXELS_PER_DEGREE,
    pixelWidth: lat => 111_200 * Math.max(Math.cos(lat * rad), 0.2) / PIXELS_PER_DEGREE,
    position(lat, lon) {
      const column = Math.floor((lon + 180) * PIXELS_PER_DEGREE) - originColumn;
      const row = Math.floor((90 - lat) * PIXELS_PER_DEGREE) - originRow;
      return column >= 0 && column < width && row >= 0 && row < height ? { column, row } : null;
    },
    coordinate: (column, row) => ({
      latitude: 90 - (originRow + row + 0.5) / PIXELS_PER_DEGREE,
      longitude: (originColumn + column + 0.5) / PIXELS_PER_DEGREE - 180,
    }),
    at: (column, row) => classes[row * width + column],
  };
}

// --- OpenHorizonFinder ---------------------------------------------------------
const AROUND_PLACE = 200, SIGHT_LINE = 600, MIN_GAIN = 5, EYE = 1.5, DIRECTIONS = 36;
const obstructionHeight = v => (v === 10 ? 15 : v === 95 ? 6 : v === 50 ? 4 : v === 20 ? 2 : 0);
const standable = v => v === 30 || v === 60 || v === 50 || v === 40 || v === 100;

function horizonProfile(column, row, cover, pw, ph) {
  const step = Math.min(pw, ph);
  const steps = Math.floor(SIGHT_LINE / step);
  return Array.from({ length: DIRECTIONS }, (_, i) => {
    const azimuth = i * 360 / DIRECTIONS;
    const east = Math.sin(azimuth * rad), north = Math.cos(azimuth * rad);
    let steepest = 0;
    for (let s = 1; s <= steps; s++) {
      const distance = s * step;
      const c = column + Math.round(east * distance / pw);
      const r = row - Math.round(north * distance / ph);
      if (c < 0 || c >= cover.width || r < 0 || r >= cover.height) break;
      const rise = obstructionHeight(cover.at(c, r)) - EYE;
      if (rise <= 0) continue;
      steepest = Math.max(steepest, Math.atan2(rise, distance) / rad);
    }
    return steepest;
  });
}

const blockedHorizon = profile => {
  const sorted = [...profile].sort((a, b) => a - b);
  return Math.ceil(sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * 0.75))]);
};

function clearestDirection(profile) {
  const window = DIRECTIONS / 4;
  let bestStart = 0, bestSum = Infinity;
  for (let start = 0; start < DIRECTIONS; start++) {
    let sum = 0;
    for (let k = 0; k < window; k++) sum += profile[(start + k) % DIRECTIONS];
    if (sum < bestSum) { bestSum = sum; bestStart = start; }
  }
  const centre = (bestStart + (window - 1) / 2) * 360 / DIRECTIONS;
  return COMPASS8[Math.floor(((centre % 360 + 360) % 360 + 22.5) / 45) % 8];
}

function bestStandingPoint(place, cover) {
  const centre = cover.position(place.latitude, place.longitude);
  if (!centre) return null;
  const ph = cover.pixelHeight, pw = cover.pixelWidth(place.latitude);
  const rowReach = Math.floor(AROUND_PLACE / ph), columnReach = Math.floor(AROUND_PLACE / pw);
  let best = null;
  for (let row = centre.row - rowReach; row <= centre.row + rowReach; row += 2) {
    for (let column = centre.column - columnReach; column <= centre.column + columnReach; column += 2) {
      if (column < 0 || column >= cover.width || row < 0 || row >= cover.height) continue;
      const dx = (column - centre.column) * pw, dy = (row - centre.row) * ph;
      const offset = Math.hypot(dx, dy);
      if (offset > AROUND_PLACE || !standable(cover.at(column, row))) continue;
      const profile = horizonProfile(column, row, cover, pw, ph);
      const horizon = blockedHorizon(profile);
      if (!best || horizon < best.horizon || (horizon === best.horizon && offset < best.offset)) best = { column, row, profile, horizon, offset };
    }
  }
  if (!best) return null;
  return { ...cover.coordinate(best.column, best.row), horizon: best.horizon, clearestDirection: clearestDirection(best.profile) };
}

/** Site.typicalHorizonAltitude: the mean of the eight directions. */
export const typicalHorizon = site => {
  const profile = site.horizonProfile?.length === 8 ? site.horizonProfile : Array(8).fill(site.horizonAltitude ?? 20);
  return profile.reduce((a, b) => a + b, 0) / 8;
};

export async function findOpenHorizon(site, radiusKm, onstage = () => {}) {
  onstage('Looking for parks and boat ramps…');
  const span = radiusKm * 1000 + AROUND_PLACE;
  const found = toPlaces(await places('horizon', [box(site.latitude, site.longitude, span)]));
  onstage('Checking satellite land cover…');
  const [grid, cover] = await Promise.all([
    nightLightsGrid(site.latitude, site.longitude),
    landCoverGrid(site.latitude, site.longitude, span + SIGHT_LINE),
  ]);
  const field = new SkyGlowField(grid);
  const home = field.brightness(site.latitude, site.longitude);
  const siteHorizon = typicalHorizon(site);
  const candidates = found.flatMap(place => {
    if (distanceKm(site.latitude, site.longitude, place.latitude, place.longitude) > radiusKm + AROUND_PLACE / 1000) return [];
    const best = bestStandingPoint(place, cover);
    if (!best || best.horizon > siteHorizon - MIN_GAIN) return [];
    if (distanceKm(site.latitude, site.longitude, best.latitude, best.longitude) > radiusKm) return [];
    return [spotFrom(place, site, field, best)];
  });
  return { goal: 'openHorizon', radiusKilometers: radiusKm, siteZenithBrightness: home, siteEstimatedBortleClass: bortleForBrightness(home), candidates };
}

// --- NearbySpotSelection -----------------------------------------------------------
const MAX_SPOTS = 3;
const margin = goal => (goal === 'darkerSky' ? 0.3 : 3);
const quality = (spot, goal) => (goal === 'darkerSky' ? spot.zenithBrightness : -(spot.horizonAltitude ?? 90));

function distinctPlaces(candidates, goal) {
  const kept = [];
  for (const c of candidates) {
    const i = kept.findIndex(k => k.name === c.name || (Math.abs(k.latitude - c.latitude) < 0.0005 && Math.abs(k.longitude - c.longitude) < 0.0005));
    if (i < 0) { kept.push(c); continue; }
    const qc = quality(c, goal), qk = quality(kept[i], goal);
    if (qc > qk || (qc === qk && c.distanceKilometers < kept[i].distanceKilometers)) kept[i] = c;
  }
  return kept;
}

/** Best first, then closer alternatives — never further than needed. */
export function recommend(candidates, goal) {
  let remaining = distinctPlaces(candidates, goal);
  const chosen = [];
  while (remaining.length && chosen.length < MAX_SPOTS) {
    const best = remaining.reduce((a, b) => (quality(b, goal) > quality(a, goal) ? b : a));
    const threshold = quality(best, goal) - margin(goal);
    const pick = remaining.filter(s => quality(s, goal) >= threshold).reduce((a, b) => (b.distanceKilometers < a.distanceKilometers ? b : a));
    chosen.push(pick);
    remaining = remaining.filter(s => s.distanceKilometers < pick.distanceKilometers);
  }
  return chosen;
}

export const spotID = spot => `${spot.name}|${spot.latitude.toFixed(4)}|${spot.longitude.toFixed(4)}`;
