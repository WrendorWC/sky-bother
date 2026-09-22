import SwiftUI

/// The Moon as it will look tonight — opened by clicking the moon in a
/// night's header, laid out like a catalogue card.
///
/// Drawn rather than photographed: NASA's lunar colour map wrapped onto a
/// sphere and lit from the Sun's real direction (see `MoonGlobe.metal`), so
/// the phase, which limb is lit and how the Moon is turned all match the view
/// from this site. It is shown at the moment the Moon is highest during the
/// night, or while it's best placed if it's up at all.
struct MoonCard: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @Environment(\.dismiss) private var dismiss
    var plan: NightPlan

    /// When the Moon stands highest between sunset and sunrise, sampled every
    /// ten minutes — the moment anyone looking at it tonight most likely will.
    private var moment: Date {
        let window = plan.chartWindow
        let samples = stride(from: window.start.timeIntervalSince1970,
                             through: window.end.timeIntervalSince1970, by: 600)
            .map { Date(timeIntervalSince1970: $0) }
        return samples.max { altitude(at: $0) < altitude(at: $1) } ?? window.midpoint
    }

    private func horizontal(of coordinate: EquatorialCoordinate, at date: Date) -> HorizontalCoordinate {
        SkyCoordinates.horizontal(coordinate, daysSinceJ2000: date.daysSinceJ2000,
                                  latitude: plan.site.latitude, longitude: plan.site.longitude)
    }

    private func altitude(at date: Date) -> Double {
        horizontal(of: Moon.position(daysSinceJ2000: date.daysSinceJ2000).coordinate, at: date).altitude
    }

    var body: some View {
        let date = moment
        let d = date.daysSinceJ2000
        let moon = Moon.position(daysSinceJ2000: d)
        let moonSky = horizontal(of: moon.coordinate, at: date)
        let view = MoonView(moon: moonSky, moonDistance: moon.distanceKilometers,
                            sun: horizontal(of: Sun.position(daysSinceJ2000: d), at: date),
                            latitude: plan.site.latitude)
        let lit = Moon.illuminatedFraction(daysSinceJ2000: d)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("The Moon")
                        .font(.scaled(.title2, scale: uiTextScale).weight(.semibold))
                    Text("\(Moon.phaseName(daysSinceJ2000: d)) · as seen from \(plan.site.name)")
                        .font(.scaled(.callout, scale: uiTextScale))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(24)

            VStack(alignment: .leading, spacing: 16) {
                MoonGlobe(view: view)
                    .frame(width: 360, height: 360)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Palette.spaceTop, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.panelBorder))

                VStack(alignment: .leading, spacing: 8) {
                    factRow("Lit", "\(Int((lit * 100).rounded()))%")
                    factRow("Shown at", "\(Format.time(date, in: plan.timeZone)) · "
                            + (moonSky.altitude > 0
                               ? "\(Format.degrees(moonSky.altitude)) up in the \(moonSky.compassPoint)"
                               : "below the horizon all night"))
                    factRow("Distance", "\(Int(moon.distanceKilometers.rounded()).formatted()) km")
                    factRow("Apparent size", String(format: "%.1f′", 3474.8 / moon.distanceKilometers * 180 / .pi * 60))
                }

                Text("Lunar surface: NASA\u{2019}s Scientific Visualization Studio, from Lunar Reconnaissance Orbiter Camera data")
                    .font(.scaled(.caption2, scale: uiTextScale))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding([.horizontal, .bottom], 24)
        }
        // Wider with larger text, so the header stays on one line.
        .frame(width: max(460, 360 * uiTextScale))
        .background(Palette.spaceBackground)
    }

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.scaled(.callout, scale: uiTextScale))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.scaled(.callout, scale: uiTextScale).monospacedDigit())
        }
    }
}

/// Where the Sun is and which way is north, in the viewer's own frame —
/// x to the right, y up, z towards them — for one look at the Moon.
struct MoonView {
    var light: SIMD3<Double>
    var north: SIMD2<Double>

    init(moon: HorizontalCoordinate, moonDistance: Double, sun: HorizontalCoordinate, latitude: Double) {
        // East, north, up.
        func vector(_ h: HorizontalCoordinate) -> SIMD3<Double> {
            SIMD3(cosDeg(h.altitude) * sinDeg(h.azimuth),
                  cosDeg(h.altitude) * cosDeg(h.azimuth),
                  sinDeg(h.altitude))
        }
        func normalized(_ v: SIMD3<Double>) -> SIMD3<Double> {
            let length = (v * v).sum().squareRoot()
            return length > 1e-9 ? v / length : v
        }
        func cross(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
            SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
        }
        func dot(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double { (a * b).sum() }

        let forward = vector(moon)
        // "Up" is towards the zenith; straight overhead that has no direction,
        // so north stands in.
        let zenith = SIMD3<Double>(0, 0, 1)
        var up = zenith - forward * dot(zenith, forward)
        if dot(up, up) < 1e-8 { up = SIMD3(0, 1, 0) - forward * forward.y }
        up = normalized(up)
        let right = normalized(cross(forward, up))

        // From the Moon to the Sun, not just the Sun's direction: at the
        // Moon's distance the difference is what makes a first quarter half lit.
        let sunDistance = 149_597_870.0
        let toSun = normalized(vector(sun) * sunDistance - forward * moonDistance)
        light = normalized(SIMD3(dot(toSun, right), dot(toSun, up), -dot(toSun, forward)))

        // Lunar north stays within a few degrees of celestial north, so the
        // celestial pole's direction on screen sets the Moon's orientation.
        let pole = SIMD3<Double>(0, cosDeg(latitude), sinDeg(latitude))
        let screenNorth = SIMD2(dot(pole, right), dot(pole, up))
        let length = (screenNorth * screenNorth).sum().squareRoot()
        north = length > 1e-9 ? screenNorth / length : SIMD2(0, 1)
    }
}

/// The lit sphere itself.
struct MoonGlobe: View {
    var view: MoonView

    private static let surface: Image? = Bundle.main.url(forResource: "MoonMap", withExtension: "jpg")
        .flatMap { NSImage(contentsOf: $0) }
        .map { Image(nsImage: $0) }

    var body: some View {
        Canvas { context, size in
            guard let surface = Self.surface else { return }
            let radius = min(size.width, size.height) / 2
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let disc = Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius,
                                              width: radius * 2, height: radius * 2))
            context.fill(disc, with: .shader(ShaderLibrary.moonGlobe(
                .image(surface),
                .float2(centre),
                .float(radius),
                .float3(view.light.x, view.light.y, view.light.z),
                .float2(view.north.x, view.north.y))))
        }
    }
}
