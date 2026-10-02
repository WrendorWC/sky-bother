<script>
  // Settings, in the Mac app's tabs (UI/SettingsView.swift): Location,
  // Equipment, Planning, and Sync — with Display (units and night mode) on a
  // tab of its own, and the ways to bring settings across between devices
  // gathered under Sync. Each tab is a column of grouped cards.
  import { setupLink } from './setupLink.js';
  import { sync } from './syncState.svelte.js';
  import ImportSettings from './ImportSettings.svelte';
  import SyncSection from './SyncSection.svelte';
  import LocationSettings from './LocationSettings.svelte';
  import EquipmentSettings from './EquipmentSettings.svelte';
  import PlanningSettings from './PlanningSettings.svelte';

  // Changes here are a draft until Save: a nudged slider shouldn't reach
  // every synced device before you meant it to. `settings` is what's saved.
  let { settings, rigPresets, onsave, onimport, ondone, onsetup, onsyncjoin, onsyncstart, onsyncnow, ondirty, focus = null } = $props();

  const copy = value => JSON.parse(JSON.stringify(value));
  let base = $state(copy(settings));
  let draft = $state(copy(settings));
  const dirty = $derived(JSON.stringify(draft) !== JSON.stringify(base));
  $effect(() => ondirty?.(dirty));
  // What's saved changed underneath (sync, say) with nothing edited here:
  // start again from it.
  $effect(() => {
    const now = settings;
    if (!dirty) {
      base = copy(now);
      draft = copy(now);
    }
  });
  const onchange = changed => (draft = changed);

  // Picking a new place, as App.setSite: the site being left joins your
  // saved sites first, so it isn't lost.
  function onsite(site) {
    const saved = [...(draft.savedSites ?? [])];
    if (!saved.some(s => s.id === draft.site.id)) saved.push({ ...draft.site });
    draft = { ...draft, site, savedSites: saved };
  }

  // Only the sections changed here are saved, onto what's saved now, so
  // anything sync brought in meanwhile stays.
  function save() {
    const next = { ...settings };
    for (const key of Object.keys(draft)) {
      if (JSON.stringify(draft[key]) !== JSON.stringify(base[key])) next[key] = draft[key];
    }
    onsave(next);
    base = copy(next);
    draft = copy(next);
    clearTimeout(savedTimer);
    saved = true;
    savedTimer = setTimeout(() => (saved = false), 2200);
  }
  let saved = $state(false);
  let savedTimer;
  function cancel() {
    draft = copy(base);
  }
  const discardOK = () => !dirty || confirm('Discard your unsaved settings changes?');
  // Cancel throws away what's here and closes Settings; it's what you
  // pressed, so it doesn't ask.
  function cancelAndClose() {
    draft = copy(base);
    ondone();
  }
  function wizard() {
    if (discardOK()) onsetup();
  }
  $effect(() => {
    const warn = e => { if (dirty) { e.preventDefault(); e.returnValue = ''; } };
    window.addEventListener('beforeunload', warn);
    return () => window.removeEventListener('beforeunload', warn);
  });

  const tabs = [
    { id: 'location', title: 'Location', icon: 'M12 21s-7-6.2-7-11.5A7 7 0 0 1 19 9.5C19 14.8 12 21 12 21Zm0-8.5a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z' },
    { id: 'equipment', title: 'Equipment', icon: 'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18Zm0 5 3.5 2v4L12 16l-3.5-2v-4L12 8Zm0-5v5m7.8 4.5-4.3-2.5m4.3 7.5-4.3-2.5M12 21v-5m-7.8-1.5 4.3-2.5M4.2 7.5l4.3 2.5' },
    { id: 'planning', title: 'Planning', icon: 'M4 6h10m4 0h2M4 12h4m4 0h8M4 18h12m4 0h0M16 4v4M10 10v4M18 16v4' },
    { id: 'display', title: 'Display', icon: 'M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5Z' },
    { id: 'sync', title: 'Sync', icon: 'M20 11a8 8 0 0 0-14.3-4.9L4 8m0-4v4h4M4 13a8 8 0 0 0 14.3 4.9L20 16m0 4v-4h-4' },
  ];
  let tab = $state('location');
  // Opened from the site name: straight to Location.
  $effect(() => {
    if (focus === 'location') tab = 'location';
  });
  $effect(() => {
    tab;
    window.scrollTo({ top: 0 });
  });

  const prefs = $derived(draft.preferences);
  const setPrefs = fields => onchange({ ...draft, preferences: { ...prefs, ...fields } });

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
</script>

