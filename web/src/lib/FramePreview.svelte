<script>
  // FramingPreview (UI/TargetDetailView.swift): the patch of sky round a
  // target from the Digitized Sky Survey, with your camera's frame drawn on
  // it to scale and rolled. Sized so the frame and the object both fit with a
  // margin; an object bigger than the frame visibly spills past its edges.
  import { view } from './view.svelte.js';
  import { fieldOfView } from './sky.js';

  let { target } = $props();

  let width = $state(0);
  const height = $derived(Math.round(width * 0.62));
  let image = $state(null);
  let failed = $state(false);

  const fov = $derived(fieldOfView(view.rig));
  // Arcminutes; the long axis of the object laid along the frame's long side.
  const frame = $derived(fov ? { w: fov.width * 60, h: fov.height * 60 } : null);
  const portrait = $derived(frame && frame.h > frame.w);
  const object = $derived({
    w: Math.max(0.2, portrait ? target.minorAxisArcminutes : target.majorAxisArcminutes),
    h: Math.max(0.2, portrait ? target.majorAxisArcminutes : target.minorAxisArcminutes),
  });
  // Pixels per arcminute.
  const scale = $derived(frame && width ? Math.min(width / (Math.max(frame.w, object.w) * 1.18), height / (Math.max(frame.h, object.h) * 1.18)) : 0);
  // Past 25° the survey is a dark patchwork (the Mac switches to its star map).
  const tooWide = $derived(frame && Math.max(frame.w, frame.h) > 1500);

  // SkyCutoutClient: DSS2 colour, the mirror first and the primary as fallback.
  const endpoints = [
    'https://alaskybis.cds.unistra.fr/hips-image-services/hips2fits',
    'https://alasky.cds.unistra.fr/hips-image-services/hips2fits',
  ];
  $effect(() => {
    if (!scale || tooWide) return;
    const ratio = Math.min(2, window.devicePixelRatio || 1);
    const query = new URLSearchParams({
      hips: 'CDS/P/DSS2/color', ra: String(target.rightAscension), dec: String(target.declination),
      fov: String(width / scale / 60), width: String(Math.round(width * ratio)), height: String(Math.round(height * ratio)),
      format: 'jpg',
    });
    let cancelled = false;
    failed = false;
    (async () => {
      for (const endpoint of endpoints) {
        try {
          const response = await fetch(`${endpoint}?${query}`);
          if (!response.ok) continue;
          const url = URL.createObjectURL(await response.blob());
          if (cancelled) return URL.revokeObjectURL(url);
          if (image) URL.revokeObjectURL(image);
          image = url;
          return;
        } catch {}
      }
      if (!cancelled) failed = true;
    })();
    return () => (cancelled = true);
  });
</script>

{#if frame}
  <div class="preview" bind:clientWidth={width} style:height="{height}px">
    {#if image}<img src={image} alt="The sky round {target.displayName ?? target.id}" />{/if}
    {#if scale}
      <svg viewBox="0 0 {width} {height}" aria-hidden="true">
        <g transform="translate({width / 2} {height / 2}) rotate({view.roll})">
          <rect x={-frame.w * scale / 2} y={-frame.h * scale / 2} width={frame.w * scale} height={frame.h * scale}
                fill="none" stroke="rgba(0,0,0,0.6)" stroke-width="4" />
          <rect x={-frame.w * scale / 2} y={-frame.h * scale / 2} width={frame.w * scale} height={frame.h * scale}
                fill="none" stroke="var(--excellent)" stroke-width="2" />
        </g>
        <g stroke="rgba(110, 180, 255, 0.85)" stroke-width="1.5">
          <line x1={width / 2 - 12} y1={height / 2} x2={width / 2 - 4} y2={height / 2} />
          <line x1={width / 2 + 4} y1={height / 2} x2={width / 2 + 12} y2={height / 2} />
          <line x1={width / 2} y1={height / 2 - 12} x2={width / 2} y2={height / 2 - 4} />
          <line x1={width / 2} y1={height / 2 + 4} x2={width / 2} y2={height / 2 + 12} />
        </g>
      </svg>
    {/if}
    <span class="size">{fov.width.toFixed(2)}° × {fov.height.toFixed(2)}°</span>
    {#if !image && !tooWide}<span class="status">{failed ? 'Sky picture unavailable' : 'Loading the sky…'}</span>{/if}
  </div>
  <p class="credit">Digitized Sky Survey (STScI/NASA), colour by CDS</p>
{/if}

<style>
  .preview {
    position: relative; width: 100%; overflow: hidden; border-radius: 10px;
    border: 1px solid var(--panel-border); background: #05060c;
  }
  img, svg { position: absolute; inset: 0; width: 100%; height: 100%; display: block; }
  img { object-fit: cover; }
  .size {
    position: absolute; top: 8px; left: 8px; padding: 2px 7px; border-radius: 5px;
    background: rgba(0, 0, 0, 0.6); color: var(--excellent); font-weight: 600; font-size: 14px;
  }
  .status { position: absolute; inset: 0; display: grid; place-items: center; color: var(--muted); font-size: 13px; }
  .credit { margin: 4px 0 0; font-size: 11px; color: var(--tertiary); }
</style>
