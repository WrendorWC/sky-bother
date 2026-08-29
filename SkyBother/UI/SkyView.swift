import SwiftUI

/// The night's sky laid flat: zenith at the centre, horizon at the rim,
/// azimuth around the edge like a compass face — a classic planisphere.
/// This is Version 2.0's spatial foundation: the same targets, the same
/// selection, and now the same scrubbed time as the rest of the night view,
/// just answering "where," not only "when."
struct SkyView: View {
    @EnvironmentObject private var state: AppState
    var plan: NightPlan
    @Binding var scrubTime: Date

    /// Not persisted to Preferences — a per-viewing toggle for one layer,
    /// not a setting worth growing the stored-settings surface for yet.
    @State private var showsMilkyWay = true

    private var daysSinceJ2000: Double { scrubTime.daysSinceJ2000 }

    private struct Placement {
        var id: String
        var point: SkyProjection.UnitPoint
        var color: Color
        var isSelected: Bool
    }

    /// Only targets currently above the horizon — anything below would
    /// otherwise project onto the rim, which reads as "grazing the horizon"
    /// rather than "not up right now."
    private var targetPlacements: [Placement] {
        plan.targets.compactMap { targetPlan in
            let horizontal = horizontal(of: targetPlan.target.coordinate)
            guard horizontal.altitude > 0 else { return nil }
            return Placement(id: targetPlan.id,
                             point: SkyProjection.project(horizontal),
                             color: Palette.score(targetPlan.score),
                             isSelected: targetPlan.id == state.selectedTargetID)
        }
    }

    private var moonHorizontal: HorizontalCoordinate {
        horizontal(of: Moon.position(daysSinceJ2000: daysSinceJ2000).coordinate)
    }

    private var sunAltitude: Double {
        Sun.altitude(daysSinceJ2000: daysSinceJ2000, latitude: plan.site.latitude, longitude: plan.site.longitude)
    }

    private var galacticCoreHorizontal: HorizontalCoordinate {
        horizontal(of: GalacticCoordinates.galacticCenter)
    }

    /// The galactic plane, sampled every 4° of galactic longitude and
    /// projected — broken into separate runs wherever it dips below the
    /// horizon, rather than one path that would otherwise cut straight
    /// through the ground.
    private var milkyWaySegments: [[SkyProjection.UnitPoint]] {
        var segments: [[SkyProjection.UnitPoint]] = []
        var current: [SkyProjection.UnitPoint] = []
        for longitude in stride(from: 0.0, through: 360.0, by: 4.0) {
            let point = horizontal(of: GalacticCoordinates.equatorial(galacticLongitude: longitude, galacticLatitude: 0))
            if point.altitude > 0 {
                current.append(SkyProjection.project(point))
            } else if !current.isEmpty {
                segments.append(current)
                current = []
            }
        }
        if !current.isEmpty { segments.append(current) }
        return segments
    }

    /// Every span tonight where the Core clears a useful altitude — the same
    /// above-threshold windowing the planner already uses for dusk/dawn and
    /// target visibility, just pointed at the Core's own altitude curve.
    private var galacticCoreWindows: [TimeWindow] {
        Ephemeris.windows(above: 20, from: plan.chartWindow.start, to: plan.chartWindow.end, stepMinutes: 5) { date in
            SkyCoordinates.horizontal(GalacticCoordinates.galacticCenter,
                                      daysSinceJ2000: date.daysSinceJ2000,
                                      latitude: plan.site.latitude,
                                      longitude: plan.site.longitude).altitude
        }
    }

    private var galacticCoreSummary: String {
        guard let bestWindow = galacticCoreWindows.max(by: { $0.duration < $1.duration }) else {
            return "Doesn't clear 20° altitude tonight."
        }
        var parts = ["Above 20° \(Format.time(bestWindow.start, in: plan.timeZone))–\(Format.time(bestWindow.end, in: plan.timeZone))"]
        if let dusk = plan.astronomicalDusk, let dawn = plan.astronomicalDawn,
           bestWindow.start < dawn, bestWindow.end > dusk {
            parts.append("overlaps astronomical darkness")
        }
        parts.append("\(plan.moon.illuminationPercent)% \(plan.moon.phaseName.lowercased())")
        return parts.joined(separator: " · ")
    }

