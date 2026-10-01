// Fetching lives here; parsing happens in the engine (OpenMeteoClient.decode),
// so the Mac and web apps read a forecast identically.

// Mirrors OpenMeteoClient.forecastURL.
const hourly = ['cloud_cover', 'cloud_cover_low', 'cloud_cover_mid', 'cloud_cover_high', 'temperature_2m', 'dew_point_2m',
  'relative_humidity_2m', 'wind_speed_10m', 'wind_gusts_10m', 'visibility', 'precipitation_probability', 'wind_direction_10m'];

export async function fetchForecast(latitude, longitude, nights) {
  const days = Math.min(16, Math.max(2, nights + 1));
  const url = models => `https://api.open-meteo.com/v1/forecast?latitude=${latitude.toFixed(4)}&longitude=${longitude.toFixed(4)}` +
    `&hourly=${hourly.join(',')}&timeformat=unixtime&timezone=UTC&wind_speed_unit=kmh&temperature_unit=celsius` +
    `&forecast_days=${days}&models=${models}`;
  // Both models, as the Mac app asks. Open-Meteo's NBM backend sometimes
  // stalls or sends back a broken body; Open-Meteo's own model alone still
  // gives a forecast. So if the pair hasn't answered in 3 s, ask for that too
  // and take the first usable answer, preferring the pair. (The Mac app falls
  // back to MET Norway instead, which a browser can't reach without a proxy.)
  const both = fetchJSONText(url('best_match,ncep_nbm_conus'));
  const head = new Promise(resolve => setTimeout(resolve, 3000, 'slow'));
  const first = await Promise.race([both.then(text => ({ text }), error => ({ error })), head]);
  if (first !== 'slow' && first.text) return first.text;
  const alone = fetchJSONText(url('best_match'));
  return Promise.any([both, alone]).catch(failure => { throw failure.errors?.[failure.errors.length - 1] ?? failure; });
}

/** The body, if it's a JSON object with an hourly forecast; throws otherwise. */
async function fetchJSONText(url) {
  // Like the Mac app's 8 s: a healthy answer takes well under a second.
  // (An AbortController rather than AbortSignal.timeout, which older
  // iPhones don't have.)
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 8000);
  const response = await fetch(url, { cache: 'no-store', signal: controller.signal }).finally(() => clearTimeout(timer));
  if (!response.ok) throw new Error(`Weather service returned HTTP ${response.status}.`);
  const text = await response.text();
  try {
    if (!JSON.parse(text).hourly) throw new Error();
  } catch {
    throw new Error('The weather service sent back an unreadable forecast.');
  }
  return text;
}

/** Towns and places, with their time zone and elevation, from Open-Meteo. */
export async function searchPlaces(name) {
  const url = `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(name)}&count=6&language=en&format=json`;
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Place search returned HTTP ${response.status}.`);
  return (await response.json()).results ?? [];
}

export async function elevationAt(latitude, longitude) {
  const response = await fetch(`https://api.open-meteo.com/v1/elevation?latitude=${latitude}&longitude=${longitude}`);
  return response.ok ? (await response.json()).elevation?.[0] ?? 0 : 0;
}

/** MPC's comet orbits, so tonight's comets are planned like everything else. */
export async function fetchCometElements() {
  try {
    const response = await fetch('https://www.minorplanetcenter.net/iau/MPCORB/CometEls.txt');
    return response.ok ? await response.text() : undefined;
  } catch {
    return undefined;
  }
}
