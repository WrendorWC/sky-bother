<script>
  // NightTimelineView: sunset to sunrise. Sky colour by the Sun's depth,
  // moonlight wash, cloud hanging from the top, the Moon's altitude, and the
  // selected target's altitude and windows. Hover (or drag a finger) to read
  // any moment.
  import * as palette from './palette.js';
  import { time, minuteOfHour, temperature, degrees } from './format.js';

  let { night, selected = null, timeZone, imperial = false, height = 152 } = $props();

  let canvas;
  let width = $state(0);
  let pointerX = $state(null);

  const start = $derived(Date.parse(night.chartWindow.start));
  const end = $derived(Date.parse(night.chartWindow.end));
  const xFor = t => ((Date.parse(t) - start) / (end - start)) * width;
  const clamp = (x, lo, hi) => Math.min(hi, Math.max(lo, x));

  const hourTicks = $derived.by(() => {
    const ticks = [];
    const quarter = 15 * 60 * 1000;
    for (let t = Math.ceil(start / quarter) * quarter; t <= end; t += quarter) {
      if (minuteOfHour(new Date(t), timeZone) === 0) ticks.push(t);
    }
    return ticks;
  });

  const hovered = $derived.by(() => {
    if (pointerX == null || !night.samples.length) return null;
    const index = Math.round(clamp(pointerX / width, 0, 1) * (night.samples.length - 1));
    return { sample: night.samples[index], index };
  });

  $effect(() => {
    draw(canvas, width, height, night, selected, hourTicks);
  });

  function draw(canvas, width, height, night, selected, ticks) {
    if (!canvas || width === 0) return;
    const ratio = window.devicePixelRatio || 1;
    canvas.width = Math.round(width * ratio);
    canvas.height = Math.round(height * ratio);
    const c = canvas.getContext('2d');
    c.setTransform(ratio, 0, 0, ratio, 0, 0);
    c.clearRect(0, 0, width, height);

    const samples = night.samples;
    const n = samples.length;
    const stepX = n > 1 ? width / (n - 1) : width;

    // Sky, then the Moon's wash over it.
    if (n > 1) {
      const sky = c.createLinearGradient(0, 0, width, 0);
      const moon = c.createLinearGradient(0, 0, width, 0);
      samples.forEach((s, i) => {
        sky.addColorStop(i / (n - 1), palette.css(palette.sky(s.sunAltitude)));
        moon.addColorStop(i / (n - 1), palette.css(palette.moonlight, s.moonAltitude > 0 ? 0.34 * s.moonBrightness : 0));
      });
      c.fillStyle = sky;
      c.fillRect(0, 0, width, height);
      c.fillStyle = moon;
      c.fillRect(0, 0, width, height);
    } else {
      c.fillStyle = palette.css(palette.astronomical);
      c.fillRect(0, 0, width, height);
    }

    // Cloud from the top, one point an hour, smoothed.
    if (night.hasWeather && n > 1) {
      const interval = Math.max(1, (Date.parse(samples[1].date) - Date.parse(samples[0].date)) / 60000);
      const perHour = Math.max(1, Math.round(60 / interval));
      const indices = [];
      for (let i = 0; i < n; i += perHour) indices.push(i);
      if (indices.at(-1) !== n - 1) indices.push(n - 1);
      const depth = height * 0.68;
      const points = indices
        .filter(i => samples[i].cloudCover != null)
        .map(i => [i * stepX, clamp(samples[i].cloudCover / 100, 0, 1) * depth]);
      if (points.length > 1) {
        const line = smoothLine(points);
        const fill = new Path2D(line);
        fill.lineTo(width, 0);
        fill.lineTo(0, 0);
        fill.closePath();
        const gradient = c.createLinearGradient(0, 0, 0, depth);
        gradient.addColorStop(0, palette.css(palette.cloud, 0.72));
        gradient.addColorStop(1, palette.css(palette.cloud, 0.34));
        c.fillStyle = gradient;
        c.fill(fill);
        c.strokeStyle = palette.css(palette.cloud, 0.85);
        c.lineWidth = 1;
        c.stroke(line);
      }
    }

    // The Moon's altitude, along the bottom.
    c.beginPath();
    let drawing = false;
    samples.forEach((s, i) => {
      if (s.moonAltitude <= 0) { drawing = false; return; }
      const y = height - 4 - clamp(s.moonAltitude / 90, 0, 1) * height * 0.42;
      drawing ? c.lineTo(i * stepX, y) : c.moveTo(i * stepX, y);
      drawing = true;
    });
    c.strokeStyle = palette.css(palette.moonlight, 0.85);
    c.lineWidth = 1.5;
    c.lineCap = 'round';
    c.stroke();

    if (selected) drawTarget(c, selected, width, height);

    // Astronomical dusk and dawn.
    c.setLineDash([3, 3]);
    c.strokeStyle = 'rgba(255,255,255,0.42)';
    c.lineWidth = 1;
    c.font = '9px system-ui, sans-serif';
    c.textAlign = 'center';
    c.textBaseline = 'middle';
    for (const [date, label] of [[night.astronomicalDusk, 'dark'], [night.astronomicalDawn, 'dawn']]) {
      if (!date) continue;
      const x = xFor(date);
      if (x < 0 || x > width) continue;
      c.beginPath();
      c.moveTo(x, 0);
      c.lineTo(x, height);
      c.stroke();
      c.fillStyle = 'rgba(255,255,255,0.7)';
      c.fillText(label, x + 15, 10);
    }
    c.setLineDash([]);

    // Hour ticks, every other one when they crowd.
    const step = width / Math.max(1, ticks.length) < 34 ? 2 : 1;
    ticks.forEach((t, i) => {
      const x = ((t - start) / (end - start)) * width;
      c.strokeStyle = 'rgba(255,255,255,0.35)';
      c.beginPath();
      c.moveTo(x, height - 14);
      c.lineTo(x, height - 10);
      c.stroke();
      if (i % step) return;
      c.fillStyle = 'rgba(255,255,255,0.75)';
      c.fillText(time(t, timeZone), clamp(x, 14, width - 14), height - 5);
    });

    // Now.
    const now = Date.now();
    if (now > start && now < end) {
      const x = ((now - start) / (end - start)) * width;
      c.strokeStyle = palette.css(palette.skip, 0.9);
      c.lineWidth = 1.5;
      c.beginPath();
      c.moveTo(x, 0);
      c.lineTo(x, height);
      c.stroke();
      c.fillStyle = palette.css(palette.skip);
      c.font = '600 9px system-ui, sans-serif';
      c.fillText('now', x + 15, height - 24);
    }
  }

  function drawTarget(c, target, width, height) {
    const y = altitude => height - clamp(altitude / 90, 0, 1) * (height - 16);
    for (const w of target.windows) {
      c.fillStyle = palette.css(palette.accent, 0.08);
      c.fillRect(xFor(w.start), 0, Math.max(1, xFor(w.end) - xFor(w.start)), height);
    }
    if (target.bestWindow) {
      const x0 = xFor(target.bestWindow.start);
      const w = Math.max(1, xFor(target.bestWindow.end) - x0);
      c.fillStyle = palette.css(palette.accent, 0.16);
      c.fillRect(x0, 0, w, height);
      c.strokeStyle = palette.css(palette.accent, 0.5);
      c.lineWidth = 1;
      c.strokeRect(x0 + 0.5, 0.5, w - 1, height - 1);
    }
    c.strokeStyle = 'rgba(255,255,255,0.08)';
    for (const altitude of [30, 60]) {
      c.beginPath();
      c.moveTo(0, y(altitude));
      c.lineTo(width, y(altitude));
      c.stroke();
    }
    const trace = target.altitudeTrace ?? [];
    if (trace.length > 1) {
      const stepX = width / (trace.length - 1);
      c.beginPath();
      trace.forEach((a, i) => (i ? c.lineTo(i * stepX, y(a)) : c.moveTo(0, y(a))));
      c.strokeStyle = palette.css(palette.accent);
      c.lineWidth = 2.5;
      c.lineJoin = 'round';
      c.stroke();
    }
    if (target.bestTime) {
      const x = xFor(target.bestTime);
      if (x >= 0 && x <= width) {
        c.strokeStyle = palette.css(palette.accent);
        c.lineWidth = 1.5;
        c.beginPath();
        c.moveTo(x, 0);
        c.lineTo(x, height);
        c.stroke();
        c.fillStyle = 'white';
        c.font = '600 10px ui-rounded, system-ui, sans-serif';
        c.textAlign = x > width - 120 ? 'right' : 'left';
        c.textBaseline = 'top';
        c.fillText(target.displayName, x > width - 120 ? x - 6 : x + 6, 6);
        c.textAlign = 'center';
        c.textBaseline = 'middle';
      }
    }
  }

  // Path.smoothLine: Catmull–Rom through the points, as Béziers.
  function smoothLine(points) {
    const path = new Path2D();
    path.moveTo(...points[0]);
    for (let i = 0; i < points.length - 1; i++) {
      const p0 = points[Math.max(0, i - 1)];
      const [p1, p2] = [points[i], points[i + 1]];
      const p3 = points[Math.min(points.length - 1, i + 2)];
      path.bezierCurveTo(
        p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6,
        p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6,
        p2[0], p2[1]);
    }
    return path;
  }

  function track(event) {
    const box = canvas.getBoundingClientRect();
    pointerX = clamp(event.clientX - box.left, 0, width);
  }

  /** The selected target's altitude at a sample, read off its trace. */
  function targetAltitude(index) {
    const trace = selected?.altitudeTrace;
    if (!trace?.length) return null;
    return trace[Math.round((index / Math.max(1, night.samples.length - 1)) * (trace.length - 1))];
  }
