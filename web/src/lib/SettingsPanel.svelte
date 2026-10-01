<script>
  // The few settings that change the scores most, set the guided way: a rig
  // preset, the kind of night you want, how much cloud you'll put up with,
  // and units. Everything else the Mac's Settings has is under "More
  // settings" (MoreSettings.svelte), closed by default.
  import { duration } from './format.js';
  import { uuid } from './uuid.js';
  import { setupLink } from './setupLink.js';
  import MoreSettings from './MoreSettings.svelte';

  let { settings, rigPresets, onchange, ondone } = $props();

  // Rig.presetGroup
  const smartMakers = ['ZWO Seestar', 'Celestron Origin', 'Unistellar', 'Vaonis', 'DwarfLab'];
  const isSmart = rig => smartMakers.some(maker => rig.name.startsWith(maker));
  const groups = $derived([
    ['Smart telescopes', rigPresets.filter(isSmart)],
    ['Cameras, lenses and telescopes', rigPresets.filter(rig => !isSmart(rig))],
  ]);

  // An imported rig that isn't one of the presets keeps its own entry.
  const presetIndex = $derived(rigPresets.findIndex(rig => rig.name === settings.rig.name));

  // GoalPreset (Model/Preferences.swift)
  const goals = [
    { id: 'quickSession', title: 'Quick session', summary: 'About an hour per target.', minutes: 60, emphasis: 'longerIntegration' },
    { id: 'deepIntegration', title: 'Deep integration', summary: 'Several hours on one or two targets.', minutes: 240, emphasis: 'longerIntegration' },
    { id: 'variety', title: 'Variety', summary: 'Many targets, about an hour each.', minutes: 120, emphasis: 'moreTargets' },
  ];
  const goal = $derived(goals.find(g => g.minutes === settings.preferences.integrationGoalMinutes
    && g.emphasis === settings.preferences.planEmphasis));

  function chooseRig(index) {
    if (index < 0) return;
    // Applying a preset is a fresh rig, as Settings → Equipment does.
    onchange({ ...settings, rig: { ...rigPresets[index], id: uuid() } });
  }

  function setFilter(on) {
    onchange({ ...settings, rig: { ...settings.rig, hasNarrowbandFilter: on } });
  }

  function chooseGoal(id) {
    const chosen = goals.find(g => g.id === id);
    if (!chosen) return;
    onchange({ ...settings, preferences: { ...settings.preferences, integrationGoalMinutes: chosen.minutes, planEmphasis: chosen.emphasis } });
  }

  // The slider moves freely; the night is re-planned when you let go.
  let cloudLimit = $state(settings.preferences.maximumCloudCover);
  $effect(() => { cloudLimit = settings.preferences.maximumCloudCover; });

  function setCloudLimit() {
    onchange({ ...settings, preferences: { ...settings.preferences, maximumCloudCover: cloudLimit } });
  }

  // Your setup as a link, for your phone or a friend.
  let linkNote = $state('');
  let linkShown = $state('');
  async function copyLink() {
    const link = setupLink(settings);
    try {
      await navigator.clipboard.writeText(link);
      linkNote = 'Copied. Open it on your phone or send it to a friend.';
      linkShown = '';
    } catch {
      linkNote = 'Copy this link:';
      linkShown = link;
    }
  }
  async function shareLink() {
    try {
      await navigator.share({ title: 'My Sky Bother setup', url: setupLink(settings) });
    } catch {}
  }
  const canShare = typeof navigator.share === 'function';
  let showsMore = $state(false);

  function setImperial(on) {
    onchange({ ...settings, preferences: { ...settings.preferences, usesImperialUnits: on } });
  }
</script>

<section class="panel settings">
  <header>
    <h2>Settings</h2>
    <button type="button" onclick={ondone}>Done</button>
  </header>

  <label class="row">
    <span class="label">Telescope</span>
    <select value={presetIndex} onchange={e => chooseRig(Number(e.currentTarget.value))}>
      {#if presetIndex < 0}<option value={-1}>{settings.rig.name} (yours)</option>{/if}
      {#each groups as [name, rigs]}
        <optgroup label={name}>
          {#each rigs as rig}<option value={rigPresets.indexOf(rig)}>{rig.name}</option>{/each}
        </optgroup>
      {/each}
    </select>
  </label>

  <label class="row check">
    <input type="checkbox" checked={settings.rig.hasNarrowbandFilter} onchange={e => setFilter(e.currentTarget.checked)} />
    <span>Dual-band / narrowband filter</span>
  </label>

  <div class="row">
    <span class="label">Kind of night</span>
    <div class="segments" role="radiogroup" aria-label="Kind of night">
      {#each goals as g}
        <button type="button" role="radio" aria-checked={goal?.id === g.id} class:on={goal?.id === g.id}
                onclick={() => chooseGoal(g.id)}>{g.title}</button>
      {/each}
    </div>
    <p class="muted">
      {goal ? goal.summary : `Your own: up to ${duration(settings.preferences.integrationGoalMinutes)} per target.`}
    </p>
  </div>

  <label class="row">
    <span class="label">Maximum cloud cover <strong>{cloudLimit}%</strong></span>
    <input type="range" min="0" max="100" step="5" bind:value={cloudLimit} onchange={setCloudLimit} />
    <span class="muted">Hours cloudier than this count less: half for every 6 points over.</span>
  </label>

  <label class="row check">
    <input type="checkbox" checked={settings.preferences.usesImperialUnits} onchange={e => setImperial(e.currentTarget.checked)} />
    <span>Use Fahrenheit and mph</span>
  </label>

  <button type="button" class="disclosure" onclick={() => (showsMore = !showsMore)} aria-expanded={showsMore}>
    {showsMore ? '▾' : '▸'} More settings
    <span class="muted">site, horizon, your own rig, darkness, altitude, what to show, night mode</span>
  </button>
  {#if showsMore}<MoreSettings {settings} {onchange} />{/if}

  <div class="row">
    <span class="label">Use this setup elsewhere</span>
    <div class="link-buttons">
      <button type="button" onclick={copyLink}>Copy Setup Link</button>
      {#if canShare}<button type="button" onclick={shareLink}>Share…</button>{/if}
    </div>
    <span class="muted">{linkNote || 'A link that gives another device your site, telescope and settings.'}</span>
    {#if linkShown}<input type="text" readonly value={linkShown} onfocus={e => e.currentTarget.select()} />{/if}
  </div>
</section>

<style>
  .settings { padding: 14px; display: grid; gap: 14px; }
  header { display: flex; justify-content: space-between; align-items: center; }
  h2 { margin: 0; font-size: 17px; }
  .row { display: grid; gap: 6px; }
  .label { font-weight: 600; display: flex; justify-content: space-between; }
  .check { display: flex; align-items: center; gap: 8px; }
  .check input { width: 16px; height: 16px; accent-color: var(--accent); }
  select { max-width: 100%; }
  input[type='range'] { width: 100%; accent-color: var(--accent); padding: 0; }
  .segments { display: flex; flex-wrap: wrap; gap: 6px; }
  .segments button.on { background: rgba(158, 133, 250, 0.25); border-color: var(--accent); }
  p { margin: 0; }
  .link-buttons { display: flex; gap: 8px; flex-wrap: wrap; }
  .disclosure { display: grid; gap: 2px; text-align: left; background: none; border: none; padding: 0; font-weight: 600; color: var(--accent); }
  .disclosure .muted { font-weight: 400; }
</style>
