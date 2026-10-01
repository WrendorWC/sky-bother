<script>
  import { defaults, planNights, catalogEntries } from './engine/engine.js';
  import { fetchForecast, fetchCometElements } from './weather.js';
  import NightList from './lib/NightList.svelte';
  import NightDetail from './lib/NightDetail.svelte';
  import SitePanel from './lib/SitePanel.svelte';
  import SettingsPanel from './lib/SettingsPanel.svelte';
  import Catalog from './lib/Catalog.svelte';
  import { age } from './lib/format.js';

  const storageKey = 'skybother.settings.v1';

  let settings = $state(loadSettings());
  let nights = $state([]);
  let catalog = $state([]);
  let loading = $state(false);
  // What's happening while the week is fetched and planned, shown up top —
  // on a phone the engine download alone can take a while.
  let status = $state('');
  let error = $state('');
  let updatedAt = $state(null);
  let editingSite = $state(false);
  let editingSettings = $state(false);
  let rigPresets = $state([]);
  let clock = $state(Date.now());
  // The last forecast and comet orbits, so a settings change re-plans
  // without fetching them again.
  let fetched = null;

  // #/2026-10-01 is a night, #/2026-10-01/M76 a target on it; anything else
  // is the list (on a phone) or tonight.
  let route = $state(location.hash);
  const routeMatch = $derived(/^#\/(\d{4}-\d{2}-\d{2})(?:\/(.+))?$/.exec(route));
  const routeKey = $derived(routeMatch?.[1] ?? null);
  const routeTarget = $derived(routeMatch?.[2] ? decodeURIComponent(routeMatch[2]) : null);
  const showingCatalog = $derived(route === '#/catalog');
  const night = $derived(nights.find(n => n.planKey === routeKey) ?? nights[0] ?? null);

  function loadSettings() {
    try {
      return JSON.parse(localStorage.getItem(storageKey)) ?? null;
    } catch {
      return null;
    }
  }

  function saveSettings() {
    try {
      localStorage.setItem(storageKey, JSON.stringify(settings));
    } catch {}
  }

  async function setSite(site) {
    nights = [];
    status = 'Starting up…';
    loading = true;
    let base;
    try {
      base = settings ?? (await defaults());
    } catch (e) {
      loading = false;
      status = '';
      error = `Sky Bother couldn't start on this browser: ${e.message}`;
      return;
    }
    settings = { rig: base.rig, preferences: base.preferences, customTargets: base.customTargets ?? [], site };
    editingSite = false;
    saveSettings();
    refresh();
  }

  function importSettings(imported) {
    nights = [];
    settings = imported;
    editingSite = false;
    saveSettings();
    refresh();
  }

  function setBortle(value) {
    settings.site.bortleClass = value;
    saveSettings();
    replan();
  }

  function changeSettings(changed) {
    settings = changed;
    saveSettings();
    replan();
  }

  async function refresh() {
    if (!settings) return;
    error = '';
    loading = true;
    status = `Getting the forecast for ${settings.site.name || 'your site'}…`;
    try {
      const { site, preferences } = settings;
      const [openMeteoResponse, cometElements] = await Promise.all([
        fetchForecast(site.latitude, site.longitude, preferences.forecastNights),
        fetchCometElements(),
      ]);
      fetched = { key: `${site.latitude},${site.longitude}`, openMeteoResponse, cometElements };
      status = 'Planning the week…';
      await plan();
      updatedAt = Date.now();
    } catch (e) {
      error = e.message;
    } finally {
      loading = false;
      status = '';
    }
  }

  /** Re-plans from the forecast already fetched for this site, or fetches it. */
  async function replan() {
    if (!fetched || fetched.key !== `${settings.site.latitude},${settings.site.longitude}`) return refresh();
    error = '';
    try {
      await plan();
    } catch (e) {
      error = e.message;
    }
  }

  async function plan() {
    const { openMeteoResponse, cometElements } = fetched;
    nights = await planNights({ ...$state.snapshot(settings), openMeteoResponse, cometElements, now: new Date().toISOString().replace(/\.\d+Z$/, 'Z') });
    catalog = await catalogEntries();
  }

  $effect(() => {
    const onHash = () => (route = location.hash);
    const tick = setInterval(() => (clock = Date.now()), 60_000);
    addEventListener('hashchange', onHash);
    return () => { removeEventListener('hashchange', onHash); clearInterval(tick); };
  });

  defaults().then(d => (rigPresets = d.rigPresets));
  refresh();
</script>

<div class="app" class:showing-night={routeKey != null || showingCatalog}>
  <header class="topbar">
    <a class="brand" href="#/">Sky Bother</a>
    {#if settings}
      <a class="nav" href="#/catalog" aria-current={showingCatalog ? 'page' : undefined}>Catalog</a>
      <button type="button" class="site-button" onclick={() => { editingSite = !editingSite; editingSettings = false; }} title="Change site">
        {settings.site.name || 'Unnamed site'} <span aria-hidden="true">▾</span>
      </button>
      <button type="button" class="icon" onclick={() => { editingSettings = !editingSettings; editingSite = false; }}
              title="Settings" aria-label="Settings" aria-expanded={editingSettings}>⚙︎</button>
      <button type="button" class="icon" onclick={refresh} disabled={loading} title="Fetch the latest forecast" aria-label="Refresh">
        <span class:spinning={loading}>↻</span>
      </button>
    {/if}
  </header>

  {#if !settings || editingSite}
    <div class="site-area">
      <SitePanel {settings} onsite={setSite} onimport={importSettings} onbortle={setBortle}
                 oncancel={() => (editingSite = false)} />
    </div>
  {/if}

  {#if settings && editingSettings && rigPresets.length}
    <div class="site-area">
      <SettingsPanel {settings} {rigPresets} onchange={changeSettings} ondone={() => (editingSettings = false)} />
    </div>
  {/if}

  {#if loading && status}<p class="status-bar" role="status"><span class="spinning">↻</span> {status}</p>{/if}
  {#if error}<p class="error banner">{error}</p>{/if}

  {#if settings}
    <div class="layout">
      <aside class="sidebar">
        <h3>Nights</h3>
        {#if nights.length}
          <NightList {nights} selectedKey={showingCatalog ? null : night?.planKey} />
        {:else if loading}
          <p class="muted">Loading forecast…</p>
        {/if}
        <footer class="muted">
          {#if updatedAt}<div>Forecast updated {(clock, age(updatedAt))}</div>{/if}
          <div>Bortle {settings.site.bortleClass} · {settings.rig.name}</div>
        </footer>
      </aside>

      <main class="content">
        {#if showingCatalog && nights.length}
          <a class="back" href="#/">‹ All nights</a>
          <Catalog entries={catalog} {nights} timeZone={settings.site.timeZoneIdentifier} />
        {:else if night}
          <a class="back" href="#/">‹ All nights</a>
          {#key night.planKey}
            <NightDetail {night} isTonight={night.planKey === nights[0]?.planKey}
                         timeZone={settings.site.timeZoneIdentifier} preferences={settings.preferences}
                         targetID={routeKey === night.planKey ? routeTarget : null} />
          {/key}
        {/if}
      </main>
    </div>
  {:else}
    <p class="empty muted">Choose a site to see the week ahead.</p>
  {/if}
</div>

<style>
  .app { max-width: 1760px; margin: 0 auto; padding: 0 16px 48px; }
  .topbar {
    position: sticky; top: 0; z-index: 2; display: flex; align-items: center; gap: 10px;
    padding: 12px 0; background: var(--space-top); border-bottom: 1px solid var(--panel-border);
  }
  .brand { font-weight: 700; font-size: 19px; color: var(--text); text-decoration: none; margin-right: auto; white-space: nowrap; }
  .nav { color: var(--muted); text-decoration: none; font-weight: 600; padding: 6px 4px; }
  .nav[aria-current='page'], .nav:hover { color: var(--accent); }
  .site-button { background: none; border-color: transparent; color: var(--muted); min-width: 0; max-width: 50vw; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .icon { width: 36px; padding: 6px 0; }
  .spinning { display: inline-block; animation: spin 1s linear infinite; }
  @keyframes spin { to { transform: rotate(360deg); } }
  .site-area { margin-top: 14px; }
  .banner { margin: 14px 0 0; }
  .status-bar {
    margin: 14px 0 0; padding: 10px 14px; border-radius: 10px; color: var(--text);
    background: rgba(158, 133, 250, 0.14); border: 1px solid rgba(158, 133, 250, 0.4);
  }
  .empty { margin: 20px 2px; }

  .layout { display: grid; grid-template-columns: 300px minmax(0, 1fr); gap: 24px; margin-top: 16px; }
  .sidebar { display: grid; gap: 6px; align-content: start; position: sticky; top: 72px; }
  .sidebar h3 { margin: 0 8px; font-size: 13px; text-transform: uppercase; letter-spacing: 0.06em; color: var(--accent); }
  .sidebar footer { display: grid; gap: 3px; margin: 14px 8px 0; padding-top: 14px; border-top: 1px solid var(--panel-border); font-size: 12px; }
  .back { display: none; }

  /* Phone: the list is one screen and a night is the next. */
  @media (max-width: 860px) {
    .layout { grid-template-columns: minmax(0, 1fr); }
    .sidebar { position: static; }
    .showing-night .sidebar { display: none; }
    .app:not(.showing-night) .content { display: none; }
    .back { display: inline-block; margin-bottom: 10px; color: var(--accent); text-decoration: none; font-weight: 600; }
  }
</style>
