<script>
  // SetupFlowView: a short guided path to a real first plan — site, horizon,
  // rig, goal, first plan — as the Mac app's Setup Wizard. Progress is kept
  // (settings.setupStep), so leaving and coming back resumes where you were.
  // A first visit can also start from the Mac app's settings instead.
  import LocationSection from './LocationSection.svelte';
  import HorizonSliders from './HorizonSliders.svelte';
  import ImportSettings from './ImportSettings.svelte';
  import FramePreview from './FramePreview.svelte';
  import ScoreBadge from './ScoreBadge.svelte';
  import { uuid } from './uuid.js';
  import { fieldOfView } from './sky.js';
  import { duration, longDate, time } from './format.js';

  let { settings, rigPresets, nights, loading, onsite, onchange, onimport, onfinish } = $props();

  const steps = ['Site', 'Horizon', 'Rig', 'Goal', 'First plan'];
  const step = $derived(settings?.setupStep ?? 0);
  const go = n => onchange({ ...settings, setupStep: n });

  // --- Rig ---------------------------------------------------------------
  const smartMakers = ['ZWO Seestar', 'Celestron Origin', 'Unistellar', 'Vaonis', 'DwarfLab'];
  const isSmart = rig => smartMakers.some(maker => rig.name.startsWith(maker));
  const groups = $derived([
    ['Smart telescopes', rigPresets.filter(isSmart)],
    ['Cameras, lenses and telescopes', rigPresets.filter(r => !isSmart(r))],
  ]);
  let showsCustom = $state(false);
  const rig = $derived(settings?.rig);
  const fov = $derived(fieldOfView(rig));
  const rigOK = $derived(rig && rig.focalLengthMillimeters > 0 && rig.apertureMillimeters > 0 && rig.sensorWidthMillimeters > 0 && rig.sensorHeightMillimeters > 0 && rig.pixelSizeMicrons > 0);
  const moons = $derived(fov ? Math.max(fov.width, fov.height) / 0.52 : 0);
  // M42 in the frame, as the Mac shows it.
  const sample = { id: 'M42', displayName: 'Orion Nebula', rightAscension: 83.82, declination: -5.39, majorAxisArcminutes: 85, minorAxisArcminutes: 60 };
  const setRig = fields => onchange({ ...settings, rig: { ...rig, ...fields } });
  function choosePreset(preset) {
    onchange({ ...settings, rig: { ...preset, id: uuid() } });
  }
  function setNumber(field, text) {
    const value = Number(text);
    if (Number.isFinite(value) && value >= 0) setRig({ [field]: value });
  }

  // --- Goal (GoalPreset) ------------------------------------------------------
  const goals = [
    { id: 'quickSession', title: 'Quick session', summary: 'About an hour per target.', minutes: 60, emphasis: 'longerIntegration' },
    { id: 'deepIntegration', title: 'Deep integration', summary: 'Several hours on one or two targets.', minutes: 240, emphasis: 'longerIntegration' },
    { id: 'variety', title: 'Variety', summary: 'Many targets, about an hour each.', minutes: 120, emphasis: 'moreTargets' },
  ];
  const prefs = $derived(settings?.preferences);
  const goal = $derived(prefs && goals.find(g => g.minutes === prefs.integrationGoalMinutes && g.emphasis === prefs.planEmphasis));
  const setPrefs = fields => onchange({ ...settings, preferences: { ...prefs, ...fields } });

  // --- First plan --------------------------------------------------------------
  const best = $derived(nights.length ? nights.reduce((a, b) => (b.score > a.score ? b : a)) : null);
  const bestTarget = $derived(best?.targets.find(t => t.usableMinutes > 0 && !t.isStar));
  const timeZone = $derived(settings?.site.timeZoneIdentifier);

  const canContinue = $derived(step === 0 ? !!settings : step === 2 ? rigOK : true);
</script>