<section class="settings">
  <div class="top">
  <header>
    <h2>Settings</h2>
    <div class="row-buttons">
      <button type="button" onclick={cancelAndClose}>Cancel</button>
      <button type="button" class="done" onclick={save} disabled={!dirty}>Save</button>
    </div>
  </header>
  {#if saved && !dirty}<p class="saved" role="status">✓ Saved{sync.code ? ' — on its way to your synced devices' : ''}</p>{/if}
  {#if dirty}<p class="unsaved">Not saved yet: nothing changes, here or on synced devices, until you tap Save.</p>{/if}

  <nav class="tabs" aria-label="Settings sections">
    {#each tabs as t}
      <button type="button" class:on={tab === t.id} aria-current={tab === t.id ? 'page' : undefined} onclick={() => (tab = t.id)}>
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d={t.icon} /></svg>
        <span>{t.title}{#if t.id === 'sync'}<i class="sync-dot" class:on={!!sync.code} class:trouble={!!sync.error}
             title={sync.error ? 'Sync has a problem' : sync.code ? 'Syncing' : 'Not syncing'}></i>{/if}</span>
      </button>
    {/each}
  </nav>
  </div>

  {#if tab === 'location'}
    <div class="wizard-card card">
      <div class="item inline">
        <div><span class="title">New here, or starting over?</span><p class="caption">The Setup Wizard walks you through your site, horizon, telescope and goal.</p></div>
        <button type="button" class="wizard" onclick={wizard}>✦ Setup Wizard</button>
      </div>
    </div>
    <LocationSettings settings={draft} {onsite} {onchange} autofocus={focus === 'location'} />
  {:else if tab === 'equipment'}
    <EquipmentSettings settings={draft} {rigPresets} {onchange} />
  {:else if tab === 'planning'}
    <PlanningSettings settings={draft} {onchange} />
  {:else if tab === 'display'}
    <div class="pane">
      <div class="group">
        <h3 class="group-title">Display</h3>
        <div class="card">
          <label class="item inline">
            <div><span class="title">Night mode</span><p class="caption">Red light only, to keep your eyes dark-adapted at the scope.</p></div>
            <input class="switch" type="checkbox" checked={prefs.nightMode ?? false} onchange={e => setPrefs({ nightMode: e.currentTarget.checked })} />
          </label>
          <label class="item inline">
            <div><span class="title">Fahrenheit and mph</span><p class="caption">Off: Celsius and km/h.</p></div>
            <input class="switch" type="checkbox" checked={prefs.usesImperialUnits} onchange={e => setPrefs({ usesImperialUnits: e.currentTarget.checked })} />
          </label>
        </div>
        <p class="group-note">These stay on this device; sync leaves them alone.</p>
      </div>
    </div>
  {:else}
    <div class="pane">
      <div class="group">
        <h3 class="group-title sync-title">Sync
          <span class="sync-state" class:on={!!sync.code} class:trouble={!!sync.error}>
            {sync.error ? 'Problem — see below' : sync.code ? 'On in this browser' : 'Off in this browser'}
          </span>
        </h3>
        <div class="card"><div class="item"><SyncSection onjoin={onsyncjoin} onstart={onsyncstart} {onsyncnow} /></div></div>
      </div>

      <div class="group">
        <h3 class="group-title">Setup link</h3>
        <div class="card">
          <div class="item">
            <p class="caption">{linkNote || 'A one-time link that gives another device, or a friend, your site, telescope and settings. Unlike sync, it doesn\'t keep them in step afterwards.'}</p>
            <div class="row-buttons">
              <button type="button" onclick={copyLink}>Copy Setup Link</button>
              {#if canShare}<button type="button" onclick={shareLink}>Share…</button>{/if}
            </div>
            {#if linkShown}<input type="text" readonly value={linkShown} onfocus={e => e.currentTarget.select()} />{/if}
          </div>
        </div>
      </div>

      <div class="group">
        <h3 class="group-title">From the Mac app</h3>
        <div class="card"><div class="item"><ImportSettings {onimport} bare /></div></div>
      </div>
    </div>
  {/if}
</section>

<style>
  .settings { display: grid; gap: 18px; max-width: 720px; margin: 0 auto; width: 100%; }
  header { display: flex; justify-content: space-between; align-items: center; gap: 12px; }
  h2 { margin: 0; font-size: 26px; }
  .done { background: var(--accent); color: #fff; border-color: var(--accent); font-weight: 700; padding: 7px 18px; }
  .done:disabled { opacity: 0.4; cursor: default; }
  .wizard { white-space: nowrap; }
  .wizard { font-weight: 600; }
  /* The header, Save and the tabs stay in reach while you scroll. */
  .top {
    display: grid; gap: 12px; position: sticky; top: 0; z-index: 5;
    margin: 0 -16px; padding: 10px 16px 12px; background: var(--space-top);
    border-bottom: 1px solid var(--divider);
  }
  .saved { margin: 0; padding: 6px 12px; border-radius: 10px; font-size: 14px; font-weight: 600; color: var(--excellent); background: color-mix(in srgb, var(--excellent) 14%, transparent); border: 1px solid color-mix(in srgb, var(--excellent) 40%, transparent); animation: pop 0.25s ease-out; }
  @keyframes pop { from { transform: scale(0.96); opacity: 0; } }
  .unsaved { margin: 0; padding: 6px 12px; border-radius: 10px; font-size: 13px; color: var(--marginal); background: color-mix(in srgb, var(--marginal) 12%, transparent); border: 1px solid color-mix(in srgb, var(--marginal) 35%, transparent); }
  .tabs {
    display: grid; grid-template-columns: repeat(5, 1fr); gap: 4px; padding: 4px;
    border-radius: 14px; background: var(--panel); border: 1px solid var(--panel-border);
  }
  .tabs button {
    display: grid; justify-items: center; gap: 3px; padding: 8px 2px; border: none; border-radius: 10px;
    background: none; color: var(--muted); font-size: 12px; font-weight: 600; min-width: 0;
  }
  .tabs button span { max-width: 100%; overflow: hidden; text-overflow: ellipsis; }
  .tabs button.on { background: rgba(158, 133, 250, 0.22); color: var(--text); }
  .tabs svg { width: 22px; height: 22px; fill: none; stroke: currentColor; stroke-width: 1.8; stroke-linecap: round; stroke-linejoin: round; }
  .tabs button.on svg { stroke: var(--accent); }
  .pane { display: grid; gap: 22px; }
  /* Sync on or off in this browser, at a glance: each browser joins on its
     own, and one that hasn't keeps its own copy. */
  .sync-dot { display: inline-block; width: 7px; height: 7px; margin-left: 5px; vertical-align: 2px; border-radius: 50%; background: var(--tertiary); }
  .sync-dot.on { background: var(--excellent); }
  .sync-dot.trouble { background: var(--marginal); }
  .sync-title { display: flex; align-items: center; gap: 10px; }
  .sync-state { text-transform: none; letter-spacing: 0; font-weight: 600; font-size: 12px; padding: 2px 9px; border-radius: 999px; color: var(--muted); background: var(--panel); border: 1px solid var(--panel-border); }
  .sync-state.on { color: var(--excellent); border-color: color-mix(in srgb, var(--excellent) 45%, transparent); }
  .sync-state.trouble { color: var(--marginal); border-color: color-mix(in srgb, var(--marginal) 45%, transparent); }
  @media (min-width: 700px) {
    .tabs button { grid-auto-flow: column; justify-content: center; gap: 7px; align-items: center; font-size: 14px; padding: 9px 4px; }
    .tabs svg { width: 18px; height: 18px; }
  }
</style>
