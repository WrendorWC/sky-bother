<script>
  // NearbySpotPanel: a real place a short drive away that's better to
  // observe from — a darker sky, or a more open horizon when the trouble is
  // trees. Folded away until opened (on a phone it starts folded, so it's
  // there without taking room); each device remembers whether it was open.
  import { findDarkerSky, findOpenHorizon, recommend, spotID, typicalHorizon } from './nearby.js';
  import { compareSite } from '../engine/engine.js';
  import { time, degrees } from './format.js';

  let { site, preferences, tonight = null, timeZone, startsOpen = false, returnSite = null, onuse, onback, onbortle } = $props();

  const openKey = 'skybother.nearby.open';
  let open = $state((() => { try { const v = localStorage.getItem(openKey); return v == null ? startsOpen : v === '1'; } catch { return startsOpen; } })());
  function toggle() {
    open = !open;
    try { localStorage.setItem(openKey, open ? '1' : '0'); } catch {}
  }

  let goal = $state('darkerSky');
  const miles = $derived(!!preferences.usesImperialUnits);
  // NearbySpotPanel.distanceOptions
  const options = $derived(goal === 'darkerSky'
    ? (miles ? [['5 mi', 8.05], ['15 mi', 24.1], ['30 mi', 48.3]] : [['10 km', 10], ['25 km', 25], ['50 km', 50]])
    : (miles ? [['1 mi', 1.61], ['3 mi', 4.83], ['5 mi', 8.05]] : [['2 km', 2], ['5 km', 5], ['8 km', 8]]));
  let steps = $state({ darkerSky: 1, openHorizon: 1 });
  const option = $derived(options[Math.min(steps[goal], options.length - 1)]);

  // Searches, cached for the session by goal, place and distance.
  const results = new Map();
  let status = $state({ kind: 'idle' });
  let stage = $state('');
  let selectedID = $state(null);
  let attempt = $state(0);

  $effect(() => {
    if (!open) return;
    const g = goal, radius = option[1], at = { ...site }, retry = attempt;
    const key = `${g}|${at.latitude.toFixed(4)}|${at.longitude.toFixed(4)}|${radius}|${retry}`;
    selectedID = null;
    if (results.has(key)) { status = { kind: 'found', result: results.get(key) }; return; }
    let cancelled = false;
    status = { kind: 'searching' };
    const search = g === 'darkerSky' ? findDarkerSky : findOpenHorizon;
    search(at, radius, s => { if (!cancelled) stage = s; }).then(found => {
      if (cancelled) return;
      // A longer search never passes over a closer spot a shorter one found.
      const shorter = [...results.entries()].filter(([k]) => k.startsWith(`${g}|${at.latitude.toFixed(4)}|${at.longitude.toFixed(4)}|`))
        .flatMap(([, r]) => r.candidates).filter(c => c.distanceKilometers <= radius);
      const result = { ...found, anchor: at, candidates: [...found.candidates, ...shorter] };
      result.spots = recommend(result.candidates, g);
      results.set(key, result);
      status = { kind: 'found', result };
    }, e => { if (!cancelled) status = { kind: 'failed', message: e.message }; });
    return () => { cancelled = true; };
  });

  const result = $derived(status.kind === 'found' ? status.result : null);
  const featured = $derived(result ? result.spots.find(s => spotID(s) === selectedID) ?? result.spots[0] ?? null : null);
  const alternates = $derived(result && featured ? result.spots.filter(s => s !== featured) : []);

  // Tonight from the spot versus from here (ComparisonLine).
  let comparison = $state(null);
  $effect(() => {
    comparison = null;
    if (!featured || result?.goal !== 'darkerSky') return;
    const spot = featured;
    compareSite({ site: siteFor(spot) }).then(c => { if (featured === spot && !c.error) comparison = c; }, () => {});
  });

  function siteFor(spot) {
    return {
      ...site, id: site.id, name: spot.name, latitude: spot.latitude, longitude: spot.longitude,
      bortleClass: spot.estimatedBortleClass, horizonAltitude: spot.horizonAltitude ?? site.horizonAltitude,
      horizonProfile: spot.horizonAltitude != null ? null : site.horizonProfile,
    };
  }

  const distanceText = km => { const v = miles ? km * 0.621371 : km; return `${v < 10 ? v.toFixed(1) : Math.round(v)} ${miles ? 'mi' : 'km'}`; };
  const siteHorizon = $derived(typicalHorizon(site));

  function detail(spot) {
    const where = `${distanceText(spot.distanceKilometers)} ${spot.direction}`;
    if (result.goal === 'darkerSky') return `${where} · Bortle ${spot.estimatedBortleClass} (here: ${result.siteEstimatedBortleClass})`;
    const parts = [where];
    if (spot.horizonAltitude != null) parts.push(`open above ${degrees(spot.horizonAltitude)} (yours: ${degrees(siteHorizon)})`);
    if (spot.clearestDirection) parts.push(`clearest to the ${spot.clearestDirection}`);
    return parts.join(' · ');
  }

  // How much more of the sky a lower horizon uncovers: 1 − sin h.
  function skyGain(spotHorizon) {
    const there = 1 - Math.sin(Math.max(spotHorizon, 0) * Math.PI / 180);
    const here = Math.max(1 - Math.sin(Math.max(siteHorizon, 0) * Math.PI / 180), 0.01);
    return Math.round((there / here - 1) * 100);
  }

  // Posted hours, and whether they leave real observing time tonight
  // (closing at least 90 minutes after astronomical dusk).
  function hoursLine(hours) {
    if (hours.closing === 'never') return ['Open 24 hours', true];
    if (hours.closing === 'sunset') return ['Closes at sunset', false];
    const label = `${String(hours.hour).padStart(2, '0')}:${String(hours.minute).padStart(2, '0')}`;
    if (hours.crossesMidnight) return [`Open until ${label}`, true];
    const dusk = tonight?.astronomicalDusk;
    if (!dusk) return [`Closes at ${label}`, false];
    const duskTime = time(dusk, timeZone).split(':').map(Number);
    const darkMinutes = hours.hour * 60 + hours.minute - (duskTime[0] * 60 + duskTime[1]);
    return [`Closes at ${label}`, darkMinutes >= 90];
  }

  const isApple = /iPhone|iPad|Macintosh/.test(navigator.userAgent);
  const mapLink = spot => isApple
    ? `https://maps.apple.com/?ll=${spot.latitude.toFixed(5)},${spot.longitude.toFixed(5)}&q=${encodeURIComponent(spot.name)}`
    : `https://www.google.com/maps/search/?api=1&query=${spot.latitude.toFixed(5)},${spot.longitude.toFixed(5)}`;

  function emptyMessage(r) {
    if (r.goal === 'darkerSky' && r.siteEstimatedBortleClass <= 3) return `Your sky is already dark — about Bortle ${r.siteEstimatedBortleClass}.`;
    if (r.goal === 'darkerSky') return `Nothing noticeably darker within ${option[0]}.`;
    return `No public spot within ${option[0]} is more open than your ${degrees(siteHorizon)} horizon.`;
  }