<section class="panel wizard" aria-label="Set up Sky Bother">
  <header>
    <h2>Set up Sky Bother</h2>
    {#if settings}<button type="button" class="link" onclick={onfinish}>Save and Close</button>{/if}
  </header>
  <ol class="steps">
    {#each steps as name, i}
      <li class:current={i === step} class:done={i < step}>
        <button type="button" disabled={!settings || i > step} onclick={() => go(i)}><span class="dot">{i < step ? '✓' : i + 1}</span>{name}</button>
      </li>
    {/each}
  </ol>

  <div class="body">
    {#if step === 0}
      <h3>Choose your observing site</h3>
      <p class="muted-strong">Search by town, city, landmark or postal code.</p>
      <LocationSection {settings} {onsite} {onchange} autofocus />
      {#if settings}
        <p class="muted">Light pollution: 1 is a truly dark sky, 9 a city centre. A guess is fine; you can change it any time.</p>
      {:else}
        <div class="alt">
          <ImportSettings {onimport} />
        </div>
      {/if}
    {:else if step === 1}
      <h3>How much sky can you see?</h3>
      <p class="muted-strong">Roughly how high trees, houses and hills reach. Targets behind them are left out.</p>
      <HorizonSliders site={settings.site} onchange={fields => onchange({ ...settings, site: { ...settings.site, ...fields } })} />
    {:else if step === 2}
      <h3>What are you imaging with?</h3>
      <p class="muted-strong">Pick your telescope or camera.</p>
      {#each groups as [name, rigs]}
        <h4>{name}</h4>
        <div class="presets">
          {#each rigs as preset}
            <button type="button" class:chosen={preset.name === rig.name} onclick={() => choosePreset(preset)}>
              <span aria-hidden="true">{preset.name === rig.name ? '●' : '○'}</span> {preset.name}
            </button>
          {/each}
        </div>
      {/each}
      <button type="button" class="link" onclick={() => (showsCustom = !showsCustom)}>{showsCustom ? '▾' : '▸'} My equipment isn't listed</button>
      {#if showsCustom}
        <div class="grid">
          <label class="wide"><span>Name</span><input type="text" value={rig.name} onchange={e => setRig({ name: e.currentTarget.value })} /></label>
          <label><span>Aperture (mm)</span><input type="number" inputmode="decimal" min="0" step="any" value={rig.apertureMillimeters} onchange={e => setNumber('apertureMillimeters', e.currentTarget.value)} /></label>
          <label><span>Focal length (mm)</span><input type="number" inputmode="decimal" min="0" step="any" value={rig.focalLengthMillimeters} onchange={e => setNumber('focalLengthMillimeters', e.currentTarget.value)} /></label>
          <label><span>Sensor width (mm)</span><input type="number" inputmode="decimal" min="0" step="any" value={rig.sensorWidthMillimeters} onchange={e => setNumber('sensorWidthMillimeters', e.currentTarget.value)} /></label>
          <label><span>Sensor height (mm)</span><input type="number" inputmode="decimal" min="0" step="any" value={rig.sensorHeightMillimeters} onchange={e => setNumber('sensorHeightMillimeters', e.currentTarget.value)} /></label>
          <label><span>Pixel size (µm)</span><input type="number" inputmode="decimal" min="0" step="any" value={rig.pixelSizeMicrons} onchange={e => setNumber('pixelSizeMicrons', e.currentTarget.value)} /></label>
          <label><span>Mount</span>
            <select value={rig.mountType} onchange={e => setRig({ mountType: e.currentTarget.value })}>
              <option value="altAzimuth">Alt-Azimuth</option><option value="equatorial">Equatorial</option>
            </select>
          </label>
        </div>
      {/if}
      {#if rigOK && fov}
        <div class="gives panel">
          <h4>What this gives you</h4>
          <p>{fov.width.toFixed(2)}° × {fov.height.toFixed(2)}° field of view — {moons >= 1.5 ? `about ${Math.round(moons)} full Moons across the long side` : 'about one full Moon across the long side'}.</p>
          <p class="muted">f/{(rig.focalLengthMillimeters / rig.apertureMillimeters).toFixed(1)} · {(206.265 * rig.pixelSizeMicrons / rig.focalLengthMillimeters).toFixed(2)}″ per pixel image scale.</p>
          <p class="muted">Orion Nebula in your frame</p>
          <FramePreview target={sample} />
        </div>
      {:else}
        <p class="warn">Fill in every number for the framing to work.</p>
      {/if}
    {:else if step === 3}
      <h3>What kind of night do you want?</h3>
      <p class="muted-strong">Shapes the suggested plan.</p>
      <div class="goals">
        {#each goals as g}
          <button type="button" class:chosen={goal?.id === g.id}
                  onclick={() => setPrefs({ integrationGoalMinutes: g.minutes, planEmphasis: g.emphasis })}>
            <strong>{g.title}</strong><span class="muted">{g.summary}</span>
          </button>
        {/each}
      </div>
      {#if !goal}<p class="muted">Your own: up to {duration(prefs.integrationGoalMinutes)} per target.</p>{/if}
      <p class="label">Show these too:</p>
      <label class="check"><input type="checkbox" checked={prefs.includeStars} onchange={e => setPrefs({ includeStars: e.currentTarget.checked })} /> Bright stars and doubles</label>
      <label class="check"><input type="checkbox" checked={prefs.includeComets} onchange={e => setPrefs({ includeComets: e.currentTarget.checked })} /> Visible comets</label>
      <p class="muted">Unticked ones start hidden in the catalog. Tick them there any time.</p>
    {:else}
      <h3>Your first plan</h3>
      {#if !best}
        <p class="muted">{loading ? 'Fetching the forecast…' : 'No forecast yet.'}</p>
      {:else}
        <div class="first panel">
          <ScoreBadge score={best.score} size={52} />
          <div>
            <p><strong>Best night coming up: {longDate(best.planKey)}</strong></p>
            <p class="muted-strong">{best.headline}</p>
            {#if best.limitation}<p class="muted">Main limitation: {best.limitation}</p>{/if}
          </div>
        </div>
        {#if bestTarget}
          <h4>{best.isCloudedOut ? 'If it clears' : 'Top recommendation'}</h4>
          <p><strong>{bestTarget.displayName} · {Math.round(bestTarget.score)}</strong></p>
          <p class="muted">{duration(bestTarget.usableMinutes)} usable · {bestTarget.framingNote}</p>
        {/if}
        {#if best.plan.length}
          <h4>Suggested plan</h4>
          <ul class="plan">
            {#each best.plan as block}<li>{time(block.window.start, timeZone)}–{time(block.window.end, timeZone)}  {block.targetName}</li>{/each}
          </ul>
        {/if}
      {/if}
    {/if}
  </div>

  {#if settings}
    <footer>
      {#if step > 0}<button type="button" onclick={() => go(step - 1)}>Back</button>{/if}
      <span class="muted saves">Progress saves automatically</span>
      <span class="spacer"></span>
      {#if step === 1 || step === 3}<button type="button" class="link" onclick={() => go(step + 1)}>Skip</button>{/if}
      {#if step < steps.length - 1}
        <button type="button" class="primary" disabled={!canContinue} onclick={() => go(step + 1)}>Continue</button>
      {:else}
        <button type="button" class="primary" onclick={() => onfinish(best?.planKey)}>Go to My Plan</button>
      {/if}
    </footer>
  {/if}
</section>

<style>
  .wizard { margin-top: 14px; padding: 18px; display: grid; gap: 16px; max-width: 860px; margin-inline: auto; }
  header { display: flex; justify-content: space-between; align-items: baseline; }
  h2 { margin: 0; font-size: 20px; }
  h3 { margin: 0; font-size: 22px; }
  h4 { margin: 8px 0 0; font-size: 13px; text-transform: uppercase; letter-spacing: 0.06em; color: var(--accent); }
  p { margin: 0; }
  .steps { list-style: none; margin: 0; padding: 0; display: flex; gap: 6px; flex-wrap: wrap; }
  .steps button { display: flex; gap: 6px; align-items: center; background: none; border: none; padding: 4px 6px; color: var(--muted); }
  .steps .current button { color: var(--text); font-weight: 600; }
  .steps .done button { color: var(--accent); }
  .dot { width: 22px; height: 22px; border-radius: 50%; display: grid; place-items: center; font-size: 12px; border: 1.5px solid currentColor; }
  .current .dot { background: var(--accent); color: #120e22; border-color: var(--accent); }
  .body { display: grid; gap: 10px; }
  .alt { margin-top: 10px; padding-top: 14px; border-top: 1px solid var(--panel-border); }
  .presets { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 8px; }
  .presets button, .goals button { text-align: left; }
  .presets button.chosen, .goals button.chosen { border-color: var(--accent); background: rgba(158, 133, 250, 0.2); }
  .goals { display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 8px; }
  .goals button { display: grid; gap: 4px; padding: 12px; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 8px; }
  .grid label { display: grid; gap: 4px; font-size: 13px; color: var(--muted); }
  .grid .wide { grid-column: 1 / -1; }
  .grid input, .grid select { width: 100%; }
  .gives { padding: 14px; display: grid; gap: 6px; }
  .gives h4 { margin: 0; }
  .first { padding: 14px; display: flex; gap: 14px; align-items: center; }
  .plan { margin: 0; padding-left: 18px; font-variant-numeric: tabular-nums; white-space: pre; }
  .label { font-weight: 600; margin-top: 6px; }
  .check { display: flex; gap: 8px; align-items: center; }
  .check input { accent-color: var(--accent); }
  .warn { color: var(--marginal); }
  .link { background: none; border: none; padding: 0; color: var(--accent); font-weight: 600; justify-self: start; }
  footer { display: flex; gap: 10px; align-items: center; padding-top: 12px; border-top: 1px solid var(--panel-border); }
  .spacer { flex: 1; }
  .primary { background: var(--accent); border-color: var(--accent); color: #120e22; font-weight: 700; padding: 8px 18px; }
  .primary:disabled { opacity: 0.4; }
  @media (max-width: 600px) { .saves { display: none; } }
</style>
