<script>
  // Settings → Location, and the whole of a first visit: where you observe
  // from — a town, place or postal code, your location, or a saved site —
  // and its Bortle class. New sites start as Site.unset does in the Mac app.
  import { searchPlaces, elevationAt, placeDetails } from '../weather.js';
  import { uuid } from './uuid.js';

  let { settings, onsite, onchange = null, autofocus = false } = $props();

  let searchBox;
  $effect(() => {
    if (autofocus && searchBox) searchBox.focus({ preventScroll: true });
  });

  const savedSites = $derived(settings?.savedSites ?? []);
  const isSaved = $derived(!!settings && savedSites.some(s => s.id === settings.site.id));
  function useSite(id) {
    const chosen = savedSites.find(s => s.id === id);
    if (chosen) onchange({ ...settings, site: { ...chosen } });
  }
  function forgetSite(id) {
    onchange({ ...settings, savedSites: savedSites.filter(s => s.id !== id) });
  }
  function saveSite() {
    onchange({ ...settings, savedSites: [...savedSites.filter(s => s.id !== settings.site.id), { ...settings.site }] });
  }
  function setBortle(value) {
    const site = { ...settings.site, bortleClass: value };
    // A saved site keeps its saved copy in step.
    onchange({ ...settings, site, savedSites: savedSites.map(s => (s.id === site.id ? { ...site } : s)) });
  }

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

  async function choosePlace(place) {
    places = [];
    query = '';
    let { timezone, elevation } = place;
    if (!timezone) {
      busy = 'Looking up that place…';
      try {
        ({ timezone, elevation } = await placeDetails(place.latitude, place.longitude));
      } catch (e) {
        busy = '';
        error = e.message;
        return;
      }
      busy = '';
    }
    onsite(newSite({
      name: place.name,
      latitude: place.latitude,
      longitude: place.longitude,
      elevationMeters: elevation ?? 0,
      timeZoneIdentifier: timezone,
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

</script>

<div class="location" id="settings-location">
  {#if settings}
    <div class="current">
      <div>
        <div class="site-name">{settings.site.name || 'Unnamed site'}</div>
        <div class="muted">
          {settings.site.latitude.toFixed(3)}°, {settings.site.longitude.toFixed(3)}° · {settings.site.timeZoneIdentifier}
        </div>
      </div>
      <label class="bortle">
        Bortle
        <select value={settings.site.bortleClass} onchange={e => setBortle(Number(e.currentTarget.value))}>
          {#each [1, 2, 3, 4, 5, 6, 7, 8, 9] as b}<option value={b}>{b}</option>{/each}
        </select>
      </label>
    </div>
  {:else}
    <p class="intro">Where do you observe from?</p>
  {/if}

  <form onsubmit={e => { e.preventDefault(); search(); }}>
    <input type="search" placeholder="Town, place or postal code" bind:value={query} bind:this={searchBox} />
    <button type="submit" disabled={!query.trim()}>Search</button>
    <button type="button" onclick={useMyLocation}>Use My Location</button>
  </form>

  {#if places.length}
    <ul class="places">
      {#each places as place}
        <li><button type="button" onclick={() => choosePlace(place)}>
          {place.label}<span class="muted">{place.detail}</span>
        </button></li>
      {/each}
    </ul>
  {/if}
  {#if busy}<p class="muted">{busy}</p>{/if}
  {#if error}<p class="error">{error}</p>{/if}

  {#if settings}
    <div class="saved-list">
      <span class="label">Saved sites</span>
      {#each savedSites as s (s.id)}
        <div class="saved">
          <button type="button" onclick={() => useSite(s.id)} disabled={s.id === settings.site.id}>{s.name}{s.id === settings.site.id ? ' (in use)' : ''}</button>
          <button type="button" class="forget" onclick={() => forgetSite(s.id)} aria-label="Forget {s.name}">✕</button>
        </div>
      {/each}
      {#if !isSaved}<button type="button" onclick={saveSite}>Save This Site</button>{/if}
      <p class="muted">Picking a new place saves the one you're leaving here first, so it isn't lost.</p>
    </div>
  {/if}
</div>

<style>
  .location { display: grid; gap: 12px; scroll-margin-top: 80px; }
  .current { display: flex; justify-content: space-between; align-items: center; gap: 12px; }
  .saved-list { display: grid; gap: 6px; }
  .label { font-weight: 600; }
  .saved { display: flex; gap: 6px; }
  .saved button:first-child { flex: 1; text-align: left; }
  .forget { width: 40px; padding: 0; }
  .site-name { font-weight: 600; font-size: 17px; }
  .intro { margin: 0; font-weight: 600; font-size: 17px; }
  form { display: flex; flex-wrap: wrap; gap: 8px; }
  input[type='search'] { flex: 1 1 220px; }
  .bortle { display: flex; align-items: center; gap: 6px; color: var(--muted); }
  .places { list-style: none; margin: 0; padding: 0; display: grid; gap: 6px; }
  .places button { width: 100%; text-align: left; display: flex; justify-content: space-between; gap: 12px; }
  p { margin: 0; }
</style>
