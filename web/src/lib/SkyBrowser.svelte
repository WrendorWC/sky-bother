<script>
  // SkyBrowserView: a window onto the real sky — pan, zoom, search — with
  // your rig's frame fixed at the centre, so you can see what any part of it
  // would give you. The sky is Aladin Lite (CDS, LGPL) showing the colour
  // Digitized Sky Survey as HiPS tiles: it pans and pinch-zooms smoothly on a
  // phone, which the Mac's cutout-per-view approach wouldn't. Loaded only
  // when this opens. Marks, "What's This?", the centre readout and the frame
  // follow the Mac.
  import Thumbnail from './Thumbnail.svelte';
  import { view } from './view.svelte.js';

  let { entries, rig, designation = null, backHref = '#/' } = $props();

  // --- The frame -------------------------------------------------------------
  const frame = $derived.by(() => {
    const f = rig.focalLengthMillimeters;
    if (!(f > 0)) return null;
    const deg = s => 2 * Math.atan(s / (2 * f)) * 180 / Math.PI;
    return { width: deg(rig.sensorWidthMillimeters), height: deg(rig.sensorHeightMillimeters) };
  });
  const frameLong = $derived(frame ? Math.max(frame.width, frame.height) : 1);
  const MIN_FOV = 0.25, MAX_FOV = 120;
  // The field across that shows the whole frame with room around it — in
  // both directions, so a wide, short view doesn't cut its top and bottom
  // off — and the whole object.
  function fitFor(entry) {
    const aspect = size.width && size.height ? size.height / size.width : 1;
    const frameFit = frame ? Math.max(frame.width * 1.8, frame.height * 1.6 / aspect) : frameLong * 2.2;
    const object = (entry?.majorAxisArcminutes ?? 0) / 60 * 1.4;
    return Math.min(MAX_FOV, Math.max(MIN_FOV, frameFit, object, object / aspect));
  }

  // --- Aladin ------------------------------------------------------------------
  let host = $state(null);
  let A = null, aladin = null, marks = null;
  let failed = $state('');
  let centre = $state({ ra: 10.6847, dec: 41.269 });
  let fov = $state([2, 2]);
  let size = $state({ width: 0, height: 0 });
  let title = $state('Sky Browser');

  const start = $derived(entries.find(e => e.designation === designation || e.id === designation) ?? entries.find(e => e.id === 'M31') ?? entries[0]);

  $effect(() => {
    if (!host || aladin) return;
    let cancelled = false;
    (async () => {
      try {
        A = (await import('aladin-lite')).default;
        await A.init;
        if (cancelled) return;
        aladin = A.aladin(host, {
          // CDS's own copy of the survey, named outright: left to choose, Aladin
          // picked a mirror (IRSA) that refuses other sites, and the sky stayed
          // black until it gave up on it.
          survey: 'https://alasky.cds.unistra.fr/DSS/DSSColor/', projection: 'TAN', cooFrame: 'ICRS',
          fov: fitFor(start), target: `${start.rightAscension} ${start.declination}`,
          showReticle: false, showZoomControl: false, showLayersControl: false, showFrame: false,
          showFullscreenControl: false, showCooGrid: false, showProjectionControl: false,
          showSimbadPointerControl: false, showContextMenu: false, showCooLocation: false,
          showStatusBar: false, showSettingsControl: false, showShareControl: false, showGotoControl: false,
        });
        marks = A.catalog({
          name: 'Sky Bother', shape: 'circle', color: '#9e85fa', sourceSize: 16,
          displayLabel: true, labelColumn: 'name', labelColor: '#ffffff', labelFont: '600 12px -apple-system, sans-serif',
        });
        aladin.addCatalog(marks);
        aladin.on('positionChanged', changed);
        aladin.on('zoomChanged', changed);
        title = start.displayName;
        changed();
        showFirstPicture(start.rightAscension, start.declination, fitFor(start));
      } catch (e) {
        failed = `The sky couldn't be loaded: ${e.message}`;
      }
    })();
    return () => { cancelled = true; };
  });

  // The first picture (as the Mac shows every view): one cutout of exactly
  // what's on screen, asked for at once and shown in place of Aladin's image
  // layer — its marks stay on top — until you pan or zoom. Survey tiles come
  // one at a time from France, a second or so each, so without this the
  // first view took ten or fifteen seconds to fill in.
  let firstPicture = $state(null);
  let pictureFor = 0;
  const cutouts = ['https://alaskybis.cds.unistra.fr/hips-image-services/hips2fits', 'https://alasky.cds.unistra.fr/hips-image-services/hips2fits'];
  // Given where the view was sent rather than read back from Aladin, which
  // hasn't settled yet (its first answer is a near-whole-sky field, and the
  // picture came back as streaks).
  async function showFirstPicture(ra, dec, fovAcross) {
    if (!aladin || !size.width || !size.height) return;
    const id = ++pictureFor;
    const fx = fovAcross, fy = fovAcross * size.height / size.width;
    const ratio = Math.min(2, devicePixelRatio || 1);
    const query = new URLSearchParams({
      hips: 'CDS/P/DSS2/color', ra: String(ra), dec: String(dec), projection: 'TAN', format: 'jpg',
      // hips2fits's field of view is along the picture's longer side.
      fov: String(Math.max(fx, fy)),
      width: String(Math.min(1600, Math.round(size.width * ratio))), height: String(Math.min(1600, Math.round(size.height * ratio))),
    });
    for (const endpoint of cutouts) {
      try {
        const response = await fetch(`${endpoint}?${query}`);
        if (!response.ok) continue;
        const blob = await response.blob();
        if (id !== pictureFor) return;
        if (firstPicture) URL.revokeObjectURL(firstPicture);
        firstPicture = URL.createObjectURL(blob);
        return;
      } catch {}
    }
  }
  function dropFirstPicture() {
    pictureFor++;
    if (firstPicture) URL.revokeObjectURL(firstPicture);
    firstPicture = null;
  }

  let markTimer = null;
  function changed() {
    if (!aladin) return;
    const [ra, dec] = aladin.getRaDec();
    centre = { ra: ((ra % 360) + 360) % 360, dec };
    fov = aladin.getFov();
    clearTimeout(markTimer);
    markTimer = setTimeout(remark, 120);
  }

  // SkyBrowserView.visibleTargets: what's in view, most prominent first, 25 at most.
  function remark() {
    if (!marks) return;
    const halfW = fov[0] / 2, halfH = fov[1] / 2;
    const cosDec = Math.max(0.02, Math.cos(centre.dec * Math.PI / 180));
    const inView = entries.filter(e => {
      let dRA = e.rightAscension - centre.ra;
      if (dRA > 180) dRA -= 360;
      if (dRA < -180) dRA += 360;
      return Math.abs(dRA * cosDec) <= halfW && Math.abs(e.declination - centre.dec) <= halfH;
    }).sort((a, b) => b.majorAxisArcminutes - a.majorAxisArcminutes).slice(0, 25);
    marks.removeAll();
    marks.addSources(inView.map(e => A.source(e.rightAscension, e.declination, { name: e.displayName })));
  }

  function go(entry) {
    search = '';
    title = entry.displayName;
    dropFirstPicture();
    aladin?.gotoRaDec(entry.rightAscension, entry.declination);
    aladin?.setFoV(fitFor(entry));
    changed();
    showFirstPicture(entry.rightAscension, entry.declination, fitFor(entry));
  }
  function zoom(factor) {
    dropFirstPicture();
    aladin?.setFoV(Math.min(MAX_FOV, Math.max(MIN_FOV, fov[0] * factor)));
  }

  // --- Search ------------------------------------------------------------------
  let search = $state('');
  const matches = $derived(search.trim() ? entries.filter(e => e.searchText.includes(search.trim().toLowerCase())).slice(0, 8) : []);

  // --- The frame, drawn at the centre ----------------------------------------
  const frameBox = $derived(frame && size.width && fov[0] > 0
    ? { width: frame.width / fov[0] * size.width, height: frame.height / fov[1] * size.height } : null);

  // --- Where the frame points (Format.preciseCoordinates) ------------------
  const readout = $derived.by(() => {
    const tenths = Math.round(centre.ra / 15 * 36_000) % (24 * 36_000);
    const seconds = Math.round(Math.abs(centre.dec) * 3600);
    const p = (n, w = 2) => String(n).padStart(w, '0');
    return `${p(Math.floor(tenths / 36_000))}h ${p(Math.floor(tenths / 600) % 60)}m ${(tenths % 600 / 10).toFixed(1).padStart(4, '0')}s  ${centre.dec < 0 ? '−' : '+'}${p(Math.floor(seconds / 3600))}° ${p(Math.floor(seconds / 60) % 60)}′ ${p(seconds % 60)}″`;
  });
  let copied = $state(false);
  async function copy() {
    try { await navigator.clipboard.writeText(readout); copied = true; setTimeout(() => (copied = false), 1500); } catch {}
  }

  // --- What's This? (SkyBrowserView.identifyCentre, SkyResolver) -----------
  let identifying = $state(false);
  let centreName = $state(null);
  let resolving = $state(false);
  let identifyTimer = null;
  $effect(() => {
    const on = identifying, c = centre, width = fov[0];
    clearTimeout(identifyTimer);
    if (!on) { centreName = null; return; }
    identifyTimer = setTimeout(() => identify(c, width), 500);
  });

  async function identify(c, width) {
    const rad = Math.PI / 180;
    const separation = e => {
      const a = Math.sin(e.declination * rad) * Math.sin(c.dec * rad) + Math.cos(e.declination * rad) * Math.cos(c.dec * rad) * Math.cos((e.rightAscension - c.ra) * rad);
      return Math.acos(Math.min(1, Math.max(-1, a))) / rad;
    };
    let best = null;
    for (const e of entries) {
      const ratio = separation(e) / Math.max(e.majorAxisArcminutes / 60 / 2, 0.02);
      if (ratio <= 1.5 && (!best || ratio < best.ratio)) best = { e, ratio };
    }
    if (best) { centreName = `${best.e.displayName} · ${best.e.typeName}`; return; }
    resolving = true;
    centreName = null;
    try {
      const radius = Math.max(0.5, Math.min(30, width * 60 / 8)).toFixed(1);
      const url = `https://simbad.harvard.edu/simbad/sim-coo?${new URLSearchParams({ Coord: `${c.ra.toFixed(5)} ${c.dec >= 0 ? '+' : ''}${c.dec.toFixed(5)}`, Radius: radius, 'Radius.unit': 'arcmin', 'output.format': 'ASCII' })}`;
      const text = await (await fetch(url)).text();
      if (centre !== c) return;
      centreName = recognisable(text);
    } catch {
      centreName = null;
    } finally {
      resolving = false;
    }
  }

  const PREFIXES = ['M ', 'NGC ', 'IC ', 'UGC ', 'PGC ', 'Sh2-', 'LBN ', 'LDN ', 'NAME '];
  const EXTENDED = new Set(['G', 'GiG', 'GiC', 'H2G', 'Sy1', 'Sy2', 'AGN', 'LIN', 'SBG', 'rG', 'IG', 'GlC', 'OpC', 'Cl*', 'PN', 'SNR', 'HII', 'RNe', 'DNe', 'GNe', 'ISM', 'MoC', 'Cld']);
  function describe(code) {
    if (['G', 'GiG', 'GiC', 'H2G', 'Sy2', 'Sy1', 'AGN', 'LIN', 'SBG', 'rG', 'IG'].includes(code)) return 'Galaxy';
    if (code === 'GlC') return 'Globular Cluster';
    if (code === 'OpC' || code === 'Cl*') return 'Open Cluster';
    if (code === 'PN' || code === 'pA*') return 'Planetary Nebula';
    if (code === 'SNR') return 'Supernova Remnant';
    if (['HII', 'ISM', 'RNe', 'DNe', 'GNe', 'Cld', 'MoC'].includes(code)) return 'Nebula';
    if (['*', 'PM*', 'V*', '**'].includes(code)) return 'Star';
    return code;
  }
  function recognisable(text) {
    let best = null, anything = null;
    for (const line of text.split('\n')) {
      const columns = line.split('|');
      if (columns.length <= 4) continue;
      const identifier = columns[2].trim(), type = columns[3].trim();
      if (!PREFIXES.some(p => identifier.startsWith(p)) || identifier.endsWith('*')) continue;
      const name = identifier.startsWith('NAME ') ? identifier.slice(5) : identifier;
      const described = type ? `${name} · ${describe(type)}` : name;
      anything ??= described;
      if (EXTENDED.has(type) && !best) best = described;
    }
    return best ?? anything;
  }

  const fovText = $derived(fov[0] >= 1 ? `${fov[0].toFixed(1)}° across` : `${Math.round(fov[0] * 60)}′ across`);
