<script>
  // "More settings": the rest of the Mac app's Settings (UI/SettingsView.swift)
  // for the web, kept behind a disclosure so the guided few above stay the
  // first thing anyone sees. Same names, ranges and captions as the Mac.
  import { duration, degrees } from './format.js';
  import { uuid } from './uuid.js';
  import HorizonSliders from './HorizonSliders.svelte';

  let { settings, onchange } = $props();

  const site = $derived(settings.site);
  const rig = $derived(settings.rig);
  const prefs = $derived(settings.preferences);

  const setSite = fields => onchange({ ...settings, site: { ...site, ...fields } });
  const setRig = fields => onchange({ ...settings, rig: { ...rig, ...fields } });
  const setPrefs = fields => onchange({ ...settings, preferences: { ...prefs, ...fields } });

  // --- Site ---------------------------------------------------------------
  const zones = (() => {
    try { return Intl.supportedValuesOf('timeZone'); } catch { return null; }
  })();

  // --- Equipment ------------------------------------------------------------
  const f = $derived(rig.focalLengthMillimeters);
  const fov = $derived(f > 0 ? {
    w: 2 * Math.atan(rig.sensorWidthMillimeters / (2 * f)) * 180 / Math.PI,
    h: 2 * Math.atan(rig.sensorHeightMillimeters / (2 * f)) * 180 / Math.PI,
  } : null);
  const sampling = $derived(f > 0 ? 206.265 * rig.pixelSizeMicrons / f : null);
  const focalRatio = $derived(rig.apertureMillimeters > 0 ? f / rig.apertureMillimeters : null);
  const opticsOK = $derived(f > 0 && rig.apertureMillimeters > 0 && rig.sensorWidthMillimeters > 0 && rig.sensorHeightMillimeters > 0 && rig.pixelSizeMicrons > 0);

  function setNumber(field, text) {
    const value = Number(text);
    if (Number.isFinite(value) && value >= 0) setRig({ [field]: value });
  }

  const savedRigs = $derived(settings.savedRigs ?? []);
  function saveRig() {
    const others = savedRigs.filter(r => r.id !== rig.id);
    onchange({ ...settings, savedRigs: [...others, { ...rig }] });
  }
  function useRig(id) {
    const chosen = savedRigs.find(r => r.id === id);
    if (chosen) onchange({ ...settings, rig: { ...chosen } });
  }
  function forgetRig(id) {
    onchange({ ...settings, savedRigs: savedRigs.filter(r => r.id !== id) });
  }
  function newRig() {
    setRig({ id: uuid(), name: `${rig.name} (mine)` });
  }

  // --- Planning -------------------------------------------------------------
  // SettingsView.darknessSunAltitude: how far below the horizon the Sun must be.
  // Kasten & Young air mass (SkyCoordinates.airMass)
  const airMass = altitude => 1 / (Math.sin(altitude * Math.PI / 180) + 0.50572 * Math.pow(altitude + 6.07995, -1.6364));
  // Preferences.sessionCapMinutes / minimumSessionMinutes
  const cap = $derived(prefs.planEmphasis === 'moreTargets' ? Math.max(20, prefs.integrationGoalMinutes / 2) : prefs.integrationGoalMinutes);
  const floor = $derived(prefs.planEmphasis === 'moreTargets' ? 20 : Math.max(30, cap / 3));
  const verdictFor = s => (s >= 90 ? 'Exceptional' : s >= 75 ? 'Excellent' : s >= 60 ? 'Good' : s >= 45 ? 'Marginal' : 'Poor');

  // Sliders move freely and apply when let go.
  let draft = $state({});
  const shown = (key, value) => draft[key] ?? value;
  const slide = key => e => (draft = { ...draft, [key]: Number(e.currentTarget.value) });
  const commit = (key, apply) => e => {
    const value = Number(e.currentTarget.value);
    draft = { ...draft, [key]: undefined };
    apply(value);
  };
</script>

