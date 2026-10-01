<script>
  import { defaults, planNights, catalogEntries } from './engine/engine.js';
  import { fetchForecast, fetchCometElements } from './weather.js';
  import NightList from './lib/NightList.svelte';
  import NightDetail from './lib/NightDetail.svelte';
  import SitePanel from './lib/SitePanel.svelte';
  import SettingsPanel from './lib/SettingsPanel.svelte';
  import Catalog from './lib/Catalog.svelte';
  import SkyView from './lib/SkyView.svelte';
  import { age } from './lib/format.js';
  import { isSetupHash, readSetup } from './lib/setupLink.js';

  const storageKey = 'skybother.settings.v1';

  let settings = $state(loadSettings());
  // A #setup= link opened here, waiting for "Use this setup".
  let offeredSetup = $state(null);
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
  // #/sky/2026-10-01, or #/sky/2026-10-01/M76 with a target selected.
  const skyMatch = $derived(/^#\/sky\/(\d{4}-\d{2}-\d{2})(?:\/(.+))?$/.exec(route));
  const skyNight = $derived(skyMatch ? nights.find(n => n.planKey === skyMatch[1]) ?? null : null);
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

  function checkForSetup() {
    if (!isSetupHash(location.hash)) return;
    try {
      offeredSetup = readSetup(location.hash);
    } catch {
      error = 'That setup link is damaged or incomplete.';
    }
    history.replaceState(null, '', location.pathname);
    route = '';
  }

  function useOfferedSetup() {
    settings = offeredSetup;
    offeredSetup = null;
    editingSite = false;
    nights = [];
    saveSettings();
    refresh();
  }

  checkForSetup();

  $effect(() => {
    const onHash = () => {
      checkForSetup();
      route = location.hash;
    };
    const tick = setInterval(() => (clock = Date.now()), 60_000);
    addEventListener('hashchange', onHash);
    return () => { removeEventListener('hashchange', onHash); clearInterval(tick); };
  });

  defaults().then(d => (rigPresets = d.rigPresets));
  refresh();
</script>

<div class="app" class:showing-night={routeKey != null || showingCatalog || skyMatch}>
  <header class="topbar">
    <a class="brand" href="#/">Sky Bother</a>
    {#if settings}
      <a class="nav" href="#/catalog" aria-current={showingCatalog ? 'page' : undefined}>Catalog</a>
      <button type="button" class="site-button" onclick={() => { editingSite = !editingSite; editingSettings = false; }} title="Change site">
        {settings.site.name || 'Unnamed site'} <span aria-hidden="true">▾</span>
      </button>
      <button type="button" class="icon" onclick={() => { editingSettings = !editingSettings; editingSite = false; }}
              title="Settings" aria-label="Settings" aria-expanded={editingSettings}>
        <svg viewBox="0 0 24 24" aria-hidden="true">
          <path d="M19.4 13a7.6 7.6 0 0 0 0-2l2.1-1.6-2-3.5-2.5 1a7.4 7.4 0 0 0-1.7-1L15 3.3h-4l-.4 2.6a7.4 7.4 0 0 0-1.7 1l-2.5-1-2 3.5L6.5 11a7.6 7.6 0 0 0 0 2l-2.1 1.6 2 3.5 2.5-1a7.4 7.4 0 0 0 1.7 1l.4 2.6h4l.4-2.6a7.4 7.4 0 0 0 1.7-1l2.5 1 2-3.5z" />
          <circle cx="12" cy="12" r="3" />
        </svg>
      </button>
      <button type="button" class="icon" onclick={refresh} disabled={loading} title="Fetch the latest forecast" aria-label="Refresh">
        <svg class:spinning={loading} viewBox="0 0 24 24" aria-hidden="true">
          <path d="M20 12a8 8 0 1 1-2.34-5.66" />
          <path d="M20 4v5h-5" />
        </svg>
      </button>
    {/if}
  </header>

  {#if offeredSetup}
    <section class="panel offer" role="dialog" aria-label="Use this setup?">
      <p><strong>Use this setup?</strong></p>
      <p class="muted-strong">
        {offeredSetup.site.name || 'Unnamed site'} · {offeredSetup.rig.name} ·
        {offeredSetup.preferences.maximumCloudCover}% cloud limit
      </p>
      {#if settings}<p class="muted">It replaces this browser's site, rig and settings.</p>{/if}
      <div class="offer-buttons">
        <button type="button" class="primary" onclick={useOfferedSetup}>Use This Setup</button>
        <button type="button" onclick={() => (offeredSetup = null)}>Cancel</button>
      </div>
    </section>
  {/if}

  {#if (!settings && !offeredSetup) || editingSite}
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
          <NightList {nights} selectedKey={showingCatalog ? null : skyNight?.planKey ?? night?.planKey} />
        {:else if loading}
          <p class="muted">Loading forecast…</p>
        {/if}
        <footer class="muted">
          {#if updatedAt}<div>Forecast updated {(clock, age(updatedAt))}</div>{/if}
          <div>Bortle {settings.site.bortleClass} · {settings.rig.name}</div>
        </footer>
      </aside>

      <main class="content">
        {#if skyNight}
          {#key skyNight.planKey}
            <SkyView night={skyNight} timeZone={settings.site.timeZoneIdentifier}
                     targetID={skyMatch[2] ? decodeURIComponent(skyMatch[2]) : null}
                     showsClouds={settings.preferences.showsClouds ?? true} />
          {/key}
        {:else if showingCatalog && nights.length}
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
  {:else if !offeredSetup}
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
  .icon { width: 40px; height: 40px; padding: 0; display: grid; place-items: center; flex: none; }
  .icon svg { width: 22px; height: 22px; fill: none; stroke: currentColor; stroke-width: 1.8; stroke-linecap: round; stroke-linejoin: round; }
  .spinning { display: inline-block; animation: spin 1s linear infinite; }
  @keyframes spin { to { transform: rotate(360deg); } }
  .site-area { margin-top: 14px; }
  .banner { margin: 14px 0 0; }
  .offer { margin-top: 14px; padding: 14px; display: grid; gap: 6px; border-color: var(--accent); }
  .offer p { margin: 0; }
  .offer-buttons { display: flex; gap: 8px; margin-top: 6px; }
  .primary { background: var(--accent); border-color: var(--accent); color: #120e22; font-weight: 600; }
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
