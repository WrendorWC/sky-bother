<script>
  // SessionModeView: at the scope. What's on now (or next, with a countdown),
  // how far through it you are, the target in your frame and in the sky right
  // now, the conditions, a little about the target, and what comes after —
  // in dim reds, as on the Mac, so a glance doesn't cost your dark adaptation.
  // On a phone it can keep the screen awake.
  import { targetDetail } from '../engine/engine.js';
  import SkyView from './SkyView.svelte';
  import FramePreview from './FramePreview.svelte';
  import ScoreBadge from './ScoreBadge.svelte';
  import { time, duration, longDate, temperature, wind } from './format.js';

  let { night, timeZone, preferences, rig } = $props();

  let now = $state(Date.now());
  $effect(() => {
    const timer = setInterval(() => (now = Date.now()), 1000);
    return () => clearInterval(timer);
  });

  // SessionClock: which block is running, which is next.
  const blocks = $derived([...night.plan].sort((a, b) => Date.parse(a.window.start) - Date.parse(b.window.start)));
  const current = $derived(blocks.find(b => now >= Date.parse(b.window.start) && now < Date.parse(b.window.end)) ?? null);
  const next = $derived(blocks.find(b => Date.parse(b.window.start) > now) ?? null);
  const phase = $derived(!blocks.length ? 'empty' : current ? 'running' : next ? (now < Date.parse(blocks[0].window.start) ? 'notStarted' : 'between') : 'finished');
  const block = $derived(current ?? next);
  const target = $derived(block ? night.targets.find(t => t.id === block.targetID) ?? null : null);
  const upcoming = $derived(blocks.filter(b => Date.parse(b.window.start) > now && b !== next));

  function countdown(ms) {
    const minutes = Math.max(0, Math.round((ms - now) / 60000));
    return minutes >= 60 ? `${Math.floor(minutes / 60)}h ${String(minutes % 60).padStart(2, '0')}m` : `${minutes}m`;
  }
  const progress = $derived(current ? (now - Date.parse(current.window.start)) / (Date.parse(current.window.end) - Date.parse(current.window.start)) : 0);

  // About the target, from its card.
  let facts = $state([]);
  $effect(() => {
    const id = block?.targetID;
    facts = [];
    if (id) targetDetail({ planKey: night.planKey, targetID: id }).then(d => (facts = d.facts ?? []), () => {});
  });

  // Right now, from the night's five-minute samples.
  const sample = $derived.by(() => {
    const samples = night.samples;
    if (!samples.length) return null;
    const t0 = Date.parse(samples[0].date), t1 = Date.parse(samples[samples.length - 1].date);
    if (now < t0 || now > t1) return null;
    const i = Math.round(((now - t0) / (t1 - t0)) * (samples.length - 1));
    return samples[i];
  });
  const imperial = $derived(preferences.usesImperialUnits);
  const skyText = sun => (sun < -18 ? 'Astronomical dark' : sun < -12 ? 'Nautical twilight' : sun < -6 ? 'Civil twilight' : sun < 0 ? 'Twilight' : 'Daylight');
  const dawn = $derived(night.astronomicalDawn ? Date.parse(night.astronomicalDawn) : null);

  // The dew heater, as SessionModeView.dewReminder words it.
  const dewLine = $derived.by(() => {
    if (!night.dew || !['High', 'Very High'].includes(night.dew.level)) return null;
    const first = blocks[0] ? Date.parse(blocks[0].window.start) : null;
    if (first && now < first) return { action: `Dew heater on before ${time(first, timeZone)}`, reason: `Dew risk ${night.dew.level.toLowerCase()} ${night.dew.when}` };
    return { action: 'Keep your dew heater on', reason: `Dew risk ${night.dew.level.toLowerCase()} ${night.dew.when}` };
  });

  // Keep the screen awake at the scope (where the browser allows it).
  const canWake = 'wakeLock' in navigator;
  let awake = $state(false);
  let lock = null;
  async function acquire() {
    try {
      lock = await navigator.wakeLock.request('screen');
      awake = true;
      lock.addEventListener('release', () => { if (document.visibilityState === 'visible' && awake) acquire(); });
    } catch {
      awake = false;
    }
  }
  async function toggleAwake() {
    if (awake) {
      awake = false;
      await lock?.release();
      lock = null;
    } else {
      await acquire();
    }
  }
  $effect(() => {
    const back = () => { if (awake && document.visibilityState === 'visible') acquire(); };
    document.addEventListener('visibilitychange', back);
    return () => { document.removeEventListener('visibilitychange', back); lock?.release(); };
  });
