<script>
  // MoonCard: the Moon as it will look tonight, opened from the Moon on a
  // night's page. Drawn rather than photographed: NASA's lunar colour map
  // wrapped onto a sphere and lit from the Sun's real direction (the Mac's
  // MoonGlobe.metal, as WebGL), so the phase, which limb is lit and how the
  // Moon is turned all match the view from the site, at the moment it
  // stands highest during the night.
  import { moonCard } from '../engine/engine.js';
  import { time, degrees } from './format.js';

  let { night, timeZone, onclose } = $props();

  let card = $state(null);
  let error = $state('');
  $effect(() => {
    moonCard({ planKey: night.planKey }).then(c => (card = c), e => (error = e.message));
  });

  const rad = Math.PI / 180;
  const compass = azimuth => ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', 'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'][Math.round(((azimuth % 360) + 360) % 360 / 22.5) % 16];

  // MoonView: where the Sun is and which way is north, in the viewer's own
  // frame — x right, y up, z towards them.
  function view(c) {
    const vector = (alt, az) => [Math.cos(alt * rad) * Math.sin(az * rad), Math.cos(alt * rad) * Math.cos(az * rad), Math.sin(alt * rad)];
    const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
    const scale = (a, k) => a.map(x => x * k);
    const sub = (a, b) => a.map((x, i) => x - b[i]);
    const norm = a => { const l = Math.hypot(...a); return l > 1e-9 ? scale(a, 1 / l) : a; };
    const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
    const forward = vector(c.altitude, c.azimuth);
    const zenith = [0, 0, 1];
    let up = sub(zenith, scale(forward, dot(zenith, forward)));
    if (dot(up, up) < 1e-8) up = sub([0, 1, 0], scale(forward, forward[1]));
    up = norm(up);
    const right = norm(cross(forward, up));
    // From the Moon to the Sun, not just the Sun's direction.
    const toSun = norm(sub(scale(vector(c.sunAltitude, c.sunAzimuth), 149_597_870), scale(forward, c.distanceKilometers)));
    const light = norm([dot(toSun, right), dot(toSun, up), -dot(toSun, forward)]);
    // Lunar north stays within a few degrees of celestial north.
    const pole = [0, Math.cos(c.latitude * rad), Math.sin(c.latitude * rad)];
    const n = [dot(pole, right), dot(pole, up)];
    const l = Math.hypot(...n);
    return { light, north: l > 1e-9 ? [n[0] / l, n[1] / l] : [0, 1] };
  }

  const vertex = `attribute vec2 position; void main() { gl_Position = vec4(position, 0.0, 1.0); }`;
  const fragment = `
    precision highp float;
    uniform sampler2D surface;
    uniform vec2 size;
    uniform vec3 light;
    uniform vec2 north;
    const float PI = 3.14159265;
    void main() {
      vec2 p = (gl_FragCoord.xy - size * 0.5) / (min(size.x, size.y) * 0.5);
      float r2 = dot(p, p);
      if (r2 > 1.0) { gl_FragColor = vec4(0.0); return; }
      vec3 n = vec3(p, sqrt(1.0 - r2));
      vec2 east = vec2(north.y, -north.x);
      float latitude = asin(clamp(dot(n.xy, north), -1.0, 1.0));
      float longitude = atan(dot(n.xy, east), n.z);
      vec2 uv = vec2(fract(0.5 + longitude / (2.0 * PI)), clamp(0.5 - latitude / PI, 0.001, 0.999));
      vec3 albedo = texture2D(surface, uv).rgb;
      float mu0 = max(dot(n, light), 0.0);
      float mu = max(n.z, 0.0);
      float lommel = 2.0 * mu0 / (mu0 + mu + 1e-4);
      float lit = mix(mu0, lommel, 0.7);
      vec3 colour = albedo * (lit * 1.05 + 0.025);
      float edge = smoothstep(1.0, 0.985, sqrt(r2));
      gl_FragColor = vec4(colour * edge, edge);
    }`;

  let canvas;
  $effect(() => {
    if (!card || !canvas) return;
    const gl = canvas.getContext('webgl', { premultipliedAlpha: true, alpha: true });
    if (!gl) return;
    const dpr = Math.min(2, devicePixelRatio || 1);
    const css = canvas.clientWidth;
    canvas.width = canvas.height = Math.round(css * dpr);
    const compile = (type, source) => { const s = gl.createShader(type); gl.shaderSource(s, source); gl.compileShader(s); return s; };
    const program = gl.createProgram();
    gl.attachShader(program, compile(gl.VERTEX_SHADER, vertex));
    gl.attachShader(program, compile(gl.FRAGMENT_SHADER, fragment));
    gl.linkProgram(program);
    gl.useProgram(program);
    const buffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
    const position = gl.getAttribLocation(program, 'position');
    gl.enableVertexAttribArray(position);
    gl.vertexAttribPointer(position, 2, gl.FLOAT, false, 0, 0);
    const { light, north } = view(card);
    let cancelled = false;
    const image = new Image();
    image.onload = () => {
      if (cancelled) return;
      const texture = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, texture);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGB, gl.RGB, gl.UNSIGNED_BYTE, image);
      // Not a power of two everywhere WebGL 1 cares about: clamp, no mipmaps.
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      gl.viewport(0, 0, canvas.width, canvas.height);
      gl.uniform2f(gl.getUniformLocation(program, 'size'), canvas.width, canvas.height);
      gl.uniform3f(gl.getUniformLocation(program, 'light'), ...light);
      gl.uniform2f(gl.getUniformLocation(program, 'north'), ...north);
      gl.clearColor(0, 0, 0, 0);
      gl.clear(gl.COLOR_BUFFER_BIT);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
      drawn = true;
    };
    image.src = '/moon-map.jpg';
    return () => { cancelled = true; };
  });
  let drawn = $state(false);

  function keydown(event) {
    if (event.key === 'Escape') onclose();
  }