</script>

<section class="nearby" class:open>
  <button type="button" class="fold" onclick={toggle} aria-expanded={open}>
    <svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9" /><path d="M15.5 8.5l-2 5-5 2 2-5z" /></svg>
    <span class="fold-text">
      <strong>Better spot nearby</strong>
      {#if !open}<span class="teaser">A darker sky or a more open horizon, a short drive away</span>{/if}
    </span>
    <span class="chevron" aria-hidden="true">{open ? '▾' : '›'}</span>
  </button>

  {#if open}
    <div class="body">
      <div class="controls">
        <div class="seg goal" role="radiogroup" aria-label="What the spot should improve on">
          <button type="button" role="radio" aria-checked={goal === 'darkerSky'} class:on={goal === 'darkerSky'} onclick={() => (goal = 'darkerSky')}>Darker sky</button>
          <button type="button" role="radio" aria-checked={goal === 'openHorizon'} class:on={goal === 'openHorizon'} onclick={() => (goal = 'openHorizon')}>Open horizon</button>
        </div>
        <div class="seg" role="radiogroup" aria-label={goal === 'darkerSky' ? 'How far you’re willing to drive' : 'How far you’re willing to go'}>
          {#each options as [label], i}
            <button type="button" role="radio" aria-checked={steps[goal] === i} class:on={steps[goal] === i} onclick={() => (steps = { ...steps, [goal]: i })}>{label}</button>
          {/each}
        </div>
      </div>

      {#if status.kind === 'searching' || status.kind === 'idle'}
        <p class="muted searching"><span class="spin">↻</span> {stage || 'Searching…'}</p>
      {:else if status.kind === 'failed'}
        <p class="warn">{status.message}</p>
        <button type="button" onclick={() => attempt++}>Try Again</button>
      {:else if result}
        {#if result.goal === 'darkerSky' && Math.abs(site.bortleClass - result.siteEstimatedBortleClass) >= 2}
          <div class="hint">
            <p>Satellite data puts {site.name} nearer Bortle {result.siteEstimatedBortleClass} than the {site.bortleClass} it’s set to.</p>
            <button type="button" class="text-button" onclick={() => onbortle(result.siteEstimatedBortleClass)}>Use Bortle {result.siteEstimatedBortleClass}</button>
          </div>
        {/if}
        {#if featured}
          <div class="spot panel">
            <strong class="name">{featured.name}</strong>
            <p class="muted">{detail(featured)}</p>
            {#if featured.hours}
              {@const [text, good] = hoursLine(featured.hours)}
              <p class="hours" class:good class:bad={!good} title={featured.hours.raw}>{text}{#if featured.website} · <a href={featured.website} target="_blank" rel="noopener">Website</a>{/if}</p>
            {:else if featured.website}
              <p class="hours"><a href={featured.website} target="_blank" rel="noopener">Website — check the hours</a></p>
            {/if}
            {#if result.goal === 'darkerSky'}
              {#if comparison}
                {@const gained = comparison.targetsThere - comparison.targetsHere}
                {@const when = comparison.isCloudedOut ? 'if it clears tonight' : 'tonight'}
                <p class="gain">✦ {gained > 0 ? `${comparison.targetsThere} good targets ${when} — ${gained} more than from here` : `Same ${comparison.targetsThere} good targets ${when} as from here`}</p>
              {/if}
            {:else if featured.horizonAltitude != null}
              <p class="gain">✦ {skyGain(featured.horizonAltitude)}% more sky than your {degrees(siteHorizon)} horizon</p>
            {/if}
            <div class="row-buttons">
              <button type="button" class="primary" onclick={() => onuse(featured)}
                      title={result.goal === 'darkerSky' ? 'Plan from here (saved with your sites)' : 'Plan from here with its estimated horizon (saved with your sites)'}>Use This Spot</button>
              <a class="button map" href={mapLink(featured)} target="_blank" rel="noopener">Map</a>
            </div>
          </div>
          {#if alternates.length}
            <p class="muted small">{featured === result.spots[0] ? (result.goal === 'darkerSky' ? 'Closer, not as dark' : 'Closer, not as open') : 'Other options'}</p>
            {#each alternates as spot (spotID(spot))}
              <button type="button" class="alternate" onclick={() => (selectedID = spotID(spot))}>
                <span>{spot.name}</span>
                <span class="muted">{distanceText(spot.distanceKilometers)} · {result.goal === 'darkerSky' ? `B${spot.estimatedBortleClass}` : degrees(spot.horizonAltitude)}</span>
              </button>
            {/each}
          {/if}
          <p class="muted small">Check if it’s open and safe after dark.</p>
        {:else}
          <p class="muted">{emptyMessage(result)}</p>
        {/if}
      {/if}

      {#if returnSite}
        <button type="button" class="text-button back" onclick={onback}>↩ Back to {returnSite.name}</button>
      {/if}
    </div>
  {/if}
</section>

<style>
  .nearby { display: grid; gap: 10px; }
  .fold { display: flex; gap: 10px; align-items: center; width: 100%; padding: 10px 12px; text-align: left; border-radius: 12px; background: var(--panel); border: 1px solid var(--panel-border); }
  .fold svg { flex: none; width: 22px; height: 22px; fill: none; stroke: var(--accent); stroke-width: 1.7; stroke-linejoin: round; }
  .fold-text { flex: 1; min-width: 0; display: grid; gap: 1px; }
  .teaser { font-size: 12px; color: var(--muted); }
  .chevron { color: var(--accent); font-size: 18px; }
  .body { display: grid; gap: 10px; }
  .controls { display: grid; gap: 6px; }
  .seg button { font-size: 13px; padding: 6px 6px; }
  .searching { margin: 0; }
  .spin { display: inline-block; animation: spin 1s linear infinite; }
  @keyframes spin { to { transform: rotate(360deg); } }
  p { margin: 0; }
  .warn { color: var(--marginal); }
  .hint { display: grid; gap: 4px; font-size: 13px; color: var(--muted); justify-items: start; }
  .spot { padding: 12px; display: grid; gap: 5px; border-radius: 12px; }
  .name { font-size: 15px; }
  .spot p { font-size: 13px; }
  .hours.good { color: var(--excellent); }
  .hours.bad { color: var(--marginal); }
  .gain { color: var(--text); }
  .row-buttons { margin-top: 4px; }
  .map { display: inline-flex; align-items: center; text-decoration: none; color: var(--text); padding: 7px 14px; border: 1px solid var(--panel-border); border-radius: 8px; background: var(--panel); }
  .small { font-size: 12px; }
  .alternate { display: flex; justify-content: space-between; gap: 8px; width: 100%; text-align: left; padding: 7px 10px; font-size: 13px; }
  .alternate span:first-child { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .back { justify-self: start; }
  @media (prefers-reduced-motion: reduce) { .spin { animation: none; } }
</style>
