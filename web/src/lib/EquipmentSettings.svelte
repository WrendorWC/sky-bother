<script>
  // Settings → Equipment (EquipmentSettings on the Mac): the telescope in use
  // and what it gives you, your saved rigs, the mount and filter, and the
  // optics numbers — tucked away while they're an unchanged preset's.
  import { degrees } from './format.js';
  import { uuid } from './uuid.js';

  let { settings, rigPresets, onchange } = $props();

  const rig = $derived(settings.rig);
  const prefs = $derived(settings.preferences);
  const savedRigs = $derived(settings.savedRigs ?? []);
  const setRig = fields => onchange({ ...settings, rig: { ...rig, ...fields } });
  const setPrefs = fields => onchange({ ...settings, preferences: { ...prefs, ...fields } });

  // Rig.presetGroup
  const smartMakers = ['ZWO Seestar', 'Celestron Origin', 'Unistellar', 'Vaonis', 'DwarfLab'];
  const isSmart = r => smartMakers.some(maker => r.name.startsWith(maker));
  const groups = $derived([
    ['Smart telescopes', rigPresets.filter(isSmart)],
    ['Cameras, lenses and telescopes', rigPresets.filter(r => !isSmart(r))],
  ]);
  const presetIndex = $derived(rigPresets.findIndex(r => r.name === rig.name));
  const specs = ['apertureMillimeters', 'focalLengthMillimeters', 'sensorWidthMillimeters', 'sensorHeightMillimeters', 'pixelSizeMicrons'];
  // AppState.rigIsUnchangedPreset
  const unchangedPreset = $derived(presetIndex >= 0 && specs.every(k => rigPresets[presetIndex][k] === rig[k]));
  let showsNumbers = $state(false);

  function choosePreset(index) {
    if (index >= 0) onchange({ ...settings, rig: { ...rigPresets[index], id: uuid() } });
  }

  // What that gives you
  const f = $derived(rig.focalLengthMillimeters);
  const opticsOK = $derived(specs.every(k => rig[k] > 0));
  const fov = $derived(opticsOK ? [rig.sensorWidthMillimeters, rig.sensorHeightMillimeters].map(s => 2 * Math.atan(s / (2 * f)) * 180 / Math.PI) : null);
  const moons = $derived(fov ? Math.max(...fov) / 0.52 : 0);
  const focalRatio = $derived(opticsOK ? f / rig.apertureMillimeters : 0);
  const sampling = $derived(opticsOK ? 206.265 * rig.pixelSizeMicrons / f : 0);
  const summary = r => {
    if (!specs.every(k => r[k] > 0)) return '';
    return `${Math.round(r.apertureMillimeters)}mm f/${(r.focalLengthMillimeters / r.apertureMillimeters).toFixed(1)} · ${(206.265 * r.pixelSizeMicrons / r.focalLengthMillimeters).toFixed(2)}″/px`;
  };

  function setNumber(field, text) {
    const value = Number(text);
    if (Number.isFinite(value) && value >= 0) setRig({ [field]: value });
  }

  // Your rigs, as on the Mac: update the saved copy, or keep a new one.
  // In use: the same rig, or a copy of it (a preset chosen again is a fresh
  // rig with the same name and numbers).
  const inUse = r => r.id === rig.id || (r.name === rig.name && specs.every(k => r[k] === rig[k]));
  const savedMatch = $derived(savedRigs.find(r => r.id === rig.id) ?? savedRigs.find(inUse));
  const isSaved = $derived(!!savedMatch);
  const updateSaved = () => onchange({ ...settings, savedRigs: savedRigs.map(r => (r.id === savedMatch.id ? { ...rig, id: r.id } : r)) });
  function saveAsNew() {
    const copy = { ...rig, id: uuid() };
    onchange({ ...settings, rig: copy, savedRigs: [...savedRigs, { ...copy }] });
  }
  const useRig = r => onchange({ ...settings, rig: { ...r } });
  const forgetRig = r => onchange({ ...settings, savedRigs: savedRigs.filter(x => x.id !== r.id) });

  // The zenith slider moves freely and applies when let go.
  let zenith = $state(null);
