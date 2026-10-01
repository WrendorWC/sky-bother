<script>
  // PlannerWorkspaceView: building a night's session. The night at the top,
  // the session timeline with its blocks to drag and resize, candidates to add
  // on the left and the selected target on the right. Nothing is saved until
  // Done; Cancel discards. A plan becomes yours only when Done saves a change
  // (PlanDraft); Reset to Suggested goes back to the app's own.
  import { planEdit } from '../engine/engine.js';
  import ScoreBadge from './ScoreBadge.svelte';
  import VerdictTag from './VerdictTag.svelte';
  import Timeline from './Timeline.svelte';
  import PlanEditor from './PlanEditor.svelte';
  import TargetRow from './TargetRow.svelte';
  import TargetDetail from './TargetDetail.svelte';
  import * as format from './format.js';

  let { night, nights, timeZone, preferences, onsave, onleave } = $props();

  let draft = $state({ segments: [], blocks: [] });
  let original = $state('[]');
  let selectedBlockID = $state(null);
  let selectedTargetID = $state(null);
  let message = $state('');
  let error = $state('');

  $effect(() => {
    const key = night.planKey;
    planEdit({ planKey: key, op: 'seed', segments: [] }).then(result => {
      draft = { segments: result.segments, blocks: result.blocks };
      original = JSON.stringify(result.segments);
      selectedBlockID = null;
      selectedTargetID = null;
      message = '';
    });
  });

  const dirty = $derived(JSON.stringify(draft.segments) !== original);
  const totalMinutes = $derived(draft.blocks.reduce((sum, b) => sum + (Date.parse(b.window.end) - Date.parse(b.window.start)) / 60000, 0));
  const unshootable = $derived(draft.blocks.reduce((sum, b) => sum + b.unusableMinutes, 0));
  const selectedBlock = $derived(draft.blocks.find(b => b.id === selectedBlockID) ?? null);
  const selectedTarget = $derived(night.targets.find(t => t.id === (selectedBlock?.targetID ?? selectedTargetID)) ?? null);

  function change(next) {
    draft = next;
    error = '';
  }

  function selectBlock(id) {
    selectedBlockID = id;
    if (id) selectedTargetID = draft.blocks.find(b => b.id === id)?.targetID ?? null;
  }

  async function add(target) {
    error = '';
    try {
      const result = await planEdit({ planKey: night.planKey, op: 'add', segments: draft.segments, targetID: target.id });
      draft = { segments: result.segments, blocks: result.blocks };
      selectedBlockID = result.added;
      selectedTargetID = target.id;
      const block = result.blocks.find(b => b.id === result.added);
      message = block ? `Added ${block.targetName}, ${format.time(block.window.start, timeZone)}–${format.time(block.window.end, timeZone)}${block.unusableMinutes > 0 ? ' — part of it is unshootable' : ''}.` : '';
    } catch (e) {
      error = e.message;
    }
  }

  async function removeTarget(id) {
    const result = await planEdit({ planKey: night.planKey, op: 'check', segments: draft.segments.filter(s => s.targetID !== id) });
    draft = { segments: result.segments, blocks: result.blocks };
    if (selectedBlock?.targetID === id) selectedBlockID = null;
  }

  async function removeBlock() {
    if (!selectedBlock) return;
    const result = await planEdit({ planKey: night.planKey, op: 'check', segments: draft.segments.filter(s => s.id !== selectedBlock.id) });
    draft = { segments: result.segments, blocks: result.blocks };
    selectedBlockID = null;
  }

  async function resetToSuggested() {
    const result = await planEdit({ planKey: night.planKey, op: 'suggest', segments: [] });
    draft = { segments: result.segments, blocks: result.blocks };
    selectedBlockID = null;
    resetPending = true;
  }
  // Reset means "follow the suggestion again" (no saved plan), not "save a
  // copy of today's suggestion as mine".
  let resetPending = $state(false);

  function clearDraft() {
    draft = { segments: [], blocks: [] };
    selectedBlockID = null;
    resetPending = false;
  }

  function done() {
    if (resetPending && !dirtyFromSuggestion) onsave(night.planKey, null);
    else if (dirty) onsave(night.planKey, $state.snapshot(draft.segments));
    onleave();
  }
  // After Reset, any further edit makes it yours again.
  let suggestionSnapshot = $state('');
  $effect(() => { if (resetPending && !suggestionSnapshot) suggestionSnapshot = JSON.stringify(draft.segments); });
  const dirtyFromSuggestion = $derived(resetPending && JSON.stringify(draft.segments) !== suggestionSnapshot);

  function cancel() {
    if ((dirty || resetPending) && !confirm('Discard your changes to this plan?')) return;
    onleave();
  }

  function switchNight(key) {
    if ((dirty || resetPending) && !confirm('Discard your changes to this plan?')) return;
    location.hash = `#/plan/${key}`;
  }

  // Candidates: what's usable tonight, best first (the Mac's "Best Score").
  let search = $state('');
  let fitsOnly = $state(false);
  let minimumHours = $state(0);
  let shownCount = $state(60);
  const plannedCount = id => draft.blocks.filter(b => b.targetID === id).length;
  const candidates = $derived.by(() => {
    const q = search.trim().toLowerCase();
    return night.targets.filter(t => {
      if (t.usableMinutes <= 0 && plannedCount(t.id) === 0) return false;
      if (preferences.includeStars === false && t.isStar) return false;
      if (q && !`${t.name} ${t.designation} ${t.typeName}`.toLowerCase().includes(q)) return false;
      if (fitsOnly && (t.needsMosaic || t.fillFraction < 0.1)) return false;
      if (minimumHours && t.usableMinutes < minimumHours * 60) return false;
      return true;
    });
  });

  const isManual = $derived(night.isManualPlan && !resetPending);
  const saveState = $derived(!dirty && !resetPending ? 'No unsaved changes' : 'Unsaved changes');

  // Wide screens get the inspector as a column; narrow ones a drawer.
  const wideQuery = matchMedia('(min-width: 1100px)');
  let wide = $state(wideQuery.matches);
  $effect(() => {
    const changed = () => (wide = wideQuery.matches);
    wideQuery.addEventListener('change', changed);
    return () => wideQuery.removeEventListener('change', changed);
  });
  let drawerID = $state(null);
