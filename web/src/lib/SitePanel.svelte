<script>
  // Choosing where you observe from: a town, your location, or the Mac app's
  // settings file. Same starting values as Site.unset in the Mac app.
  import { searchPlaces, elevationAt } from '../weather.js';
  import { uuid } from './uuid.js';

  let { settings, onsite, onimport, onbortle, oncancel } = $props();

  let query = $state('');
  let places = $state([]);
  let error = $state('');
  let busy = $state('');

  function newSite(fields) {
    return { id: uuid(), bortleClass: 5, horizonAltitude: 20, ...fields };
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
    places = [];
    query = '';
    onsite(newSite({
      name: [place.name, place.admin1, place.country_code].filter(Boolean).join(', '),
      latitude: place.latitude,
      longitude: place.longitude,
      elevationMeters: place.elevation ?? 0,
      timeZoneIdentifier: place.timezone,
    }));
  }

  function useMyLocation() {
    error = '';
    busy = 'Finding you…';
    navigator.geolocation.getCurrentPosition(
      async ({ coords }) => {
        const elevation = await elevationAt(coords.latitude, coords.longitude);
        busy = '';
        onsite(newSite({
          name: 'My Location',
          latitude: coords.latitude,
          longitude: coords.longitude,
          elevationMeters: elevation,
          timeZoneIdentifier: Intl.DateTimeFormat().resolvedOptions().timeZone,
        }));
      },
      e => {
        busy = '';
        // 1 is PERMISSION_DENIED: the browser or the phone blocks location
        // for this site. Say how to fix it rather than the browser's wording.
        error = e.code === 1
          ? 'Location is blocked for this site. On an iPhone: Settings → Privacy & Security → Location Services → your browser → While Using the App, then reload. Or search for your town instead.'
          : `Couldn't find your location: ${e.message}`;
      },
      { enableHighAccuracy: false, timeout: 20_000, maximumAge: 600_000 },
    );
  }

  // Reads the Mac app's settings.json (~/Library/Application Support/SkyBother).
  async function importMacSettings(event) {
    const file = event.currentTarget.files?.[0];
    if (!file) return;
    try {
      const stored = JSON.parse(await file.text());
      if (!stored.site || !stored.rig || !stored.preferences) throw new Error('That isn’t a Sky Bother settings file.');
      onimport({ site: stored.site, rig: stored.rig, preferences: stored.preferences, customTargets: stored.customTargets ?? [] });
    } catch (e) {
      error = e.message;
    }
  }
</script>

<section class="panel site">
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
        <select value={settings.site.bortleClass} onchange={e => onbortle(Number(e.currentTarget.value))}>
          {#each [1, 2, 3, 4, 5, 6, 7, 8, 9] as b}<option value={b}>{b}</option>{/each}
        </select>
      </label>
    </div>
  {:else}
    <p class="intro">Where do you observe from?</p>
  {/if}

  <form onsubmit={e => { e.preventDefault(); search(); }}>
    <input type="search" placeholder="Search for a town or place" bind:value={query} />
    <button type="submit" disabled={!query.trim()}>Search</button>
    <button type="button" onclick={useMyLocation}>Use My Location</button>
    <label class="button">
      Import Mac Settings
      <input type="file" accept=".json,application/json" onchange={importMacSettings} hidden />
    </label>
    {#if settings && oncancel}<button type="button" onclick={oncancel}>Done</button>{/if}
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
  {#if busy}<p class="muted">{busy}</p>{/if}
  {#if error}<p class="error">{error}</p>{/if}
</section>

<style>
  .site { padding: 14px; display: grid; gap: 12px; }
  .site-row { display: flex; justify-content: space-between; align-items: center; gap: 12px; }
  .site-name { font-weight: 600; font-size: 17px; }
  .intro { margin: 0; font-weight: 600; font-size: 17px; }
  form { display: flex; flex-wrap: wrap; gap: 8px; }
  input[type='search'] { flex: 1 1 220px; }
  .bortle { display: flex; align-items: center; gap: 6px; color: var(--muted); }
  .places { list-style: none; margin: 0; padding: 0; display: grid; gap: 6px; }
  .places button { width: 100%; text-align: left; display: flex; justify-content: space-between; gap: 12px; }
  p { margin: 0; }
</style>