</script>

<section class="browser">
  <header>
    <a class="back" href={backHref}>‹ Back</a>
    <h2>Sky Browser{title !== 'Sky Browser' ? ` — ${title}` : ''}</h2>
  </header>

  <div class="toolbar">
    <div class="search">
      <input type="search" placeholder="Find an object" bind:value={search}
             onkeydown={e => { if (e.key === 'Enter' && matches[0]) go(matches[0]); }} />
      {#if matches.length}
        <ul class="results panel">
          {#each matches as entry (entry.id)}
            <li><button type="button" onclick={() => go(entry)}>
              <Thumbnail designation={entry.designation} size={30} label={entry.displayName} />
              <span><strong>{entry.displayName}</strong><span class="muted">{entry.designation} · {entry.typeName}</span></span>
            </button></li>
          {/each}
        </ul>
      {/if}
    </div>
    <button type="button" class="identify" class:on={identifying} onclick={() => (identifying = !identifying)} title="Name what's at the centre">
      {identifying ? '🏷 What’s This? On' : '🏷 What’s This?'}
    </button>
    <span class="fov">{fovText}</span>
    <button type="button" class="zoom" onclick={() => zoom(1 / 1.6)} aria-label="Zoom in">+</button>
    <button type="button" class="zoom" onclick={() => zoom(1.6)} aria-label="Zoom out">−</button>
  </div>
  {#if identifying}
    <p class="identified">{resolving ? 'Looking…' : centreName ?? 'Nothing catalogued here'}</p>
  {/if}

  <div class="sky" class:picture={firstPicture} bind:clientWidth={size.width} bind:clientHeight={size.height}
       onpointerdown={dropFirstPicture} onwheel={dropFirstPicture}>
    {#if firstPicture}<img class="first" src={firstPicture} alt="" />{/if}
    <div class="aladin" bind:this={host}></div>
    {#if frameBox}
      <div class="frame" style:width="{frameBox.width}px" style:height="{frameBox.height}px"
           style:transform="translate(-50%, -50%) rotate({view.roll ?? 0}deg)"></div>
    {/if}
    <div class="readout">
      <span>{readout}</span>
      <button type="button" onclick={copy} title="Copy the frame's centre (J2000)">{copied ? '✓ Copied' : 'Copy'}</button>
    </div>
    {#if failed}<p class="error failed">{failed}</p>{/if}
  </div>

  <footer class="muted">
    <span>Drag to pan · pinch or scroll to zoom</span>
    <span>{rig.name}{frame ? ` · ${frame.width.toFixed(2)}° × ${frame.height.toFixed(2)}°` : ''}</span>
    <span>Digitized Sky Survey (STScI/NASA), colour by CDS · <a href="https://aladin.cds.unistra.fr/AladinLite/" target="_blank" rel="noopener">Aladin Lite</a> (CDS, LGPL)</span>
  </footer>
</section>

<style>
  .browser { display: grid; gap: 10px; padding-top: 12px; }
  header { display: grid; gap: 2px; }
  .back { color: var(--accent); text-decoration: none; font-weight: 600; }
  h2 { margin: 0; font-size: 22px; }
  .toolbar { display: flex; flex-wrap: wrap; gap: 8px 10px; align-items: center; position: relative; z-index: 3; }
  .search { position: relative; flex: 1 1 220px; max-width: 340px; }
  .search input { width: 100%; }
  .results { position: absolute; top: calc(100% + 4px); left: 0; right: 0; list-style: none; margin: 0; padding: 4px; display: grid; gap: 2px; box-shadow: 0 12px 30px rgba(0, 0, 0, 0.5); }
  .results button { display: flex; gap: 9px; align-items: center; width: 100%; padding: 5px 7px; text-align: left; background: none; border: none; }
  .results button:hover { background: rgba(158, 133, 250, 0.15); }
  .results span { display: grid; min-width: 0; }
  .results strong, .results .muted { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .identify { font-weight: 600; }
  .identify.on { border-color: var(--accent); color: var(--accent); background: rgba(158, 133, 250, 0.18); }
  .fov { color: var(--muted); font-variant-numeric: tabular-nums; font-size: 13px; margin-left: auto; }
  .zoom { width: 38px; padding: 6px 0; font-size: 18px; font-weight: 700; }
  .identified { margin: 0; font-weight: 600; color: var(--accent); }
  .sky { position: relative; height: clamp(320px, 70vh, 860px); border-radius: 12px; overflow: hidden; border: 1px solid var(--panel-border); background: #000; touch-action: none; }
  .aladin { position: absolute; inset: 0; z-index: 1; }
  .first { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; z-index: 0; }
  /* While the first picture shows, Aladin's image layer steps aside; its
     marks stay drawn over the picture. */
  .sky.picture .aladin, .sky.picture .aladin :global(.aladin-container) { background: transparent !important; }
  .sky.picture .aladin :global(.aladin-imageCanvas) { opacity: 0; }
  .frame { position: absolute; left: 50%; top: 50%; border: 2px solid #3dc778; box-shadow: 0 0 0 1px rgba(0, 0, 0, 0.6); pointer-events: none; z-index: 2; }
  .readout { position: absolute; left: 12px; bottom: 12px; z-index: 2; display: flex; gap: 8px; align-items: center; padding: 5px 9px; border-radius: 6px; background: rgba(0, 0, 0, 0.75); color: #fff; font-variant-numeric: tabular-nums; font-size: 14px; }
  .readout button { padding: 2px 8px; font-size: 12px; background: rgba(255, 255, 255, 0.12); border-color: transparent; color: #fff; }
  .failed { position: absolute; inset: auto 12px 50% 12px; text-align: center; }
  footer { display: flex; flex-wrap: wrap; gap: 4px 16px; justify-content: space-between; font-size: 12px; }
  footer a { color: inherit; }
  /* Aladin's own controls and logo stay out of the way. */
  .aladin :global(.aladin-logo-container) { opacity: 0.5; }
  /* Its field-size label sat under the centre readout; the toolbar says it. */
  .aladin :global(.aladin-fov), .aladin :global(.aladin-fov-text), .aladin :global(.aladin-location) { display: none !important; }
</style>