</script>

<svelte:window onkeydown={keydown} />

<div class="backdrop" onclick={onclose} aria-hidden="true"></div>
<div class="card panel" role="dialog" aria-label="The Moon">
  <header>
    <div>
      <h2>The Moon</h2>
      {#if card}<p class="muted-strong">{card.phaseName} · as seen from {card.siteName}</p>{/if}
    </div>
    <button type="button" onclick={onclose}>Done</button>
  </header>
  {#if error}
    <p class="error">{error}</p>
  {:else}
    <div class="globe">
      <canvas bind:this={canvas}></canvas>
      {#if !drawn}<p class="muted loading">Drawing the Moon…</p>{/if}
    </div>
    {#if card}
      <dl>
        <div><dt>Lit</dt><dd>{Math.round(card.illuminatedFraction * 100)}%</dd></div>
        <div><dt>Shown at</dt><dd>{time(card.at, timeZone)} · {card.altitude > 0 ? `${degrees(card.altitude)} up in the ${compass(card.azimuth)}` : 'below the horizon all night'}</dd></div>
        <div><dt>Distance</dt><dd>{Math.round(card.distanceKilometers).toLocaleString()} km</dd></div>
        <div><dt>Apparent size</dt><dd>{(3474.8 / card.distanceKilometers * 180 / Math.PI * 60).toFixed(1)}′</dd></div>
      </dl>
    {/if}
    <p class="credit">Lunar surface: NASA’s Scientific Visualization Studio, from Lunar Reconnaissance Orbiter Camera data</p>
  {/if}
</div>

<style>
  .backdrop { position: fixed; inset: 0; background: rgba(0, 0, 0, 0.55); z-index: 40; }
  .card {
    position: fixed; z-index: 41; top: 50%; left: 50%; transform: translate(-50%, -50%);
    width: min(460px, calc(100vw - 24px)); max-height: calc(100vh - 24px); overflow-y: auto;
    padding: 20px; display: grid; gap: 14px; border-radius: 16px; background: var(--space-bottom);
  }
  header { display: flex; justify-content: space-between; align-items: flex-start; gap: 12px; }
  h2 { margin: 0; font-size: 22px; }
  header p { margin: 3px 0 0; }
  .globe { position: relative; display: grid; place-items: center; padding: 12px; border-radius: 12px; background: var(--space-top); border: 1px solid var(--panel-border); }
  canvas { width: min(360px, 100%); aspect-ratio: 1; }
  .loading { position: absolute; margin: 0; }
  dl { margin: 0; display: grid; gap: 8px; }
  dl div { display: flex; justify-content: space-between; gap: 12px; }
  dt { color: var(--muted); }
  dd { margin: 0; font-variant-numeric: tabular-nums; text-align: right; }
  .credit { margin: 0; font-size: 11px; color: var(--tertiary); }
</style>
