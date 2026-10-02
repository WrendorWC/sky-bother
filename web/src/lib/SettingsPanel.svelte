<script>
  // Settings, in the Mac app's tabs (UI/SettingsView.swift): Location,
  // Equipment, Planning, and Sync — with Display (units and night mode) on a
  // tab of its own, and the ways to bring settings across between devices
  // gathered under Sync. Each tab is a column of grouped cards.
  import { setupLink } from './setupLink.js';
  import ImportSettings from './ImportSettings.svelte';
  import SyncSection from './SyncSection.svelte';
  import LocationSettings from './LocationSettings.svelte';
  import EquipmentSettings from './EquipmentSettings.svelte';
  import PlanningSettings from './PlanningSettings.svelte';

  let { settings, rigPresets, onchange, onimport, onsite, ondone, onsetup, onsyncjoin, onsyncstart, onsyncnow, focus = null } = $props();

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

  const prefs = $derived(settings.preferences);
  const setPrefs = fields => onchange({ ...settings, preferences: { ...prefs, ...fields } });

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
  <header>
    <h2>Settings</h2>
    <div class="row-buttons">
      <button type="button" class="wizard" onclick={onsetup} title="Walks you through your site, horizon, telescope and goal">✦ Setup Wizard</button>
      <button type="button" class="done" onclick={ondone}>Done</button>
    </div>
  </header>

  <nav class="tabs" aria-label="Settings sections">
    {#each tabs as t}
      <button type="button" class:on={tab === t.id} aria-current={tab === t.id ? 'page' : undefined} onclick={() => (tab = t.id)}>
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d={t.icon} /></svg>
        <span>{t.title}</span>
      </button>
    {/each}
  </nav>

  {#if tab === 'location'}
    <LocationSettings {settings} {onsite} {onchange} autofocus={focus === 'location'} />
  {:else if tab === 'equipment'}
    <EquipmentSettings {settings} {rigPresets} {onchange} />
  {:else if tab === 'planning'}
    <PlanningSettings {settings} {onchange} />
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
        <h3 class="group-title">Sync</h3>
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
  .wizard { font-weight: 600; }
  .tabs {
    display: grid; grid-template-columns: repeat(5, 1fr); gap: 4px; padding: 4px;
    border-radius: 14px; background: var(--panel); border: 1px solid var(--panel-border);
    position: sticky; top: 8px; z-index: 5;
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
  @media (min-width: 700px) {
    .tabs button { grid-auto-flow: column; justify-content: center; gap: 7px; align-items: center; font-size: 14px; padding: 9px 4px; }
    .tabs svg { width: 18px; height: 18px; }
  }
</style>
