<script>
  // Settings → Location (LocationSettings on the Mac): the site in use, a
  // new one found by name or your location, your saved sites, and the
  // horizon there.
  import { degrees } from './format.js';
  import LocationSection from './LocationSection.svelte';
  import HorizonSliders from './HorizonSliders.svelte';

  let { settings, onsite, onchange, autofocus = false } = $props();

  const site = $derived(settings.site);
  const savedSites = $derived(settings.savedSites ?? []);
  const isSaved = $derived(savedSites.some(s => s.id === site.id));
  // Finder's order, so "Spot 10" comes after "Spot 2".
  const sorted = $derived([...savedSites].sort((a, b) => a.name.localeCompare(b.name, undefined, { numeric: true })));

  // Site.bortleDescription
  const bortle = ['', 'Excellent dark site', 'Truly dark site', 'Rural sky', 'Rural/suburban transition', 'Suburban sky',
    'Bright suburban sky', 'Suburban/urban transition', 'City sky', 'Inner-city sky'];

  const zones = (() => {
    try { return Intl.supportedValuesOf('timeZone'); } catch { return null; }
  })();

  // A change to the site in use keeps its saved copy in step.
  function setSite(fields) {
    const next = { ...site, ...fields };
    onchange({ ...settings, site: next, savedSites: savedSites.map(s => (s.id === next.id ? { ...next } : s)) });
  }
  const useSite = s => onchange({ ...settings, site: { ...s } });
  const forgetSite = s => onchange({ ...settings, savedSites: savedSites.filter(x => x.id !== s.id) });
  const saveSite = () => onchange({ ...settings, savedSites: [...savedSites.filter(s => s.id !== site.id), { ...site }] });

  // Site.horizonSummary
  const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  function horizonSummary(s) {
    const all = degrees(s.horizonAltitude ?? 20);
    const profile = s.horizonProfile?.length === 8 ? s.horizonProfile : null;
    if (!profile) return `${all} all round`;
    const worst = Math.max(...profile);
    return `${all} all round, ${degrees(worst)} ${profile.map((v, i) => (v === worst ? directions[i] : null)).filter(Boolean).join('/')}`;
  }
</script>

<div class="pane">
  <div class="group">
    <h3 class="group-title">Site in use</h3>
    <div class="card">
      <div class="item">
        <input class="name" type="text" aria-label="Site name" value={site.name} placeholder="Name this site"
               onchange={e => setSite({ name: e.currentTarget.value })} />
        <p class="caption">{site.latitude.toFixed(4)}°, {site.longitude.toFixed(4)}° · {Math.round(site.elevationMeters ?? 0)} m up</p>
      </div>
      <label class="item inline">
        <div><span class="title">Light pollution</span><p class="caption">How bright the sky is there, on the Bortle scale.</p></div>
        <select value={site.bortleClass} onchange={e => setSite({ bortleClass: Number(e.currentTarget.value) })}>
          {#each [1, 2, 3, 4, 5, 6, 7, 8, 9] as b}<option value={b}>{b} · {bortle[b]}</option>{/each}
        </select>
      </label>
      <label class="item inline">
        <span class="title">Time zone</span>
        {#if zones}
          <select value={site.timeZoneIdentifier} onchange={e => setSite({ timeZoneIdentifier: e.currentTarget.value })}>
            {#each zones as zone}<option value={zone}>{zone.replaceAll('_', ' ')}</option>{/each}
          </select>
        {:else}
          <input type="text" value={site.timeZoneIdentifier} onchange={e => setSite({ timeZoneIdentifier: e.currentTarget.value })} />
        {/if}
      </label>
      {#if !isSaved}
        <div class="item inline">
          <p class="caption">Not in your saved sites yet.</p>
          <button type="button" class="primary" onclick={saveSite}>Save This Site</button>
        </div>
      {/if}
    </div>
  </div>

  <div class="group">
    <h3 class="group-title">Change site</h3>
    <div class="card"><div class="item"><LocationSection {settings} {onsite} {onchange} {autofocus} searchOnly /></div></div>
    <p class="group-note">Picking a new place saves the one you're leaving first, so it isn't lost.</p>
  </div>

  {#if sorted.length}
    <div class="group">
      <h3 class="group-title">Saved sites</h3>
      <div class="card">
        {#each sorted as s (s.id)}
          <div class="item inline">
            <div>
              <span class="title">{s.name}</span>
              <p class="caption">Bortle {s.bortleClass} · horizon {horizonSummary(s)}</p>
            </div>
            <div class="row-buttons">
              {#if s.id === site.id}<span class="in-use">In use</span>{:else}<button type="button" onclick={() => useSite(s)}>Use</button>{/if}
              <button type="button" class="forget" onclick={() => forgetSite(s)} aria-label="Remove {s.name}" title="Remove">✕</button>
            </div>
          </div>
        {/each}
      </div>
    </div>
  {/if}

  <div class="group">
    <h3 class="group-title">Horizon at {site.name || 'this site'}</h3>
    <div class="card">
      <div class="item">
        <p class="caption">How high trees and buildings reach in each direction. Targets lower than this don't count.</p>
        <HorizonSliders {site} onchange={setSite} />
      </div>
    </div>
  </div>
</div>

<style>
  .pane { display: grid; gap: 22px; }
  .name { font-size: 18px; font-weight: 700; background: none; border-color: transparent; padding: 4px 6px; margin: -4px -6px 0; }
  .name:hover, .name:focus { border-color: var(--panel-border); background: var(--space-top); }
  .in-use { color: var(--muted); font-size: 13px; align-self: center; }
  .forget { width: 36px; padding: 6px 0; }
  .item.inline select { max-width: 55%; }
</style>
