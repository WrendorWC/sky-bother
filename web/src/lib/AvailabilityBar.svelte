<script>
  // TargetAvailabilityBar (UI/NightTimelineView.swift): the target's night on
  // the sunset–sunrise axis. Its altitude as a faint line, its usable windows,
  // a tick where it's highest, and optionally a planned block spotlit: solid,
  // standing proud of the bar, with the rest of the night dimmed behind it.
  import { scoreColor } from './palette.js';

  let { night, target, height = 26, highlight = null } = $props();

  const start = $derived(Date.parse(night.chartWindow.start));
  const span = $derived(Date.parse(night.chartWindow.end) - start);
  const percent = t => Math.min(100, Math.max(0, ((Date.parse(t) - start) / span) * 100));

  // In a 100 × 100 box, stretched to the bar.
  const altitude = $derived.by(() => {
    const trace = target.altitudeTrace ?? [];
    if (trace.length < 2) return '';
    return trace.map((a, i) => `${(i / (trace.length - 1)) * 100},${100 - Math.min(1, Math.max(0, a / 90)) * 100}`).join(' ');
  });
  const best = $derived(target.bestTime ? percent(target.bestTime) : null);
</script>

<div class="bar" class:spotlit={highlight} style:height="{height}px" aria-hidden="true">
  <div class="track">
  {#if altitude}
    <svg viewBox="0 0 100 100" preserveAspectRatio="none">
      <polyline points={altitude} fill="none" stroke="rgba(255,255,255,0.28)" stroke-width="1" vector-effect="non-scaling-stroke" />
    </svg>
  {/if}
  {#each target.windows as w}
    <span class="window" style:left="{percent(w.start)}%" style:width="{percent(w.end) - percent(w.start)}%"
          style:background={scoreColor(target.score, highlight ? 0.25 : 0.55)}></span>
  {/each}
  {#if best != null && best > 0 && best < 100}
    <span class="best" style:left="{best}%" style:background={scoreColor(target.score)}></span>
  {/if}
  </div>
  {#if highlight}
    <span class="planned" style:left="{percent(highlight.start)}%" style:width="{percent(highlight.end) - percent(highlight.start)}%"
          style:background={scoreColor(target.score)}></span>
  {/if}
</div>

<style>
  .bar { position: relative; }
  .track { position: absolute; inset: 0; border-radius: 3px; background: rgba(255,255,255,0.07); }
  /* Room for the planned block to stand past the track. */
  .spotlit .track { inset: 2px 0; }
  svg { position: absolute; inset: 0; width: 100%; height: 100%; }
  span { position: absolute; top: 0; bottom: 0; }
  .window { border-radius: 3px; min-width: 2px; }
  .best { width: 1.5px; margin-left: -0.75px; }
  .planned { min-width: 3px; border-radius: 3px; border: 1px solid rgba(255, 255, 255, 0.85); box-sizing: border-box; }
</style>
