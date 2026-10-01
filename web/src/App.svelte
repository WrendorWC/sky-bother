<script>
  import { defaults, planNights } from './engine/engine.js';
  import { fetchForecast, fetchCometElements } from './weather.js';
  import NightList from './lib/NightList.svelte';
  import NightDetail from './lib/NightDetail.svelte';
  import SitePanel from './lib/SitePanel.svelte';
  import { age } from './lib/format.js';

  const storageKey = 'skybother.settings.v1';

  let settings = $state(loadSettings());
  let nights = $state([]);
  let loading = $state(false);
  let error = $state('');
  let updatedAt = $state(null);
  let editingSite = $state(false);
  let clock = $state(Date.now());

  // #/2026-10-01 is a night; anything else is the list (on a phone) or tonight.
  let route = $state(location.hash);
  const routeKey = $derived(/^#\/(\d{4}-\d{2}-\d{2})$/.exec(route)?.[1] ?? null);
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
    const base = settings ?? (await defaults());
    settings = { rig: base.rig, preferences: base.preferences, customTargets: base.customTargets ?? [], site };
    editingSite = false;
    saveSettings();
    refresh();
  }

  function importSettings(imported) {
    settings = imported;
    editingSite = false;
    saveSettings();
    refresh();
  }

  function setBortle(value) {
    settings.site.bortleClass = value;
    saveSettings();
    refresh();
  }

  async function refresh() {
    if (!settings) return;
    error = '';
    loading = true;
    try {
      const { site, preferences } = settings;
      const [openMeteoResponse, cometElements] = await Promise.all([
        fetchForecast(site.latitude, site.longitude, preferences.forecastNights),
        fetchCometElements(),
      ]);
      nights = await planNights({ ...$state.snapshot(settings), openMeteoResponse, cometElements, now: new Date().toISOString().replace(/\.\d+Z$/, 'Z') });
      updatedAt = Date.now();
    } catch (e) {
      error = e.message;
    } finally {
      loading = false;
    }
  }

  $effect(() => {
    const onHash = () => (route = location.hash);
    const tick = setInterval(() => (clock = Date.now()), 60_000);
    addEventListener('hashchange', onHash);
    return () => { removeEventListener('hashchange', onHash); clearInterval(tick); };
  });

  refresh();
</script>

<div class="app" class:showing-night={routeKey != null}>
  <header class="topbar">
    <a class="brand" href="#/">Sky Bother</a>
    {#if settings}
      <button type="button" class="site-button" onclick={() => (editingSite = !editingSite)} title="Change site">
        {settings.site.name || 'Unnamed site'} <span aria-hidden="true">▾</span>
      </button>
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

  {#if error}<p class="error banner">{error}</p>{/if}

  {#if settings}
    <div class="layout">
      <aside class="sidebar">
        <h3>Nights</h3>
        {#if nights.length}
          <NightList {nights} selectedKey={night?.planKey} />
        {:else if loading}
          <p class="muted">Loading forecast…</p>
        {/if}
        <footer class="muted">
          {#if updatedAt}<div>Forecast updated {(clock, age(updatedAt))}</div>{/if}
          <div>Bortle {settings.site.bortleClass} · {settings.rig.name}</div>
        </footer>
      </aside>

      <main class="content">
        {#if night}
          <a class="back" href="#/">‹ All nights</a>
          {#key night.planKey}
            <NightDetail {night} isTonight={night.planKey === nights[0]?.planKey}
                         timeZone={settings.site.timeZoneIdentifier} preferences={settings.preferences} />
          {/key}
        {/if}
      </main>
    </div>
  {:else}
    <p class="empty muted">Choose a site to see the week ahead.</p>
  {/if}
</div>

<style>
  .app { max-width: 1280px; margin: 0 auto; padding: 0 16px 48px; }
  .topbar {
    position: sticky; top: 0; z-index: 2; display: flex; align-items: center; gap: 10px;
    padding: 12px 0; background: var(--space-top); border-bottom: 1px solid var(--panel-border);
  }
  .brand { font-weight: 700; font-size: 19px; color: var(--text); text-decoration: none; margin-right: auto; }
  .site-button { background: none; border-color: transparent; color: var(--muted); max-width: 50vw; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .icon { width: 36px; padding: 6px 0; }
  .spinning { display: inline-block; animation: spin 1s linear infinite; }
  @keyframes spin { to { transform: rotate(360deg); } }
  .site-area { margin-top: 14px; }
  .banner { margin: 14px 0 0; }
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