</script>

<section class="session">
  <header>
    <a class="back" href="#/{night.planKey}">‹ Home</a>
    <div class="title">
      <h2>Session</h2>
      <p>{longDate(night.planKey)}</p>
    </div>
    <span class="clock">{time(now, timeZone)}</span>
  </header>

  <div class="main panel">
    {#if phase === 'empty'}
      <p class="big">Nothing planned for this night</p>
      <p class="muted">Plan a session first, or let the app suggest one.</p>
    {:else if phase === 'finished'}
      <p class="big">Tonight's plan is finished</p>
      <p class="muted">The last block ended at {time(blocks[blocks.length - 1].window.end, timeZone)}.</p>
    {:else if block}
      <p class="heading">{phase === 'running' ? 'NOW' : `NEXT · STARTS IN ${countdown(Date.parse(block.window.start))}`}</p>
      <div class="name-row">
        <p class="big">{block.targetName}</p>
        <p class="times">
          {time(block.window.start, timeZone)}–{time(block.window.end, timeZone)} ·
          {phase === 'running' ? `${countdown(Date.parse(block.window.end))} left` : duration((Date.parse(block.window.end) - Date.parse(block.window.start)) / 60000)}
        </p>
      </div>
      {#if phase === 'running'}<div class="progress"><span style:width="{Math.min(100, Math.max(0, progress * 100))}%"></span></div>{/if}
      {#if dewLine}
        <div class="dew"><strong>{dewLine.action}</strong><span>{dewLine.reason}</span></div>
      {/if}
      <div class="views">
        {#if target}
          <div class="view">
            <p class="label">In your frame</p>
            <FramePreview {target} />
          </div>
        {/if}
        <div class="view">
          <p class="label">In the sky now · {time(now, timeZone)}</p>
          <div class="sky"><SkyView {night} {timeZone} {rig} {preferences} targetID={block.targetID} compact /></div>
        </div>
      </div>
      {#if block.unusableMinutes > 0}<p class="warn">⚠︎ {duration(block.unusableMinutes)} of this block is unshootable.</p>{/if}
    {/if}
  </div>

  <div class="panels">
    <div class="panel side">
      <p class="label">Right now</p>
      {#if sample}
        {#if sample.hasWeather && sample.temperature != null}
          <div class="line"><span>Temperature</span><span class:warnText={sample.dewSpread != null && sample.dewSpread < 2}>{temperature(sample.temperature, imperial)}{sample.dewSpread != null ? ` · dew point ${temperature(sample.temperature - sample.dewSpread, imperial)}` : ''}</span></div>
        {/if}
        {#if sample.hasWeather && sample.cloudCover != null}
          <div class="line"><span>Cloud</span><span class:warnText={sample.cloudCover > preferences.maximumCloudCover}>{Math.round(sample.cloudCover)}% · low {Math.round(sample.cloudLow ?? 0)}%, mid {Math.round(sample.cloudMid ?? 0)}%, high {Math.round(sample.cloudHigh ?? 0)}%</span></div>
        {/if}
        {#if sample.windSpeed != null}<div class="line"><span>Wind</span><span>{wind(sample.windSpeed, imperial)}</span></div>{/if}
        <div class="line"><span>Sky</span><span>{skyText(sample.sunAltitude)}</span></div>
        <div class="line"><span>Moon</span><span>{Math.round(night.moonIlluminatedFraction * 100)}% lit · {sample.moonAltitude > 0 ? `${Math.round(sample.moonAltitude)}° up` : 'below the horizon'}</span></div>
      {:else}
        <p class="muted">The night hasn't started yet.</p>
      {/if}
      {#if dawn && now < dawn}<div class="line"><span>Dark until</span><span>{time(dawn, timeZone)} · {countdown(dawn)} left</span></div>{/if}
    </div>

    <div class="panel side">
      <p class="label">{block ? `About ${block.targetName}` : 'About'}</p>
      {#if facts.length}
        <ul>{#each facts as fact}<li>{fact}</li>{/each}</ul>
      {:else}
        <p class="muted">Nothing more on record for this one.</p>
      {/if}
    </div>

    <div class="panel side">
      <p class="label">After that</p>
      {#if upcoming.length}
        {#each upcoming as b}
          {@const t = night.targets.find(x => x.id === b.targetID)}
          <div class="after">
            {#if t}<ScoreBadge score={t.score} size={30} />{/if}
            <div><strong>{b.targetName}</strong><p class="muted">{time(b.window.start, timeZone)}–{time(b.window.end, timeZone)} · {duration((Date.parse(b.window.end) - Date.parse(b.window.start)) / 60000)}</p></div>
          </div>
        {/each}
      {:else}
        <p class="muted">Nothing more planned.</p>
      {/if}
      {#if canWake}
        <button type="button" class="wake" class:on={awake} onclick={toggleAwake}>{awake ? '☀︎ Screen stays on' : 'Keep Screen On'}</button>
      {/if}
    </div>
  </div>
</section>

<style>
  /* SessionModeView's palette: everything a dim red, whatever the theme. */
  .session {
    --bg: rgb(9, 5, 8); --panel-bg: rgb(23, 13, 15); --line: rgb(69, 38, 46);
    --ink: rgb(255, 237, 237); --dim: rgb(204, 168, 173); --red: rgb(219, 77, 77); --amber: rgb(242, 179, 102);
    display: grid; gap: 14px; color: var(--ink); background: var(--bg);
    margin: 0 -16px; padding: 0 16px 24px; min-height: calc(100vh - 80px);
  }
  header { display: flex; gap: 14px; align-items: center; padding: 12px 0; border-bottom: 1px solid var(--line); }
  .back { color: var(--dim); text-decoration: none; }
  .title { flex: 1; }
  h2 { margin: 0; font-size: 20px; }
  p { margin: 0; }
  .title p, .muted { color: var(--dim); }
  .clock { font-size: 24px; font-weight: 600; font-variant-numeric: tabular-nums; }
  .panel { background: var(--panel-bg); border: 1px solid var(--line); border-radius: 14px; }
  .main { padding: 16px; display: grid; gap: 10px; }
  .heading, .label { color: var(--red); font-size: 12px; font-weight: 700; letter-spacing: 0.08em; text-transform: uppercase; }
  .name-row { display: flex; gap: 14px; align-items: baseline; flex-wrap: wrap; }
  .big { font-size: 32px; font-weight: 700; line-height: 1.1; }
  .times { color: var(--dim); font-size: 18px; font-variant-numeric: tabular-nums; }
  .progress { height: 6px; border-radius: 3px; background: var(--line); overflow: hidden; }
  .progress span { display: block; height: 100%; background: var(--red); }
  .dew { display: grid; gap: 2px; padding: 8px 10px; border-radius: 8px; color: var(--amber); background: rgba(242, 179, 102, 0.12); border: 1px solid rgba(242, 179, 102, 0.35); justify-self: start; }
  .dew span { font-size: 13px; opacity: 0.85; }
  .views { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 14px; align-items: start; }
  .view { display: grid; gap: 6px; }
  .sky { padding: 10px; background: rgba(0, 0, 0, 0.35); border-radius: 10px; }
  .warn, .warnText { color: var(--amber); }
  .panels { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 14px; align-items: start; }
  .side { padding: 16px; display: grid; gap: 8px; }
  .line { display: flex; justify-content: space-between; gap: 10px; }
  .line span:first-child { color: var(--dim); }
  .line span:last-child { text-align: right; }
  ul { margin: 0; padding-left: 18px; display: grid; gap: 6px; }
  li::marker { color: var(--red); }
  .after { display: flex; gap: 10px; align-items: center; }
  .wake { margin-top: 6px; background: var(--panel-bg); color: var(--ink); border-color: var(--line); }
  .wake.on { border-color: var(--red); color: var(--red); }
  /* The dome and frame picture keep their colours unless night mode is on;
     here they're toned toward red to match. */
  .views :global(canvas), .views :global(.preview img), .views :global(.preview svg), .views :global(.preview .size) { filter: sepia(1) hue-rotate(-50deg) saturate(2.2) brightness(0.8); }
</style>
