#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The real night sky, re-projected onto the planisphere every frame.
//
// Each pixel is taken back through the dome's own projection (azimuthal
// equidistant: altitude linear in radius, azimuth clockwise from north with
// east on the right, exactly as `SkyProjection.project` lays it out) to an
// altitude and azimuth, then to right ascension and declination for this
// moment's sidereal time, and looked up in an equirectangular map of the whole
// sky. Doing it per pixel on the GPU is what lets the sky turn smoothly while
// the night plays back; a pre-rendered picture per moment could not.
//
// Twilight and moonlight are added as glows, and a glow drowns faint light
// before bright: the Milky Way goes first, the brightest stars last.

constant float kDeg = M_PI_F / 180.0;

static float separation(float alt1, float az1, float alt2, float az2) {
    float c = sin(alt1 * kDeg) * sin(alt2 * kDeg)
            + cos(alt1 * kDeg) * cos(alt2 * kDeg) * cos((az1 - az2) * kDeg);
    return acos(clamp(c, -1.0, 1.0)) / kDeg;
}

static float luminance(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

// Clouds. Representative, not real: the forecast says how much of the sky
// each layer covers, not where, so the shapes are noise, thresholded to
// cover that fraction and drifted with the forecast wind.

static float hash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float valueNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash(i), b = hash(i + float2(1, 0)), c = hash(i + float2(0, 1)), d = hash(i + float2(1, 1));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float fbm(float2 p) {
    float total = 0.0, amplitude = 0.5;
    for (int octave = 0; octave < 5; octave++) {
        total += amplitude * valueNoise(p);
        p = p * 2.03 + float2(17.1, 9.2);
        amplitude *= 0.5;
    }
    return total;
}

// How opaque one layer is at this point of the sky. The view direction is
// carried up to a flat deck `height` km overhead, so clouds shrink and crowd
// towards the horizon the way real ones do.
static float cloudLayer(float3 direction, float height, float cover, float2 drift,
                        float featureKm, float2 stretch, float seed) {
    if (cover < 0.01) return 0.0;
    float up = max(direction.z, 0.04);
    float2 deck = direction.xy / up * height - drift;
    float n = fbm(deck / featureKm * stretch + seed);
    // fbm sits around 0.5 give or take 0.25; this threshold makes the
    // covered fraction roughly track `cover`.
    float threshold = mix(0.78, 0.22, cover);
    float density = smoothstep(threshold - 0.06, threshold + 0.10, n);
    // Overcast is overcast, whatever the noise says.
    density = max(density, smoothstep(0.9, 1.0, cover));
    // Looking low, you look through more of the deck.
    return density * mix(1.0, 0.75, smoothstep(0.35, 0.05, up));
}

[[ stitchable ]] half4 skyDome(float2 position,
                               texture2d<half> starMap,
                               float2 centre,
                               float radius,
                               float latitude,
                               float siderealTime,
                               float4 sun,       // altitude, azimuth, unused, unused
                               float4 moon,      // altitude, azimuth, illuminated fraction, unused
                               half4 skyColour,  // the app's twilight colour for this sun altitude
                               half4 nightColour,
                               float gain,
                               float4 clouds,    // low, mid, high cover 0-1, 1 to draw them
                               float2 drift) {   // how far the wind has carried them, km east and north
    float2 unit = (position - centre) / radius;
    float r = min(length(unit), 1.0);
    float altitude = 90.0 * (1.0 - r);
    float azimuth = atan2(unit.x, -unit.y) / kDeg;

    // Horizon to equator.
    float phi = latitude * kDeg, a = altitude * kDeg, A = azimuth * kDeg;
    float sinDec = sin(phi) * sin(a) + cos(phi) * cos(a) * cos(A);
    float declination = asin(clamp(sinDec, -1.0, 1.0)) / kDeg;
    float hourAngle = atan2(-sin(A) * cos(a), sin(a) * cos(phi) - cos(a) * sin(phi) * cos(A)) / kDeg;
    float rightAscension = siderealTime - hourAngle;

    // The map is centred on 0h with right ascension increasing to the left,
    // north at the top.
    constexpr sampler linearRepeat(coord::normalized, address::repeat, filter::linear);
    float2 uv = float2(fract(0.5 - rightAscension / 360.0),
                       clamp(0.5 - declination / 180.0, 0.0005, 0.9995));
    float3 stars = float3(starMap.sample(linearRepeat, uv).rgb) * gain;

    // Thicker air near the horizon.
    stars *= mix(0.45, 1.0, smoothstep(0.0, 30.0, altitude));

    float towardHorizon = 1.0 - altitude / 90.0;

    // Twilight: the app's own sky colour, brighter towards the sun and down
    // near the horizon, with a warm band on the sun's side as it sets.
    float3 twilight = float3(skyColour.rgb);
    float sunDistance = separation(altitude, azimuth, sun.x, sun.y);
    float sunUp = smoothstep(-18.0, -4.0, sun.x);
    twilight *= mix(1.0, (0.6 + 0.9 * exp(-sunDistance / 55.0)) * (0.75 + 0.5 * towardHorizon * towardHorizon), sunUp);
    float warmth = exp(-sunDistance / 28.0) * pow(towardHorizon, 3.0) * smoothstep(-13.0, -3.0, sun.x) * (1.0 - smoothstep(4.0, 12.0, sun.x));
    twilight += float3(1.0, 0.52, 0.28) * warmth * 0.45;

    // Moonlight: by phase and by how high it is, brightest around the Moon
    // itself and lifting the whole sky a little.
    float3 moonlight = float3(0.0);
    if (moon.x > -3.0) {
        float strength = pow(moon.z, 1.5) * smoothstep(-3.0, 25.0, moon.x);
        float moonDistance = separation(altitude, azimuth, moon.x, moon.y);
        // A bright moon lights the whole sky, not just a halo — a gibbous
        // moon is enough to hide the Milky Way from horizon to horizon.
        float spread = 0.55 + 0.9 * exp(-moonDistance / 25.0) + 0.25 * towardHorizon;
        moonlight = float3(0.34, 0.41, 0.55) * strength * spread * 0.75;
    }

    float3 glow = twilight + moonlight;

    // Stars show through only as far as they outshine the added light.
    float added = max(luminance(glow) - luminance(float3(nightColour.rgb)), 0.0);
    float threshold = added * 3.0;
    float starLight = luminance(stars);
    stars *= clamp((starLight - threshold) / max(starLight, 1e-4), 0.0, 1.0);

    float3 sky = stars + glow;
    if (clouds.w < 0.5 || altitude < 0.0) return half4(half3(sky), 1.0h);

    float3 direction = float3(sin(A) * cos(a), cos(A) * cos(a), sin(a));
    // High cloud: thin, and streaked along the wind.
    float high = cloudLayer(direction, 9.0, clouds.z, drift * 1.6, 7.0, float2(0.35, 1.0), 3.1) * 0.45;
    float mid = cloudLayer(direction, 4.0, clouds.y, drift * 1.2, 3.5, float2(1.0), 11.7) * 0.8;
    float low = cloudLayer(direction, 1.5, clouds.x, drift, 1.6, float2(1.0), 23.9) * 0.95;

    // Lit by whatever lights the sky: white by day, the twilight's own
    // colour at dusk, a faint moonlit grey at night.
    // Moonlit cloud is brighter than the moonlit sky around it, or it
    // vanishes into it; a moonless night leaves it a dim starless grey.
    float3 nightCloud = float3(0.045, 0.048, 0.06) + moonlight * 2.6;
    // At dusk and dawn cloud catches the light the sky has lost, warm on
    // the sun's side.
    float glowSide = exp(-sunDistance / 70.0);
    float3 duskCloud = float3(twilight) * 1.35 + 0.08
        + float3(1.0, 0.55, 0.4) * 0.35 * glowSide * smoothstep(-12.0, -3.0, sun.x) * (1.0 - smoothstep(3.0, 12.0, sun.x));
    float3 dayCloud = float3(0.95, 0.96, 0.98);
    float3 lit = mix(nightCloud, duskCloud, smoothstep(-15.0, -4.0, sun.x));
    lit = mix(lit, dayCloud, smoothstep(0.0, 12.0, sun.x));

    // Far layers first, the low deck in front; each hides what's behind it.
    sky = mix(sky, lit * 1.05, high);
    sky = mix(sky, lit * 0.92, mid);
    sky = mix(sky, lit * 0.8, low);
    return half4(half3(sky), 1.0h);
}

// A flat camera's view of the same map, for framing previews too wide for
// the survey cutouts to look like anything: gnomonic (the projection a
// rectilinear lens makes), centred on the target, north up and east to the
// left like the survey pictures beside it. `planePerPoint` converts points
// from the centre into the tangent plane, so the frame drawn over it lands
// on the sensor's real edges.
[[ stitchable ]] half4 wideField(float2 position,
                                 texture2d<half> starMap,
                                 float2 centre,
                                 float planePerPoint,
                                 float rightAscension0,
                                 float declination0,
                                 float gain) {
    float xi = -(position.x - centre.x) * planePerPoint;   // east is left
    float eta = -(position.y - centre.y) * planePerPoint;  // north is up
    float rho = length(float2(xi, eta));
    float d0 = declination0 * kDeg;
    float declination, rightAscension;
    if (rho < 1e-6) {
        declination = declination0;
        rightAscension = rightAscension0;
    } else {
        float c = atan(rho);
        declination = asin(clamp(cos(c) * sin(d0) + eta * sin(c) * cos(d0) / rho, -1.0, 1.0)) / kDeg;
        rightAscension = rightAscension0
            + atan2(xi * sin(c), rho * cos(d0) * cos(c) - eta * sin(d0) * sin(c)) / kDeg;
    }
    constexpr sampler linearRepeat(coord::normalized, address::repeat, filter::linear);
    float2 uv = float2(fract(0.5 - rightAscension / 360.0),
                       clamp(0.5 - declination / 180.0, 0.0005, 0.9995));
    return half4(half3(float3(starMap.sample(linearRepeat, uv).rgb) * gain), 1.0h);
}