</script>

<section class="planner">
  <header class="head">
    <ScoreBadge score={night.score} size={52} />
    <div class="title">
      <div class="title-row">
        <select class="night-pick" value={night.planKey} onchange={e => switchNight(e.currentTarget.value)} aria-label="Night">
          {#each nights as n, i}<option value={n.planKey}>{i === 0 ? 'Tonight' : format.fullWeekday(n.planKey)}, {format.dayAndMonth(n.planKey)} · {Math.round(n.score)}</option>{/each}
        </select>
        <VerdictTag verdict={night.verdict} />
      </div>
      <p class="muted-strong">
        {night.bestImagingWindow ? `Best imaging ${format.time(night.bestImagingWindow.start, timeZone)}–${format.time(night.bestImagingWindow.end, timeZone)}` : night.headline}{night.limitation ? ` · Main limitation: ${night.limitation}` : ''}
      </p>
    </div>
    <a class="pill" href="#/sky/{night.planKey}">Sky View</a>
  </header>

  <div class="timeline-area">
    <div class="timeline-head">
      <h3>Session timeline</h3>
      {#if night.dew && night.dew.level !== 'Low'}<span class="dew">● {night.dew.advice}</span>{/if}
      <span class="muted summary" class:warn={unshootable > 0}>
        {draft.blocks.length} block{draft.blocks.length === 1 ? '' : 's'} · {format.duration(totalMinutes)}{unshootable > 0 ? ` · ${format.duration(unshootable)} unshootable` : ''}
      </span>
    </div>
    <Timeline {night} selected={selectedTarget} {timeZone} imperial={preferences.usesImperialUnits} height={110} />
    <PlanEditor {night} {draft} selectedID={selectedBlockID} onchange={change} onselect={selectBlock} {timeZone} />
    {#if selectedBlock}
      <p class="block-line">
        <strong>{selectedBlock.targetName}</strong> {format.time(selectedBlock.window.start, timeZone)}–{format.time(selectedBlock.window.end, timeZone)}
        {#if selectedBlock.unusableMinutes > 0}<span class="warn"> · {format.duration(selectedBlock.unusableMinutes)} unshootable</span>{/if}
        <button type="button" class="link" onclick={removeBlock}>Remove block</button>
      </p>
    {:else}
      <p class="muted">Drag a block to move it, or an edge to resize. Tap a block to select it; arrow keys nudge it. Hatching marks unshootable time.</p>
    {/if}
    {#if message}<p class="muted">{message}</p>{/if}
    {#if error}<p class="error">{error}</p>{/if}
  </div>

  <div class="lower" class:wide>
    <div class="candidates">
      <div class="filters">
        <input type="search" placeholder="Search targets" bind:value={search} />
        <label class="check"><input type="checkbox" bind:checked={fitsOnly} /> Fits my frame</label>
        <select bind:value={minimumHours} aria-label="Usable for at least">
          <option value={0}>Any usable time</option>
          {#each [1, 2, 3] as h}<option value={h}>At least {h}h</option>{/each}
        </select>
        <span class="muted">{candidates.length} targets</span>
      </div>
      <ul>
        {#each candidates.slice(0, shownCount) as target (target.id)}
          {@const count = plannedCount(target.id)}
          <li class:picked={target.id === selectedTarget?.id}>
            <TargetRow {night} {target} {timeZone} selected={target.id === selectedTarget?.id}
                       onselect={id => { selectedTargetID = id; selectedBlockID = null; }}
                       onopen={id => (wide ? (selectedTargetID = id) : (drawerID = id))} />
            <div class="row-actions">
              {#if count}
                <span class="planned">✓ Planned{count > 1 ? ` ×${count}` : ''}</span>
                <button type="button" class="small" onclick={() => removeTarget(target.id)} aria-label="Remove {target.displayName} from the plan">✕</button>
              {/if}
              <button type="button" class="add" onclick={() => add(target)}>+ Add</button>
            </div>
          </li>
        {/each}
      </ul>
      {#if candidates.length > shownCount}<button type="button" class="more" onclick={() => (shownCount += 120)}>Show more</button>{/if}
    </div>
    {#if wide}
      <div class="inspector">
        {#if selectedTarget}
          <TargetDetail {night} targetID={selectedTarget.id} {timeZone} inline />
        {:else}
          <div class="pick panel"><p><strong>Pick a candidate</strong></p><p class="muted">Select a target to see how it fits this night.</p></div>
        {/if}
      </div>
    {/if}
  </div>

  <footer class="actions">
    <span class="badge">{isManual ? 'Manual' : 'Suggested'}</span>
    <span class="muted">{saveState}</span>
    <span class="spacer"></span>
    {#if night.isManualPlan && !resetPending}<button type="button" class="link" onclick={resetToSuggested}>Reset to Suggested</button>{/if}
    <button type="button" class="link" onclick={clearDraft} disabled={!draft.blocks.length}>Clear</button>
    <button type="button" onclick={cancel}>Cancel</button>
    <button type="button" class="primary" onclick={done}>Done</button>
  </footer>
</section>

{#if drawerID}
  <TargetDetail {night} targetID={drawerID} {timeZone} onclose={() => (drawerID = null)} />
{/if}

<style>
  .planner { display: grid; gap: 14px; min-width: 0; padding-bottom: 72px; }
  .head { display: flex; gap: 14px; align-items: center; flex-wrap: wrap; }
  .title { flex: 1; min-width: 0; display: grid; gap: 4px; }
  .title-row { display: flex; gap: 10px; align-items: center; flex-wrap: wrap; }
  .night-pick { font-size: 20px; font-weight: 700; background: none; border-color: transparent; padding: 2px 4px; max-width: 100%; }
  p { margin: 0; }
  .pill { padding: 8px 14px; border-radius: 999px; border: 1px solid var(--panel-border); color: var(--accent); text-decoration: none; font-weight: 600; background: var(--panel); }
  .timeline-area { display: grid; gap: 8px; }
  .timeline-head { display: flex; gap: 12px; align-items: baseline; flex-wrap: wrap; }
  h3 { margin: 0; font-size: 13px; text-transform: uppercase; letter-spacing: 0.06em; color: var(--accent); }
  .dew { color: var(--poor); font-size: 13px; }
  .summary { margin-left: auto; }
  .warn { color: var(--marginal); }
  .block-line { display: flex; gap: 8px; align-items: baseline; flex-wrap: wrap; }
  .link { background: none; border: none; padding: 0; color: var(--accent); font-weight: 600; }
  .lower { display: grid; gap: 16px; }
  .lower.wide { grid-template-columns: minmax(0, 1.4fr) minmax(320px, 1fr); align-items: start; }
  .candidates { display: grid; gap: 8px; min-width: 0; }
  .filters { display: flex; gap: 8px 12px; flex-wrap: wrap; align-items: center; }
  .filters input[type='search'] { flex: 1 1 200px; }
  .check { display: flex; gap: 6px; align-items: center; color: var(--muted); }
  .check input { accent-color: var(--accent); }
  ul { list-style: none; margin: 0; padding: 0; display: grid; gap: 4px; }
  li { display: flex; gap: 8px; align-items: center; border-radius: 10px; background: var(--panel); border: 1.5px solid var(--panel-border); }
  li.picked { background: rgba(158, 133, 250, 0.16); border-color: var(--accent); }
  li > :global(.row), li > :global(.row.selected) { flex: 1; min-width: 0; border: none; background: none; }
  .row-actions { display: flex; gap: 6px; align-items: center; padding-right: 10px; flex: none; }
  .planned { color: var(--accent); font-size: 13px; font-weight: 600; white-space: nowrap; }
  .small { width: 32px; height: 32px; padding: 0; }
  .add { color: var(--accent); font-weight: 600; white-space: nowrap; }
  .more { justify-self: center; }
  .inspector { position: sticky; top: 76px; }
  .pick { padding: 28px; text-align: center; display: grid; gap: 6px; }
  .actions {
    position: fixed; left: 0; right: 0; bottom: 0; z-index: 5; display: flex; gap: 12px; align-items: center;
    padding: 12px max(16px, calc((100vw - 1760px) / 2 + 16px)); background: var(--space-top); border-top: 1px solid var(--panel-border);
  }
  .badge { font-size: 12px; color: var(--muted); border: 1px solid var(--panel-border); border-radius: 999px; padding: 2px 9px; }
  .spacer { flex: 1; }
  .primary { background: var(--accent); border-color: var(--accent); color: #120e22; font-weight: 700; padding: 8px 18px; }
  @media (max-width: 600px) {
    .head { flex-wrap: nowrap; align-items: flex-start; }
    .night-pick { font-size: 17px; }
    .pill { display: none; }
    .actions .muted { display: none; }
    .row-actions .planned { display: none; }
  }
</style>
