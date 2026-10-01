<script>
  import { defaults, planNights } from './engine/engine.js';
  import { fetchForecast, searchPlaces, elevationAt, fetchCometElements } from './weather.js';

  const storageKey = 'skybother.settings.v1';

  let settings = $state(loadSettings());
  let nights = $state([]);
  let status = $state('');
  let error = $state('');
  let query = $state('');
  let places = $state([]);

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
    places = [];
    query = '';
    saveSettings();
    refresh();
  }

  async function search() {
    error = '';
    try {
      places = await searchPlaces(query);
      if (places.length === 0) error = `Nothing found for “${query}”.`;
    } catch (e) {
      error = e.message;
    }
  }

  function choosePlace(place) {
    setSite(newSite({
      name: [place.name, place.admin1, place.country_code].filter(Boolean).join(', '),
      latitude: place.latitude,
      longitude: place.longitude,
      elevationMeters: place.elevation ?? 0,
      timeZoneIdentifier: place.timezone,
    }));
  }

  function useMyLocation() {
    error = '';
    status = 'Finding you…';
    navigator.geolocation.getCurrentPosition(
      async ({ coords }) => {
        const elevation = await elevationAt(coords.latitude, coords.longitude);
        setSite(newSite({
          name: 'My Location',
          latitude: coords.latitude,
          longitude: coords.longitude,
          elevationMeters: elevation,
          timeZoneIdentifier: Intl.DateTimeFormat().resolvedOptions().timeZone,
        }));
      },
      e => { status = ''; error = e.message; },
    );
  }

  // Same starting values as Site.unset in the Mac app.
  function newSite(fields) {
    return { id: crypto.randomUUID().toUpperCase(), bortleClass: 5, horizonAltitude: 20, ...fields };
  }

  // Reads the Mac app's settings.json (~/Library/Application Support/SkyBother).
  async function importMacSettings(event) {
    const file = event.currentTarget.files?.[0];
    if (!file) return;
    try {
      const stored = JSON.parse(await file.text());
      if (!stored.site || !stored.rig || !stored.preferences) throw new Error('That isn’t a Sky Bother settings file.');
      settings = { site: stored.site, rig: stored.rig, preferences: stored.preferences, customTargets: stored.customTargets ?? [] };
      saveSettings();
      refresh();
    } catch (e) {
      error = e.message;
    }
  }

  function setBortle(value) {
    settings.site.bortleClass = Number(value);
    saveSettings();
    refresh();
  }

  async function refresh() {
    if (!settings) return;
    error = '';
    status = 'Fetching the forecast…';
    try {
      const { site, preferences } = settings;
      const [openMeteoResponse, cometElements] = await Promise.all([
        fetchForecast(site.latitude, site.longitude, preferences.forecastNights),
        fetchCometElements(),
      ]);
      status = 'Planning…';
      const started = performance.now();
      nights = await planNights({ ...$state.snapshot(settings), openMeteoResponse, cometElements, now: new Date().toISOString().replace(/\.\d+Z$/, 'Z') });
      status = `Planned ${nights.length} nights in ${Math.round(performance.now() - started)} ms`;
    } catch (e) {
      status = '';
      error = e.message;
    }
  }

  function nightTitle(night) {
    const [y, m, d] = night.planKey.split('-').map(Number);
    return new Date(Date.UTC(y, m - 1, d, 12)).toLocaleDateString('en', { weekday: 'long', month: 'short', day: 'numeric', timeZone: 'UTC' });
  }

  function clock(iso) {
    return iso ? new Date(iso).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', timeZone: settings.site.timeZoneIdentifier }) : '—';
  }

  const verdictClass = verdict => verdict.toLowerCase();

  refresh();
</script>

<main>
  <header>
    <h1>Sky Bother</h1>
    <p class="tagline">Is tonight worth setting up for?</p>
  </header>

  <section class="site">
    {#if settings}
      <div class="site-row">
        <div>
          <div class="site-name">{settings.site.name || 'Unnamed site'}</div>
          <div class="muted">
            {settings.site.latitude.toFixed(3)}°, {settings.site.longitude.toFixed(3)}° · {settings.site.timeZoneIdentifier} · {settings.rig.name}
          </div>
        </div>
        <label class="bortle">
          Bortle
          <select value={settings.site.bortleClass} onchange={e => setBortle(e.currentTarget.value)}>
            {#each [1, 2, 3, 4, 5, 6, 7, 8, 9] as b}<option value={b}>{b}</option>{/each}
          </select>
        </label>
      </div>
    {/if}

    <form onsubmit={e => { e.preventDefault(); search(); }}>
      <input type="search" placeholder="Search for a town or place" bind:value={query} />
      <button type="submit" disabled={!query.trim()}>Search</button>
      <button type="button" onclick={useMyLocation}>Use My Location</button>
      <label class="button">
        Import Mac Settings
        <input type="file" accept=".json,application/json" onchange={importMacSettings} hidden />
      </label>
    </form>

    {#if places.length}
      <ul class="places">
        {#each places as place}
          <li><button type="button" onclick={() => choosePlace(place)}>
            {place.name}<span class="muted">{[place.admin1, place.country].filter(Boolean).join(', ')}</span>
          </button></li>
        {/each}
      </ul>
    {/if}
  </section>

  {#if error}<p class="error">{error}</p>{/if}
  {#if status}<p class="muted status">{status}</p>{/if}

  {#if !settings}
    <p class="empty">Choose a site to see the week ahead.</p>
  {/if}

  <ol class="nights">
    {#each nights as night (night.planKey)}
      <li class="night">
        <div class="score {verdictClass(night.verdict)}">{Math.round(night.score)}</div>
        <div class="night-body">
          <div class="night-title">{nightTitle(night)} <span class="verdict {verdictClass(night.verdict)}">{night.verdict}</span></div>
          <div>{night.headline}</div>
          <div class="muted">
            Sunset {clock(night.sunset)} · Sunrise {clock(night.sunrise)} · Moon {Math.round(night.moonIlluminatedFraction * 100)}% {night.moonPhase.toLowerCase()}
          </div>
          {#if !night.isCloudedOut}
            <div class="targets">
              {#each night.targets.filter(t => t.usableMinutes > 0).slice(0, 4) as target}
                <span class="target">{target.name} <span class="muted">{Math.round(target.score)}</span></span>
              {/each}
            </div>
          {/if}
        </div>
      </li>
    {/each}
  </ol>
</main>
