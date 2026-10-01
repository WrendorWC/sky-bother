<script>
  // TargetCatalogView: every target, searchable and filterable, each scored
  // against a night you choose. The rules are CatalogQuery's (Planner/
  // CatalogQuery.swift): the type filter, "Good or better", "Fits my frame",
  // "Usable for at least", and the five orders.
  import ScoreBadge from './ScoreBadge.svelte';
  import Thumbnail from './Thumbnail.svelte';
  import TargetDetail from './TargetDetail.svelte';
  import { verdictFor, verdictColor } from './palette.js';
  import { weekday, dayAndMonth, hours } from './format.js';

  let { entries, nights, timeZone, preferences = {} } = $props();

  // Bright stars and comets start hidden when Settings says so; choosing
  // their type in the filter still shows them (AppState's hidden types).
  const hiddenTypes = $derived(new Set([
    ...(preferences.includeStars === false ? ['star'] : []),
    ...(preferences.includeComets === false ? ['comet'] : []),
  ]));

  let search = $state('');
  let types = $state(new Set());
  let sort = $state('alphabetical');
  let nightKey = $state(nights[0]?.planKey);
  let goodOnly = $state(false);
  let fitsFrameOnly = $state(false);
  let minimumHours = $state(0);
  let shown = $state(120);
  let openID = $state(null);

  const sorts = [
    ['alphabetical', 'Alphabetical'],
    ['bestOnNight', 'Best on This Night'],
    ['longestWindow', 'Longest Window'],
    ['size', 'Size in the Sky'],
    ['brightness', 'Brightness'],
  ];

  const night = $derived(nights.find(n => n.planKey === nightKey) ?? nights[0]);
  const scored = $derived(new Map(night.targets.filter(t => t.usableMinutes > 0).map(t => [t.id, t])));
  const typeNames = $derived([...new Set(entries.map(e => e.typeName))].sort((a, b) => a.localeCompare(b)));

  // CatalogQuery.fitsFrame
  const fitsFrame = t => !t.needsMosaic && t.fillFraction >= 0.1;
  const byName = (a, b) => a.displayName.localeCompare(b.displayName, undefined, { sensitivity: 'base' });

  const results = $derived.by(() => {
    const query = search.trim().toLowerCase();
    const byNight = goodOnly || fitsFrameOnly || minimumHours > 0;
    const filtered = entries.filter(entry => {
      if (types.size && !types.has(entry.typeName)) return false;
      if (!types.size && hiddenTypes.has(entry.type)) return false;
      if (query && !entry.searchText.includes(query)) return false;
      if (!byNight) return true;
      const result = scored.get(entry.id);
      if (!result) return false;
      if (goodOnly && result.score < 60) return false;
      if (fitsFrameOnly && !fitsFrame(result)) return false;
      if (minimumHours > 0 && result.usableMinutes < minimumHours * 60) return false;
      return true;
    });
    if (sort === 'alphabetical') return filtered.sort(byName);
    if (sort === 'size') return filtered.sort((a, b) => b.majorAxisArcminutes - a.majorAxisArcminutes);
    if (sort === 'brightness') return filtered.sort((a, b) => a.magnitude - b.magnitude);
    const key = sort === 'bestOnNight' ? t => t.score : t => t.usableMinutes;
    return filtered.sort((a, b) => {
      const x = scored.get(a.id), y = scored.get(b.id);
      if (x && y) return key(x) !== key(y) ? key(y) - key(x) : byName(a, b);
      if (x) return -1;
      if (y) return 1;
      return byName(a, b);
    });
  });

  function toggleType(name) {
    const next = new Set(types);
    next.has(name) ? next.delete(name) : next.add(name);
    types = next;
  }

  const nightName = (n, i) => `${i === 0 ? 'Tonight' : weekday(n.planKey)} ${dayAndMonth(n.planKey)}`;

  // Reset paging when the list changes underneath it.
  $effect(() => {
    results;
    shown = 120;
  });
</script>

