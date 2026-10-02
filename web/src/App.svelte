<script>
  import { defaults, planNights, catalogEntries } from './engine/engine.js';
  import { fetchForecast, fetchCometElements } from './weather.js';
  import NightList from './lib/NightList.svelte';
  import NightDetail from './lib/NightDetail.svelte';
  import SettingsPanel from './lib/SettingsPanel.svelte';
  import Catalog from './lib/Catalog.svelte';
  import SkyView from './lib/SkyView.svelte';
  import Planner from './lib/Planner.svelte';
  import SessionView from './lib/SessionView.svelte';
  import HelpPage from './lib/HelpPage.svelte';
  import NearbySpots from './lib/NearbySpots.svelte';
  import { uuid as newID } from './lib/uuid.js';
  import SetupWizard from './lib/SetupWizard.svelte';
  import { age } from './lib/format.js';
  import { isSetupHash, readSetup } from './lib/setupLink.js';
  import { view } from './lib/view.svelte.js';
  import { sync, runSync, startSync } from './lib/syncState.svelte.js';
  import { format as formatCode, normalize as normalizeCode, SECTIONS as SYNC_SECTIONS } from './lib/sync.js';

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
  // Which forecast the week came from; anything but 'open-meteo' is a backup.
  let forecastSource = $state('open-meteo');
  let editingSettings = $state(false);
  // Where Settings opens: 'location' from the site name.
  let settingsFocus = $state(null);
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
  // Where the Catalog's Done (or the Catalog button again) goes back to.
  let catalogReturn = $state('#/');
  $effect(() => {
    if (route !== '#/catalog' && !route.startsWith('#/help')) catalogReturn = route || '#/';
  });
  function leaveCatalog() {
    location.hash = catalogReturn;
  }
  // #/help or #/help/<topic>
  const helpMatch = $derived(/^#\/help(?:\/([a-z]+))?$/.exec(route));
  function openHelp(event) {
    event.preventDefault();
    if (editingSettings && settingsDirty && !confirm('Discard your unsaved settings changes?')) return;
    editingSettings = false;
    settingsDirty = false;
    location.hash = '#/help';
  }
  // #/sky/2026-10-01, or #/sky/2026-10-01/M76 with a target selected.
  const skyMatch = $derived(/^#\/sky\/(\d{4}-\d{2}-\d{2})(?:\/(.+))?$/.exec(route));
  const skyNight = $derived(skyMatch ? nights.find(n => n.planKey === skyMatch[1]) ?? null : null);
  // #/session/2026-10-01: Session View, for use at the scope.
  const sessionMatch = $derived(/^#\/session\/(\d{4}-\d{2}-\d{2})$/.exec(route));
  const sessionNight = $derived(sessionMatch ? nights.find(n => n.planKey === sessionMatch[1]) ?? null : null);
  // #/plan/2026-10-01: the planner on that night.
  const planMatch = $derived(/^#\/plan\/(\d{4}-\d{2}-\d{2})$/.exec(route));
  const planNight = $derived(planMatch ? nights.find(n => n.planKey === planMatch[1]) ?? null : null);

  // Done in the planner: a night's plan becomes yours (null goes back to
  // the suggestion), stored as the Mac app stores it (sessionPlans).
  const inSetup = $derived(!offeredSetup && (!settings || settings.setupStep != null));

  function finishSetup(planKey) {
    const { setupStep, ...rest } = settings;
    settings = rest;
    saveSettings();
    location.hash = planKey ? `#/${planKey}` : '#/';
  }

  function startSetup() {
    editingSettings = false;
    changeSettings({ ...settings, setupStep: 0 });
  }

  function savePlan(planKey, segments) {
    const plans = { ...(settings.sessionPlans ?? {}) };
    if (segments) plans[planKey] = segments;
    else delete plans[planKey];
    settings = { ...settings, sessionPlans: plans };
    saveSettings();
    replan();
  }
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
    scheduleSync();
  }

  // --- Sync -------------------------------------------------------------------
  // Shortly after any change, when the page comes back into view, every two
  // minutes, and on load. What comes back from other devices replaces what's
  // here and re-plans.
  let syncTimer = null;
  function scheduleSync() {
    if (!sync.code) return;
    clearTimeout(syncTimer);
    syncTimer = setTimeout(() => syncNow(), 2000);
  }

  async function syncNow({ joining = false } = {}) {
    const sent = settings;
    let next = await runSync(sent, { joining });
    // A change saved while a round was out (or while one was busy, when
    // this one did nothing) still needs to go up.
    if (!next) {
      if (sent && settings !== sent && JSON.stringify(settings) !== JSON.stringify(sent)) setTimeout(() => syncNow(), 0);
      return;
    }
    // Anything changed here while the round was out — a Save in Settings,
    // say — is newer than what came back, and taking the round's result
    // over it put the old value back for good. Those sections stay, and go
    // up in another round.
    let changedMeanwhile = false;
    if (!joining && sent && settings !== sent) {
      next = { ...next };
      for (const key of SYNC_SECTIONS) {
        if (JSON.stringify(settings[key]) !== JSON.stringify(sent[key])) {
          next[key] = settings[key];
          changedMeanwhile = true;
        }
      }
      if (changedMeanwhile) setTimeout(() => syncNow(), 0);
    }
    const siteChanged = JSON.stringify(next.site) !== JSON.stringify(settings?.site);
    settings = next;
    try { localStorage.setItem(storageKey, JSON.stringify(settings)); } catch {}
    siteChanged ? refresh() : replan();
  }

  function joinSync() {
    editingSettings = false;
    syncNow({ joining: true });
  }

  // A #sync=CODE link: offer to join.
  let offeredSync = $state(null);
  function checkForSyncLink() {
    const match = /^#sync=([0-9A-Za-z-]+)$/.exec(location.hash);
    if (!match) return;
    history.replaceState(null, '', location.pathname);
    route = '';
    if (normalizeCode(match[1]).length === 26) offeredSync = formatCode(match[1]);
  }
  function acceptSync() {
    startSync(offeredSync);
    offeredSync = null;
    joinSync();
  }

  $effect(() => {
    const visible = () => { if (document.visibilityState === 'visible') syncNow(); };
    // Only while the page is in front: a tab left open in the background
    // doesn't need to keep checking in.
    const timer = setInterval(() => { if (document.visibilityState === 'visible') syncNow(); }, 120_000);
    document.addEventListener('visibilitychange', visible);
    return () => { clearInterval(timer); document.removeEventListener('visibilitychange', visible); };
  });

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
    // Saved sites and rigs come along (a fresh browser has none yet), and
    // the site being left is saved first if it wasn't: replacing it outright
    // is how a Mac back-yard site with its horizon got lost.
    const saved = [...(base.savedSites ?? [])];
    if (settings?.site && !saved.some(s => s.id === settings.site.id)) saved.push({ ...settings.site });
    settings = { ...base, rig: base.rig, preferences: base.preferences, customTargets: base.customTargets ?? [], site, savedSites: saved };
    // A first site starts the rest of the setup wizard (or keeps its step).
    settings.setupStep = base.setupStep ?? (base.site ? undefined : 0);
    delete settings.rigPresets;
    editingSettings = false;
    saveSettings();
    refresh();
  }

  function importSettings(imported) {
    nights = [];
    settings = imported;
    editingSettings = false;
    saveSettings();
    refresh();
  }

  // Settings' Save: a new site needs a new forecast; anything else a replan.
  let settingsDirty = $state(false);
  function saveFromSettings(changed) {
    const before = settings.site;
    const siteMoved = before.latitude !== changed.site.latitude || before.longitude !== changed.site.longitude
      || before.timeZoneIdentifier !== changed.site.timeZoneIdentifier
      || changed.preferences.forecastNights !== settings.preferences.forecastNights;
    settings = changed;
    saveSettings();
    if (siteMoved) { nights = []; refresh(); } else replan();
  }
  // Leaving Settings from the toolbar with unsaved changes asks first.
  function toggleSettings(focus) {
    if (editingSettings && settingsDirty && !confirm('Discard your unsaved settings changes?')) return;
    settingsFocus = focus;
    editingSettings = focus === 'location' ? true : !editingSettings;
    if (!editingSettings) settingsDirty = false;
  }

  // Better Spot Nearby (AppState.useNearbySpot): plan from the spot, saved
  // beside the site it came from, with "Back to …" while it's in use.
  let spotDetour = $state(null);
  const spotReturnSite = $derived(spotDetour && settings?.site.id === spotDetour.toID
    ? (settings.savedSites ?? []).find(s => s.id === spotDetour.from.id) ?? spotDetour.from : null);
  function useNearbySpot(spot) {
    const previous = settings.site;
    const saved = [...(settings.savedSites ?? [])];
    const index = saved.findIndex(s => s.id === previous.id);
    if (index >= 0) saved[index] = { ...previous }; else saved.push({ ...previous });
    // Picking the same place twice reuses it, with any corrections since.
    const site = saved.find(s => Math.abs(s.latitude - spot.latitude) < 0.002 && Math.abs(s.longitude - spot.longitude) < 0.002) ?? {
      id: newID(), name: spot.name, latitude: spot.latitude, longitude: spot.longitude,
      elevationMeters: previous.elevationMeters, timeZoneIdentifier: previous.timeZoneIdentifier,
      bortleClass: spot.estimatedBortleClass, horizonAltitude: spot.horizonAltitude ?? previous.horizonAltitude,
    };
    if (!saved.some(s => s.id === site.id)) saved.push(site);
    spotDetour = { from: previous, toID: site.id };
    settings = { ...settings, site, savedSites: saved };
    saveSettings();
    nights = [];
    refresh();
  }
  function returnFromSpot() {
    const home = spotReturnSite;
    if (!home) return;
    spotDetour = null;
    settings = { ...settings, site: home };
    saveSettings();
    nights = [];
    refresh();
  }
  // Adopts the satellite estimate as this site's Bortle class, saved copy too.
  function useEstimatedBortle(bortleClass) {
    const site = { ...settings.site, bortleClass };
    changeSettings({ ...settings, site, savedSites: (settings.savedSites ?? []).map(s => (s.id === site.id ? { ...site } : s)) });
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
      const [forecast, cometElements] = await Promise.all([
        fetchForecast(site.latitude, site.longitude, preferences.forecastNights),
        fetchCometElements(),
      ]);
      fetched = { key: `${site.latitude},${site.longitude}`, forecast, cometElements };
      forecastSource = forecast.source;
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
    const { forecast, cometElements } = fetched;
    const body = forecast.source === 'met-norway' ? { metNorwayResponse: forecast.body } : { openMeteoResponse: forecast.body };
    nights = await planNights({ ...$state.snapshot(settings), ...body, cometElements, now: new Date().toISOString().replace(/\.\d+Z$/, 'Z') });
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
    nights = [];
    saveSettings();
    refresh();
  }

  checkForSetup();
  checkForSyncLink();

  // The rig every frame drawing uses (Sky View, "In your frame").
  $effect(() => {
    view.rig = settings?.rig ?? null;
  });

  // Night mode: everything in shades of red (app.css), to keep your eyes
  // dark-adapted at the scope.
  $effect(() => {
    document.documentElement.classList.toggle('night-mode', !!settings?.preferences?.nightMode);
  });

  $effect(() => {
    const onHash = () => {
      checkForSetup();
      checkForSyncLink();
      route = location.hash;
    };
    const tick = setInterval(() => (clock = Date.now()), 60_000);
    addEventListener('hashchange', onHash);
    return () => { removeEventListener('hashchange', onHash); clearInterval(tick); };
  });

  defaults().then(d => (rigPresets = d.rigPresets));
  refresh();
  syncNow();
</script>

<div class="app" class:showing-night={routeKey != null || showingCatalog || skyMatch || planMatch || sessionMatch} class:planning={planMatch || sessionMatch}>
  <!-- The Mac window's toolbar: the site and refresh on the left of the
       tools, then Settings, Catalog and Night Mode as labelled buttons in
       one group (icons only on a phone). -->
  <header class="topbar">
    <a class="brand" href="#/">Sky Bother</a>
    {#if settings}
      <button type="button" class="site-button" onclick={() => toggleSettings('location')} title="Change location">
        <svg class="pin" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 21s-7-6.2-7-11.5A7 7 0 0 1 19 9.5C19 14.8 12 21 12 21z" /><circle cx="12" cy="9.5" r="2.5" /></svg>
        <span class="site-name">{settings.site.name || 'Unnamed site'}</span>
      </button>
      <button type="button" class="icon" onclick={refresh} disabled={loading} title="Fetch the latest forecast" aria-label="Refresh">
        <svg class:spinning={loading} viewBox="0 0 24 24" aria-hidden="true">
          <path d="M20 12a8 8 0 1 1-2.34-5.66" />
          <path d="M20 4v5h-5" />
        </svg>
      </button>
    {/if}
    <nav class="tools" aria-label="Tools">
      <button type="button" class="tool" class:on={editingSettings} onclick={() => toggleSettings(null)}
              title="Settings" aria-label="Settings" aria-expanded={editingSettings}>
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9.96 5.10 L10.17 2.58 L13.83 2.58 L14.04 5.10 L15.44 5.67 L17.37 4.04 L19.96 6.63 L18.33 8.56 L18.90 9.96 L21.42 10.17 L21.42 13.83 L18.90 14.04 L18.33 15.44 L19.96 17.37 L17.37 19.96 L15.44 18.33 L14.04 18.90 L13.83 21.42 L10.17 21.42 L9.96 18.90 L8.56 18.33 L6.63 19.96 L4.04 17.37 L5.67 15.44 L5.10 14.04 L2.58 13.83 L2.58 10.17 L5.10 9.96 L5.67 8.56 L4.04 6.63 L6.63 4.04 L8.56 5.67 Z" /><circle cx="12" cy="12" r="3" /></svg><span class="tool-label">Settings</span>
      </button>
      {#if settings}
        <a class="tool" href="#/help" onclick={openHelp} aria-current={helpMatch ? 'page' : undefined} title="Help">
          <svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9" /><path d="M9.6 9.3a2.5 2.5 0 1 1 3.5 2.3c-.7.3-1.1.9-1.1 1.6v.6" /><circle cx="12" cy="16.8" r="0.4" /></svg><span class="tool-label">Help</span>
        </a>
        <a class="tool" href={showingCatalog ? catalogReturn : '#/catalog'} aria-current={showingCatalog ? 'page' : undefined}
           title={showingCatalog ? 'Close the catalog' : 'Catalog'}>
          <svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="4" width="18" height="16" rx="2" /><path d="M3 9h18M8 4v16" /></svg><span class="tool-label">Catalog</span>
        </a>
        <button type="button" class="tool" class:on={settings.preferences.nightMode} title="Night mode: red light only"
                aria-pressed={!!settings.preferences.nightMode}
                onclick={() => changeSettings({ ...settings, preferences: { ...settings.preferences, nightMode: !settings.preferences.nightMode } })}>
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z" /></svg><span class="tool-label">Night Mode</span>
        </button>
      {/if}
    </nav>
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

  {#if offeredSync}
    <section class="panel offer" role="dialog" aria-label="Sync this browser?">
      <p><strong>Sync this browser?</strong></p>
      <p class="muted-strong">Code {offeredSync}</p>
      <p class="muted">This browser takes on the synced sites, telescope, settings and plans, and keeps them in step from now on.</p>
      <div class="offer-buttons">
        <button type="button" class="primary" onclick={acceptSync}>Sync</button>
        <button type="button" onclick={() => (offeredSync = null)}>Cancel</button>
      </div>
    </section>
  {/if}

  {#if inSetup}
    <SetupWizard {settings} {rigPresets} {nights} {loading} onsite={setSite} onchange={changeSettings}
                 onimport={importSettings} onfinish={finishSetup} onsyncjoin={joinSync} />
  {/if}

  {#if settings && !inSetup && editingSettings && rigPresets.length}
    <div class="site-area">
      <SettingsPanel {settings} {rigPresets} onsave={saveFromSettings} onimport={importSettings} onsetup={startSetup}
                     onsyncjoin={joinSync} onsyncstart={() => syncNow()} onsyncnow={() => syncNow()}
                     ondirty={d => (settingsDirty = d)} focus={settingsFocus} ondone={() => { editingSettings = false; settingsDirty = false; }} />
    </div>
  {/if}

  {#if loading && status}<p class="status-bar" role="status"><span class="spinning">↻</span> {status}</p>{/if}
  {#if error}<p class="error banner">{error}</p>{/if}

  <!-- Settings is a screen of its own: nothing else shows until it's closed. -->
  {#if helpMatch && !editingSettings}
    <HelpPage topic={helpMatch[1] ?? null} />
  {:else if settings && !inSetup && !editingSettings}
    <div class="layout">
      <aside class="sidebar">
        <h3>Nights</h3>
        {#if nights.length}
          <NightList {nights} selectedKey={showingCatalog ? null : planNight?.planKey ?? skyNight?.planKey ?? night?.planKey}
                     linkPrefix={planNight ? '#/plan/' : '#/'} />
        {:else if loading}
          <p class="muted">Loading forecast…</p>
        {/if}
        {#if nights.length}
          <NearbySpots site={settings.site} preferences={settings.preferences} tonight={nights[0]} timeZone={settings.site.timeZoneIdentifier} returnSite={spotReturnSite} onuse={useNearbySpot} onback={returnFromSpot} onbortle={useEstimatedBortle} />
        {/if}
        <footer class="muted">
          {#if updatedAt}
            <div>Forecast updated {(clock, age(updatedAt))}{forecastSource !== 'open-meteo' ? ' · backup source' : ''}</div>
            {#if forecastSource !== 'open-meteo'}
              <div class="backup">Open-Meteo's main forecast wasn't answering, so this week is from {forecastSource === 'met-norway' ? 'MET Norway' : "Open-Meteo's basic model"}. Scores can differ from the Mac app until it's back; refresh to try again.</div>
            {/if}
          {/if}
          <div>Bortle {settings.site.bortleClass} · {settings.rig.name}</div>
        </footer>
      </aside>

      <main class="content">
        {#if sessionNight}
          {#key sessionNight.planKey}
            <SessionView night={sessionNight} timeZone={settings.site.timeZoneIdentifier} preferences={settings.preferences} rig={settings.rig} />
          {/key}
        {:else if planNight}
          {#key planNight.planKey}
            <Planner night={planNight} {nights} timeZone={settings.site.timeZoneIdentifier} preferences={settings.preferences}
                     onsave={savePlan} onleave={() => (location.hash = `#/${planNight.planKey}`)} />
          {/key}
        {:else if skyNight}
          {#key skyNight.planKey}
            <SkyView night={skyNight} timeZone={settings.site.timeZoneIdentifier}
                     targetID={skyMatch[2] ? decodeURIComponent(skyMatch[2]) : null}
                     rig={settings.rig} preferences={settings.preferences} />
          {/key}
        {:else if showingCatalog && nights.length}
          <a class="back" href="#/">‹ All nights</a>
          <Catalog entries={catalog} {nights} timeZone={settings.site.timeZoneIdentifier} preferences={settings.preferences}
                   customTargets={settings.customTargets ?? []} oncustom={list => changeSettings({ ...settings, customTargets: list })}
                   onclose={leaveCatalog} />
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
  {/if}
</div>

<style>
  .app { max-width: 1760px; margin: 0 auto; padding: 0 16px 48px; }
  .topbar {
    position: sticky; top: 0; z-index: 2; display: flex; align-items: center; gap: 10px;
    padding: 12px 0; background: var(--space-top); border-bottom: 1px solid var(--panel-border);
  }
  .brand { font-weight: 700; font-size: 19px; color: var(--text); text-decoration: none; margin-right: auto; white-space: nowrap; }
  .tools {
    display: flex; gap: 2px; padding: 3px; border-radius: 12px; flex: none;
    background: var(--panel); border: 1px solid var(--panel-border);
  }
  .tool {
    display: flex; gap: 7px; align-items: center; padding: 7px 11px; border-radius: 9px; border: none;
    background: none; color: var(--text); font-weight: 600; text-decoration: none; font-size: 15px;
  }
  .tool:hover { background: rgba(158, 133, 250, 0.12); }
  .tool.on, .tool[aria-current='page'] { background: rgba(158, 133, 250, 0.25); color: var(--accent); }
  .tool svg, .pin { width: 20px; height: 20px; fill: none; stroke: currentColor; stroke-width: 1.8; stroke-linecap: round; stroke-linejoin: round; flex: none; }
  .site-button { display: flex; gap: 6px; align-items: center; }
  .site-name { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .site-button { background: none; border-color: transparent; color: var(--muted); min-width: 0; max-width: 50vw; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  /* 44 px: a comfortable tap on a phone. */
  .icon { width: 44px; height: 44px; padding: 0; display: grid; place-items: center; flex: none; }
  .icon svg { width: 26px; height: 26px; fill: none; stroke: currentColor; stroke-width: 2; stroke-linecap: round; stroke-linejoin: round; }
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
  .backup { color: var(--marginal); }
  .sidebar footer { display: grid; gap: 3px; margin: 14px 8px 0; padding-top: 14px; border-top: 1px solid var(--panel-border); font-size: 12px; }
  .back { display: none; }
  /* The planner takes the whole window, as on the Mac. */
  .planning .layout { grid-template-columns: minmax(0, 1fr); }
  .planning .sidebar { display: none; }

  /* Phone: the list is one screen and a night is the next. */
  @media (max-width: 860px) {
    .layout { grid-template-columns: minmax(0, 1fr); }
    .sidebar { position: static; }
    .showing-night .sidebar { display: none; }
    .app:not(.showing-night) .content { display: none; }
    .tool-label { display: none; }
    .tool { padding: 9px; }
    .tool svg { width: 24px; height: 24px; }
    .back { display: inline-block; margin-bottom: 10px; color: var(--accent); text-decoration: none; font-weight: 600; }
  }
</style>
