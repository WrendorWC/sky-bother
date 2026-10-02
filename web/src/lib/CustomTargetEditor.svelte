<script>
  // CustomTargetEditor (TargetCatalogView.swift): add a target the catalog
  // doesn't have, or edit or delete one you added. Stored as the Mac stores
  // them (StoredSettings.customTargets, keyed by designation), so they sync
  // and import either way. Positions can be typed as star charts give them —
  // 20h 45m 38s, +30° 43′ 0″ — or in decimal degrees, as on the Mac.
  let { existing = null, catalogIDs = new Set(), onsave, ondelete, onclose } = $props();

  // TargetType.displayName, less comets: a custom target has a fixed position.
  const types = [
    ['asterism', 'Asterism'], ['emissionNebula', 'Emission Nebula'], ['galaxy', 'Galaxy'],
    ['galaxyGroup', 'Galaxy Group'], ['globularCluster', 'Globular Cluster'], ['openCluster', 'Open Cluster'],
    ['planetaryNebula', 'Planetary Nebula'], ['reflectionNebula', 'Reflection Nebula'], ['star', 'Star'],
    ['starCloud', 'Star Cloud'], ['supernovaRemnant', 'Supernova Remnant'],
  ];

  const numberText = (value, digits) => (value == null ? '' : String(Number(value.toFixed(digits))));
  let designation = $state(existing?.designation ?? '');
  let commonName = $state(existing?.commonName ?? '');
  let type = $state(existing?.type ?? 'emissionNebula');
  let constellation = $state(existing?.constellation ?? '');
  let raText = $state(numberText(existing?.rightAscension, 4));
  let decText = $state(numberText(existing?.declination, 4));
  let magnitudeText = $state(numberText(existing?.magnitude ?? 8, 1));
  let majorText = $state(numberText(existing?.majorAxisArcminutes ?? 10, 1));
  let minorText = $state(numberText(existing?.minorAxisArcminutes ?? 10, 1));

  // "20h 45m 38s", "20 45 38", "20:45:38" → hours → degrees; a plain number
  // is decimal degrees.
  function parseRA(text) {
    const t = text.trim();
    if (!t) return null;
    if (/^-?\d+(\.\d+)?$/.test(t)) return Number(t);
    const parts = t.replace(/[hms:'"′″]/gi, ' ').trim().split(/\s+/).map(Number);
    if (parts.some(n => !Number.isFinite(n)) || parts.length > 3) return null;
    const [h, m = 0, s = 0] = parts;
    return (h + m / 60 + s / 3600) * 15;
  }
  // "+30° 43′ 12″", "-5 23 28", "30:43:12" → degrees; a plain number is degrees.
  function parseDec(text) {
    const t = text.trim();
    if (!t) return null;
    if (/^[-+]?\d+(\.\d+)?$/.test(t)) return Number(t);
    const negative = /^\s*[-−]/.test(t);
    const parts = t.replace(/^[-+−]/, '').replace(/[°d:'"′″ms]/gi, ' ').trim().split(/\s+/).map(Number);
    if (parts.some(n => !Number.isFinite(n)) || parts.length > 3) return null;
    const [d, m = 0, s = 0] = parts;
    return (negative ? -1 : 1) * (d + m / 60 + s / 3600);
  }
  const number = text => (text.trim() === '' ? null : Number(text));

  const ra = $derived(parseRA(raText));
  const dec = $derived(parseDec(decText));
  const id = $derived(designation.trim());
  const clash = $derived(id && id !== existing?.designation && catalogIDs.has(id));
  const problems = $derived([
    !id && 'Give it a designation.',
    clash && `“${id}” is already in the catalog.`,
    (ra == null || ra < 0 || ra > 360) && 'Right ascension: 0h–24h, or 0–360°.',
    (dec == null || dec < -90 || dec > 90) && 'Declination: −90° to +90°.',
    !Number.isFinite(number(magnitudeText)) && 'Magnitude must be a number.',
    !(number(majorText) > 0) && 'Size must be more than 0.',
  ].filter(Boolean));

  const raHint = $derived(ra != null && ra >= 0 && ra <= 360
    ? (() => { const h = ra / 15; const hh = Math.floor(h); const mm = Math.floor((h - hh) * 60); const ss = Math.round(((h - hh) * 60 - mm) * 60); return `= ${hh}h ${mm}m ${ss}s · ${ra.toFixed(4)}°`; })()
    : '');
  const decHint = $derived(dec != null && Math.abs(dec) <= 90 ? `= ${dec.toFixed(4)}°` : '');

  function save() {
    if (problems.length) return;
    const major = number(majorText);
    const minor = number(minorText);
    onsave({
      designation: id,
      ...(commonName.trim() ? { commonName: commonName.trim() } : {}),
      type,
      rightAscension: ra,
      declination: dec,
      magnitude: number(magnitudeText),
      majorAxisArcminutes: major,
      minorAxisArcminutes: minor > 0 ? minor : major,
      constellation: constellation.trim(),
    }, existing?.designation ?? null);
  }

  let confirmingDelete = $state(false);
  function keydown(event) {
    if (event.key === 'Escape') onclose();
  }
</script>

<svelte:window onkeydown={keydown} />

<div class="backdrop" onclick={onclose} aria-hidden="true"></div>
<form class="editor panel" role="dialog" aria-label={existing ? 'Edit custom target' : 'Add custom target'}
      onsubmit={e => { e.preventDefault(); save(); }}>
  <header>
    <h2>{existing ? 'Edit Custom Target' : 'Add Custom Target'}</h2>
    <div class="row-buttons">
      <button type="button" onclick={onclose}>Cancel</button>
      <button type="submit" class="primary" disabled={problems.length > 0}>Save</button>
    </div>
  </header>

  <div class="group">
    <h3 class="group-title">Identity</h3>
    <div class="card">
      <label class="item"><span class="title">Designation</span><input type="text" bind:value={designation} placeholder="e.g. Sh2-129" autocapitalize="off" /></label>
      <label class="item"><span class="title">Common name <span class="caption">(optional)</span></span><input type="text" bind:value={commonName} placeholder="e.g. Flying Bat Nebula" /></label>
      <label class="item inline"><span class="title">Type</span>
        <select bind:value={type}>{#each types as [value, name]}<option {value}>{name}</option>{/each}</select>
      </label>
      <label class="item"><span class="title">Constellation <span class="caption">(optional, e.g. Cep)</span></span><input type="text" bind:value={constellation} /></label>
    </div>
  </div>

  <div class="group">
    <h3 class="group-title">Position (J2000)</h3>
    <div class="card">
      <label class="item"><span class="title">Right ascension</span>
        <input type="text" bind:value={raText} placeholder="21h 11m 48s, or degrees" inputmode="text" autocapitalize="off" />
        {#if raHint}<span class="caption">{raHint}</span>{/if}
      </label>
      <label class="item"><span class="title">Declination</span>
        <input type="text" bind:value={decText} placeholder="+59° 59′, or degrees" inputmode="text" autocapitalize="off" />
        {#if decHint}<span class="caption">{decHint}</span>{/if}
      </label>
    </div>
  </div>

  <div class="group">
    <h3 class="group-title">Size and brightness</h3>
    <div class="card">
      <div class="item numbers">
        <label><span>Magnitude</span><input type="text" inputmode="decimal" bind:value={magnitudeText} /></label>
        <label><span>Major axis (′)</span><input type="text" inputmode="decimal" bind:value={majorText} /></label>
        <label><span>Minor axis (′)</span><input type="text" inputmode="decimal" bind:value={minorText} /></label>
      </div>
    </div>
    <p class="group-note">Sizes in arcminutes. The Moon is about 31′ across.</p>
  </div>

  {#if problems.length}<ul class="problems">{#each problems as p}<li>{p}</li>{/each}</ul>{/if}

  {#if existing}
    <div class="delete">
      {#if confirmingDelete}
        <span>Delete {existing.commonName || existing.designation}?</span>
        <button type="button" onclick={() => (confirmingDelete = false)}>Keep</button>
        <button type="button" class="danger-fill" onclick={() => ondelete(existing.designation)}>Delete</button>
      {:else}
        <button type="button" class="text-button danger" onclick={() => (confirmingDelete = true)}>Delete Target</button>
      {/if}
    </div>
  {/if}
</form>

<style>
  .backdrop { position: fixed; inset: 0; background: rgba(0, 0, 0, 0.55); z-index: 40; }
  .editor {
    position: fixed; z-index: 41; top: 50%; left: 50%; transform: translate(-50%, -50%);
    width: min(480px, calc(100vw - 24px)); max-height: calc(100vh - 24px); overflow-y: auto;
    padding: 18px; display: grid; gap: 16px; border-radius: 16px; background: var(--space-bottom);
  }
  header { display: flex; justify-content: space-between; align-items: center; gap: 12px; flex-wrap: wrap; }
  h2 { margin: 0; font-size: 20px; }
  .item input[type='text'] { width: 100%; }
  .numbers { grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 10px; }
  .numbers label { display: grid; gap: 4px; font-size: 13px; color: var(--muted); }
  .numbers input { width: 100%; }
  .problems { margin: 0; padding-left: 18px; color: var(--marginal); font-size: 14px; display: grid; gap: 3px; }
  .delete { display: flex; gap: 10px; align-items: center; justify-content: flex-end; flex-wrap: wrap; }
  .danger-fill { background: var(--poor); border-color: var(--poor); color: #fff; font-weight: 700; }
</style>
