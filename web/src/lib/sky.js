// Sky View's geometry, the Mac app's own formulas (Core/JulianDate.swift,
// Core/SkyCoordinates.swift, Core/SkyProjection.swift), so the dome agrees
// with the Mac's. The Sun, Moon and wind come from the engine's sky track
// (EngineAPI.skyTrack); everything else is worked out here.

const rad = Math.PI / 180;
const sin = d => Math.sin(d * rad);
const cos = d => Math.cos(d * rad);
const normalize360 = d => ((d % 360) + 360) % 360;
const clamp = (x, lo, hi) => Math.min(hi, Math.max(lo, x));

/** Date.daysSinceJ2000 */
export const daysSinceJ2000 = ms => ms / 86_400_000 + 2440587.5 - 2451545.0;

/** SkyCoordinates.localSiderealTime, degrees. Longitude east-positive. */
export const localSiderealTime = (d, longitude) => normalize360(280.46061837 + 360.98564736629 * d + longitude);

/** SkyCoordinates.horizontal: { altitude, azimuth } in degrees, geometric. */
export function horizontal(rightAscension, declination, d, latitude, longitude) {
  const hourAngle = normalize360(localSiderealTime(d, longitude) - rightAscension);
  const altitude = Math.asin(sin(latitude) * sin(declination) + cos(latitude) * cos(declination) * cos(hourAngle)) / rad;
  const azimuth = Math.atan2(-cos(declination) * sin(hourAngle),
    sin(declination) * cos(latitude) - cos(declination) * sin(latitude) * cos(hourAngle)) / rad;
  return { altitude, azimuth: normalize360(azimuth) };
}

/** SkyProjection.project: azimuthal equidistant, north up, east right. */
export function project({ altitude, azimuth }) {
  const r = clamp((90 - altitude) / 90, 0, 1);
  return { x: r * sin(azimuth), y: -r * cos(azimuth) };
}

/** Site.blockedAltitude, from the track's eight-sector horizon. */
export const blockedAltitude = (horizon, azimuth) => horizon[Math.round(normalize360(azimuth) / 45) % 8];

/** The track's values at a moment, interpolated; right ascension across 0h too. */
export function trackAt(track, ms) {
  const step = track.stepMinutes * 60_000;
  const f = clamp((ms - Date.parse(track.start)) / step, 0, track.sun.length - 1);
  const i = Math.min(Math.floor(f), track.sun.length - 2);
  const t = f - i;
  const mix = (a, b) => a + (b - a) * t;
  const mixRA = (a, b) => normalize360(a + ((((b - a) % 360) + 540) % 360 - 180) * t);
  const [s0, s1] = [track.sun[i], track.sun[i + 1]];
  const [m0, m1] = [track.moon[i], track.moon[i + 1]];
  return {
    sun: { rightAscension: mixRA(s0[0], s1[0]), declination: mix(s0[1], s1[1]) },
    moon: {
      rightAscension: mixRA(m0[0], m1[0]), declination: mix(m0[1], m1[1]),
      illuminatedFraction: mix(m0[2], m1[2]), diameter: mix(m0[3], m1[3]), waxing: m0[4] > 0.5,
    },
  };
}

/**
 * How far the wind has carried the clouds since `fromMs`, in km east and
 * north: summed ten minutes at a time like SkyView.cloudDrift, so a change of
 * wind doesn't swing every cloud across the sky.
 */
export function cloudDrift(track, fromMs, toMs) {
  const step = track.stepMinutes * 60_000;
  const start = Date.parse(track.start);
  const total = toMs - fromMs;
  if (Math.abs(total) < 1000) return { east: 0, north: 0 };
  const steps = Math.max(1, Math.round(Math.abs(total) / step));
  const dt = total / steps;
  let east = 0, north = 0;
  for (let k = 0; k < steps; k++) {
    const at = fromMs + dt * (k + 0.5);
    const f = clamp((at - start) / step, 0, track.wind.length - 1);
    const i = Math.min(Math.floor(f), track.wind.length - 2), t = f - i;
    const [a, b] = [track.wind[i], track.wind[i + 1]];
    east += (a[0] + (b[0] - a[0]) * t) * dt / 3_600_000;
    north += (a[1] + (b[1] - a[1]) * t) * dt / 3_600_000;
  }
  return { east, north };
}

/**
 * The forecast's cloud by layer at a moment, 0–1, as the Mac's dome reads it
 * (forecast.interpolated): from the sky track's hourly forecast, which covers
 * the day as well as the night, else the night's own samples. Null beyond the
 * forecast.
 */
export function cloudAt(night, ms, track = null) {
  if (track?.cloud?.length) {
    const step = track.stepMinutes * 60_000;
    const f = clamp((ms - Date.parse(track.start)) / step, 0, track.cloud.length - 1);
    const i = Math.min(Math.floor(f), track.cloud.length - 2), t = f - i;
    const a = track.cloud[i], b = track.cloud[i + 1] ?? a;
    if (a.length !== 3 || b.length !== 3) return null;
    return { low: a[0] + (b[0] - a[0]) * t, mid: a[1] + (b[1] - a[1]) * t, high: a[2] + (b[2] - a[2]) * t };
  }
  return nightCloudAt(night, ms);
}

function nightCloudAt(night, ms) {
  const samples = night.samples;
  if (!night.hasWeather || samples.length < 2) return null;
  const t0 = Date.parse(samples[0].date), t1 = Date.parse(samples[samples.length - 1].date);
  const f = clamp((ms - t0) / (t1 - t0), 0, 1) * (samples.length - 1);
  const i = Math.min(Math.floor(f), samples.length - 2), t = f - i;
  const a = samples[i], b = samples[i + 1];
  if (a.cloudCover == null || b.cloudCover == null) return null;
  const mix = (x, y) => ((x ?? 0) + ((y ?? 0) - (x ?? 0)) * t) / 100;
  return { low: mix(a.cloudLow, b.cloudLow), mid: mix(a.cloudMid, b.cloudMid), high: mix(a.cloudHigh, b.cloudHigh) };
}
