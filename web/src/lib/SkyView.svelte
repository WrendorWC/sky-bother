<script>
  // Sky View (UI/SkyView.swift, SkyViewScreen.swift): the sky as a dome,
  // zenith in the centre, horizon at the rim, north up and east right, at any
  // moment of the night. The real sky (domeShader.js), with the Sun, Moon,
  // signpost stars and the selected target's path and position drawn over it.
  import { skyTrack } from '../engine/engine.js';
  import { domeRenderer } from './domeShader.js';
  import * as sky from './sky.js';
  import * as palette from './palette.js';
  import { time, degrees, longDate } from './format.js';
  import PlanStrip from './PlanStrip.svelte';

  let { night, timeZone, targetID = null, showsClouds = true } = $props();

  const start = $derived(Date.parse(night.chartWindow.start));
  const end = $derived(Date.parse(night.chartWindow.end));

  let track = $state(null);
  let error = $state('');
  // The moment shown. Like the Mac: the middle of the best imaging window,
  // or of the night; Now when tonight is under way.
  let at = $state(0);
  let playing = $state(false);
  let followingNow = $state(false);
  let selectedID = $state(null);

  let size = $state(0);
  let domeCanvas;
  let overlay;
  let dome = null;

  $effect(() => {
    const key = night.planKey;
    track = null;
    error = '';
    skyTrack({ planKey: key }).then(t => (track = t), e => (error = e.message));
    const best = night.bestImagingWindow;
    const now = Date.now();
    at = now > start && now < end ? now
      : best ? (Date.parse(best.start) + Date.parse(best.end)) / 2 : (start + end) / 2;
    followingNow = now > start && now < end;
    selectedID = targetID ?? night.plan[0]?.targetID ?? night.targets.find(t => t.usableMinutes > 0 && !t.isStar)?.id ?? null;
  });

  const selected = $derived(night.targets.find(t => t.id === selectedID) ?? null);
  const d = $derived(sky.daysSinceJ2000(at));

  // Where everything is at `at`.
  const scene = $derived.by(() => {
    if (!track) return null;
    const lat = track.latitude, lon = track.longitude;
    const bodies = sky.trackAt(track, at);
    const sun = sky.horizontal(bodies.sun.rightAscension, bodies.sun.declination, d, lat, lon);
    const moon = { ...sky.horizontal(bodies.moon.rightAscension, bodies.moon.declination, d, lat, lon), ...bodies.moon };
    return { sun, moon };
  });

  // Dome: sized to the space it's given, square.
  $effect(() => {
    if (!domeCanvas || !track || size === 0) return;
    if (!dome) {
      try {
        dome = domeRenderer(domeCanvas, '/catalog/starmap.jpg');
        dome?.ready.then(() => draw());
      } catch (e) {
        error = `The sky dome needs WebGL: ${e.message}`;
      }
    }
    draw();
  });

  // Redraw whenever anything shown changes.
  $effect(() => {
    at; selectedID; scene; showsClouds;
    draw();
  });

  // The dome's radius is the horizon's (altitude 0); a raised horizon trims
  // the rim, so it's scaled up until the visible sky fills the space.
  function geometry() {
    const margin = 22;
    const widest = Math.max(...track.horizon.map(h => Math.min(1, Math.max(0.05, (90 - h) / 90))));
    return { width: size, height: size, centreX: size / 2, centreY: size / 2, radius: (size / 2 - margin) / widest };
  }

  const rimRadius = (g, azimuth) => g.radius * Math.min(1, Math.max(0, (90 - sky.blockedAltitude(track.horizon, azimuth)) / 90));

  function draw() {
    if (!track || !scene || size === 0) return;
    const g = geometry();
    dome?.render({
      ...g,
      horizon: track.horizon,
      latitude: track.latitude,
      siderealTime: sky.localSiderealTime(d, track.longitude),
      sun: scene.sun,
      moon: scene.moon,
      skyColour: palette.sky(scene.sun.altitude),
      nightColour: palette.sky(-90),
      clouds: showsClouds ? sky.cloudAt(night, at, track) : null,
      drift: sky.cloudDrift(track, start, at),
    });
    drawOverlay(g);
  }

  const screen = (g, horizontal) => {
    const p = sky.project(horizontal);
    return { x: g.centreX + p.x * g.radius, y: g.centreY + p.y * g.radius };
  };

  function rimPath(g) {
    const path = new Path2D();
    for (let sector = 0; sector < 8; sector++) {
      const r = g.radius * Math.min(1, Math.max(0, (90 - track.horizon[sector]) / 90));
      for (let step = 0; step <= 9; step++) {
        const azimuth = sector * 45 - 22.5 + step * 5;
        const p = sky.project({ altitude: 0, azimuth });
        const x = g.centreX + p.x * r, y = g.centreY + p.y * r;
        sector === 0 && step === 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
    }
    path.closePath();
    return path;
  }

  function drawOverlay(g) {
    if (!overlay) return;
    const ratio = window.devicePixelRatio || 1;
    overlay.width = Math.round(g.width * ratio);
    overlay.height = Math.round(g.height * ratio);
    const c = overlay.getContext('2d');
    c.setTransform(ratio, 0, 0, ratio, 0, 0);
    c.clearRect(0, 0, g.width, g.height);
    if (!dome) {
      c.fillStyle = palette.css(palette.sky(scene.sun.altitude));
      c.fill(rimPath(g));
    }
    const rim = rimPath(g);
    c.strokeStyle = 'rgba(158, 133, 250, 0.35)';
    c.lineWidth = 1;
    c.stroke(rim);

    // Compass points just outside the rim.
    c.font = '600 12px system-ui, sans-serif';
    c.textAlign = 'center';
    c.textBaseline = 'middle';
    c.fillStyle = 'rgba(255,255,255,0.7)';
    for (const [label, azimuth] of [['N', 0], ['E', 90], ['S', 180], ['W', 270]]) {
      const r = rimRadius(g, azimuth) + 11, a = azimuth * Math.PI / 180;
      c.fillText(label, g.centreX + Math.sin(a) * r, g.centreY - Math.cos(a) * r);
    }

    c.save();
    c.clip(rim);
    const lat = track.latitude, lon = track.longitude;

    // The Sun, below the horizon only as twilight.
    if (scene.sun.altitude > -0.8) {
      const s = screen(g, scene.sun);
      const disc = moonDiameter(g);
      const glow = c.createRadialGradient(s.x, s.y, disc / 2, s.x, s.y, disc * 2.2);
      glow.addColorStop(0, 'rgba(255, 219, 115, 0.55)');
      glow.addColorStop(1, 'rgba(255, 219, 115, 0)');
      c.fillStyle = glow;
      c.beginPath(); c.arc(s.x, s.y, disc * 2.2, 0, Math.PI * 2); c.fill();
      c.fillStyle = 'rgb(255, 219, 115)';
      c.beginPath(); c.arc(s.x, s.y, disc / 2, 0, Math.PI * 2); c.fill();
    }

    // 30° and 60° rings.
    c.strokeStyle = 'rgba(255,255,255,0.08)';
    for (const altitude of [30, 60]) {
      c.beginPath();
      c.arc(g.centreX, g.centreY, g.radius * (90 - altitude) / 90, 0, Math.PI * 2);
      c.stroke();
    }

    // The celestial pole.
    const pole = screen(g, { altitude: Math.abs(lat), azimuth: lat >= 0 ? 0 : 180 });
    c.strokeStyle = 'rgba(255,255,255,0.35)';
    c.beginPath(); c.moveTo(pole.x - 5, pole.y); c.lineTo(pole.x + 5, pole.y); c.moveTo(pole.x, pole.y - 5); c.lineTo(pole.x, pole.y + 5); c.stroke();


    // The Moon, at its real size (within reason).
    if (scene.moon.altitude > 0) {
      const p = screen(g, scene.moon);
      c.fillStyle = palette.css(palette.moonlight);
      c.beginPath(); c.arc(p.x, p.y, moonDiameter(g) / 2, 0, Math.PI * 2); c.fill();
    }

    if (selected) drawTarget(c, g, selected);
    c.restore();

    // Signpost stars, named faintly; outside the clip so a name near the rim
    // isn't cut off, and to the left of a star near the right-hand edge.
    c.font = '11px system-ui, sans-serif';
    c.textBaseline = 'middle';
    c.fillStyle = 'rgba(255,255,255,0.6)';
    for (const star of track.stars) {
      const h = sky.horizontal(star.rightAscension, star.declination, d, lat, lon);
      if (h.altitude <= sky.blockedAltitude(track.horizon, h.azimuth)) continue;
      const p = screen(g, h);
      const width = c.measureText(star.name).width;
      const right = p.x + 6 + width < g.width - 4;
      c.textAlign = right ? 'left' : 'right';
      c.fillText(star.name, right ? p.x + 6 : p.x - 6, p.y);
    }
  }

  function moonDiameter(g) {
    const real = (scene.moon.diameter ?? 0.52) * g.radius / 90;
    return Math.min(Math.max(real, 10), 26);
  }

  // The target's whole daily loop (a day centred on the night, every 6
  // minutes), bold above the horizon and faint below, then brackets and its
  // name where it is now.
  function drawTarget(c, g, target) {
    const lat = track.latitude, lon = track.longitude;
    const middle = (start + end) / 2;
    let run = [], runVisible = null;
    const flush = () => {
      if (run.length > 1) {
        c.strokeStyle = palette.css(palette.accent, runVisible ? 0.55 : 0.16);
        c.lineWidth = runVisible ? 2 : 1.25;
        c.beginPath();
        run.forEach((p, i) => (i ? c.lineTo(p.x, p.y) : c.moveTo(p.x, p.y)));
        c.stroke();
      }
      run = run.slice(-1);
    };
    for (let t = middle - 12 * 3_600_000; t <= middle + 12 * 3_600_000; t += 360_000) {
      const h = sky.horizontal(target.rightAscension, target.declination, sky.daysSinceJ2000(t), lat, lon);
      const visible = h.altitude > sky.blockedAltitude(track.horizon, h.azimuth);
      if (runVisible !== null && visible !== runVisible) { run.push(screen(g, h)); flush(); }
      runVisible = visible;
      run.push(screen(g, h));
    }
    flush();

    const now = sky.horizontal(target.rightAscension, target.declination, d, lat, lon);
    if (now.altitude <= sky.blockedAltitude(track.horizon, now.azimuth)) return;
    const m = screen(g, now);
    const half = 18, arm = half * 0.5;
    const brackets = new Path2D();
    for (const [dx, dy] of [[-1, -1], [1, -1], [1, 1], [-1, 1]]) {
      const x = m.x + half * dx, y = m.y + half * dy;
      brackets.moveTo(x - arm * dx, y);
      brackets.lineTo(x, y);
      brackets.lineTo(x, y - arm * dy);
    }
    c.lineCap = 'round'; c.lineJoin = 'round';
    c.strokeStyle = 'rgba(0,0,0,0.6)'; c.lineWidth = 5.5; c.stroke(brackets);
    c.strokeStyle = palette.verdictColor('Excellent'); c.lineWidth = 2.5; c.stroke(brackets);
    c.font = '600 12px system-ui, sans-serif';
    c.textAlign = 'center';
    const w = c.measureText(target.displayName).width;
    const y = m.y + half + 16;
    c.fillStyle = 'rgba(0,0,0,0.7)';
    c.beginPath(); c.roundRect ? c.roundRect(m.x - w / 2 - 6, y - 9, w + 12, 18, 4) : c.rect(m.x - w / 2 - 6, y - 9, w + 12, 18); c.fill();
    c.fillStyle = 'white';
    c.fillText(target.displayName, m.x, y);
  }

  // Playback: the night in about 25 seconds.
  $effect(() => {
    if (!playing) return;
    let last = performance.now(), frame;
    const tick = now => {
      const next = at + ((now - last) / 25_000) * (end - start);
      last = now;
      if (next >= end) { at = end; playing = false; return; }
      at = Math.max(start, next);
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  });

  // Now: keep up with the clock.
  $effect(() => {
    if (!followingNow) return;
    at = Date.now();
    const timer = setInterval(() => (at = Date.now()), 30_000);
    return () => clearInterval(timer);
  });

  function togglePlay() {
    followingNow = false;
    if (!playing && at >= end - 60_000) at = start;
    playing = !playing;
  }

  function goNow() {
    playing = false;
    followingNow = true;
  }

  function scrub(event) {
    playing = false;
    followingNow = false;
    at = start + (Number(event.currentTarget.value) / 1000) * (end - start);
  }

  function jumpTo(id) {
    const block = night.plan.find(b => b.targetID === id);
    playing = false;
    followingNow = false;
    selectedID = id;
    if (block) at = (Date.parse(block.window.start) + Date.parse(block.window.end)) / 2;
  }

  // The side panel's readings.
  const compass = azimuth => ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', 'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'][Math.round(((azimuth % 360) + 360) % 360 / 22.5) % 16];
  const targetNow = $derived.by(() => {
    if (!track || !selected) return null;
    const here = sky.horizontal(selected.rightAscension, selected.declination, d, track.latitude, track.longitude);
    const soon = sky.horizontal(selected.rightAscension, selected.declination, d + 5 / 1440, track.latitude, track.longitude);
    return { ...here, rising: soon.altitude > here.altitude, blocked: sky.blockedAltitude(track.horizon, here.azimuth) };
  });
  // Now works whenever the sky track covers it (half a day either side of
  // the night), so by day it shows today's sky, like the Mac's Now.
  const trackEnd = $derived(track ? Date.parse(track.start) + (track.sun.length - 1) * track.stepMinutes * 60_000 : 0);
  const nowAvailable = $derived(track != null && Date.now() > Date.parse(track.start) && Date.now() < trackEnd);
  const outsideNight = $derived(at < start || at > end);
</script>

<section class="sky-view">
  <header>
    <a class="back" href="#/{night.planKey}">‹ {longDate(night.planKey)}</a>
    <h2>Sky View</h2>
  </header>

  {#if error}<p class="error">{error}</p>{/if}

  <div class="layout">
    <div class="dome-area">
      <div class="dome" bind:clientWidth={size} style:height="{size}px">
        <canvas bind:this={domeCanvas} style:width="{size}px" style:height="{size}px"></canvas>
        <canvas class="overlay" bind:this={overlay} style:width="{size}px" style:height="{size}px"></canvas>
        {#if !track && !error}<p class="loading muted">Loading the sky…</p>{/if}
      </div>

      <div class="controls">
        <button type="button" class="play" onclick={togglePlay} aria-label={playing ? 'Pause' : 'Play the night'}>
          {#if playing}
            <svg viewBox="0 0 24 24" aria-hidden="true"><rect x="6" y="5" width="4" height="14" rx="1" /><rect x="14" y="5" width="4" height="14" rx="1" /></svg>
          {:else}
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 5l12 7-12 7z" /></svg>
          {/if}
        </button>
        <button type="button" class:on={followingNow} onclick={goNow} disabled={!nowAvailable}
                title={nowAvailable ? 'Show the sky now' : 'Now is a different day from this night'}>Now</button>
        <span class="clock">{followingNow ? 'Now · ' : ''}{time(at, timeZone)}</span>
      </div>
      <input class="scrubber" class:outside={outsideNight} type="range" min="0" max="1000" step="1" aria-label="Time"
             value={Math.round(Math.min(1, Math.max(0, (at - start) / (end - start))) * 1000)} oninput={scrub} />
      {#if night.plan.length}
        <PlanStrip {night} selectedID={selectedID} onselect={jumpTo} />
      {/if}
      <p class="credit">Star map: NASA/Goddard SVS, from Gaia DR2 (ESA/Gaia/DPAC), Hipparcos and Tycho-2</p>
    </div>

    <aside class="panel side">
      <h3>{time(at, timeZone)}</h3>
      {#if scene}
        <p class="muted-strong">
          {#if scene.sun.altitude > 0}Sun up, {degrees(scene.sun.altitude)}
          {:else if scene.sun.altitude > -18}Twilight, Sun {degrees(-scene.sun.altitude)} below
          {:else}Fully dark{/if}
        </p>
        <p class="muted-strong">
          Moon {Math.round(scene.moon.illuminatedFraction * 100)}% lit,
          {scene.moon.altitude > 0 ? `${degrees(scene.moon.altitude)} up in the ${compass(scene.moon.azimuth)}` : 'below the horizon'}
        </p>
      {/if}

      {#if selected && targetNow}
        <h3 class="target-name">{selected.displayName}</h3>
        {#if targetNow.altitude <= 0}
          <p class="warn">Below the horizon</p>
        {:else if targetNow.altitude <= targetNow.blocked}
          <p class="warn">{degrees(targetNow.altitude)} up but behind your horizon to the {compass(targetNow.azimuth)}</p>
        {:else}
          <p>{degrees(targetNow.altitude)} up in the {compass(targetNow.azimuth)}, {targetNow.rising ? 'rising' : 'setting'}</p>
        {/if}
      {/if}

      {#if night.plan.length}
        <h3>Planned</h3>
        <ul class="picks">
          {#each night.plan as block (block.targetID + block.window.start)}
            <li><button type="button" class:on={block.targetID === selectedID} onclick={() => jumpTo(block.targetID)}>
              {block.targetName} <span class="muted">{time(block.window.start, timeZone)}–{time(block.window.end, timeZone)}</span>
            </button></li>
          {/each}
        </ul>
      {/if}
    </aside>
  </div>
</section>

<style>
  .sky-view { display: grid; gap: 12px; min-width: 0; }
  header { display: grid; gap: 4px; }
  .back { color: var(--accent); text-decoration: none; font-weight: 600; }
  h2 { margin: 0; font-size: 22px; }
  h3 { margin: 0; font-size: 13px; text-transform: uppercase; letter-spacing: 0.06em; color: var(--accent); }
  p { margin: 0; }
  .layout { display: grid; gap: 20px; grid-template-columns: minmax(0, 1fr) 280px; align-items: start; }
  .dome-area { display: grid; gap: 10px; min-width: 0; max-width: 760px; }
  .dome { position: relative; width: 100%; touch-action: none; }
  .dome canvas { position: absolute; inset: 0; display: block; }
  .loading { position: absolute; inset: 0; display: grid; place-items: center; }
  .controls { display: flex; gap: 10px; align-items: center; }
  .play { width: 44px; height: 44px; padding: 0; display: grid; place-items: center; border-radius: 50%; }
  .play svg { width: 20px; height: 20px; fill: currentColor; }
  .controls .on { background: rgba(158, 133, 250, 0.25); border-color: var(--accent); }
  .clock { font-size: 22px; font-weight: 600; font-variant-numeric: tabular-nums; }
  .scrubber { width: 100%; accent-color: var(--accent); padding: 0; }
  /* Now, by day: the slider only spans the night. */
  .scrubber.outside { opacity: 0.4; }
  .credit { font-size: 11px; color: var(--tertiary); }
  .side { padding: 14px; display: grid; gap: 8px; }
  .target-name { margin-top: 8px; color: var(--text); text-transform: none; letter-spacing: 0; font-size: 17px; }
  .warn { color: var(--marginal); }
  .picks { list-style: none; margin: 0; padding: 0; display: grid; gap: 4px; }
  .picks button { width: 100%; text-align: left; display: flex; justify-content: space-between; gap: 8px; }
  .picks button.on { border-color: var(--accent); background: rgba(158, 133, 250, 0.18); }
  @media (max-width: 860px) {
    .layout { grid-template-columns: minmax(0, 1fr); }
  }
</style>
