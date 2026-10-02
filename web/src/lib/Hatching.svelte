<script>
  // PlanStripView.drawHatching: diagonal stripes over just the parts of a
  // block that can't be shot (diagonals rather than a wash, so they read over
  // any score colour). Sits inside the block, positioned against its window.
  let { block } = $props();
  const start = $derived(Date.parse(block.window.start));
  const span = $derived(Date.parse(block.window.end) - start);
</script>

{#each block.unusable ?? [] as fragment}
  <span class="hatching" aria-hidden="true"
        style:left="{Math.max(0, (Date.parse(fragment.start) - start) / span) * 100}%"
        style:right="{Math.max(0, 1 - (Date.parse(fragment.end) - start) / span) * 100}%"></span>
{/each}

<style>
  .hatching {
    position: absolute; top: 0; bottom: 0; pointer-events: none;
    background-image: repeating-linear-gradient(-45deg, transparent 0 3px, rgba(0, 0, 0, 0.45) 3px 5px);
  }
</style>
