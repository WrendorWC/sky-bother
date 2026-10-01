<script>
  // ScoreBadge (UI/Components.swift): a ring filled to the score, in its verdict's colour.
  import { scoreColor, verdictFor } from './palette.js';

  let { score, size = 40 } = $props();

  const stroke = $derived(Math.max(2, size * 0.1));
  const radius = $derived((size - stroke) / 2);
  const circumference = $derived(2 * Math.PI * radius);
  const fill = $derived(Math.max(0.015, Math.min(1, score / 100)));
  const exceptional = $derived(verdictFor(score) === 'Exceptional');
</script>

<svg width={size} height={size} viewBox="0 0 {size} {size}" role="img" aria-label="Score {Math.round(score)}"
     style:filter={exceptional ? `drop-shadow(0 0 ${size * 0.2}px ${scoreColor(score, 0.75)})` : null}>
  <circle cx={size / 2} cy={size / 2} r={radius} fill="none" stroke="rgba(255,255,255,0.09)" stroke-width={stroke} />
  <circle cx={size / 2} cy={size / 2} r={radius} fill="none" stroke={scoreColor(score)} stroke-width={stroke}
          stroke-linecap="round" stroke-dasharray="{circumference * fill} {circumference}"
          transform="rotate(-90 {size / 2} {size / 2})" />
  <text x="50%" y="50%" dy="0.35em" text-anchor="middle" fill={scoreColor(score)}
        font-size={size * 0.36} font-weight="700">{Math.round(score)}</text>
</svg>

<style>
  svg { flex: none; display: block; }
  text { font-family: ui-rounded, 'SF Pro Rounded', system-ui, sans-serif; }
</style>