</script>

<div class="pane">
  <div class="group">
    <h3 class="group-title">Telescope</h3>
    <div class="card">
      <div class="item">
        <input class="name" type="text" aria-label="Telescope name" value={rig.name} onchange={e => setRig({ name: e.currentTarget.value })} />
        {#if opticsOK}
          <div class="gives">
            <div><strong>{fov[0].toFixed(2)}° × {fov[1].toFixed(2)}°</strong><span>field of view</span></div>
            <div><strong>f/{focalRatio.toFixed(1)}</strong><span>focal ratio</span></div>
            <div><strong>{sampling.toFixed(2)}″</strong><span>per pixel</span></div>
          </div>
          <p class="caption">{moons >= 1.5 ? `About ${Math.round(moons)} full Moons across the long side.` : 'About one full Moon across the long side.'}</p>
        {:else}
          <p class="warn">Fill in every optics number below for the framing to work.</p>
        {/if}
      </div>
      <label class="item inline">
        <div><span class="title">Load a preset</span><p class="caption">Fills in every number for you.</p></div>
        <select value={presetIndex} onchange={e => choosePreset(Number(e.currentTarget.value))}>
          {#if presetIndex < 0}<option value={-1}>Your own</option>{/if}
          {#each groups as [name, rigs]}
            <optgroup label={name}>
              {#each rigs as r}<option value={rigPresets.indexOf(r)}>{r.name}</option>{/each}
            </optgroup>
          {/each}
        </select>
      </label>
    </div>
  </div>

  <div class="group">
    <h3 class="group-title">Your rigs</h3>
    <div class="card">
      {#each savedRigs as r (r.id)}
        <div class="item inline">
          <div><span class="title">{r.name}</span><p class="caption">{summary(r)}</p></div>
          <div class="row-buttons">
            {#if inUse(r)}<span class="in-use">In use</span>{:else}<button type="button" onclick={() => useRig(r)}>Use</button>{/if}
            <button type="button" class="forget" onclick={() => forgetRig(r)} aria-label="Remove {r.name}" title="Remove">✕</button>
          </div>
        </div>
      {/each}
      <div class="item">
        {#if !savedRigs.length}<p class="caption">Save the telescope above to switch back to it later.</p>{/if}
        <div class="row-buttons">
          {#if isSaved}<button type="button" onclick={updateSaved} disabled={!opticsOK}>Update Saved Rig</button>{/if}
          <button type="button" class:primary={!isSaved} onclick={saveAsNew} disabled={!opticsOK}>{isSaved ? 'Save as New Rig' : 'Save This Rig'}</button>
        </div>
        {#if isSaved}<p class="caption">Edits apply now. The saved copy changes only with Update Saved Rig.</p>{/if}
      </div>
    </div>
  </div>

  <div class="group">
    <h3 class="group-title">Mount and filters</h3>
    <div class="card">
      <div class="item inline">
        <span class="title">Mount</span>
        <div class="seg mount" role="radiogroup" aria-label="Mount">
          <button type="button" role="radio" aria-checked={rig.mountType !== 'equatorial'} class:on={rig.mountType !== 'equatorial'} onclick={() => setRig({ mountType: 'altAzimuth' })}>Alt-Az</button>
          <button type="button" role="radio" aria-checked={rig.mountType === 'equatorial'} class:on={rig.mountType === 'equatorial'} onclick={() => setRig({ mountType: 'equatorial' })}>Equatorial</button>
        </div>
      </div>
      <label class="item inline">
        <div><span class="title">Dual-band / narrowband filter</span><p class="caption">Cuts light pollution and some moonlight on nebulae.</p></div>
        <input class="switch" type="checkbox" checked={rig.hasNarrowbandFilter} onchange={e => setRig({ hasNarrowbandFilter: e.currentTarget.checked })} />
      </label>
      <label class="item inline">
        <span class="title">Can shoot mosaics</span>
        <input class="switch" type="checkbox" checked={rig.supportsMosaic} onchange={e => setRig({ supportsMosaic: e.currentTarget.checked })} />
      </label>
      {#if rig.mountType !== 'equatorial'}
        <label class="item inline">
          <div><span class="title">Zenith risk warnings</span><p class="caption">Alt-az mounts struggle with targets passing nearly overhead.</p></div>
          <input class="switch" type="checkbox" checked={prefs.showsZenithRiskWarnings ?? true} onchange={e => setPrefs({ showsZenithRiskWarnings: e.currentTarget.checked })} />
        </label>
        {#if prefs.showsZenithRiskWarnings ?? true}
          <label class="item">
            <div class="head"><span class="title">Warn above</span><span class="value">{degrees(zenith ?? rig.zenithAvoidanceAltitude)}</span></div>
            <input type="range" min="60" max="90" step="1" value={zenith ?? rig.zenithAvoidanceAltitude}
                   oninput={e => (zenith = Number(e.currentTarget.value))}
                   onchange={e => { setRig({ zenithAvoidanceAltitude: Number(e.currentTarget.value) }); zenith = null; }} />
          </label>
        {/if}
      {/if}
    </div>
  </div>

  <div class="group">
    <h3 class="group-title">Optics</h3>
    <div class="card">
      {#if unchangedPreset && !showsNumbers}
        <div class="item inline">
          <p class="caption">The preset's numbers are right as they are.</p>
          <button type="button" class="text-button" onclick={() => (showsNumbers = true)}>Show Numbers</button>
        </div>
      {:else}
        <div class="item numbers">
          <label><span>Aperture (mm)</span><input type="number" inputmode="decimal" min="0" step="any" value={rig.apertureMillimeters} onchange={e => setNumber('apertureMillimeters', e.currentTarget.value)} /></label>
          <label><span>Focal length (mm)</span><input type="number" inputmode="decimal" min="0" step="any" value={rig.focalLengthMillimeters} onchange={e => setNumber('focalLengthMillimeters', e.currentTarget.value)} /></label>
          <label><span>Sensor width (mm)</span><input type="number" inputmode="decimal" min="0" step="any" value={rig.sensorWidthMillimeters} onchange={e => setNumber('sensorWidthMillimeters', e.currentTarget.value)} /></label>
          <label><span>Sensor height (mm)</span><input type="number" inputmode="decimal" min="0" step="any" value={rig.sensorHeightMillimeters} onchange={e => setNumber('sensorHeightMillimeters', e.currentTarget.value)} /></label>
          <label><span>Pixel size (µm)</span><input type="number" inputmode="decimal" min="0" step="any" value={rig.pixelSizeMicrons} onchange={e => setNumber('pixelSizeMicrons', e.currentTarget.value)} /></label>
        </div>
      {/if}
    </div>
  </div>
</div>

<style>
  .pane { display: grid; gap: 22px; }
  .name { font-size: 18px; font-weight: 700; background: none; border-color: transparent; padding: 4px 6px; margin: -4px -6px 0; }
  .name:hover, .name:focus { border-color: var(--panel-border); background: var(--space-top); }
  .gives { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 8px; margin-top: 4px; }
  @media (max-width: 380px) { .gives strong { font-size: 13px; } .gives div { padding: 8px 4px; } }
  .gives div { display: grid; gap: 2px; padding: 10px; border-radius: 10px; background: var(--space-top); text-align: center; }
  .gives strong { font-size: 16px; white-space: nowrap; font-variant-numeric: tabular-nums; }
  .gives span { font-size: 12px; color: var(--muted); }
  .in-use { color: var(--muted); font-size: 13px; align-self: center; }
  .forget { width: 36px; padding: 6px 0; }
  .item.inline select { max-width: 55%; }
  .mount { flex: 0 1 240px; }
  .numbers { grid-template-columns: repeat(auto-fill, minmax(140px, 1fr)); gap: 10px; }
  .numbers label { display: grid; gap: 4px; font-size: 13px; color: var(--muted); }
  .numbers input { width: 100%; }
  .warn { color: var(--marginal); margin: 0; }
</style>
