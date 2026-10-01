// The Mac app's Format helpers (Support/Formatting.swift), for the page's own
// text. Times are always the site's, never the browser's.

const timeFormats = new Map();

function timeFormat(timeZone) {
  if (!timeFormats.has(timeZone)) {
    timeFormats.set(timeZone, new Intl.DateTimeFormat('en-GB', { hour: '2-digit', minute: '2-digit', hourCycle: 'h23', timeZone }));
  }
  return timeFormats.get(timeZone);
}

/** "21:05" at the site. */
export function time(date, timeZone) {
  return date ? timeFormat(timeZone).format(new Date(date)) : '—';
}

/** Minutes past the hour at the site, for hour ticks. */
export function minuteOfHour(date, timeZone) {
  return Number(timeFormat(timeZone).formatToParts(date).find(p => p.type === 'minute').value);
}

/** "4h 25m", "45m", "—" */
export function duration(minutes) {
  if (!Number.isFinite(minutes) || minutes <= 0) return '—';
  const total = Math.round(minutes);
  const h = Math.floor(total / 60);
  const m = total % 60;
  if (h === 0) return `${m}m`;
  return m === 0 ? `${h}h` : `${h}h ${m}m`;
}

export const hours = value => duration(value * 60);

export function temperature(celsius, imperial) {
  if (celsius == null || !Number.isFinite(celsius)) return '—';
  return imperial ? `${Math.round(celsius * 9 / 5 + 32)}°F` : `${Math.round(celsius)}°C`;
}

export function wind(kmh, imperial) {
  if (kmh == null || !Number.isFinite(kmh)) return '—';
  return imperial ? `${Math.round(kmh * 0.621371)} mph` : `${Math.round(kmh)} km/h`;
}

export const degrees = value => (Number.isFinite(value) ? `${Math.round(value)}°` : '—');

/** A night's evening as a calendar date, from its planKey ("2026-10-01"). */
function evening(planKey) {
  const [y, m, d] = planKey.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d, 12));
}

export const weekday = planKey => evening(planKey).toLocaleDateString('en', { weekday: 'short', timeZone: 'UTC' });
export const fullWeekday = planKey => evening(planKey).toLocaleDateString('en', { weekday: 'long', timeZone: 'UTC' });
export const dayAndMonth = planKey => evening(planKey).toLocaleDateString('en', { month: 'short', day: 'numeric', timeZone: 'UTC' });
export const longDate = planKey => evening(planKey).toLocaleDateString('en', { weekday: 'long', month: 'long', day: 'numeric', timeZone: 'UTC' });

/** "just now", "12 min ago", "3 h ago" */
export function age(date) {
  const minutes = Math.round((Date.now() - date) / 60000);
  if (minutes < 1) return 'just now';
  if (minutes < 60) return `${minutes} min ago`;
  return `${Math.round(minutes / 60)} h ago`;
}