    private func horizontal(of coordinate: EquatorialCoordinate) -> HorizontalCoordinate {
        SkyCoordinates.horizontal(coordinate,
                                  daysSinceJ2000: daysSinceJ2000,
                                  latitude: plan.site.latitude,
                                  longitude: plan.site.longitude)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Milky Way", isOn: $showsMilkyWay)
                .toggleStyle(.button)
                .controlSize(.small)
                .tint(Palette.accentWarm)

            GeometryReader { geometry in
                let side = min(geometry.size.width, geometry.size.height)
                let radius = side / 2 - 20
                let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

                ZStack {
                    Canvas { context, _ in
                        draw(context: context, center: center, radius: radius)
                    }
                    compassLabels(center: center, radius: radius)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onEnded { value in handleTap(at: value.location, center: center, radius: radius) }
                )
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity, alignment: .center)

            timeScrubber
        }
    }

    // MARK: - Drawing

    private func draw(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        guard radius > 0 else { return }
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let horizonPath = Path(ellipseIn: rect)

        context.fill(horizonPath, with: .color(Palette.sky(sunAltitude: sunAltitude)))

        // Blocked-horizon ring: the annulus between the true horizon and
        // whatever altitude trees/houses/hills actually allow — the same
        // single blocked-altitude value used everywhere else in the app.
        let blockedRadius = radius * CGFloat(clamp((90 - plan.site.horizonAltitude) / 90, 0, 1))
        if blockedRadius < radius {
            let blockedRect = CGRect(x: center.x - blockedRadius, y: center.y - blockedRadius,
                                     width: blockedRadius * 2, height: blockedRadius * 2)
            var ring = Path(ellipseIn: rect)
            ring.addPath(Path(ellipseIn: blockedRect))
            context.fill(ring, with: .color(.black.opacity(0.38)), style: FillStyle(eoFill: true))
        }

        for altitude in [30.0, 60.0] {
            let r = radius * CGFloat(clamp((90 - altitude) / 90, 0, 1))
            let ringRect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            context.stroke(Path(ellipseIn: ringRect), with: .color(.white.opacity(0.12)), lineWidth: 1)
        }
        context.stroke(horizonPath, with: .color(Palette.panelBorder), lineWidth: 1)

        if showsMilkyWay {
            drawMilkyWay(context: context, center: center, radius: radius)
        }

        // Celestial pole, for orientation — a fixed cross, not a moving object.
        let poleAltitude = abs(plan.site.latitude)
        let poleAzimuth: Double = plan.site.latitude >= 0 ? 0 : 180
        drawCross(context: context, center: center, radius: radius,
                 at: HorizontalCoordinate(altitude: poleAltitude, azimuth: poleAzimuth),
                 size: 5, color: .white.opacity(0.35))

        if moonHorizontal.altitude > 0 {
            let screen = screenPoint(for: moonHorizontal, center: center, radius: radius)
            context.fill(Path(ellipseIn: CGRect(x: screen.x - 6, y: screen.y - 6, width: 12, height: 12)),
                        with: .color(Palette.moonlight))
        }

        for placement in targetPlacements {
            let screen = CGPoint(x: center.x + CGFloat(placement.point.x) * radius,
                                 y: center.y + CGFloat(placement.point.y) * radius)
            let size: CGFloat = placement.isSelected ? 10 : 6
            let color = placement.isSelected ? Palette.accent : placement.color
            context.fill(Path(ellipseIn: CGRect(x: screen.x - size / 2, y: screen.y - size / 2, width: size, height: size)),
                        with: .color(color))
            if placement.isSelected {
                let haloSize = size + 5
                context.stroke(Path(ellipseIn: CGRect(x: screen.x - haloSize / 2, y: screen.y - haloSize / 2,
                                                       width: haloSize, height: haloSize)),
                              with: .color(color.opacity(0.6)), lineWidth: 1.5)
            }
        }
    }

    private func screenPoint(for horizontal: HorizontalCoordinate, center: CGPoint, radius: CGFloat) -> CGPoint {
        screenPoint(for: SkyProjection.project(horizontal), center: center, radius: radius)
    }

    private func screenPoint(for unit: SkyProjection.UnitPoint, center: CGPoint, radius: CGFloat) -> CGPoint {
        CGPoint(x: center.x + CGFloat(unit.x) * radius, y: center.y + CGFloat(unit.y) * radius)
    }

    /// A soft, layered stroke — a wide faint pass plus a narrower brighter
    /// one, the same cheap trick the main timeline's cloud layer uses —
    /// reads as diffuse structure rather than a hard drawn line. The Core
    /// itself gets its own warm-accent marker so it doesn't blend into
    /// either the band or the target dots.
    private func drawMilkyWay(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        for segment in milkyWaySegments where segment.count > 1 {
            let points = segment.map { screenPoint(for: $0, center: center, radius: radius) }
            let path = Path.smoothLine(through: points)
            context.stroke(path, with: .color(Palette.milkyWay.opacity(0.12)), lineWidth: 14)
            context.stroke(path, with: .color(Palette.milkyWay.opacity(0.22)), lineWidth: 6)
        }

        guard galacticCoreHorizontal.altitude > 0 else { return }
        let screen = screenPoint(for: galacticCoreHorizontal, center: center, radius: radius)
        context.fill(Path(ellipseIn: CGRect(x: screen.x - 5, y: screen.y - 5, width: 10, height: 10)),
                    with: .color(Palette.accentWarm))
        context.stroke(Path(ellipseIn: CGRect(x: screen.x - 8, y: screen.y - 8, width: 16, height: 16)),
                      with: .color(Palette.accentWarm.opacity(0.5)), lineWidth: 1.5)
    }

    private func drawCross(context: GraphicsContext, center: CGPoint, radius: CGFloat,
                           at horizontal: HorizontalCoordinate, size: CGFloat, color: Color) {
        guard horizontal.altitude > 0 else { return }
        let screen = screenPoint(for: horizontal, center: center, radius: radius)
        var path = Path()
        path.move(to: CGPoint(x: screen.x - size, y: screen.y))
        path.addLine(to: CGPoint(x: screen.x + size, y: screen.y))
        path.move(to: CGPoint(x: screen.x, y: screen.y - size))
        path.addLine(to: CGPoint(x: screen.x, y: screen.y + size))
        context.stroke(path, with: .color(color), lineWidth: 1.5)
    }

    private func compassLabels(center: CGPoint, radius: CGFloat) -> some View {
        let points: [(String, Double)] = [("N", 0), ("E", 90), ("S", 180), ("W", 270)]
        return ForEach(points, id: \.0) { label, azimuth in
            let point = SkyProjection.project(HorizontalCoordinate(altitude: 0, azimuth: azimuth))
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .position(x: center.x + CGFloat(point.x) * (radius + 14),
                         y: center.y + CGFloat(point.y) * (radius + 14))
        }
    }

    private func handleTap(at location: CGPoint, center: CGPoint, radius: CGFloat) {
        guard radius > 0 else { return }
        let tapUnit = SkyProjection.UnitPoint(x: Double((location.x - center.x) / radius),
                                              y: Double((location.y - center.y) / radius))
        guard let nearest = targetPlacements.min(by: { distance($0.point, tapUnit) < distance($1.point, tapUnit) }),
              distance(nearest.point, tapUnit) < 0.08 else { return }
        state.selectedTargetID = nearest.id
    }

    private func distance(_ a: SkyProjection.UnitPoint, _ b: SkyProjection.UnitPoint) -> Double {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    // MARK: - Time scrubber

    private var timeScrubber: some View {
        let window = plan.chartWindow
        let duration = max(1, window.duration)
        let fraction = Binding<Double>(
            get: { clamp(scrubTime.timeIntervalSince(window.start) / duration, 0, 1) },
            set: { scrubTime = window.start.addingTimeInterval($0 * duration) }
        )
        return VStack(alignment: .leading, spacing: 4) {
            Slider(value: fraction, in: 0...1)
            HStack(spacing: 8) {
                Text(Format.time(scrubTime, in: plan.timeZone))
                    .font(.callout.monospacedDigit().weight(.semibold))
                if let selectedID = state.selectedTargetID,
                   let targetPlan = plan.targets.first(where: { $0.id == selectedID }) {
                    let position = horizontal(of: targetPlan.target.coordinate)
                    Text("\(targetPlan.target.displayName) · \(position.altitude > 0 ? "\(Format.degrees(position.altitude)) \(position.compassPoint)" : "below the horizon")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(Format.time(window.start, in: plan.timeZone))–\(Format.time(window.end, in: plan.timeZone))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if showsMilkyWay {
                let core = galacticCoreHorizontal
                let position = core.altitude > 0
                    ? "\(Int(core.azimuth.rounded()))° \(core.compassPoint) · \(Format.degrees(core.altitude))"
                    : "below the horizon"
                Text("Galactic Core · \(Format.time(scrubTime, in: plan.timeZone)) · \(position)")
                    .font(.caption)
                    .foregroundStyle(Palette.accentWarm)
                    .lineLimit(1)
                Text(galacticCoreSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
