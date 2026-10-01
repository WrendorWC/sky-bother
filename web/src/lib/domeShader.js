// The real night sky on the dome, in WebGL: a port of `skyDome` in the Mac
// app's SkyDome.metal — keep the two in step. Each pixel is taken back through
// the dome's projection to an altitude and azimuth, then to right ascension
// and declination for this moment's sidereal time, and looked up in the
// whole-sky map; twilight and moonlight are added as glows that drown faint
// stars first; the forecast's cloud is representative noise thresholded to
// each layer's cover and drifted with the wind. The Mac clips the dome to the
// horizon with a path; here each pixel checks its compass sector instead.

const vertex = `
attribute vec2 corner;
void main() { gl_Position = vec4(corner, 0.0, 1.0); }
`;

const fragment = `
precision highp float;
uniform vec2 viewport;      // device pixels
uniform vec2 centre;        // device pixels, y down
uniform float radius;       // device pixels
uniform float horizon[8];   // blocked altitude by sector, N, NE … NW
uniform sampler2D starMap;
uniform float latitude;
uniform float siderealTime;
uniform vec4 sun;           // altitude, azimuth
uniform vec4 moon;          // altitude, azimuth, illuminated fraction
uniform vec3 skyColour;
uniform vec3 nightColour;
uniform float gain;
uniform vec4 clouds;        // low, mid, high cover 0-1, 1 to draw them
uniform vec2 drift;         // km east and north

const float kDeg = 3.14159265 / 180.0;

float separation(float alt1, float az1, float alt2, float az2) {
  float c = sin(alt1 * kDeg) * sin(alt2 * kDeg) + cos(alt1 * kDeg) * cos(alt2 * kDeg) * cos((az1 - az2) * kDeg);
  return acos(clamp(c, -1.0, 1.0)) / kDeg;
}

float luminance(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float valueNoise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
  float total = 0.0, amplitude = 0.5;
  for (int octave = 0; octave < 5; octave++) {
    total += amplitude * valueNoise(p);
    p = p * 2.03 + vec2(17.1, 9.2);
    amplitude *= 0.5;
  }
  return total;
}

// smoothstep with its edges either way round, as Metal's allows.
float ramp(float edge0, float edge1, float x) {
  float t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

float cloudLayer(vec3 direction, float height, float cover, vec2 shift, float featureKm, vec2 stretch, float seed) {
  if (cover < 0.01) return 0.0;
  float up = max(direction.z, 0.04);
  vec2 deck = direction.xy / up * height - shift;
  float n = fbm(deck / featureKm * stretch + seed);
  float threshold = mix(0.78, 0.22, cover);
  float density = ramp(threshold - 0.06, threshold + 0.10, n);
  density = max(density, ramp(0.9, 1.0, cover));
  return density * mix(1.0, 0.75, ramp(0.35, 0.05, up));
}

float horizonAt(float azimuth) {
  int sector = int(mod(floor(azimuth / 45.0 + 0.5), 8.0));
  for (int k = 0; k < 8; k++) if (k == sector) return horizon[k];
  return horizon[0];
}

void main() {
  vec2 position = vec2(gl_FragCoord.x, viewport.y - gl_FragCoord.y);
  vec2 unit = (position - centre) / radius;
  float rRaw = length(unit);
  float r = min(rRaw, 1.0);
  float altitude = 90.0 * (1.0 - r);
  float azimuth = atan(unit.x, -unit.y) / kDeg;
  if (azimuth < 0.0) azimuth += 360.0;

  // Outside the horizon (and the trees): nothing.
  float rim = (90.0 - horizonAt(azimuth)) / 90.0;
  float inside = 1.0 - ramp(rim - 1.0 / radius, rim + 0.5 / radius, rRaw);
  if (inside <= 0.0) { gl_FragColor = vec4(0.0); return; }

  float phi = latitude * kDeg, a = altitude * kDeg, A = azimuth * kDeg;
  float sinDec = sin(phi) * sin(a) + cos(phi) * cos(a) * cos(A);
  float declination = asin(clamp(sinDec, -1.0, 1.0)) / kDeg;
  float hourAngle = atan(-sin(A) * cos(a), sin(a) * cos(phi) - cos(a) * sin(phi) * cos(A)) / kDeg;
  float rightAscension = siderealTime - hourAngle;

  vec2 uv = vec2(fract(0.5 - rightAscension / 360.0), clamp(0.5 - declination / 180.0, 0.0005, 0.9995));
  vec3 stars = texture2D(starMap, uv).rgb * gain;
  stars *= mix(0.45, 1.0, ramp(0.0, 30.0, altitude));

  float towardHorizon = 1.0 - altitude / 90.0;

  vec3 twilight = skyColour;
  float sunDistance = separation(altitude, azimuth, sun.x, sun.y);
  float sunUp = ramp(-18.0, -4.0, sun.x);
  twilight *= mix(1.0, (0.6 + 0.9 * exp(-sunDistance / 55.0)) * (0.75 + 0.5 * towardHorizon * towardHorizon), sunUp);
  float warmth = exp(-sunDistance / 28.0) * pow(towardHorizon, 3.0) * ramp(-13.0, -3.0, sun.x) * (1.0 - ramp(4.0, 12.0, sun.x));
  twilight += vec3(1.0, 0.52, 0.28) * warmth * 0.45;

  vec3 moonlight = vec3(0.0);
  if (moon.x > -3.0) {
    float strength = pow(moon.z, 1.5) * ramp(-3.0, 25.0, moon.x);
    float moonDistance = separation(altitude, azimuth, moon.x, moon.y);
    float spread = 0.55 + 0.9 * exp(-moonDistance / 25.0) + 0.25 * towardHorizon;
    moonlight = vec3(0.34, 0.41, 0.55) * strength * spread * 0.75;
  }

  vec3 glow = twilight + moonlight;
  float added = max(luminance(glow) - luminance(nightColour), 0.0);
  float threshold = added * 3.0;
  float starLight = luminance(stars);
  stars *= clamp((starLight - threshold) / max(starLight, 1e-4), 0.0, 1.0);

  vec3 sky = stars + glow;
  if (clouds.w > 0.5 && altitude >= 0.0) {
    vec3 direction = vec3(sin(A) * cos(a), cos(A) * cos(a), sin(a));
    float high = cloudLayer(direction, 9.0, clouds.z, drift * 1.6, 7.0, vec2(0.35, 1.0), 3.1) * 0.45;
    float mid = cloudLayer(direction, 4.0, clouds.y, drift * 1.2, 3.5, vec2(1.0), 11.7) * 0.8;
    float low = cloudLayer(direction, 1.5, clouds.x, drift, 1.6, vec2(1.0), 23.9) * 0.95;
    vec3 nightCloud = vec3(0.045, 0.048, 0.06) + moonlight * 2.6;
    float glowSide = exp(-sunDistance / 70.0);
    vec3 duskCloud = twilight * 1.35 + 0.08
      + vec3(1.0, 0.55, 0.4) * 0.35 * glowSide * ramp(-12.0, -3.0, sun.x) * (1.0 - ramp(3.0, 12.0, sun.x));
    vec3 dayCloud = vec3(0.95, 0.96, 0.98);
    vec3 lit = mix(nightCloud, duskCloud, ramp(-15.0, -4.0, sun.x));
    lit = mix(lit, dayCloud, ramp(0.0, 12.0, sun.x));
    sky = mix(sky, lit * 1.05, high);
    sky = mix(sky, lit * 0.92, mid);
    sky = mix(sky, lit * 0.8, low);
  }
  gl_FragColor = vec4(sky * inside, inside);
}
`;

