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
                               float gain) {
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

    return half4(half3(stars + glow), 1.0h);
}
