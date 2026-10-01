<script>
  // PlanStripView, read-only: the night's blocks on the same sunset–sunrise
  // axis as the timeline above it, each in its target's score colour.
  import { scoreColor } from './palette.js';

  let { night, selectedID = null, onselect } = $props();

  const start = $derived(Date.parse(night.chartWindow.start));
  const span = $derived(Date.parse(night.chartWindow.end) - start);
  const percent = t => ((Date.parse(t) - start) / span) * 100;
  const scoreOf = id => night.targets.find(t => t.id === id)?.score ?? 0;
</script>

<div class="strip">
  {#each night.plan as block (block.targetID + block.window.start)}
    {@const score = scoreOf(block.targetID)}
    <button type="button" class="block" class:selected={selectedID === block.targetID}
            class:unshootable={block.unusableMinutes > 0}
            style:left="{percent(block.window.start)}%"
            style:width="{percent(block.window.end) - percent(block.window.start)}%"
            style:background={scoreColor(score, selectedID === block.targetID ? 0.95 : 0.75)}
            style:border-color={selectedID === block.targetID ? 'var(--accent)' : scoreColor(score)}
            title={block.targetName}
            onclick={() => onselect?.(block.targetID)}>
      <span>{block.targetName}</span>
    </button>
  {/each}
</div>

<style>
  .strip { position: relative; height: 38px; border-radius: 6px; background: var(--space-top); border: 1px solid var(--panel-border); }
  .block {
    position: absolute; top: 0; bottom: 0; margin: 0 1.5px; padding: 0 4px;
    border: 1px solid; border-radius: 5px; overflow: hidden; color: rgba(0,0,0,0.82);
    font-size: 11px; font-weight: 600; display: grid; place-items: center; min-width: 2px;
  }
  .block span { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 100%; }
  .block.selected { border-width: 2px; }
  .block.unshootable {
    background-image: repeating-linear-gradient(-45deg, transparent 0 6px, rgba(0,0,0,0.28) 6px 9px);
  }
</style>
