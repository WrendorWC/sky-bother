<script>
  // The horizon by compass direction (HorizonEditor on the Mac), as sliders:
  // one for everywhere at once and one per direction. Changes apply when a
  // slider is let go.
  import { degrees } from './format.js';

  let { site, onchange } = $props();

  const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  const horizon = $derived(site.horizonProfile?.length === 8 ? site.horizonProfile : directions.map(() => site.horizonAltitude ?? 20));

  let draft = $state({});
  const shown = (key, value) => draft[key] ?? value;
  const slide = key => e => (draft = { ...draft, [key]: Number(e.currentTarget.value) });
  const commit = (key, apply) => e => {
    const value = Number(e.currentTarget.value);
    draft = { ...draft, [key]: undefined };
    apply(value);
  };

  function setSector(index, value) {
    const profile = [...horizon];
    profile[index] = value;
    // The same everywhere is just a flat horizon.
    const flat = profile.every(v => v === profile[0]);
    onchange({ horizonProfile: flat ? null : profile, horizonAltitude: flat ? profile[0] : Math.min(...profile) });
  }
</script>

<div class="horizon">
  <label class="slider">
    <span>Everywhere</span>
    <input type="range" min="0" max="60" step="1" value={shown('all', Math.min(...horizon))}
           oninput={slide('all')} onchange={commit('all', v => onchange({ horizonProfile: null, horizonAltitude: v }))} />
    <strong>{degrees(shown('all', Math.min(...horizon)))}</strong>
  </label>
  {#each directions as direction, i}
    <label class="slider">
      <span>{direction}</span>
      <input type="range" min="0" max="60" step="1" value={shown(`h${i}`, horizon[i])}
             oninput={slide(`h${i}`)} onchange={commit(`h${i}`, v => setSector(i, v))} />
      <strong>{degrees(shown(`h${i}`, horizon[i]))}</strong>
    </label>
  {/each}
</div>

<style>
  .horizon { display: grid; gap: 4px; }
  .slider { display: grid; grid-template-columns: 82px 1fr 44px; gap: 8px; align-items: center; }
  .slider input { width: 100%; padding: 0; accent-color: var(--accent); }
  .slider strong { text-align: right; font-variant-numeric: tabular-nums; }
</style>