</script>

<div class="timeline" role="img" aria-label="The night from sunset to sunrise: darkness, cloud, Moon and the selected target" style:height="{height}px" bind:clientWidth={width}
     onpointermove={track} onpointerdown={track} onpointerleave={() => (pointerX = null)}
     onpointercancel={() => (pointerX = null)}>
  <canvas bind:this={canvas} style:width="{width}px" style:height="{height}px"></canvas>
  {#if hovered}
    {@const s = hovered.sample}
    {@const altitude = targetAltitude(hovered.index)}
    <div class="cursor" style:left="{pointerX}px"></div>
    <div class="readout" style:left="{clamp(pointerX - 70, 0, Math.max(0, width - 170))}px">
      <strong>{time(s.date, timeZone)}</strong>
      {#if s.hasWeather && s.cloudCover != null}<div>{Math.round(s.cloudCover)}% cloud · {temperature(s.temperature, imperial)}</div>{/if}
      <div>darkness {Math.round(s.darkness * 100)}%</div>
      {#if s.moonAltitude > 0}<div>Moon {degrees(s.moonAltitude)} up</div>{/if}
      {#if selected && altitude != null}
        <div class="accent">{selected.displayName} {altitude > 0 ? `${degrees(altitude)} up` : 'below the horizon'}</div>
      {/if}
    </div>
  {/if}
</div>

<style>
  .timeline {
    position: relative; border-radius: 8px; overflow: hidden;
    border: 1px solid var(--panel-border); touch-action: pan-y; user-select: none;
  }
  canvas { display: block; }
  .cursor { position: absolute; top: 0; bottom: 0; width: 1px; background: rgba(255,255,255,0.5); pointer-events: none; }
  .readout {
    position: absolute; top: 8px; width: 170px; padding: 8px; border-radius: 6px;
    background: rgba(0,0,0,0.72); color: white; font-size: 12px; line-height: 1.4; pointer-events: none;
  }
  .readout strong { font-size: 14px; font-variant-numeric: tabular-nums; }
  .accent { color: var(--accent); }
</style>
