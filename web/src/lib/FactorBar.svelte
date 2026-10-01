<script>
  // FactorBar (UI/Components.swift): a factor's name, its rating, the points
  // the score loses to it, a bar, and the real figure behind it.
  import { verdictColor, verdictFor } from './palette.js';

  let { factor } = $props();

  const verdict = $derived(verdictFor(Math.round(factor.value * 100)));
  const points = $derived(Math.round(factor.impact));
</script>

<div class="factor">
  <div class="head">
    <span>{factor.name}</span>
    <span class="verdict" style:color={verdictColor(verdict)}>{verdict}</span>
    <span class="impact" class:marginal={points >= 3 && points < 8} class:skip={points >= 8}>{points >= 1 ? `−${points}` : '0'}</span>
  </div>
  <div class="bar"><span style:width="{Math.max(1, factor.value * 100)}%" style:background={verdictColor(verdict)}></span></div>
  <p class="muted">{factor.detail}</p>
</div>

<style>
  .factor { display: grid; gap: 3px; margin-bottom: 6px; }
  .head { display: flex; gap: 8px; align-items: baseline; }
  .verdict { font-size: 11px; font-weight: 600; }
  .impact { margin-left: auto; font-variant-numeric: tabular-nums; font-weight: 600; color: var(--muted); }
  .impact.marginal { color: var(--marginal); font-weight: 700; }
  .impact.skip { color: var(--poor); font-weight: 700; }
  .bar { height: 6px; border-radius: 3px; background: rgba(255, 255, 255, 0.08); overflow: hidden; }
  .bar span { display: block; height: 100%; border-radius: 3px; }
  p { margin: 0; }
</style>
