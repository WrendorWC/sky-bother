<script>
  // PlanStripView in editing mode: the night's blocks on the sunset–sunrise
  // axis. Drag a block to move it, an edge to resize it; a block dragged into
  // its neighbour shortens it, and pushed far enough the two swap. Every step
  // of a drag is worked out by the engine (SessionPlanRules, as on the Mac),
  // from the layout the drag began with; a step it refuses just leaves the
  // last good one showing. Tap a block to select it.
  import { planEdit } from '../engine/engine.js';
  import { scoreColor } from './palette.js';
  import { time } from './format.js';

  let { night, draft, selectedID = null, onchange, onselect, timeZone } = $props();

  let strip;
  let width = $state(0);
  let preview = $state(null);  // blocks while dragging
  let hover = $state('');      // cursor: 'move', 'edge', 'grabbing'

  const start = $derived(Date.parse(night.chartWindow.start));
  const span = $derived(Date.parse(night.chartWindow.end) - start);
  const shown = $derived(preview ?? draft.blocks);
  const x = t => ((Date.parse(t) - start) / span) * width;
  const scoreOf = id => night.targets.find(t => t.id === id)?.score ?? 0;
  const edge = 12;  // px either side of an end that grabs it

  function gripAt(block, px) {
    const left = x(block.window.start), right = x(block.window.end);
    if (right - left > edge * 3) {
      if (px - left <= edge) return 'start';
      if (right - px <= edge) return 'end';
    }
    return 'move';
  }

  let drag = null;
  let pending = false, queued = null;

  function down(event, block) {
    event.preventDefault();
    const box = strip.getBoundingClientRect();
    drag = { id: block.id, grip: gripAt(block, event.clientX - box.left), from: event.clientX, moved: false, original: draft.segments };
    hover = drag.grip === 'move' ? 'grabbing' : 'edge';
    event.currentTarget.setPointerCapture(event.pointerId);
  }

  function move(event, block) {
    if (!drag) {
      const box = strip.getBoundingClientRect();
      hover = gripAt(block, event.clientX - box.left) === 'move' ? 'move' : 'edge';
      return;
    }
    const dx = event.clientX - drag.from;
    if (Math.abs(dx) > 3) drag.moved = true;
    if (!drag.moved) return;
    request(dx);
  }

  // One engine call at a time; the latest position wins.
  function request(dx) {
    queued = dx;
    if (pending) return;
    pending = true;
    const seconds = (queued / width) * span / 1000;
    queued = null;
    const op = drag.grip === 'move' ? 'move' : 'resize';
    planEdit({ planKey: night.planKey, op, segments: drag.original, id: drag.id, seconds, movingStart: drag.grip === 'start' })
      .then(result => {
        if (drag && result.segments) {
          drag.latest = result;
          preview = result.blocks;
        }
      })
      .finally(() => {
        pending = false;
        if (queued != null && drag) request(queued);
      });
  }

  async function up(event, block) {
    const finished = drag;
    drag = null;
    hover = '';
    if (!finished) return;
    if (!finished.moved) {
      onselect?.(block.id);
      return;
    }
    // Let the last request land before committing.
    while (pending) await new Promise(r => setTimeout(r, 10));
    if (finished.latest) onchange({ segments: finished.latest.segments, blocks: finished.latest.blocks });
    preview = null;
    onselect?.(finished.id);
  }

  // Arrow keys nudge the selected block five minutes, as on the Mac;
  // Shift moves its end, Option its start.
  async function key(event) {
    const block = draft.blocks.find(b => b.id === selectedID);
    if (!block) return;
    if (event.key === 'Backspace' || event.key === 'Delete') {
      event.preventDefault();
      const segments = draft.segments.filter(s => s.id !== block.id);
      const result = await planEdit({ planKey: night.planKey, op: 'check', segments });
      onchange({ segments: result.segments, blocks: result.blocks });
      onselect?.(null);
      return;
    }
    if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
    event.preventDefault();
    const seconds = (event.key === 'ArrowLeft' ? -300 : 300);
    const op = event.shiftKey || event.altKey ? 'resize' : 'move';
    const result = await planEdit({ planKey: night.planKey, op, segments: draft.segments, id: block.id, seconds, movingStart: event.altKey });
    if (result.segments) onchange({ segments: result.segments, blocks: result.blocks });
  }
</script>

<div class="editor" bind:this={strip} bind:clientWidth={width} role="group" aria-label="The plan: drag a block to move it, an edge to resize it"
     style:cursor={hover === 'edge' ? 'ew-resize' : hover === 'grabbing' ? 'grabbing' : hover === 'move' ? 'grab' : 'default'}>
  {#each shown as block (block.id)}
    {@const left = x(block.window.start)}
    {@const w = Math.max(3, x(block.window.end) - left)}
    {@const score = scoreOf(block.targetID)}
    <button type="button" class="block" class:selected={block.id === selectedID} class:unshootable={block.unusableMinutes > 0}
            style:left="{left}px" style:width="{w}px"
            style:background={scoreColor(score, block.id === selectedID ? 0.95 : 0.78)}
            style:border-color={block.id === selectedID ? 'var(--accent)' : scoreColor(score)}
            title="{block.targetName} · {time(block.window.start, timeZone)}–{time(block.window.end, timeZone)}"
            onpointerdown={e => down(e, block)} onpointermove={e => move(e, block)} onpointerup={e => up(e, block)}
            onpointerleave={() => { if (!drag) hover = ''; }} onkeydown={key}>
      {#if w > edge * 3}<span class="grip left"></span><span class="grip right"></span>{/if}
      <span class="name">{block.targetName}</span>
    </button>
  {/each}
  {#if !shown.length}<p class="empty">No blocks yet: add targets from the list below.</p>{/if}
</div>

<style>
  .editor {
    position: relative; height: 56px; border-radius: 8px; touch-action: pan-y;
    background: var(--space-top); border: 2px solid var(--accent);
  }
  .block {
    position: absolute; top: 3px; bottom: 3px; padding: 0 8px; margin: 0;
    border: 1px solid; border-radius: 6px; overflow: hidden; color: rgba(0,0,0,0.85);
    font-size: 13px; font-weight: 600; display: grid; place-items: center; touch-action: none; cursor: inherit;
  }
  .block.selected { border-width: 2px; box-shadow: 0 0 0 2px rgba(158, 133, 250, 0.4); }
  .block.unshootable { background-image: repeating-linear-gradient(-45deg, transparent 0 6px, rgba(0,0,0,0.28) 6px 9px); }
  .name { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 100%; pointer-events: none; }
  .grip { position: absolute; top: 25%; bottom: 25%; width: 2px; border-radius: 1px; background: rgba(0,0,0,0.45); pointer-events: none; }
  .grip.left { left: 5px; }
  .grip.right { right: 5px; }
  .empty { margin: 0; height: 100%; display: grid; place-items: center; color: var(--muted); font-size: 13px; }
</style>
