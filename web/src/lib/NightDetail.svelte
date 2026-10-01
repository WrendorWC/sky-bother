<script>
  // NightDetailView: is this night worth it? The summary, the numbers, the
  // timeline, the app's suggested plan and the best of the rest.
  import ScoreBadge from './ScoreBadge.svelte';
  import VerdictTag from './VerdictTag.svelte';
  import MoonDisc from './MoonDisc.svelte';
  import Timeline from './Timeline.svelte';
  import PlanStrip from './PlanStrip.svelte';
  import TargetRow from './TargetRow.svelte';
  import AvailabilityBar from './AvailabilityBar.svelte';
  import Thumbnail from './Thumbnail.svelte';
  import TargetDetail from './TargetDetail.svelte';
  import FactorBar from './FactorBar.svelte';
  import { scoreColor, dewColor } from './palette.js';
  import * as format from './format.js';

  let { night, isTonight, timeZone, preferences, targetID = null } = $props();

  const imperial = $derived(preferences.usesImperialUnits);
  const usable = $derived(night.targets.filter(t => t.usableMinutes > 0));
  const best = $derived(usable.find(t => !t.isStar));

  // The best target starts selected, so the timeline shows something to
  // shoot rather than an empty sky; a new night starts over.
  let chosenID = $state(null);
  let chosenFor = $state(null);
  const selectedID = $derived(chosenFor === night.planKey ? chosenID : (night.plan[0]?.targetID ?? best?.id ?? null));
  const selected = $derived(night.targets.find(t => t.id === selectedID) ?? null);

  function select(id) {
    chosenID = id;
    chosenFor = night.planKey;
  }

  // A wide screen keeps the selected target's details in a column of their
  // own, as the Mac's wide layout does; narrower ones open them in a drawer.
  const wideQuery = matchMedia('(min-width: 1360px)');
  let wide = $state(wideQuery.matches);
  $effect(() => {
    const changed = () => (wide = wideQuery.matches);
    wideQuery.addEventListener('change', changed);
    return () => wideQuery.removeEventListener('change', changed);
  });

  // A target's link selects it (and, on a wide screen, shows it in the column).
  $effect(() => {
    if (targetID && night.targets.some(t => t.id === targetID)) select(targetID);
  });

  /** The target's details, at its own link; selects it too. */
  function open(id) {
    select(id);
    location.hash = `#/${night.planKey}/${encodeURIComponent(id)}`;
  }

  function closeDetail() {
    location.hash = `#/${night.planKey}`;
  }

  const planned = $derived(new Set(night.plan.map(b => b.targetID)));
  const others = $derived(usable.filter(t => !planned.has(t.id) && !t.isStar && t.score >= preferences.minimumScore));
  let showsAll = $state(false);
  const listed = $derived(showsAll ? usable.filter(t => !planned.has(t.id)) : others.slice(0, 8));

  const summaryLine = $derived(night.bestImagingWindow && Date.parse(night.bestImagingWindow.end) > Date.parse(night.bestImagingWindow.start)
    ? `Best imaging ${format.time(night.bestImagingWindow.start, timeZone)}–${format.time(night.bestImagingWindow.end, timeZone)}`
    : night.headline);

  const darkWindow = $derived(night.astronomicalDusk && night.astronomicalDawn
    ? `${format.time(night.astronomicalDusk, timeZone)}–${format.time(night.astronomicalDawn, timeZone)}`
    : night.darkHours > 0 ? format.hours(night.darkHours) : 'none');

  const planMinutes = $derived(night.plan.reduce((sum, b) => sum + (Date.parse(b.window.end) - Date.parse(b.window.start)) / 60000, 0));
  const unshootable = $derived(night.plan.reduce((sum, b) => sum + b.unusableMinutes, 0));
  const scoreOf = id => night.targets.find(t => t.id === id);

  let showsScore = $state(false);
  const cap = $derived(night.cappedBy ? night.targets.find(t => t.id === night.cappedBy) : null);
