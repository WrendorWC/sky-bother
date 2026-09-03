import SwiftUI

/// The night's sky laid flat: zenith at the centre, horizon at the rim,
/// azimuth around the edge like a compass face — a classic planisphere.
/// This is Version 2.0's spatial foundation: the same targets, the same
/// selection, and now the same scrubbed time as the rest of the night view,
/// just answering "where," not only "when."
struct SkyView: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @EnvironmentObject private var state: AppState
    var plan: NightPlan
    @Binding var scrubTime: Date

    /// Not persisted to Preferences — a per-viewing toggle for one layer,
    /// not a setting worth growing the stored-settings surface for yet.
    @State private var showsMilkyWay = true
    @State private var showsCameraFrame = false
    /// Nil until the user picks something other than their active rig —
    /// previewing equipment here never touches `state.rig` itself.
    @State private var framingRigOverride: Rig?
    @State private var cameraRollDegrees: Double = 0

    private var daysSinceJ2000: Double { scrubTime.daysSinceJ2000 }

    private struct Placement {
        var id: String
        var point: SkyProjection.UnitPoint
        var color: Color
        var isSelected: Bool
        var majorAxisArcminutes: Double
    }

    /// Only targets actually visible from this site right now — above the
    /// *blocked* horizon (trees/houses/hills), not just the geometric one,
    /// since the circle itself is cropped to that same boundary below and
    /// nothing outside it should be selectable either.
    private var targetPlacements: [Placement] {
        plan.targets.compactMap { targetPlan in
            let horizontal = horizontal(of: targetPlan.target.coordinate)
            guard horizontal.altitude > plan.site.horizonAltitude else { return nil }
            return Placement(id: targetPlan.id,
                             point: SkyProjection.project(horizontal),
                             color: Palette.score(targetPlan.score),
                             isSelected: targetPlan.id == state.selectedTargetID,
                             majorAxisArcminutes: targetPlan.target.majorAxisArcminutes)
        }
    }

    private var moonPosition: MoonPosition { Moon.position(daysSinceJ2000: daysSinceJ2000) }

    private var moonHorizontal: HorizontalCoordinate { horizontal(of: moonPosition.coordinate) }

    /// The Moon's real apparent diameter, from its actual distance tonight
    /// rather than the ~0.52° average — small-angle approximation (real
    /// Moon diameter ÷ distance, in radians), plenty accurate at this scale.
    private var moonAngularDiameterDegrees: Double {
        (3474.8 / moonPosition.distanceKilometers) * (180 / Double.pi)
    }

    private var sunAltitude: Double {
        Sun.altitude(daysSinceJ2000: daysSinceJ2000, latitude: plan.site.latitude, longitude: plan.site.longitude)
    }

    private var galacticCoreHorizontal: HorizontalCoordinate {
        horizontal(of: GalacticCoordinates.galacticCenter)
    }

    private var framingRig: Rig { framingRigOverride ?? state.rig }

    /// The selected target, if there is one — tracking it live as time
    /// moves is exactly the point, the same "traced live" idea the main
    /// timeline already uses for whichever target is selected — or dead
    /// centre of the view (the zenith) when nothing is. Deliberately just
    /// these two states, nothing else: an earlier click-to-place override
    /// could survive a rig change or scrub and leave the frame visually
    /// "pinned" wherever it was last clicked, no longer describing anything
    /// live on the sky.
    private var cameraFrameCenter: HorizontalCoordinate {
        if let selectedID = state.selectedTargetID,
           let targetPlan = plan.targets.first(where: { $0.id == selectedID }) {
            return horizontal(of: targetPlan.target.coordinate)
        }
        return HorizontalCoordinate(altitude: 90, azimuth: 0)
    }

    private var selectedTargetPlan: TargetPlan? {
        guard let selectedID = state.selectedTargetID else { return nil }
        return plan.targets.first { $0.id == selectedID }
    }

    /// One sample every 6 minutes across the whole chart window — dense
    /// enough for a smooth arc, cheap enough to recompute on every scrub
    /// (it's only evaluated for the one selected target, not all of them).
    private struct PathSample {
        var point: SkyProjection.UnitPoint
        var isVisible: Bool
        var isZenithRisk: Bool
    }

    private func pathSamples(for targetPlan: TargetPlan) -> [PathSample] {
        stride(from: plan.chartWindow.start.timeIntervalSince1970,
               through: plan.chartWindow.end.timeIntervalSince1970,
               by: 360).map { epoch in
            let date = Date(timeIntervalSince1970: epoch)
            let position = SkyCoordinates.horizontal(targetPlan.target.coordinate,
                                                      daysSinceJ2000: date.daysSinceJ2000,
                                                      latitude: plan.site.latitude,
                                                      longitude: plan.site.longitude)
            let isRisk = targetPlan.zenithRiskWindows.contains { $0.contains(date) }
            return PathSample(point: SkyProjection.project(position),
                              isVisible: position.altitude > plan.site.horizonAltitude,
                              isZenithRisk: isRisk)
        }
    }

    /// The galactic plane's real width, not a stylized line: a closed
    /// ribbon spanning `halfWidthDegrees` of galactic latitude either side
    /// of the plane, sampled every 4° of longitude and projected — broken
    /// into separate runs wherever the centreline dips below the horizon,
    /// rather than one path that would otherwise cut straight through the
    /// ground. Each returned segment is a closed polygon: the "top" edge
    /// (positive latitude) followed by the "bottom" edge reversed, ready to
    /// fill directly.
    private func milkyWayBandSegments(halfWidthDegrees: Double) -> [[SkyProjection.UnitPoint]] {
        var segments: [[SkyProjection.UnitPoint]] = []
        var top: [SkyProjection.UnitPoint] = []
        var bottom: [SkyProjection.UnitPoint] = []
        for longitude in stride(from: 0.0, through: 360.0, by: 4.0) {
            let centerline = horizontal(of: GalacticCoordinates.equatorial(galacticLongitude: longitude, galacticLatitude: 0))
            if centerline.altitude > 0 {
                let topPoint = horizontal(of: GalacticCoordinates.equatorial(galacticLongitude: longitude, galacticLatitude: halfWidthDegrees))
                let bottomPoint = horizontal(of: GalacticCoordinates.equatorial(galacticLongitude: longitude, galacticLatitude: -halfWidthDegrees))
                top.append(SkyProjection.project(topPoint))
                bottom.append(SkyProjection.project(bottomPoint))
            } else if !top.isEmpty {
                segments.append(top + bottom.reversed())
                top = []
                bottom = []
            }
        }
        if !top.isEmpty { segments.append(top + bottom.reversed()) }
        return segments
    }

    /// Two nested bands rather than one — a wide, faint outer glow and a
    /// narrower, brighter core — reads as diffuse structure rather than a
    /// hard-edged shape, the same layering the old fixed-width stroke used,
    /// just now sized to the plane's actual extent instead of flat pixels.
    /// The real photographic Milky Way's width varies a lot along its
    /// length; these are representative constants, not a rigorous model.
    private var milkyWayOuterBand: [[SkyProjection.UnitPoint]] { milkyWayBandSegments(halfWidthDegrees: 8) }
    private var milkyWayInnerBand: [[SkyProjection.UnitPoint]] { milkyWayBandSegments(halfWidthDegrees: 3) }

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
            HStack(spacing: 8) {
                milkyWayToggle
                cameraFrameToggle
            }

            if showsCameraFrame {
                cameraFrameControls
            }

            GeometryReader { geometry in
                let side = min(geometry.size.width, geometry.size.height)
                let radius = side / 2 - 20
                let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

                ZStack {
                    Canvas { context, _ in
                        draw(context: context, center: center, radius: radius)
                    }
                    compassLabels(center: center, radius: visibleRadius(radius))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onEnded { value in handleTap(at: value.location, center: center, radius: radius) }
                )
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 840)
            .frame(maxWidth: .infinity, alignment: .center)

            timeScrubber
        }
    }

    /// `.toggleStyle(.button)` alone doesn't give a clear at-a-glance
    /// on/off read — a filled capsule with a checkmark when active versus
    /// an outline-only one when not is the same on/off language the rest
    /// of the app already uses for filter chips and tags.
    private var milkyWayToggle: some View {
        Button {
            showsMilkyWay.toggle()
        } label: {
            Label("Milky Way", systemImage: showsMilkyWay ? "checkmark.circle.fill" : "circle")
                .font(.scaled(.caption, scale: uiTextScale).weight(.semibold))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(showsMilkyWay ? Palette.accentWarm.opacity(0.22) : Color.clear, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.accentWarm.opacity(showsMilkyWay ? 0.55 : 0.3)))
        .foregroundStyle(showsMilkyWay ? Palette.accentWarm : .secondary)
    }

    private var cameraFrameToggle: some View {
        Button {
            showsCameraFrame.toggle()
        } label: {
            Label("Camera Frame", systemImage: showsCameraFrame ? "checkmark.circle.fill" : "circle")
                .font(.scaled(.caption, scale: uiTextScale).weight(.semibold))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(showsCameraFrame ? Palette.cameraFrame.opacity(0.18) : Color.clear, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.cameraFrame.opacity(showsCameraFrame ? 0.55 : 0.3)))
        .foregroundStyle(showsCameraFrame ? Palette.cameraFrame : .secondary)
    }

    /// A rig picker (previewing equipment without touching `state.rig`) and
    /// a roll slider — direct-manipulation drag-to-rotate on a shape that's
    /// curved post-projection isn't worth the complexity here, so a slider
    /// is the pragmatic middle ground.
    private var cameraFrameControls: some View {
        HStack(spacing: 14) {
            Menu {
                ForEach(Rig.presets) { preset in
                    Button(preset.name) { framingRigOverride = preset }
                }
                if !state.settings.savedRigs.isEmpty {
                    Divider()
                    ForEach(state.settings.savedRigs) { saved in
                        Button(saved.name) { framingRigOverride = saved }
                    }
                }
            } label: {
                Label(framingRig.name, systemImage: "camera.aperture")
                    .font(.scaled(.caption, scale: uiTextScale))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            HStack(spacing: 6) {
                Text("Roll")
                    .font(.scaled(.caption, scale: uiTextScale))
                    .foregroundStyle(.secondary)
                Slider(value: $cameraRollDegrees, in: 0...359)
                    .frame(width: 120)
                Text("\(Int(cameraRollDegrees))°")
                    .font(.scaled(.caption, scale: uiTextScale).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }

            Spacer()
        }
    }

    // MARK: - Drawing

    /// The radius of the sky actually visible from this site — the full
    /// 90° hemisphere shrunk to whatever altitude trees/houses/hills allow,
    /// the same single blocked-altitude value used everywhere else in the
    /// app. This *is* the drawn circle's boundary, not a dimmed overlay on
    /// top of the full hemisphere — anything below it isn't visible from
    /// here, so it isn't shown.
    private func visibleRadius(_ radius: CGFloat) -> CGFloat {
        radius * CGFloat(clamp((90 - plan.site.horizonAltitude) / 90, 0, 1))
    }

    private func draw(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        guard radius > 0 else { return }
        var context = context
        let visible = visibleRadius(radius)
        let visibleRect = CGRect(x: center.x - visible, y: center.y - visible, width: visible * 2, height: visible * 2)
        let horizonPath = Path(ellipseIn: visibleRect)

        context.fill(horizonPath, with: .color(Palette.sky(sunAltitude: sunAltitude)))
        context.stroke(horizonPath, with: .color(Palette.panelBorder), lineWidth: 1)

        // Everything from here down is confined to the visible dome —
        // altitude rings, the Milky Way, targets, the Moon, the camera
        // frame — rather than each needing its own check against the
        // blocked horizon, so a target or a frame that only partially
        // clears it is honestly truncated right at the rim instead of
        // either vanishing entirely or spilling out past a boundary that's
        // supposed to mean "can't see past here."
        context.clip(to: horizonPath)

        for altitude in [30.0, 60.0] {
            let r = radius * CGFloat(clamp((90 - altitude) / 90, 0, 1))
            let ringRect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            context.stroke(Path(ellipseIn: ringRect), with: .color(.white.opacity(0.12)), lineWidth: 1)
        }

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
            let diameter = moonDiameter(radius: radius)
            context.fill(Path(ellipseIn: CGRect(x: screen.x - diameter / 2, y: screen.y - diameter / 2,
                                                width: diameter, height: diameter)),
                        with: .color(Palette.moonlight))
        }

        if let selectedTargetPlan {
            drawSelectedTargetPath(context: context, center: center, radius: radius, targetPlan: selectedTargetPlan)
        }

        for placement in targetPlacements {
            let screen = CGPoint(x: center.x + CGFloat(placement.point.x) * radius,
                                 y: center.y + CGFloat(placement.point.y) * radius)
            let size = targetDotDiameter(majorAxisArcminutes: placement.majorAxisArcminutes,
                                         isSelected: placement.isSelected, radius: radius)
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

        if showsCameraFrame {
            drawCameraFrame(context: context, center: center, radius: radius)
        }
    }

    /// The selected target's track across the whole chart window, so its
    /// dot's motion through the night is visible rather than just its
    /// current position. Split into contiguous runs by visibility and by
    /// zenith-risk state, rather than one path, so the portion where the
    /// target passes close enough to the zenith to risk field rotation or an
    /// alt-az stall gets its own warning-coloured stroke instead of that
    /// risk living only in a warning string elsewhere.
    private func drawSelectedTargetPath(context: GraphicsContext, center: CGPoint, radius: CGFloat, targetPlan: TargetPlan) {
        let samples = pathSamples(for: targetPlan)
        guard samples.count > 1 else { return }

        var runPoints: [CGPoint] = []
        var runIsRisk = false

        func flush() {
            guard runPoints.count > 1 else { runPoints = []; return }
            let color = runIsRisk ? Palette.marginal : Palette.accent
            context.stroke(Path.smoothLine(through: runPoints), with: .color(color.opacity(0.55)), lineWidth: runIsRisk ? 2.5 : 2)
            runPoints = []
        }

        for sample in samples {
            guard sample.isVisible else { flush(); continue }
            if !runPoints.isEmpty && sample.isZenithRisk != runIsRisk { flush() }
            runIsRisk = sample.isZenithRisk
            runPoints.append(screenPoint(for: sample.point, center: center, radius: radius))
        }
        flush()
    }

    /// Only drawn when the whole frame clears the horizon — partially
    /// clipping a frame that dips below it would need real polygon
    /// clipping against the horizon circle, not worth it for a planning
    /// overlay; the readout below explains why nothing's shown instead.
    private func drawCameraFrame(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let footprint = CameraFrame.footprint(centerAltitude: cameraFrameCenter.altitude,
                                              centerAzimuth: cameraFrameCenter.azimuth,
                                              fieldOfViewWidthDegrees: framingRig.fieldOfViewWidthDegrees,
                                              fieldOfViewHeightDegrees: framingRig.fieldOfViewHeightDegrees,
                                              rollDegrees: cameraRollDegrees)
        guard !footprint.isEmpty, footprint.allSatisfy({ $0.altitude > 0 }) else { return }
        let points = footprint.map { screenPoint(for: $0, center: center, radius: radius) }
        var path = Path.smoothLine(through: points)
        path.closeSubpath()
        context.fill(path, with: .color(Palette.cameraFrame.opacity(0.05)))
        context.stroke(path, with: .color(Palette.cameraFrame.opacity(0.85)), lineWidth: 1.5)
    }

    private func screenPoint(for horizontal: HorizontalCoordinate, center: CGPoint, radius: CGFloat) -> CGPoint {
        screenPoint(for: SkyProjection.project(horizontal), center: center, radius: radius)
    }

    private func screenPoint(for unit: SkyProjection.UnitPoint, center: CGPoint, radius: CGFloat) -> CGPoint {
        CGPoint(x: center.x + CGFloat(unit.x) * radius, y: center.y + CGFloat(unit.y) * radius)
    }

    /// Sized to the target's real catalogued extent rather than a flat 6pt
    /// for everything — a fixed dot told you *where* something was but
    /// nothing about *how big*, which is exactly what matters once you're
    /// comparing it against a drawn camera frame. `radius` already encodes
    /// how many points correspond to one degree at this zoom (90° of
    /// altitude spans the whole radius), so the real angular size converts
    /// straight to a screen size. Floored so small objects stay visible and
    /// clickable, and capped so a genuinely huge target (the Veil, M31)
    /// doesn't swallow its neighbours.
    private func targetDotDiameter(majorAxisArcminutes: Double, isSelected: Bool, radius: CGFloat) -> CGFloat {
        let pointsPerDegree = radius / 90
        let realDiameter = CGFloat(majorAxisArcminutes / 60) * pointsPerDegree
        let floor: CGFloat = isSelected ? 10 : 6
        return min(max(realDiameter, floor), 30)
    }

    /// Same real-size-to-screen-size conversion as `targetDotDiameter`, for
    /// the Moon's own true angular size — floored well above its literal
    /// (tiny) size at most zoom levels so it stays a recognisable disc
    /// rather than a near-invisible speck, capped so it can't dominate.
    private func moonDiameter(radius: CGFloat) -> CGFloat {
        let pointsPerDegree = radius / 90
        let realDiameter = CGFloat(moonAngularDiameterDegrees) * pointsPerDegree
        return min(max(realDiameter, 10), 26)
    }

    /// Filled ribbons rather than a stroked line, so the band reads as the
    /// swath of sky it actually is — a wide faint outer glow plus a
    /// narrower brighter core, reading as diffuse structure rather than a
    /// hard edge. The Core itself gets its own warm-accent marker so it
    /// doesn't blend into either band or the target dots.
    private func drawMilkyWay(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        for segment in milkyWayOuterBand where segment.count > 3 {
            let points = segment.map { screenPoint(for: $0, center: center, radius: radius) }
            var path = Path.smoothLine(through: points)
            path.closeSubpath()
            context.fill(path, with: .color(Palette.milkyWay.opacity(0.14)))
        }
        for segment in milkyWayInnerBand where segment.count > 3 {
            let points = segment.map { screenPoint(for: $0, center: center, radius: radius) }
            var path = Path.smoothLine(through: points)
            path.closeSubpath()
            context.fill(path, with: .color(Palette.milkyWay.opacity(0.24)))
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
                .font(.scaled(.caption, scale: uiTextScale).weight(.semibold))
                .foregroundStyle(.secondary)
                .position(x: center.x + CGFloat(point.x) * (radius + 14),
                         y: center.y + CGFloat(point.y) * (radius + 14))
        }
    }

    private func handleTap(at location: CGPoint, center: CGPoint, radius: CGFloat) {
        guard radius > 0 else { return }
        let tapUnit = SkyProjection.UnitPoint(x: Double((location.x - center.x) / radius),
                                              y: Double((location.y - center.y) / radius))
        if let nearest = targetPlacements.min(by: { distance($0.point, tapUnit) < distance($1.point, tapUnit) }),
           distance(nearest.point, tapUnit) < 0.08 {
            state.selectedTargetID = nearest.id
        }
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
                    .font(.scaled(.callout, scale: uiTextScale).monospacedDigit().weight(.semibold))
                if let selectedID = state.selectedTargetID,
                   let targetPlan = plan.targets.first(where: { $0.id == selectedID }) {
                    let position = horizontal(of: targetPlan.target.coordinate)
                    Text("\(targetPlan.target.displayName) · \(position.altitude > 0 ? "\(Format.degrees(position.altitude)) \(position.compassPoint)" : "below the horizon")")
                        .font(.scaled(.caption, scale: uiTextScale))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(Format.time(window.start, in: plan.timeZone))–\(Format.time(window.end, in: plan.timeZone))")
                    .font(.scaled(.caption, scale: uiTextScale))
                    .foregroundStyle(.tertiary)
            }

            if showsMilkyWay {
                let core = galacticCoreHorizontal
                let position = core.altitude > 0
                    ? "\(Int(core.azimuth.rounded()))° \(core.compassPoint) · \(Format.degrees(core.altitude))"
                    : "below the horizon"
                Text("Galactic Core · \(Format.time(scrubTime, in: plan.timeZone)) · \(position)")
                    .font(.scaled(.caption, scale: uiTextScale))
                    .foregroundStyle(Palette.accentWarm)
                    .lineLimit(1)
                Text(galacticCoreSummary)
                    .font(.scaled(.caption, scale: uiTextScale))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if showsCameraFrame {
                let frameCenter = cameraFrameCenter
                let centerText = frameCenter.altitude > 0
                    ? "\(Int(frameCenter.azimuth.rounded()))° \(frameCenter.compassPoint) · \(Format.degrees(frameCenter.altitude))"
                    : "below the horizon"
                Text("Camera Frame · \(framingRig.fieldOfViewSummary) · \(centerText)")
                    .font(.scaled(.caption, scale: uiTextScale))
                    .foregroundStyle(Palette.cameraFrame)
                    .lineLimit(1)
                if showsMilkyWay {
                    Text(coreFitSummary)
                        .font(.scaled(.caption, scale: uiTextScale))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    /// A rough check, not a real point-in-polygon test against the actual
    /// projected (and possibly rolled) rectangle — comparing the Core's
    /// separation from the frame centre against half the field's diagonal.
    /// Worded as "roughly" rather than implying more precision than that.
    private var coreFitSummary: String {
        guard galacticCoreHorizontal.altitude > 0 else { return "The Galactic Core is below the horizon." }
        let diagonal = (framingRig.fieldOfViewWidthDegrees * framingRig.fieldOfViewWidthDegrees
                       + framingRig.fieldOfViewHeightDegrees * framingRig.fieldOfViewHeightDegrees).squareRoot()
        let fits = cameraFrameCenter.separation(to: galacticCoreHorizontal) < diagonal / 2
        return fits ? "The Galactic Core roughly fits in this frame." : "The Galactic Core is outside this frame."
    }
}
