<script>
  // TargetDetailView: one target on one night. Its score and why, when it's
  // up, how it sits in your frame, and what's worth knowing. The words come
  // from the engine (EngineAPI.targetDetail), the same functions the Mac
  // app's panel uses.
  import { targetDetail } from '../engine/engine.js';
  import ScoreBadge from './ScoreBadge.svelte';
  import VerdictTag from './VerdictTag.svelte';
  import FactorBar from './FactorBar.svelte';
  import FramePreview from './FramePreview.svelte';
  import { targetImage } from './images.js';
  import { verdictColor, verdictFor } from './palette.js';
  import { time, degrees, weekday, dayAndMonth, hours } from './format.js';

  // `inline`: a permanent column on a wide screen, not a drawer.
  // `nights`, when given, lets the panel point to a better night this week.
  let { night, targetID, timeZone, onclose = null, inline = false, nights = null } = $props();

  let detail = $state(null);
  let error = $state('');
  let showsTechnical = $state(false);

  // Fetched again whenever the night is re-planned (a new `night` object).
  $effect(() => {
    const request = { planKey: night.planKey, targetID };
    error = '';
    targetDetail(request).then(d => (detail = d), e => (error = e.message));
  });

  const image = $derived(detail && targetImage(detail.designation));
  const blocks = $derived(night.plan.filter(b => b.targetID === targetID));

  // "Better on Sunday", as the Mac's catalogue card says: the week's best
  // night for this target, when it isn't this one.
  const better = $derived.by(() => {
    if (!nights) return null;
    const here = night.targets.find(t => t.id === targetID && t.usableMinutes > 0)?.score ?? -1;
    let best = null;
    nights.forEach((n, i) => {
      const t = n.targets.find(t => t.id === targetID && t.usableMinutes > 0);
      if (t && n.planKey !== night.planKey && t.score > here + 0.5 && (!best || t.score > best.target.score)) {
        best = { night: n, target: t, name: `${i === 0 ? 'tonight' : weekday(n.planKey)} ${dayAndMonth(n.planKey)}` };
      }
    });
    return best;
  });

  function onkeydown(event) {
    if (event.key === 'Escape' && !inline) onclose?.();
  }

</script>

<svelte:window {onkeydown} />