</script>

<div class="night-layout" class:wide>
<article class="detail">
  <section class="panel summary">
    <ScoreBadge score={night.score} size={58} />
    <div class="summary-body">
      <div class="headline">
        <h2>{format.longDate(night.planKey)}</h2>
        <VerdictTag verdict={night.verdict} />
        {#if night.isCloudedOut}<span class="clouded" title="The forecast writes this night off.">Clouded Out</span>{/if}
      </div>
      <p class="muted-strong">{summaryLine}</p>
      {#if best}
        <button type="button" class="best" onclick={() => open(best.id)}>
          <span class="label">{night.isCloudedOut ? 'If it clears' : 'Best target'}</span>
          {best.displayName} · {Math.round(best.score)} <span class="chevron">›</span>
        </button>
      {/if}
      {#if night.limitation}<p class="muted-strong limitation">ⓘ Main limitation: {night.limitation}</p>{/if}
      <!-- Carries a target you picked on this night (not the default one). -->
      <a class="sky-link" href="#/sky/{night.planKey}{chosenFor === night.planKey && chosenID ? `/${encodeURIComponent(chosenID)}` : ''}">
        <svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9" /><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18" /></svg>
        Open Sky View
      </a>
    </div>
  </section>

  <dl class="stats">
    <div><dt>Astronomical dark</dt><dd>{darkWindow}</dd></div>
    <div><dt>Moon down</dt><dd>{night.moonlessDarkHours > 0.02 ? format.hours(night.moonlessDarkHours) : 'none'}</dd></div>
    <div><dt>Moon</dt><dd><MoonDisc fraction={night.moonIlluminatedFraction} waxing={night.moonIsWaxing} size={14} />
      {Math.round(night.moonIlluminatedFraction * 100)}% {night.moonPhase.toLowerCase()}</dd></div>
    {#if night.hasWeather}
      <div><dt>Cloud in the dark</dt><dd>{night.meanCloudDuringDark != null ? `${Math.round(night.meanCloudDuringDark)}%` : '—'}</dd></div>
      <div><dt>Low</dt><dd>{format.temperature(night.minimumTemperature, imperial)}</dd></div>
      {#if night.dew}
        <div title={night.dew.advice}><dt>Dew risk</dt>
          <dd><span class="dot" style:background={dewColor(night.dew.level)}></span>{night.dew.level}{night.dew.level !== 'Low' ? ` · ${night.dew.when}` : ''}</dd></div>
      {/if}
      <div><dt>Gusts</dt><dd>{format.wind(night.maximumGust, imperial)}</dd></div>
    {/if}
  </dl>

  <Timeline {night} {selected} {timeZone} {imperial} height={168} />

  <ul class="legend muted">
    <li><span class="swatch" style:background="rgba(219, 227, 240, 0.7)"></span>cloud from the top · sky dulls past your {Math.round(preferences.maximumCloudCover)}% cloud limit</li>
    <li><span class="swatch" style:background="rgba(250, 237, 189, 0.8)"></span>moonlight and its altitude</li>
    <li><span class="swatch" style:background="rgb(6, 8, 19)"></span>darker background = darker sky</li>
    {#if selected}<li><span class="swatch" style:background="var(--accent)"></span>{selected.displayName}'s altitude · shaded box = its best window</li>{/if}
  </ul>

  <section class="why">
    <button type="button" class="disclosure" onclick={() => (showsScore = !showsScore)} aria-expanded={showsScore}>
      <h3>{showsScore ? '▾' : '▸'} Why this score</h3>
    </button>
    {#if showsScore}
      <div class="panel why-body">
        {#each night.factors as factor}<FactorBar {factor} />{/each}
        {#if cap}
          <p class="cap">
            The sky alone scores {Math.round(night.skyScore)}, but the night is capped at {Math.round(night.score)} by its best
            target, <button type="button" class="inline-link" onclick={() => open(cap.id)}>{cap.displayName}</button>:
            a night is only as good as the best thing you can shoot on it.
          </p>
        {/if}
      </div>
    {/if}
  </section>

  <section class="plan">
    <header>
      <h3>{isTonight ? 'Tonight’s plan' : `${format.fullWeekday(night.planKey)}’s plan`}</h3>
      <span class="badge">Suggested</span>
      {#if night.plan.length}
        <span class="muted" class:warn={unshootable > 0}>
          {night.plan.length} block{night.plan.length === 1 ? '' : 's'} · {format.duration(planMinutes)}{unshootable > 0 ? ` · ${format.duration(unshootable)} unshootable` : ''}
        </span>
      {/if}
    </header>

    {#if !night.plan.length}
      <p class="muted-strong">{night.isCloudedOut ? 'Clouded out — nothing to plan.' : 'Nothing clears your minimum score for long enough on this night.'}</p>
    {:else}
      {#if night.plan.length > 1}<PlanStrip {night} selectedID={selectedID} onselect={select} />{/if}
      <ol class="panel blocks">
        {#each night.plan as block (block.targetID + block.window.start)}
          {@const target = scoreOf(block.targetID)}
          <li class:selected={selectedID === block.targetID}>
            <button type="button" class="block" class:selected={selectedID === block.targetID} onclick={() => select(block.targetID)}>
              <ScoreBadge score={target?.score ?? 0} size={30} />
              <div class="block-body">
                <strong>{block.targetName}</strong>
                {#if !target}
                  <span class="warn">⚠︎ Not up, dark or clear at all this night</span>
                {:else if block.unusableMinutes > 0}
                  <span class="warn">⚠︎ {format.duration(block.unusableMinutes)} unshootable</span>
                {:else}
                  <span class="muted">{target.framingNote}</span>
                {/if}
                <!-- The target's whole night, this block outlined: planned
                     targets leave the other-targets list, and its bar with them. -->
                {#if target}<div class="block-bar"><AvailabilityBar {night} {target} height={16} highlight={block.window} /></div>{/if}
              </div>
              <div class="times muted">
                <span>{format.time(block.window.start, timeZone)}–{format.time(block.window.end, timeZone)}</span>
                <span>{format.duration((Date.parse(block.window.end) - Date.parse(block.window.start)) / 60000)}</span>
              </div>
            </button>
            {#if target}
              <button type="button" class="thumb-button" onclick={() => open(block.targetID)} aria-label="Details for {block.targetName}">
                <Thumbnail designation={target.designation} size={44} label={block.targetName} />
              </button>
            {/if}
          </li>
        {/each}
      </ol>
    {/if}
  </section>

  {#if listed.length}
    <section class="others">
      <h3>{showsAll ? 'Everything up tonight' : night.isCloudedOut ? 'If it clears' : 'Other targets of interest'}</h3>
      <div class="panel target-list">
        {#each listed as target (target.id)}
          <TargetRow {night} {target} {timeZone} selected={selectedID === target.id} onselect={select} onopen={open} />
        {/each}
      </div>
      <button type="button" class="link" onclick={() => (showsAll = !showsAll)}>
        {showsAll ? 'Show fewer' : `Show all ${usable.length - planned.size} targets up tonight`}
      </button>
    </section>
  {/if}
</article>

{#if wide && selected}
  <TargetDetail {night} targetID={selected.id} {timeZone} inline />
{:else if !wide && targetID}
  <TargetDetail {night} {targetID} {timeZone} onclose={closeDetail} />
{/if}
</div>

<style>
  .night-layout { display: grid; gap: 24px; }
  .night-layout.wide { grid-template-columns: minmax(0, 1fr) 380px; align-items: start; }
  .detail { display: grid; gap: 14px; min-width: 0; }
  .summary { display: flex; gap: 16px; align-items: center; padding: 16px; border-radius: 14px; }
  .summary-body { display: grid; gap: 6px; min-width: 0; }
  .headline { display: flex; gap: 9px; align-items: center; flex-wrap: wrap; }
  h2 { margin: 0; font-size: 22px; }
  p { margin: 0; }
  .clouded {
    font-size: 12px; font-weight: 600; color: var(--marginal); padding: 2px 7px;
    border-radius: 999px; background: rgba(242, 179, 61, 0.15);
  }
  .sky-link {
    justify-self: start; display: inline-flex; gap: 6px; align-items: center; margin-top: 4px;
    color: var(--accent); text-decoration: none; font-weight: 600;
  }
  .sky-link svg { width: 18px; height: 18px; fill: none; stroke: currentColor; stroke-width: 1.6; }
  .best { justify-self: start; display: flex; gap: 6px; align-items: baseline; padding: 0; background: none; border: none; font-weight: 500; }
  .best .label { color: var(--accent); font-size: 12px; font-weight: 600; }
  .chevron { color: var(--accent); }
  .stats { display: flex; flex-wrap: wrap; gap: 12px 26px; margin: 0; }
  .stats div { display: grid; gap: 1px; }
  dt { font-size: 12px; color: var(--muted); }
  dd { margin: 0; font-weight: 600; display: flex; align-items: center; gap: 5px; }
  .dot { width: 8px; height: 8px; border-radius: 50%; }
  .legend { list-style: none; padding: 0; margin: -6px 0 0; display: flex; flex-wrap: wrap; gap: 6px 16px; }
  .legend li { display: flex; align-items: center; gap: 6px; }
  .swatch { width: 10px; height: 10px; border-radius: 3px; border: 1px solid rgba(255,255,255,0.15); }
  .plan, .others, .why { display: grid; gap: 8px; }
  .disclosure { justify-self: start; background: none; border: none; padding: 0; }
  .why-body { padding: 12px 14px; display: grid; gap: 4px; }
  .cap { margin: 4px 0 0; color: var(--muted); }
  .inline-link { background: none; border: none; padding: 0; color: var(--accent); font: inherit; }
  .plan header { display: flex; gap: 10px; align-items: baseline; flex-wrap: wrap; }
  h3 { margin: 0; font-size: 13px; text-transform: uppercase; letter-spacing: 0.06em; color: var(--accent); }
  .badge { font-size: 11px; color: var(--muted); border: 1px solid var(--panel-border); border-radius: 999px; padding: 0 7px; }
  .blocks { list-style: none; margin: 0; padding: 0; overflow: hidden; }
  .blocks li { display: flex; align-items: center; }
  .blocks li + li { border-top: 1px solid var(--divider); }
  .thumb-button { padding: 0; margin-right: 12px; border: none; background: none; border-radius: 8px; }
  .block {
    display: flex; gap: 12px; align-items: center; flex: 1; min-width: 0; text-align: left;
    padding: 8px 12px; background: none; border: none; border-radius: 0; box-shadow: inset 0 0 0 transparent;
  }
  .block:hover { background: rgba(158, 133, 250, 0.07); }
  .block.selected { box-shadow: inset 3px 0 0 var(--accent); }
  .blocks li.selected { background: rgba(158, 133, 250, 0.18); }
  .block-body { flex: 1; min-width: 0; display: grid; gap: 2px; }
  .block-bar { margin-top: 2px; }
  .block-body > span { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .times { display: grid; justify-items: end; font-variant-numeric: tabular-nums; white-space: nowrap; }
  .warn { color: var(--marginal); font-size: 13px; }
  .target-list { padding: 4px; display: grid; gap: 2px; }
  .link { justify-self: start; background: none; border: none; padding: 0; color: var(--accent); font-weight: 600; }

  @media (max-width: 560px) {
    .summary { align-items: flex-start; padding: 14px; gap: 12px; }
    h2 { font-size: 19px; }
  }
</style>
