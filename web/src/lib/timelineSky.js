// The night timeline's sky in WebGL: twilight colours, the Moon's wash,
// stars wherever it's properly dark, and the forecast's cloud hanging from the
// top as deep as the sky is covered. The Mac app draws the same thing with
// `nightTimeline` in SkyDome.metal; keep the two in step.
//
// Cloud itself is drawn over this by Timeline.svelte, hanging from the top
// as deep as the sky is covered. What this adds is the score's verdict:
// wherever its cloud credit (Preferences.cloudCredit) falls the sky dulls a
// little; where cloud is under your limit it stays clear. Stars dim
// gradually as the cloud thickens, so a clear window shows as a starry gap.

const vertex = `
attribute vec2 corner;
void main() { gl_Position = vec4(corner, 0.0, 1.0); }
`;

const fragment = `
precision highp float;
uniform vec2 size;          // CSS pixels
uniform float ratio;        // device pixels per CSS pixel
uniform float count;        // samples across the width
uniform sampler2D skyData;  // sun altitude, moon wash, low cover, mid cover
uniform sampler2D cloudData;// high cover, total cover, cloud credit, has weather

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

// smoothstep with its edges either way round.
float ramp(float edge0, float edge1, float x) {
  float t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

// Palette.sky(sunAltitude:)
vec3 twilightColour(float sun) {
  vec3 day = vec3(0.42, 0.62, 0.86), civil = vec3(0.18, 0.24, 0.45);
  vec3 nautical = vec3(0.07, 0.10, 0.22), astronomical = vec3(0.025, 0.03, 0.075);
  if (sun >= 0.0) return day;
  if (sun >= -6.0) return mix(day, civil, ramp(0.0, -6.0, sun));
  if (sun >= -12.0) return mix(civil, nautical, ramp(-6.0, -12.0, sun));
  if (sun >= -18.0) return mix(nautical, astronomical, ramp(-12.0, -18.0, sun));
  return astronomical;
}

void main() {
  vec2 position = vec2(gl_FragCoord.x, size.y * ratio - gl_FragCoord.y) / ratio;
  float u = clamp(position.x / size.x, 0.0, 1.0);
  float texel = 1.0 / count;
  vec2 at = vec2((u * (count - 1.0) + 0.5) * texel, 0.5);
  vec4 a = texture2D(skyData, at), b = texture2D(cloudData, at);
  float sun = a.r * 180.0 - 90.0;
  // The Moon's light steps hour by hour with the forecast; average it over
  // a couple of hours so it fades instead of banding.
  float wash = 0.0;
  for (int k = -4; k <= 4; k++) wash += texture2D(skyData, at + vec2(float(k) * 3.0 * texel, 0.0)).g;
  wash *= 0.34 / 9.0;
  float credit = b.b, weather = b.a;
  if (weather < 0.5) credit = 1.0;

  vec3 moonlight = vec3(0.98, 0.93, 0.74);
  vec3 sky = mix(twilightColour(sun), moonlight, wash);

  // Stars where the sky is dark, fading as the Moon washes it out and
  // dimming gradually as cloud thickens: full on a clear night, about half
  // at 40% cover, faint past 60%. Whatever the score fully credits keeps
  // them at full strength.
  float seen = weather > 0.5 ? max(clamp(1.0 - b.g * 1.3, 0.1, 1.0), credit) : 1.0;
  float starry = ramp(-9.0, -15.0, sun) * mix(1.0, 0.12, ramp(0.0, 0.3, wash)) * seen;
  vec2 cell = floor(position / 3.0);
  if (starry > 0.0 && hash(cell) > 0.968) {
    vec2 centre = (cell + 0.25 + 0.5 * vec2(hash(cell + 3.1), hash(cell + 7.7))) * 3.0;
    float d = length(position - centre);
    float brightness = 0.25 + 0.75 * pow(hash(cell + 11.3), 4.0);
    sky += vec3(0.85, 0.9, 1.0) * brightness * exp(-d * d / 0.7) * starry;
  }

  // Where the score loses the sky, it dulls: gently, so the cloud drawn
  // over it stays the thing you read. Squared, so a window the score half
  // counts already looks like open sky.
  if (weather > 0.5) {
    float lost = (1.0 - credit) * (1.0 - credit);
    sky = mix(sky, mix(vec3(0.17, 0.18, 0.21), twilightColour(sun) * 0.7 + 0.08, ramp(-12.0, 0.0, sun)), lost * 0.5);
  }

  // A touch of dither, so the soft gradients don't band.
  sky += (hash(gl_FragCoord.xy) - 0.5) / 255.0;
  gl_FragColor = vec4(sky, 1.0);
}
`;

function compile(gl, type, source) {
  const shader = gl.createShader(type);
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(shader));
  return shader;
}

function dataTexture(gl, unit) {
  const texture = gl.createTexture();
  gl.activeTexture(gl.TEXTURE0 + unit);
  gl.bindTexture(gl.TEXTURE_2D, texture);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  return texture;
}

/** A renderer on `canvas`, or null where WebGL isn't available. */
export function timelineSky(canvas) {
  const gl = canvas.getContext('webgl', { antialias: false, premultipliedAlpha: false });
  if (!gl) return null;
  const program = gl.createProgram();
  gl.attachShader(program, compile(gl, gl.VERTEX_SHADER, vertex));
  gl.attachShader(program, compile(gl, gl.FRAGMENT_SHADER, fragment));
  gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(program));
  gl.useProgram(program);

  const corners = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, corners);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
  const corner = gl.getAttribLocation(program, 'corner');
  gl.enableVertexAttribArray(corner);
  gl.vertexAttribPointer(corner, 2, gl.FLOAT, false, 0, 0);

  const skyTexture = dataTexture(gl, 0);
  const cloudTexture = dataTexture(gl, 1);
  gl.uniform1i(gl.getUniformLocation(program, 'skyData'), 0);
  gl.uniform1i(gl.getUniformLocation(program, 'cloudData'), 1);
  const uniform = name => gl.getUniformLocation(program, name);

  const byte = value => Math.round(Math.min(1, Math.max(0, value)) * 255);

  return function render(night, width, height, ratio) {
    canvas.width = Math.round(width * ratio);
    canvas.height = Math.round(height * ratio);
    const samples = night.samples;
    const sky = new Uint8Array(samples.length * 4);
    const cloud = new Uint8Array(samples.length * 4);
    samples.forEach((s, i) => {
      const weather = night.hasWeather && s.hasWeather && s.cloudCover != null;
      sky.set([byte((s.sunAltitude + 90) / 180), byte(s.moonAltitude > 0 ? s.moonBrightness : 0),
               byte(weather ? s.cloudLow / 100 : 0), byte(weather ? s.cloudMid / 100 : 0)], i * 4);
      cloud.set([byte(weather ? s.cloudHigh / 100 : 0), byte(weather ? s.cloudCover / 100 : 0),
                 byte(weather ? s.cloudCredit ?? 1 : 1), weather ? 255 : 0], i * 4);
    });
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, skyTexture);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, samples.length, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, sky);
    gl.activeTexture(gl.TEXTURE1);
    gl.bindTexture(gl.TEXTURE_2D, cloudTexture);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, samples.length, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, cloud);

    gl.uniform2f(uniform('size'), width, height);
    gl.uniform1f(uniform('ratio'), ratio);
    gl.uniform1f(uniform('count'), samples.length);
    gl.viewport(0, 0, canvas.width, canvas.height);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  };
}
