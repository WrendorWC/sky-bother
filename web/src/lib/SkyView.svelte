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
  import ScoreBadge from './ScoreBadge.svelte';

  let { night, timeZone, targetID = null, rig = null, preferences = {} } = $props();

  // The view options above the Mac's dome: representative clouds, and the
  // camera's roll for the frame drawn round the selected target.
  let showsClouds = $state(preferences.showsClouds ?? true);
  let roll = $state(0);
  const fov = $derived(sky.fieldOfView(rig));
  // Highlights placed on the last draw, for tapping.
  let placedHighlights = [];

  const start = $derived(Date.parse(night.chartWindow.start));
  const end = $derived(Date.parse(night.chartWindow.end));

  let track = $state(null);
  let error = $state('');
  // The moment shown. Like the Mac's Sky View: astronomical dusk, where the
  // part of the night worth looking at starts (sunset if there's none).
  let at = $state(0);
  let playing = $state(false);
  let followingNow = $state(false);
  let selectedID = $state(null);
  // SkyView.PlaybackMode: follow the plan's blocks as time moves, or stay
  // on the selected target.
  let mode = $state('follow');

  // The Mac's 0.7 s fade (SkyView.startFade): a newly selected target's path,
  // brackets and name fade in while the last one fades out. Instant with
  // Reduce Motion on.
  const fadeDuration = 700;
  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
  let shownID = null;        // what the dome last finished showing
  let fadingOutID = null;
  let fadeStart = 0;
  let fadeFrame = 0;

  let size = $state(0);
  let domeCanvas;
  let overlay;
  let dome = null;

  $effect(() => {
    const key = night.planKey;
    track = null;
    error = '';
    skyTrack({ planKey: key }).then(t => (track = t), e => (error = e.message));
    const dusk = night.astronomicalDusk ? Date.parse(night.astronomicalDusk) : null;
    at = dusk && dusk > start && dusk < end ? dusk : start;
    followingNow = false;
    playing = false;
    // (A local, not `selectedID`: reading that here would rerun all this,
    // back to dusk, every time the plan moves the selection on.)
    // Nothing selected unless a target was selected on the night before
    // opening; following the plan, a target appears only while its block runs.
    const first = targetID ?? null;
    selectedID = first;
    fadingOutID = null;
    shownID = first;
    // A target selected before opening stays selected, and playback stays on
    // it; with nothing selected, the plan is followed from dusk.
    mode = first ? 'stay' : 'follow';
  });

  // SkyView.syncSelectionToPlayback, stricter: blocks never overlap, so at
  // most one holds `at`, and only its target is selected. Before the first
  // block, between blocks and after the last, nothing is (nothing is being
  // shot). It follows the slider as well as playback.
  const blocksInOrder = $derived([...night.plan].sort((a, b) => Date.parse(a.window.start) - Date.parse(b.window.start)));
  $effect(() => {
    if (mode !== 'follow' || !blocksInOrder.length) return;
    const running = blocksInOrder.find(b => at >= Date.parse(b.window.start) && at < Date.parse(b.window.end));
    const next = running ? running.targetID : null;
    if (next !== selectedID) selectedID = next;
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

  // Selection changed: start a fade, redrawing every frame until it's done.
  $effect(() => {
    const next = selectedID;
    if (next === shownID) return;
    fadingOutID = reduceMotion ? null : shownID;
    shownID = next;
    if (reduceMotion) return;
    fadeStart = performance.now();
    cancelAnimationFrame(fadeFrame);
    const step = () => {
      draw();
      if (performance.now() - fadeStart < fadeDuration) fadeFrame = requestAnimationFrame(step);
      else fadingOutID = null;
    };
    fadeFrame = requestAnimationFrame(step);
  });

  // Redraw whenever anything shown changes.
  $effect(() => {
    at; selectedID; scene; showsClouds; roll; playing;
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

    placedHighlights = playing ? [] : placeHighlights(c, g);

    const progress = reduceMotion ? 1 : Math.min(1, (performance.now() - fadeStart) / fadeDuration);
    const outgoing = fadingOutID && progress < 1 && fadingOutID !== selectedID
      ? night.targets.find(t => t.id === fadingOutID) : null;
    if (outgoing) {
      c.globalAlpha = 1 - progress;
      drawTarget(c, g, outgoing);
    }
    if (selected) {
      c.globalAlpha = progress;
      drawTarget(c, g, selected);
    }
    c.globalAlpha = 1;
    c.restore();
    // Outside the clip, so a label near the rim isn't cut off.
    drawHighlights(c, placedHighlights);

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

  // AppState.domeHighlights / SkyView.placedHighlights: the plan's targets,
  // then showpieces, above the visible horizon, skipping any whose brackets
  // and label would overlap one already placed; at most 14. Hidden while the
  // night plays, when the plan's own targets are the story.
  function placeHighlights(c, g) {
    const lat = track.latitude, lon = track.longitude;
    const ids = [...new Set([...blocksInOrder.map(b => b.targetID), ...track.highlights])];
    const byID = new Map(night.targets.map(t => [t.id, t]));
    c.font = '600 11px system-ui, sans-serif';
    const size = 22;
    const claimed = [];
    if (selected) {
      const h = sky.horizontal(selected.rightAscension, selected.declination, d, lat, lon);
      const p = screen(g, h);
      const w = Math.max(size * 1.6, c.measureText(selected.displayName).width + 16);
      claimed.push({ x: p.x - w / 2, y: p.y - size, w, h: size * 2 + 22 });
    }
    const placed = [];
    for (const id of ids) {
      if (id === selectedID) continue;
      const target = byID.get(id);
      if (!target) continue;
      const h = sky.horizontal(target.rightAscension, target.declination, d, lat, lon);
      if (h.altitude <= Math.max(3, sky.blockedAltitude(track.horizon, h.azimuth))) continue;
      const p = screen(g, h);
      const w = Math.max(size, c.measureText(target.displayName).width + 10);
      const box = { x: p.x - w / 2 - 4, y: p.y - size / 2 - 3, w: w + 8, h: size + 3 + 18 + 6 };
      if (claimed.some(r => r.x < box.x + box.w && box.x < r.x + r.w && r.y < box.y + box.h && box.y < r.y + r.h)) continue;
      claimed.push(box);
      placed.push({ target, x: p.x, y: p.y });
      if (placed.length >= 14) break;
    }
    return placed;
  }

  function drawHighlights(c, placed) {
    const half = 11, arm = 5;
    c.lineCap = 'round';
    for (const { target, x, y } of placed) {
      const path = new Path2D();
      for (const [dx, dy] of [[-1, -1], [1, -1], [1, 1], [-1, 1]]) {
        const cx = x + half * dx, cy = y + half * dy;
        path.moveTo(cx - arm * dx, cy);
        path.lineTo(cx, cy);
        path.lineTo(cx, cy - arm * dy);
      }
      c.strokeStyle = palette.css(palette.accent);
      c.lineWidth = 2;
      c.stroke(path);
      c.font = '600 11px system-ui, sans-serif';
      c.textAlign = 'center';
      c.textBaseline = 'middle';
      const w = c.measureText(target.displayName).width;
      // Kept inside the canvas: on a phone the dome reaches its edges.
      const lx = Math.min(Math.max(x, w / 2 + 6), size - w / 2 - 6);
      c.fillStyle = 'rgba(0,0,0,0.55)';
      c.fillRect(lx - w / 2 - 5, y + half + 3, w + 10, 16);
      c.fillStyle = 'white';
      c.fillText(target.displayName, lx, y + half + 11);
    }
  }

  // Tap a marked target to select it (and stay on it).
  let downAt = null;
  function pointerDown(event) {
    downAt = { x: event.clientX, y: event.clientY };
  }
  function pointerUp(event) {
    if (!downAt || Math.hypot(event.clientX - downAt.x, event.clientY - downAt.y) > 8) return;
    const box = overlay.getBoundingClientRect();
    const x = event.clientX - box.left, y = event.clientY - box.top;
    let best = null, bestDistance = 26;
    for (const h of placedHighlights) {
      const distance = Math.hypot(h.x - x, h.y + 6 - y);
      if (distance < bestDistance) { best = h; bestDistance = distance; }
    }
    if (best) {
      playing = false;
      selectedID = best.target.id;
      mode = 'stay';
    }
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

    // Your camera's frame, to scale (SkyView.drawActiveTarget); not within
    // 2° of the zenith, where a flat dome can't show which way it faces.
    let extent = 0;
    if (fov && now.altitude <= 88) {
      const outline = sky.footprint(now.altitude, now.azimuth, fov.width, fov.height, roll,
        rig.mountType === 'equatorial' ? lat : null);
      if (outline.every(p => p.altitude > 0)) {
        const points = outline.map(p => screen(g, p));
        const frame = new Path2D();
        points.forEach((p, i) => (i ? frame.lineTo(p.x, p.y) : frame.moveTo(p.x, p.y)));
        frame.closePath();
        c.fillStyle = palette.verdictColor('Excellent', 0.3);
        c.fill(frame);
        c.strokeStyle = 'rgba(0,0,0,0.6)'; c.lineWidth = 3.5; c.stroke(frame);
        c.strokeStyle = palette.verdictColor('Excellent'); c.lineWidth = 1.5; c.stroke(frame);
        extent = Math.max(...points.map(p => Math.max(Math.abs(p.x - m.x), Math.abs(p.y - m.y))));
      }
    }
    const half = Math.max(extent + 10, 18), arm = half * 0.5;
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
    const y = m.y + half + 14;
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
    if (block) {
      at = (Date.parse(block.window.start) + Date.parse(block.window.end)) / 2;
      mode = 'follow';
    }
  }

  // The side panel's readings.
  const compass = azimuth => ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', 'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'][Math.round(((azimuth % 360) + 360) % 360 / 22.5) % 16];
  const targetNow = $derived.by(() => {
    if (!track || !selected) return null;
    const here = sky.horizontal(selected.rightAscension, selected.declination, d, track.latitude, track.longitude);
    const soon = sky.horizontal(selected.rightAscension, selected.declination, d + 5 / 1440, track.latitude, track.longitude);
    return { ...here, rising: soon.altitude > here.altitude, blocked: sky.blockedAltitude(track.horizon, here.azimuth) };
  });
  // The Mac's "Shootable now, until …" / "Not shootable now — why" line,
  // from the target's usable windows and the reason it's out of one.
  const shootable = $derived.by(() => {
    if (!selected || !targetNow) return {};
    const windows = selected.windows.map(w => ({ start: Date.parse(w.start), end: Date.parse(w.end) }));
    const now = windows.find(w => at >= w.start && at < w.end);
    if (now) return { now };
    const next = windows.find(w => w.start > at) ?? null;
    const minimum = preferences.minimumUsefulAltitude ?? 30;
    const darkSun = -(9 + 9 * (preferences.minimumDarkness ?? 0.5));
    let reason = '';
    if (targetNow.altitude <= 0) reason = 'below the horizon';
    else if (targetNow.altitude <= targetNow.blocked) reason = `behind your horizon to the ${compass(targetNow.azimuth)}`;
    else if (targetNow.altitude < minimum) reason = `below your ${minimum}° minimum altitude`;
    else if (scene && scene.sun.altitude > darkSun) reason = 'not dark enough yet';
    else reason = 'too cloudy';
    return { next, reason };
  });

  function jumpToBest() {
    const w = selected?.bestWindow;
    if (!w) return;
    playing = false;
    followingNow = false;
    mode = 'stay';
    at = (Date.parse(w.start) + Date.parse(w.end)) / 2;
  }

  // Now works whenever the sky track covers it (half a day either side of
  // the night), so by day it shows today's sky, like the Mac's Now.
  const trackEnd = $derived(track ? Date.parse(track.start) + (track.sun.length - 1) * track.stepMinutes * 60_000 : 0);
  const nowAvailable = $derived(track != null && Date.now() > Date.parse(track.start) && Date.now() < trackEnd);
  const outsideNight = $derived(at < start || at > end);
</script>

{#snippet controls()}
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
{/snippet}

{#snippet modes()}
<div class="modes" role="radiogroup" aria-label="As time moves">
  <button type="button" role="radio" aria-checked={mode === 'follow'} class:on={mode === 'follow'}
          onclick={() => (mode = 'follow')}>Follow planned targets</button>
  <button type="button" role="radio" aria-checked={mode === 'stay'} class:on={mode === 'stay'}
          onclick={() => (mode = 'stay')} disabled={!selectedID}>Stay on selected target</button>
</div>
{/snippet}

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
        <canvas class="overlay" bind:this={overlay} style:width="{size}px" style:height="{size}px"
                onpointerdown={pointerDown} onpointerup={pointerUp}></canvas>
        {#if !track && !error}<p class="loading muted">Loading the sky…</p>{/if}
      </div>

      <div class="phone-only">{@render controls()}</div>
      <input class="scrubber" class:outside={outsideNight} type="range" min="0" max="1000" step="1" aria-label="Time"
             value={Math.round(Math.min(1, Math.max(0, (at - start) / (end - start))) * 1000)} oninput={scrub} />
      {#if night.plan.length}
        <PlanStrip {night} selectedID={selectedID} onselect={jumpTo} />
        <div class="phone-only">{@render modes()}</div>
      {/if}
      <p class="credit">Star map: NASA/Goddard SVS, from Gaia DR2 (ESA/Gaia/DPAC), Hipparcos and Tycho-2</p>
    </div>

    <aside class="panel side">
      <!-- On a wide screen the time controls live here, leaving the dome
           the height of the window. -->
      <div class="wide-only">{@render controls()}</div>
      {#if night.plan.length}<div class="wide-only">{@render modes()}</div>{/if}
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

      {#if !selected && mode === 'follow' && blocksInOrder.length}
        {@const next = blocksInOrder.find(b => Date.parse(b.window.start) > at)}
        <p class="muted-strong">{next ? `Next: ${next.targetName} at ${time(next.window.start, timeZone)}` : 'The plan is done for the night.'}</p>
      {/if}
      {#if selected && targetNow}
        <div class="target-head">
          <h3 class="target-name">{selected.displayName}</h3>
          <ScoreBadge score={selected.score} size={40} />
        </div>
        {#if targetNow.altitude <= 0}
          <p class="warn">Below the horizon</p>
        {:else if targetNow.altitude <= targetNow.blocked}
          <p class="warn">{degrees(targetNow.altitude)} up but behind your horizon to the {compass(targetNow.azimuth)}</p>
        {:else}
          <p>{degrees(targetNow.altitude)} up in the {compass(targetNow.azimuth)}, {targetNow.rising ? 'rising' : 'setting'}</p>
        {/if}
        {#if shootable.now}
          <p class="good">✓ Shootable now, until {time(shootable.now.end, timeZone)}</p>
        {:else}
          <p class="warn">Not shootable now{shootable.reason ? ` — ${shootable.reason}` : ''}</p>
          <p class="muted-strong">{shootable.next ? `Usable from ${time(shootable.next.start, timeZone)} to ${time(shootable.next.end, timeZone)}` : 'No usable time left this night.'}</p>
        {/if}
        {#if selected.bestWindow}
          <button type="button" class="link" onclick={jumpToBest}>Jump to its best window</button>
        {/if}
        {@const planned = night.plan.filter(b => b.targetID === selected.id)}
        {#if planned.length}
          <p class="planned">✓ Planned · {planned.map(b => `${time(b.window.start, timeZone)}–${time(b.window.end, timeZone)}`).join(', ')}</p>
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

      <h3>View</h3>
      <label class="check"><input type="checkbox" bind:checked={showsClouds} /> Show clouds</label>
      <p class="muted">Representative: the forecast's amount, not where the clouds really are.</p>
      {#if fov}
        <label class="roll">
          <span>Camera roll <strong>{roll}°</strong></span>
          <input type="range" min="0" max="359" step="1" bind:value={roll} />
        </label>
        <p class="muted">{rig.name} · {fov.width.toFixed(2)}° × {fov.height.toFixed(2)}°</p>
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
  .dome-area { display: grid; gap: 10px; min-width: 0; max-width: 900px; }
  /* As wide as there's room for, but never taller than the window less the
     header and the controls below it, so the whole dome and its controls
     are on screen together. */
  .dome {
    position: relative; touch-action: none; justify-self: center;
    width: min(100%, max(280px, calc(100dvh - 250px)));
  }
  .phone-only { display: none; }
  .dome canvas { position: absolute; inset: 0; display: block; }
  .loading { position: absolute; inset: 0; display: grid; place-items: center; }
  .controls { display: flex; gap: 10px; align-items: center; }
  .play { width: 52px; height: 52px; padding: 0; display: grid; place-items: center; border-radius: 50%; }
  .play svg { width: 24px; height: 24px; fill: currentColor; }
  .controls > button:not(.play) { min-height: 44px; }
  .controls .on { background: rgba(158, 133, 250, 0.25); border-color: var(--accent); }
  .clock { font-size: 22px; font-weight: 600; font-variant-numeric: tabular-nums; }
  .scrubber { width: 100%; accent-color: var(--accent); padding: 0; }
  /* Now, by day: the slider only spans the night. */
  .scrubber.outside { opacity: 0.4; }
  .credit { font-size: 11px; color: var(--tertiary); }
  .modes { display: flex; gap: 6px; flex-wrap: wrap; }
  .modes button { border-radius: 999px; padding: 4px 12px; font-size: 14px; }
  .modes button.on { background: rgba(158, 133, 250, 0.3); border-color: var(--accent); font-weight: 600; }
  .side { padding: 14px; display: grid; gap: 8px; }
  .target-name { margin-top: 8px; color: var(--text); text-transform: none; letter-spacing: 0; font-size: 17px; }
  .warn { color: var(--marginal); }
  .good { color: var(--excellent); }
  .planned { color: var(--accent); font-weight: 600; }
  .target-head { display: flex; justify-content: space-between; align-items: center; gap: 8px; margin-top: 8px; }
  .target-head .target-name { margin-top: 0; }
  .link { justify-self: start; background: none; border: none; padding: 0; color: var(--accent); font-weight: 600; text-align: left; }
  .check { display: flex; gap: 8px; align-items: center; }
  .check input, .roll input { accent-color: var(--accent); }
  .roll { display: grid; gap: 4px; }
  .roll span { display: flex; justify-content: space-between; }
  .picks { list-style: none; margin: 0; padding: 0; display: grid; gap: 4px; }
  .picks button { width: 100%; text-align: left; display: flex; justify-content: space-between; gap: 8px; }
  .picks button.on { border-color: var(--accent); background: rgba(158, 133, 250, 0.18); }
  @media (max-width: 860px) {
    .layout { grid-template-columns: minmax(0, 1fr); }
    .phone-only { display: block; }
    .wide-only { display: none; }
    .dome { width: min(100%, max(260px, calc(100dvh - 400px))); }
  }
  .side .controls { margin-bottom: 4px; }
  .side .modes { margin-bottom: 8px; }
</style>
