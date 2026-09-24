#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The Moon as a lit sphere, seen from one place at one moment.
//
// Each pixel of the disc is a point on the near hemisphere. Its normal is
// turned into selenographic latitude and longitude — with lunar north set to
// wherever celestial north falls in this view — and looked up in an
// equirectangular map of the whole Moon. It is then lit from the Sun's
// actual direction, so the phase, which limb is lit and the tilt of the
// terminator are all what an observer at the site would see.
//
// Screen space here: x to the right, y up, z towards the viewer.

[[ stitchable ]] half4 moonGlobe(float2 position,
                                 texture2d<half> surface,
                                 float2 centre,
                                 float radius,
                                 float3 light,      // unit vector towards the Sun
                                 float2 north) {    // unit vector: lunar north on screen
    float2 p = (position - centre) / radius;
    p.y = -p.y;                                    // screen y grows downward
    float r2 = dot(p, p);
    if (r2 > 1.0) return half4(0.0h);
    float3 n = float3(p, sqrt(1.0 - r2));

    // Body frame: north as given, east (increasing selenographic longitude)
    // a quarter turn clockwise from it, so north-up puts east on the right —
    // the same way round as the map and as the Moon looks to the eye.
    float2 east = float2(north.y, -north.x);
    float latitude = asin(clamp(dot(n.xy, north), -1.0, 1.0));
    float longitude = atan2(dot(n.xy, east), n.z);

    constexpr sampler linearRepeat(coord::normalized, address::repeat, filter::linear);
    float2 uv = float2(fract(0.5 + longitude / (2.0 * M_PI_F)),
                       clamp(0.5 - latitude / M_PI_F, 0.001, 0.999));
    float3 albedo = float3(surface.sample(linearRepeat, uv).rgb);

    // The Moon barely darkens towards its limb when full — a Lommel–Seeliger
    // surface — so mostly that, with a little Lambert to round it off.
    float mu0 = max(dot(n, light), 0.0);
    float mu = max(n.z, 0.0);
    float lommel = 2.0 * mu0 / (mu0 + mu + 1e-4);
    float lit = mix(mu0, lommel, 0.7);

    // A trace of earthshine on the night side, the way a crescent shows its
    // dark part faintly.
    float3 colour = albedo * (lit * 1.05 + 0.025);

    // A soft rim so the edge isn't aliased.
    float edge = smoothstep(1.0, 0.985, sqrt(r2));
    return half4(half3(colour * edge), half(edge));
}