function compile(gl, type, source) {
  const shader = gl.createShader(type);
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(shader));
  return shader;
}

/**
 * A dome renderer on `canvas`, or null without WebGL. `ready` resolves once
 * the star map has loaded; until then the dome draws twilight and cloud only.
 */
export function domeRenderer(canvas, starMapURL) {
  const gl = canvas.getContext('webgl', { premultipliedAlpha: true, alpha: true });
  if (!gl) return null;
  const program = gl.createProgram();
  gl.attachShader(program, compile(gl, gl.VERTEX_SHADER, vertex));
  gl.attachShader(program, compile(gl, gl.FRAGMENT_SHADER, fragment));
  gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(program));
  gl.useProgram(program);

  const buffer = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
  const corner = gl.getAttribLocation(program, 'corner');
  gl.enableVertexAttribArray(corner);
  gl.vertexAttribPointer(corner, 2, gl.FLOAT, false, 0, 0);

  const texture = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, texture);
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array([0, 0, 0, 255]));
  const ready = new Promise(resolve => {
    const image = new Image();
    image.onload = () => {
      gl.bindTexture(gl.TEXTURE_2D, texture);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, image);
      gl.generateMipmap(gl.TEXTURE_2D);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      resolve(true);
    };
    image.onerror = () => resolve(false);
    image.src = starMapURL;
  });

  const u = name => gl.getUniformLocation(program, name);
  gl.uniform1i(u('starMap'), 0);
  gl.enable(gl.BLEND);
  gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);

  /** Everything in degrees, CSS pixels and 0–1 colours; see the uniforms above. */
  function render(scene) {
    const ratio = window.devicePixelRatio || 1;
    canvas.width = Math.round(scene.width * ratio);
    canvas.height = Math.round(scene.height * ratio);
    gl.viewport(0, 0, canvas.width, canvas.height);
    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.uniform2f(u('viewport'), canvas.width, canvas.height);
    gl.uniform2f(u('centre'), scene.centreX * ratio, scene.centreY * ratio);
    gl.uniform1f(u('radius'), scene.radius * ratio);
    gl.uniform1fv(u('horizon'), new Float32Array(scene.horizon));
    gl.uniform1f(u('latitude'), scene.latitude);
    gl.uniform1f(u('siderealTime'), scene.siderealTime);
    gl.uniform4f(u('sun'), scene.sun.altitude, scene.sun.azimuth, 0, 0);
    gl.uniform4f(u('moon'), scene.moon.altitude, scene.moon.azimuth, scene.moon.illuminatedFraction, 0);
    gl.uniform3fv(u('skyColour'), scene.skyColour);
    gl.uniform3fv(u('nightColour'), scene.nightColour);
    gl.uniform1f(u('gain'), 1.3);
    const c = scene.clouds;
    gl.uniform4f(u('clouds'), c?.low ?? 0, c?.mid ?? 0, c?.high ?? 0, c ? 1 : 0);
    gl.uniform2f(u('drift'), scene.drift.east, scene.drift.north);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  }

  return { render, ready };
}