{#if !inline}<div class="backdrop" onclick={onclose} aria-hidden="true"></div>{/if}
<aside class="drawer" class:inline aria-label="Target details">
  {#if inline}
    <h3 class="column-title">Selected target</h3>
  {:else}
    <button type="button" class="close" onclick={onclose} aria-label="Close">✕</button>
  {/if}
  {#if error}
    <p class="error">{error}</p>
  {:else if detail}
    <header>
      <div>
        <h2>{detail.displayName}</h2>
        <p class="muted-strong">{detail.subtitle}</p>
      </div>
      {#if detail.scored}<ScoreBadge score={detail.score} size={50} />{/if}
    </header>
    <div class="verdict-row">
      {#if detail.scored}<VerdictTag verdict={detail.verdict} />{/if}
      <span class="muted-strong">{detail.recommendation}</span>
    </div>
    <p class="sentence">{detail.verdictSentence}</p>
    {#if better}
      <p class="better">Better on {better.name} · {Math.round(better.target.score)} {verdictFor(better.target.score)} · {hours(better.target.usableMinutes / 60)} usable</p>
    {/if}

    {#if blocks.length}
      <p class="planned">✓ Planned · {blocks.map(b => `${time(b.window.start, timeZone)}–${time(b.window.end, timeZone)}`).join(', ')}</p>
    {/if}

    {#if detail.scored}
    <section>
      <h3>Through the night</h3>
      {#if detail.transitTime}<p class="muted-strong">Highest at {time(detail.transitTime, timeZone)} · {degrees(detail.maximumAltitude)}</p>{/if}
      {#if detail.bestWindow}
        <p class="muted-strong">Best window {time(detail.bestWindow.start, timeZone)}–{time(detail.bestWindow.end, timeZone)}</p>
      {/if}
      {#if detail.zenithRisk}
        <p class="warn">⚠︎ Zenith risk {time(detail.zenithRisk.start, timeZone)}–{time(detail.zenithRisk.end, timeZone)}</p>
      {/if}
    </section>
    {/if}

    <section>
      <h3>In your frame</h3>
      <FramePreview target={detail} />
      <a class="browse" href="#/browse/{encodeURIComponent(detail.designation)}">Explore around it in Sky Browser ›</a>
      {#if image}
        <img class="photo" src={image.url} alt={detail.displayName} />
      {/if}
      {#if detail.framingNote}<p>{detail.framingNote}</p>{/if}
      {#if detail.samplingNote}<p class="muted">{detail.samplingNote}</p>{/if}
      <p class="muted faint">{detail.rigSummary}</p>
      {#if image}
        {#if image.sourceURL}
          <a class="credit" href={image.sourceURL} target="_blank" rel="noopener">{image.credit}</a>
        {:else}
          <p class="muted faint">{image.credit}</p>
        {/if}
      {/if}
    </section>

    {#if detail.whyNot.length}
      <section>
        <h3>Why not recommended</h3>
        {#each detail.whyNot as line}<p class="warn">⚠︎ {line}</p>{/each}
      </section>
    {/if}

    {#if detail.warnings.length}
      <section>
        <h3>Worth knowing</h3>
        {#each detail.warnings as line}<p class="warn">⚠︎ {line}</p>{/each}
      </section>
    {/if}

    {#if detail.facts.length}
      <section>
        <h3>Did you know</h3>
        <ul class="facts">{#each detail.facts as fact}<li>{fact}</li>{/each}</ul>
      </section>
    {/if}

    {#if detail.scored}
    <section>
      <h3>Why this score</h3>
      {#each detail.factors as factor}<FactorBar {factor} />{/each}
      {#if detail.filterNote}<p class="muted">{detail.filterNote}</p>{/if}
    </section>
    {/if}

    <section>
      <button type="button" class="disclosure" onclick={() => (showsTechnical = !showsTechnical)} aria-expanded={showsTechnical}>
        <h3>{showsTechnical ? '▾' : '▸'} Technical details</h3>
      </button>
      {#if showsTechnical}
        <dl class="numbers">
          {#each detail.numbers as number}<dt>{number.label}</dt><dd>{number.value}</dd>{/each}
        </dl>
      {/if}
    </section>
  {:else}
    <p class="muted">Loading…</p>
  {/if}
</aside>

<style>
  .backdrop { position: fixed; inset: 0; background: rgba(0, 0, 0, 0.45); z-index: 10; }
  .drawer {
    position: fixed; top: 0; right: 0; bottom: 0; z-index: 11; width: min(440px, 100vw);
    overflow-y: auto; padding: 20px 20px 40px; display: grid; gap: 16px; align-content: start;
    background: linear-gradient(var(--space-top), var(--space-bottom)); border-left: 1px solid var(--panel-border);
    box-shadow: -12px 0 40px rgba(0, 0, 0, 0.4);
  }
  .drawer.inline {
    position: sticky; top: 72px; z-index: auto; width: auto; max-height: calc(100vh - 88px);
    padding: 16px; border: 1px solid var(--panel-border); border-radius: 14px; box-shadow: none;
    background: var(--panel);
  }
  .inline header { padding-right: 0; }
  .column-title { margin: 0; }
  .close { position: absolute; top: 12px; right: 12px; width: 32px; height: 32px; padding: 0; border-radius: 50%; }
  header { display: flex; justify-content: space-between; align-items: flex-start; gap: 12px; padding-right: 40px; }
  h2 { margin: 0; font-size: 22px; }
  h3 { margin: 0 0 6px; font-size: 13px; text-transform: uppercase; letter-spacing: 0.06em; color: var(--accent); }
  p { margin: 0; }
  section { display: grid; gap: 5px; }
  .verdict-row { display: flex; gap: 9px; align-items: center; flex-wrap: wrap; margin-top: -6px; }
  .sentence { font-weight: 500; }
  .planned { color: var(--accent); font-weight: 600; }
  .better { color: var(--accent); }
  .warn { color: var(--marginal); }
  .photo { width: 100%; max-height: 300px; object-fit: cover; border-radius: 10px; border: 1px solid var(--panel-border); }
  .faint { color: var(--tertiary); }
  .credit { font-size: 13px; }
  .facts { margin: 0; padding-left: 18px; color: var(--muted); display: grid; gap: 4px; }
  .facts li::marker { color: var(--accent); }
  .disclosure { background: none; border: none; padding: 0; text-align: left; }
  .numbers { display: grid; grid-template-columns: auto 1fr; gap: 4px 16px; margin: 0; font-size: 14px; }
  dt { color: var(--muted); }
  dd { margin: 0; font-variant-numeric: tabular-nums; }
  .browse { justify-self: start; color: var(--accent); font-weight: 600; text-decoration: none; font-size: 14px; }
</style>
