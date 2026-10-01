<script>
  // TargetRowView: score, name and type, when it's up across the night, and
  // a line of numbers.
  import ScoreBadge from './ScoreBadge.svelte';
  import AvailabilityBar from './AvailabilityBar.svelte';
  import Thumbnail from './Thumbnail.svelte';
  import { time, degrees } from './format.js';

  let { night, target, timeZone, selected = false, onselect, onopen } = $props();

  const summary = $derived(
    [target.bestTime && `${time(target.bestTime, timeZone)} best`, `${degrees(target.maximumAltitude)} peak`,
     `${Math.round(target.fillFraction * 100)}% frame`].filter(Boolean).join(' · '));
</script>

<div class="row" class:selected>
  <button type="button" class="main" onclick={() => onselect?.(target.id)}>
  <ScoreBadge score={target.score} size={40} />
  <div class="body">
    <div class="title">
      <strong>{target.displayName}</strong>
      {#if target.commonName}<span class="muted">{target.designation}</span>{/if}
      <span class="type">{target.typeName}</span>
    </div>
    <AvailabilityBar {night} {target} />
    <div class="muted numbers">
      {summary}
      {#if target.zenithRisk}<span class="warning" title="Zenith risk from {time(target.zenithRisk.start, timeZone)}">⚠︎</span>{/if}
    </div>
  </div>
</button>
  <button type="button" class="thumb-button" onclick={() => onopen?.(target.id)} aria-label="Details for {target.displayName}">
    <Thumbnail designation={target.designation} size={56} label={target.displayName} />
  </button>
</div>

<style>
  .row { display: flex; gap: 8px; align-items: flex-start; padding-right: 8px; border: 1.5px solid transparent; border-radius: 8px; }
  .main {
    display: flex; gap: 13px; align-items: flex-start; flex: 1; min-width: 0; text-align: left;
    padding: 8px; border: none; border-radius: 8px; background: none;
  }
  .thumb-button { padding: 0; margin-top: 8px; border: none; background: none; border-radius: 8px; }
  .row:hover { background: rgba(158, 133, 250, 0.07); }
  .row.selected { background: rgba(158, 133, 250, 0.18); border-color: var(--accent); }
  .body { flex: 1; min-width: 0; display: grid; gap: 6px; }
  .title { display: flex; gap: 7px; align-items: baseline; flex-wrap: wrap; }
  .type { font-size: 12px; color: var(--tertiary); }
  .numbers { font-variant-numeric: tabular-nums; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .warning { color: var(--marginal); margin-left: 4px; }
</style>