<section class="catalog">
  <header>
    <h2>Catalog</h2>
    <span class="muted">{results.length} target{results.length === 1 ? '' : 's'}</span>
  </header>

  <div class="toolbar">
    <input type="search" placeholder="Search the catalog" bind:value={search} />
    <details class="types">
      <summary>{types.size === 0 ? 'All Types' : types.size === 1 ? [...types][0] : `${types.size} Types`}</summary>
      <div class="menu panel">
        {#each typeNames as name}
          <label><input type="checkbox" checked={types.has(name)} onchange={() => toggleType(name)} /> {name}</label>
        {/each}
        {#if types.size}<button type="button" class="link" onclick={() => (types = new Set())}>Show all types</button>{/if}
      </div>
    </details>
    <select bind:value={sort} aria-label="Sort by">
      {#each sorts as [value, label]}<option {value}>{label}</option>{/each}
    </select>
  </div>

  <div class="toolbar">
    <select bind:value={nightKey} aria-label="The night each card is scored for">
      {#each nights as n, i}<option value={n.planKey}>Night: {nightName(n, i)} · {Math.round(n.score)} {n.verdict}</option>{/each}
    </select>
    <label class="check"><input type="checkbox" bind:checked={goodOnly} /> Good or better</label>
    <label class="check" title="Hide targets that overflow the frame or are tiny in it (under 10% of the long side)">
      <input type="checkbox" bind:checked={fitsFrameOnly} /> Fits my frame
    </label>
    <select bind:value={minimumHours} aria-label="Usable for at least">
      <option value={0}>Any usable time</option>
      {#each [1, 2, 3, 4] as h}<option value={h}>At least {h}h usable</option>{/each}
    </select>
  </div>

  <ul class="cards">
    {#each results.slice(0, shown) as entry (entry.id)}
      {@const result = scored.get(entry.id)}
      <li>
        <button type="button" class="card panel" onclick={() => (openID = entry.id)}>
          <Thumbnail designation={entry.designation} size={64} label={entry.displayName} />
          <div class="card-body">
            <strong>{entry.displayName}</strong>
            <span class="muted">{entry.commonName ? `${entry.designation} · ` : ''}{entry.typeName}{entry.constellation ? ` · ${entry.constellation}` : ''}</span>
            {#if result}
              <span class="verdict" style:color={verdictColor(verdictFor(result.score))}>{verdictFor(result.score)} · {hours(result.usableMinutes / 60)}</span>
            {:else}
              <span class="muted faint">Not up this night</span>
            {/if}
          </div>
          {#if result}<ScoreBadge score={result.score} size={36} />{/if}
        </button>
      </li>
    {/each}
  </ul>
  {#if results.length > shown}
    <button type="button" class="more" onclick={() => (shown += 240)}>Show more ({results.length - shown} left)</button>
  {/if}
  {#if results.length === 0}<p class="muted">Nothing matches.</p>{/if}
</section>

{#if openID}
  <TargetDetail {night} {nights} targetID={openID} {timeZone} onclose={() => (openID = null)} />
{/if}

<style>
  .catalog { display: grid; gap: 12px; min-width: 0; }
  header { display: flex; align-items: baseline; gap: 12px; }
  h2 { margin: 0; font-size: 22px; }
  .toolbar { display: flex; flex-wrap: wrap; gap: 8px 12px; align-items: center; }
  input[type='search'] { flex: 1 1 220px; max-width: 320px; }
  .check { display: flex; gap: 6px; align-items: center; color: var(--muted); }
  .check input { accent-color: var(--accent); }
  .types { position: relative; }
  .types summary {
    list-style: none; cursor: pointer; padding: 7px 10px; border-radius: 8px;
    border: 1px solid var(--panel-border); background: var(--panel);
  }
  .types summary::-webkit-details-marker { display: none; }
  .types summary::after { content: ' ▾'; color: var(--muted); }
  .menu {
    position: absolute; z-index: 5; top: calc(100% + 4px); left: 0; padding: 10px; min-width: 220px;
    display: grid; gap: 6px; box-shadow: 0 12px 30px rgba(0, 0, 0, 0.4);
  }
  .menu label { display: flex; gap: 8px; align-items: center; white-space: nowrap; }
  .menu input { accent-color: var(--accent); }
  .link { background: none; border: none; padding: 0; color: var(--accent); text-align: left; }
  .cards { list-style: none; margin: 0; padding: 0; display: grid; gap: 8px; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); }
  .card { display: flex; gap: 12px; align-items: center; width: 100%; padding: 8px; text-align: left; }
  .card:hover { border-color: var(--accent); }
  .card-body { flex: 1; min-width: 0; display: grid; gap: 2px; }
  .card-body > * { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .verdict { font-size: 13px; font-weight: 600; }
  .faint { color: var(--tertiary); }
  .more { justify-self: center; }
</style>