<div class="more">
  <section>
    <h3>Site details</h3>
    <label class="row">
      <span class="label">Name</span>
      <input type="text" value={site.name} onchange={e => setSite({ name: e.currentTarget.value })} />
    </label>
    <p class="muted">{site.latitude.toFixed(4)}°, {site.longitude.toFixed(4)}° · {Math.round(site.elevationMeters ?? 0)} m</p>
    <label class="row">
      <span class="label">Time zone</span>
      {#if zones}
        <select value={site.timeZoneIdentifier} onchange={e => setSite({ timeZoneIdentifier: e.currentTarget.value })}>
          {#each zones as zone}<option value={zone}>{zone}</option>{/each}
        </select>
      {:else}
        <input type="text" value={site.timeZoneIdentifier} onchange={e => setSite({ timeZoneIdentifier: e.currentTarget.value })} />
      {/if}
    </label>

    <div class="row">
      <span class="label">Your horizon</span>
      <p class="muted">How high trees and buildings reach in each direction. Targets lower than this don't count.</p>
      <HorizonSliders {site} onchange={setSite} />
    </div>

  </section>

  <section>
    <h3>Equipment</h3>
    <label class="row">
      <span class="label">Name</span>
      <input type="text" value={rig.name} onchange={e => setRig({ name: e.currentTarget.value })} />
    </label>
    <div class="grid">
      <label><span>Aperture (mm)</span><input type="number" inputmode="decimal" min="0" step="any" value={rig.apertureMillimeters} onchange={e => setNumber('apertureMillimeters', e.currentTarget.value)} /></label>
      <label><span>Focal length (mm)</span><input type="number" inputmode="decimal" min="0" step="any" value={rig.focalLengthMillimeters} onchange={e => setNumber('focalLengthMillimeters', e.currentTarget.value)} /></label>
      <label><span>Sensor width (mm)</span><input type="number" inputmode="decimal" min="0" step="any" value={rig.sensorWidthMillimeters} onchange={e => setNumber('sensorWidthMillimeters', e.currentTarget.value)} /></label>
      <label><span>Sensor height (mm)</span><input type="number" inputmode="decimal" min="0" step="any" value={rig.sensorHeightMillimeters} onchange={e => setNumber('sensorHeightMillimeters', e.currentTarget.value)} /></label>
      <label><span>Pixel size (µm)</span><input type="number" inputmode="decimal" min="0" step="any" value={rig.pixelSizeMicrons} onchange={e => setNumber('pixelSizeMicrons', e.currentTarget.value)} /></label>
    </div>
    {#if opticsOK && fov}
      <p class="muted">{fov.w.toFixed(2)}° × {fov.h.toFixed(2)}° field · f/{focalRatio.toFixed(1)} · {sampling.toFixed(2)}″/px</p>
    {:else}
      <p class="warn">Fill in every number for the framing to work.</p>
    {/if}
    <label class="row">
      <span class="label">Mount</span>
      <select value={rig.mountType} onchange={e => setRig({ mountType: e.currentTarget.value })}>
        <option value="altAzimuth">Alt-Azimuth</option>
        <option value="equatorial">Equatorial</option>
      </select>
    </label>
    <label class="check"><input type="checkbox" checked={rig.supportsMosaic} onchange={e => setRig({ supportsMosaic: e.currentTarget.checked })} /> Can shoot mosaics</label>
    {#if rig.mountType === 'altAzimuth'}
      <label class="check"><input type="checkbox" checked={prefs.showsZenithRiskWarnings ?? true} onchange={e => setPrefs({ showsZenithRiskWarnings: e.currentTarget.checked })} /> Show zenith risk warnings</label>
      {#if prefs.showsZenithRiskWarnings ?? true}
        <label class="slider">
          <span>Warn above</span>
          <input type="range" min="60" max="90" step="1" value={shown('zen', rig.zenithAvoidanceAltitude)}
                 oninput={slide('zen')} onchange={commit('zen', v => setRig({ zenithAvoidanceAltitude: v }))} />
          <strong>{degrees(shown('zen', rig.zenithAvoidanceAltitude))}</strong>
        </label>
      {/if}
    {/if}
    <div class="row">
      <span class="label">Your rigs</span>
      {#each savedRigs as r (r.id)}
        <div class="saved">
          <button type="button" onclick={() => useRig(r.id)} disabled={r.id === rig.id}>{r.name}{r.id === rig.id ? ' (in use)' : ''}</button>
          <button type="button" class="forget" onclick={() => forgetRig(r.id)} aria-label="Forget {r.name}">✕</button>
        </div>
      {/each}
      <div class="buttons">
        <button type="button" onclick={saveRig}>Save This Rig</button>
        <button type="button" onclick={newRig}>Start a Custom Rig From This</button>
      </div>
    </div>
  </section>

  <section>
    <h3>Planning</h3>
    <label class="slider wide">
      <span>Minimum darkness</span>
      <input type="range" min="0.1" max="1" step="0.05" value={shown('dark', prefs.minimumDarkness)}
             oninput={slide('dark')} onchange={commit('dark', v => setPrefs({ minimumDarkness: v }))} />
      <strong>Sun {Math.round(Math.pow(shown('dark', prefs.minimumDarkness), 1 / 1.4) * 12 + 6)}° below the horizon</strong>
    </label>
    <p class="muted">18° below is full astronomical darkness. Moonlight is scored separately.</p>
    <label class="slider wide">
      <span>Minimum altitude</span>
      <input type="range" min="10" max="60" step="5" value={shown('alt', prefs.minimumUsefulAltitude)}
             oninput={slide('alt')} onchange={commit('alt', v => setPrefs({ minimumUsefulAltitude: v }))} />
      <strong>{degrees(shown('alt', prefs.minimumUsefulAltitude))}</strong>
    </label>
    <p class="muted">Targets lower than this are ignored — there you look through {airMass(shown('alt', prefs.minimumUsefulAltitude)).toFixed(1)} times as much air as straight up.</p>
    <label class="slider wide">
      <span>Integration goal</span>
      <input type="range" min="30" max="480" step="15" value={shown('goal', prefs.integrationGoalMinutes)}
             oninput={slide('goal')} onchange={commit('goal', v => setPrefs({ integrationGoalMinutes: v }))} />
      <strong>{duration(shown('goal', prefs.integrationGoalMinutes))}</strong>
    </label>
    <p class="muted">Full marks for time once a target is usable this long.</p>
    <div class="row">
      <span class="label">Suggested plan favours</span>
      <div class="segments">
        <button type="button" class:on={prefs.planEmphasis !== 'moreTargets'} onclick={() => setPrefs({ planEmphasis: 'longerIntegration' })}>Longer integration</button>
        <button type="button" class:on={prefs.planEmphasis === 'moreTargets'} onclick={() => setPrefs({ planEmphasis: 'moreTargets' })}>More targets</button>
      </div>
      <p class="muted">At most {duration(cap)} per target{prefs.planEmphasis === 'moreTargets' ? ', so about twice as many fit,' : ', and nothing shorter than'} {prefs.planEmphasis === 'moreTargets' ? `down to ${duration(floor)}` : duration(floor)}.</p>
    </div>
  </section>

  <section>
    <h3>What to show</h3>
    <label class="slider wide">
      <span>Hide below score</span>
      <input type="range" min="0" max="80" step="5" value={shown('min', prefs.minimumScore)}
             oninput={slide('min')} onchange={commit('min', v => setPrefs({ minimumScore: v }))} />
      <strong>{shown('min', prefs.minimumScore)} · {verdictFor(shown('min', prefs.minimumScore))}</strong>
    </label>
    <label class="slider wide">
      <span>Plan nights ahead</span>
      <input type="range" min="1" max="14" step="1" value={shown('nights', prefs.forecastNights)}
             oninput={slide('nights')} onchange={commit('nights', v => setPrefs({ forecastNights: v }))} />
      <strong>{shown('nights', prefs.forecastNights)}</strong>
    </label>
    <label class="check"><input type="checkbox" checked={prefs.includeStarClusters} onchange={e => setPrefs({ includeStarClusters: e.currentTarget.checked })} /> Include star clusters</label>
    <label class="check"><input type="checkbox" checked={prefs.includeStars} onchange={e => setPrefs({ includeStars: e.currentTarget.checked })} /> Show bright stars and doubles</label>
    <label class="check"><input type="checkbox" checked={prefs.includeComets} onchange={e => setPrefs({ includeComets: e.currentTarget.checked })} /> Show visible comets</label>
    <label class="check"><input type="checkbox" checked={prefs.includeOversizedTargets} onchange={e => setPrefs({ includeOversizedTargets: e.currentTarget.checked })} /> Include targets larger than the frame</label>
    <label class="check"><input type="checkbox" checked={prefs.nightMode ?? false} onchange={e => setPrefs({ nightMode: e.currentTarget.checked })} /> Night mode (red light only)</label>
  </section>
</div>

<style>
  .more { display: grid; gap: 18px; }
  section { display: grid; gap: 8px; padding-top: 12px; border-top: 1px solid var(--panel-border); }
  h3 { margin: 0; font-size: 13px; text-transform: uppercase; letter-spacing: 0.06em; color: var(--accent); }
  p { margin: 0; }
  .row { display: grid; gap: 6px; }
  .label { font-weight: 600; }
  .check { display: flex; gap: 8px; align-items: center; }
  input[type='checkbox'], input[type='range'] { accent-color: var(--accent); }
  .slider { display: grid; grid-template-columns: 82px 1fr 44px; gap: 8px; align-items: center; }
  .slider.wide { grid-template-columns: 1fr; gap: 4px; }
  .slider.wide span { font-weight: 600; }
  .slider strong { text-align: right; font-variant-numeric: tabular-nums; }
  .slider.wide strong { text-align: left; font-weight: 500; color: var(--muted); }
  .slider input { width: 100%; padding: 0; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(140px, 1fr)); gap: 8px; }
  .grid label { display: grid; gap: 4px; font-size: 13px; color: var(--muted); }
  .grid input { width: 100%; }
  .saved { display: flex; gap: 6px; }
  .saved button:first-child { flex: 1; text-align: left; }
  .forget { width: 40px; padding: 0; }
  .buttons, .segments { display: flex; gap: 8px; flex-wrap: wrap; }
  .segments button.on { background: rgba(158, 133, 250, 0.25); border-color: var(--accent); }
  .warn { color: var(--marginal); }
</style>
