// The Mac app's Palette (UI/Components.swift).

const rgb = (r, g, b) => [r, g, b];

export const daylight = rgb(0.42, 0.62, 0.86);
export const civil = rgb(0.18, 0.24, 0.45);
export const nautical = rgb(0.07, 0.10, 0.22);
export const astronomical = rgb(0.025, 0.03, 0.075);
export const moonlight = rgb(0.98, 0.93, 0.74);
export const cloud = rgb(0.86, 0.89, 0.94);
export const accent = rgb(0.62, 0.52, 0.98);
export const skip = rgb(0.85, 0.36, 0.34);
export const marginal = rgb(0.95, 0.70, 0.24);
export const spaceTop = rgb(0.055, 0.05, 0.11);

const verdictColors = {
  Exceptional: rgb(0.20, 0.92, 0.55),
  Excellent: rgb(0.24, 0.78, 0.47),
  Good: rgb(0.70, 0.80, 0.28),
  Marginal: rgb(0.95, 0.70, 0.24),
  Poor: rgb(0.85, 0.36, 0.34),
};

const dewColors = {
  Low: verdictColors.Excellent,
  Moderate: rgb(0.93, 0.84, 0.30),
  High: rgb(0.96, 0.56, 0.22),
  'Very High': skip,
};

/** CSS colour from a palette entry, optionally translucent. */
export function css([r, g, b], alpha = 1) {
  return `rgba(${Math.round(r * 255)}, ${Math.round(g * 255)}, ${Math.round(b * 255)}, ${alpha})`;
}

/** Verdict.forScore */
export function verdictFor(score) {
  if (score >= 90) return 'Exceptional';
  if (score >= 75) return 'Excellent';
  if (score >= 60) return 'Good';
  if (score >= 45) return 'Marginal';
  return 'Poor';
}

export const verdictColor = (verdict, alpha) => css(verdictColors[verdict], alpha);
export const scoreColor = (score, alpha) => verdictColor(verdictFor(score), alpha);
export const dewColor = level => css(dewColors[level] ?? dewColors.Low);

const clamp = (x, lo, hi) => Math.min(hi, Math.max(lo, x));

function smoothstep(edge0, edge1, x) {
  const t = clamp((x - edge0) / (edge1 - edge0), 0, 1);
  return t * t * (3 - 2 * t);
}

function blend(a, b, t) {
  const k = clamp(t, 0, 1);
  return a.map((v, i) => v + (b[i] - v) * k);
}

/** Palette.sky(sunAltitude:) — the timeline's background. */
export function sky(sunAltitude) {
  if (sunAltitude >= 0) return daylight;
  if (sunAltitude >= -6) return blend(daylight, civil, smoothstep(0, -6, sunAltitude));
  if (sunAltitude >= -12) return blend(civil, nautical, smoothstep(-6, -12, sunAltitude));
  if (sunAltitude >= -18) return blend(nautical, astronomical, smoothstep(-12, -18, sunAltitude));
  return astronomical;
}
