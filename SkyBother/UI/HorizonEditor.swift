import SwiftUI

/// How much sky the trees, houses and hills around a site take away, set
/// either as one value all the way round or direction by direction. Used by
/// guided setup and by Settings, so the two can never describe the horizon
/// differently.
struct HorizonEditor: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @Binding var site: Site

    @State private var showsDirections = false
    @State private var isConfirmingLevel = false
    /// Set once the user has agreed to level a directional horizon, so the
    /// all-round slider can take over without asking again.
    @State private var levellingAgreed = false

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 6) {
                HorizonDiagram(profile: site.horizonByDirection)
                    .frame(width: 150 * uiTextScale, height: 150 * uiTextScale)
                Text("Light: open sky\nDark: blocked")
                    .font(.scaled(.caption2, scale: uiTextScale))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement()
            .accessibilityLabel("Horizon diagram")
            .accessibilityValue(zip(Site.horizonDirections, site.horizonByDirection)
                .map { "\($0) \(Int($1)) degrees" }.joined(separator: ", "))

            VStack(alignment: .leading, spacing: 10) {
                allRoundControl

                Text("0° is an open horizon; 45° is blocked halfway up.")
                    .font(.scaled(.caption, scale: uiTextScale))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                DisclosureGroup(isExpanded: $showsDirections) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Site.horizonDirections.indices, id: \.self) { index in
                            HStack(spacing: 8) {
                                Text(Site.horizonDirections[index])
                                    .font(.scaled(.caption, scale: uiTextScale).weight(.semibold).monospaced())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 26 * uiTextScale, alignment: .leading)
                                Slider(value: directionBinding(index), in: 0...60, step: 1)
                                    .accessibilityLabel("Blocked horizon to the \(Site.horizonDirections[index])")
                                    .accessibilityValue("\(Int(site.horizonByDirection[index])) degrees")
                                Text(Format.degrees(site.horizonByDirection[index]))
                                    .font(.scaled(.caption, scale: uiTextScale).monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 36 * uiTextScale, alignment: .trailing)
                            }
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Text("Customize horizon by direction")
                        .contentShape(Rectangle())
                        .onTapGesture { showsDirections.toggle() }
                }
            }
        }
        // Opened for you when this site already has a direction recorded, so
        // it isn't hidden behind a triangle you have no reason to click.
        .task(id: site.id) {
            showsDirections = site.hasDirectionalHorizon
            levellingAgreed = false
        }
        .confirmationDialog("Set every direction to \(Format.degrees(site.horizonAltitude))?",
                            isPresented: $isConfirmingLevel) {
            Button("Set Every Direction to \(Format.degrees(site.horizonAltitude))") {
                site.setHorizonEverywhere(to: site.horizonAltitude)
                levellingAgreed = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your values for each direction will be replaced by one value all the way round.")
        }
    }

    /// One value for every direction. While a directional horizon exists it
    /// is replaced by a button that asks first, because moving it would
    /// silently wipe every direction's own value.
    @ViewBuilder
    private var allRoundControl: some View {
        if site.hasDirectionalHorizon && !levellingAgreed {
            VStack(alignment: .leading, spacing: 6) {
                Text("Blocked by direction: \(Format.degrees(site.horizonAltitude)) at its most open, \(Format.degrees(site.worstHorizonAltitude)) at its worst.")
                    .font(.scaled(.callout, scale: uiTextScale))
                Button("Use One Value All the Way Round…") { isConfirmingLevel = true }
                    .help("Replace the values for each direction with one")
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Blocked all the way round")
                        .font(.scaled(.callout, scale: uiTextScale))
                    Spacer()
                    Text(Format.degrees(site.horizonAltitude))
                        .font(.scaled(.callout, scale: uiTextScale).monospacedDigit().weight(.semibold))
                }
                Slider(value: Binding(get: { site.horizonAltitude },
                                      set: { site.setHorizonEverywhere(to: $0) }),
                       in: 0...60, step: 1)
                    .accessibilityLabel("Blocked horizon all the way round")
                    .accessibilityValue("\(Int(site.horizonAltitude)) degrees")
            }
        }
    }

    private func directionBinding(_ index: Int) -> Binding<Double> {
        Binding(get: { site.horizonByDirection[index] },
                set: { site.setHorizon(to: $0, forDirectionAt: index) })
    }
}

/// The horizon seen from above, north up and east to the right as in Sky
/// View: the open disc is sky you can see, and the shaded band around the rim
/// is what each direction's trees and houses take away.
struct HorizonDiagram: View {
    var profile: [Double]

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2 - 14
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let disc = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                              width: radius * 2, height: radius * 2))
            // Light sky you can see, dark ground and trees that hide it — the
            // two have to read apart at a glance.
            context.fill(disc, with: .color(Palette.accent.opacity(0.45)))

            for (index, altitude) in profile.enumerated() where altitude > 0 {
                let inner = radius * CGFloat(max(0, 1 - altitude / 90))
                let middle = Double(index) * 45
                var wedge = Path()
                for step in 0...9 {
                    let azimuth = (middle - 22.5 + Double(step) * 5) * .pi / 180
                    let point = CGPoint(x: center.x + CGFloat(sin(azimuth)) * radius,
                                        y: center.y - CGFloat(cos(azimuth)) * radius)
                    if step == 0 { wedge.move(to: point) } else { wedge.addLine(to: point) }
                }
                for step in (0...9).reversed() {
                    let azimuth = (middle - 22.5 + Double(step) * 5) * .pi / 180
                    wedge.addLine(to: CGPoint(x: center.x + CGFloat(sin(azimuth)) * inner,
                                              y: center.y - CGFloat(cos(azimuth)) * inner))
                }
                wedge.closeSubpath()
                context.fill(wedge, with: .color(Color.black.opacity(0.75)))
            }
            context.stroke(disc, with: .color(Palette.accent.opacity(0.6)), lineWidth: 1)

            for (label, azimuth) in [("N", 0.0), ("E", 90.0), ("S", 180.0), ("W", 270.0)] {
                let angle = azimuth * .pi / 180
                let point = CGPoint(x: center.x + CGFloat(sin(angle)) * (radius + 8),
                                    y: center.y - CGFloat(cos(angle)) * (radius + 8))
                context.draw(Text(label).font(.caption2.weight(.semibold)).foregroundColor(.secondary), at: point)
            }
        }
    }
}
