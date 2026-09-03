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
    /// Tonight's suggested schedule, handed down from `NightDetailView`
    /// (which already computes it for its own "Tonight's Plan" section)
    /// rather than recomputed here — same slots, same source of truth,
    /// just also consulted while playback cycles through them.
    var autoPlanSlots: [AutoPlanSlot] = []

    /// Not persisted to Preferences — a per-viewing toggle for one layer,
    /// not a setting worth growing the stored-settings surface for yet.
    @State private var showsMilkyWay = true
    @State private var showsCameraFrame = false
    /// Nil until the user picks something other than their active rig —
    /// previewing equipment here never touches `state.rig` itself.
    @State private var framingRigOverride: Rig?
    @State private var cameraRollDegrees: Double = 0

    @State private var isPlaying = false
    @State private var playbackMode: PlaybackMode = .cycleThroughPlan

    /// A `static let` rather than an instance property: SwiftUI recomputes
    /// `body` (and therefore reinitialises every stored property of this
    /// struct) on every scrub, up to 30 times a second while playing — an
    /// instance-level `Timer.publish(...).autoconnect()` would spin up a
    /// fresh, independently-ticking Combine timer on each of those, not one
    /// steady clock. Scoped to the type instead, it's created once for the
    /// life of the process no matter how often the view itself is rebuilt.
    private static let frameInterval: TimeInterval = 1.0 / 30.0
    private static let playbackTimer = Timer.publish(every: frameInterval, on: .main, in: .common).autoconnect()
    /// Real seconds for a full sunset-to-sunrise playthrough, one flat rate
    /// the whole way — the readable pace an object was already moving at
    /// while in view. A separate, faster rate for the dead twilight outside
    /// Tonight's Plan's own span made object-switching keep pace with the
    /// plan bar better, but the two-rate boundary kept producing exactly the
    /// kind of subtle timing bug it was trying to fix, tick after tick — not
    /// worth it for what's ultimately just a nice-to-have.
    private static let playbackRealSeconds: Double = 25

    private enum PlaybackMode: String, CaseIterable, Identifiable {
        case trackSelected
        case cycleThroughPlan

        var id: String { rawValue }

        var label: String {
            switch self {
            case .trackSelected: return "Track Selected"
            case .cycleThroughPlan: return "Cycle Plan"
            }
        }
    }

    /// Re-picks a sensible default every time the selection itself changes,
    /// rather than leaving whichever mode was last set to quietly stop
    /// making sense: something picked from outside tonight's plan has
    /// nothing to cycle through *to*, so playback would just ignore it the
    /// next time it started, jumping back to a plan object regardless. A
    /// plan object — or nothing at all, the common starting case — has no
    /// such mismatch, so cycling stays the default. Still just a default:
    /// the chips below remain free to override it until the next change.
    private func updatePlaybackModeForSelection() {
        guard let selectedID = state.selectedTargetID else {
            playbackMode = .cycleThroughPlan
            return
        }
        playbackMode = autoPlanSlots.contains { $0.targetPlan.id == selectedID } ? .cycleThroughPlan : .trackSelected
    }

    private var daysSinceJ2000: Double { scrubTime.daysSinceJ2000 }

    /// Wall-clock time and `scrubTime` at the moment Play was last pressed —
    /// what every tick projects forward from. See `advancePlayback` for why
    /// this replaced accumulating a per-tick delta.
    @State private var playbackAnchorWallClock: Date?
    @State private var playbackAnchorScrubTime: Date?

    /// Ticking `scrubTime` forward by a fixed per-tick delta each time this
    /// fires seemed straightforward, but it's an accumulator — any error
    /// compounds and never self-corrects. Projecting `scrubTime` directly
    /// from *elapsed real time since Play was pressed* instead has no
    /// accumulator to drift: every tick recomputes the exact answer for
    /// however much real time has actually passed, so a slow frame, a late
    /// timer firing, or anything else that makes ticks land unevenly just
    /// changes how many recomputations happen — never the answer itself.
    private func advancePlayback() {
        guard isPlaying, let anchorWallClock = playbackAnchorWallClock, let anchorScrubTime = playbackAnchorScrubTime else { return }
        let window = plan.chartWindow
        guard window.duration > 0 else {
            isPlaying = false
            return
        }
        let elapsedReal = Date().timeIntervalSince(anchorWallClock)
        let simulatedSecondsPerRealSecond = window.duration / Self.playbackRealSeconds
        let projected = anchorScrubTime.addingTimeInterval(elapsedReal * simulatedSecondsPerRealSecond)
        if projected >= window.end {
            scrubTime = window.end
            isPlaying = false
        } else {
            scrubTime = projected
        }
        if playbackMode == .cycleThroughPlan {
            syncSelectionToPlayback()
        }
    }

    /// Slots never overlap (that's `AutoPlanner`'s whole job), so at most one
    /// ever contains `scrubTime` — nothing to disambiguate between.
    /// Consecutive slots aren't always back-to-back — a stretch between two
    /// scheduled targets that nothing's own usable window actually covers
    /// reads as a real gap, not a bug. Waiting for the *next* slot's window
    /// to open before switching left the previous target selected through
    /// that whole gap, which on the Tonight's Plan strip (spanning the same
    /// timeline) looked like the switch was firing late — sometimes right on
    /// the boundary, sometimes only once the next slot's own span began.
    /// Switching the instant the current slot's window *ends* instead —
    /// to whatever's coming up next, not only what's already open — keeps
    /// the two in step regardless of whether the slots actually touch.
    private func syncSelectionToPlayback() {
        let sorted = autoPlanSlots.sorted { $0.window.start < $1.window.start }
        guard let first = sorted.first, let last = sorted.last,
              scrubTime >= first.window.start, scrubTime < last.window.end else { return }
        guard let upcoming = sorted.first(where: { $0.window.end > scrubTime }) else { return }
        if state.selectedTargetID != upcoming.targetPlan.id {
            state.selectedTargetID = upcoming.targetPlan.id
        }
    }

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
    /// nothing outside it should be selectable either. Also, as of this
    /// filter, only targets that actually clear the main list's own
    /// minimum-score/type/search filters — this used to draw every
    /// catalogue object above the horizon regardless, which on a typical
    /// night meant several hundred dots, most of them below the score
    /// you'd bothered to set as a floor. The selected target is the one
    /// exception: it never simply vanishes just because it doesn't clear
    /// the filter, since you're looking right at it.
    private var targetPlacements: [Placement] {
        let visible = state.visibleTargets(for: plan)
        let selectedButFiltered = plan.targets.first { candidate in
            candidate.id == state.selectedTargetID && !visible.contains { $0.id == candidate.id }
        }
        // Worst-scoring first, so a better/more relevant target always ends
        // up drawn on top when two dots genuinely overlap on screen, rather
        // than z-order being arbitrary catalogue order.
        let candidates = (selectedButFiltered.map { visible + [$0] } ?? visible)
            .sorted { $0.score < $1.score }

        return candidates.compactMap { targetPlan in
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

    /// This view draws the whole sky as a flat disc with the zenith at its
    /// exact centre — azimuth becomes angle around that centre, so *every*
    /// azimuth collapses onto the same point right at the zenith. A target
    /// passing near or through it genuinely does swing azimuth by close to
    /// 180° (confirmed numerically, not a bug: real geometry, the same
    /// reason a straight line through the North Pole looks like it reverses
    /// on a flat polar map). The frame's actual 3D orientation never
    /// wavers — only the disc renders it as an apparent flip — so rather
    /// than show that confusing artifact, the frame just isn't drawn this
    /// close in, the same call already made for dipping below the horizon.
    private static let nearZenithThreshold: Double = 88

    private var isCameraFrameTooCloseToZenith: Bool {
        cameraFrameCenter.altitude > Self.nearZenithThreshold
    }

    private var cameraFrameCenterText: String {
        let frameCenter = cameraFrameCenter
        if frameCenter.altitude <= 0 {
            return "below the horizon"
        } else if isCameraFrameTooCloseToZenith {
            return "too near the zenith to draw meaningfully on this flat view"
        } else {
            return "\(Int(frameCenter.azimuth.rounded()))° \(frameCenter.compassPoint) · \(Format.degrees(frameCenter.altitude))"
        }
    }

    private var selectedTargetPlan: TargetPlan? {
        guard let selectedID = state.selectedTargetID else { return nil }
        return plan.targets.first { $0.id == selectedID }
    }

    /// One sample every 6 minutes across a full day centred on tonight —
    /// dense enough for a smooth arc, cheap enough to recompute on every
    /// scrub (it's only evaluated for the one selected target, not all of
    /// them). A fixed-coordinate target genuinely traces one full closed
    /// loop around the pole every day; sampling only the plotted dusk-to-
    /// dawn window used to cut that loop off at both ends, so the path
    /// looked like it simply began and ended at nightfall rather than the
    /// same real circle the target is on all day, most of it just not up
    /// (or not dark) right now.
    private struct PathSample {
        var point: SkyProjection.UnitPoint
        var isVisible: Bool
        var isZenithRisk: Bool
    }

    private func pathSamples(for targetPlan: TargetPlan) -> [PathSample] {
        let center = plan.chartWindow.midpoint
        let start = center.addingTimeInterval(-12 * 3600)
        let end = center.addingTimeInterval(12 * 3600)
        return stride(from: start.timeIntervalSince1970,
               through: end.timeIntervalSince1970,
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
        .onAppear { updatePlaybackModeForSelection() }
        .onChange(of: state.selectedTargetID) { _, _ in updatePlaybackModeForSelection() }
        .onDisappear { isPlaying = false }
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
                                         isSelected: placement.isSelected)
            let color = placement.isSelected ? Palette.accent : placement.color
            // Unselected dots get real transparency, not just a slightly
            // muted fill — where two genuinely overlap (the Milky Way band
            // is the worst of it) the overlap reads as visibly denser
            // rather than one dot silently hiding behind another. Full
            // opacity for the selected one: it already carries a halo and
            // the one accent colour, and burying it under that same
            // transparency would undercut the point of both.
            let opacity = placement.isSelected ? 1.0 : 0.72
            context.fill(Path(ellipseIn: CGRect(x: screen.x - size / 2, y: screen.y - size / 2, width: size, height: size)),
                        with: .color(color.opacity(opacity)))
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
    /// Above the horizon and in zenith risk, above the horizon and clear of
    /// it, or below the horizon entirely — the loop is drawn in full either
    /// way, this only decides how boldly each stretch of it reads, so the
    /// below-horizon portion still completes the ring rather than vanishing.
    private enum PathStyle: Equatable {
        case zenithRisk
        case aboveHorizon
        case belowHorizon

        init(_ sample: PathSample) {
            if !sample.isVisible { self = .belowHorizon }
            else { self = sample.isZenithRisk ? .zenithRisk : .aboveHorizon }
        }

        var color: Color {
            switch self {
            case .zenithRisk: return Palette.marginal.opacity(0.55)
            case .aboveHorizon: return Palette.accent.opacity(0.55)
            case .belowHorizon: return Palette.accent.opacity(0.16)
            }
        }

        var lineWidth: CGFloat {
            switch self {
            case .zenithRisk: return 2.5
            case .aboveHorizon: return 2
            case .belowHorizon: return 1.25
            }
        }
    }

    private func drawSelectedTargetPath(context: GraphicsContext, center: CGPoint, radius: CGFloat, targetPlan: TargetPlan) {
        let samples = pathSamples(for: targetPlan)
        guard samples.count > 1 else { return }

        var runPoints: [CGPoint] = []
        var runStyle: PathStyle = .belowHorizon

        func flush() {
            guard runPoints.count > 1 else { runPoints = []; return }
            context.stroke(Path.smoothLine(through: runPoints), with: .color(runStyle.color), lineWidth: runStyle.lineWidth)
            runPoints = []
        }

        for sample in samples {
            let style = PathStyle(sample)
            if !runPoints.isEmpty && style != runStyle { flush() }
            runStyle = style
            runPoints.append(screenPoint(for: sample.point, center: center, radius: radius))
        }
        flush()
    }

    /// Not drawn when the whole frame doesn't clear the horizon (partially
    /// clipping one that dips below it would need real polygon clipping
    /// against the horizon circle, not worth it for a planning overlay) or
    /// when it's too close to the zenith to draw meaningfully on this flat
    /// projection (see `isCameraFrameTooCloseToZenith`) — the readout below
    /// explains which, when nothing's shown.
    private func drawCameraFrame(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        // An alt-az mount holds the frame's "up" fixed to the zenith, which
        // is exactly why it visibly rotates relative to the stars over a
        // session — real field rotation, not a rendering quirk. A polar-
        // aligned equatorial mount holds up fixed to the celestial pole
        // instead, so its frame keeps one orientation relative to the star
        // field all night; this is the one thing that actually needs to
        // know which kind of mount is pointing it.
        let upReference: CameraFrame.UpReference = framingRig.mountType.rotatesField
            ? .zenith
            : .celestialPole(latitude: state.site.latitude)
        let footprint = CameraFrame.footprint(centerAltitude: cameraFrameCenter.altitude,
                                              centerAzimuth: cameraFrameCenter.azimuth,
                                              fieldOfViewWidthDegrees: framingRig.fieldOfViewWidthDegrees,
                                              fieldOfViewHeightDegrees: framingRig.fieldOfViewHeightDegrees,
                                              rollDegrees: cameraRollDegrees,
                                              upReference: upReference)
        guard !isCameraFrameTooCloseToZenith,
              !footprint.isEmpty, footprint.allSatisfy({ $0.altitude > 0 }) else { return }
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
    /// Real catalogue sizes span more than four orders of magnitude — 0.03′
    /// to 645′, and the middle 90% alone still runs from about 1′ to 14′ —
    /// so a linear points-per-arcminute scale left nearly everything but a
    /// handful of giant showpieces pinned to the same floor size; only M31,
    /// the Veil and a few others ever cleared it. Logarithmic instead:
    /// clamp into the range most of the catalogue actually falls in and
    /// interpolate log-linearly across it, so a 2′ galaxy reads visibly
    /// smaller than an 8′ one instead of both just being "the minimum dot."
    /// Fixed point sizes rather than scaled by the view's own radius —
    /// deliberately decoupled from true physical scale, since physical
    /// scale is exactly what caused the uniform-dot problem.
    private func targetDotDiameter(majorAxisArcminutes: Double, isSelected: Bool) -> CGFloat {
        let minArcmin = 0.5
        let maxArcmin = 200.0
        let minDiameter: CGFloat = 4
        let maxDiameter: CGFloat = 22

        let clamped = clamp(majorAxisArcminutes, minArcmin, maxArcmin)
        let t = (log(clamped) - log(minArcmin)) / (log(maxArcmin) - log(minArcmin))
        let diameter = (minDiameter + CGFloat(t) * (maxDiameter - minDiameter)) * uiTextScale
        return isSelected ? max(diameter, 10 * uiTextScale) : diameter
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
            // A deliberate pick overrides whatever playback would have
            // chosen next — same as dragging the scrubber by hand.
            isPlaying = false
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
            set: { newFraction in
                isPlaying = false
                scrubTime = window.start.addingTimeInterval(newFraction * duration)
            }
        )
        return VStack(alignment: .leading, spacing: 4) {
            // `scrubTrack` on its own row, full width: sharing a row with a
            // `GeometryReader`-based sibling was leaving the button no space
            // at all, not just crowding it — worth its own row rather than
            // fighting that layout further.
            scrubTrack(fraction: fraction)
            HStack(spacing: 8) {
                playPauseButton
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
                if !autoPlanSlots.isEmpty {
                    playbackModeToggle
                }
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
                Text("Camera Frame · \(framingRig.fieldOfViewSummary) · \(cameraFrameCenterText)")
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
        .onReceive(Self.playbackTimer) { _ in advancePlayback() }
    }

    /// A plain `Slider` looked right but didn't line up with the same
    /// scrubbed time's marker on the main timeline above — `NSSlider`'s
    /// thumb has its own built-in end padding, so a given fraction lands at
    /// a different pixel than the timeline's marker, which maps fraction to
    /// position with nothing but `fraction * width` (see `TimeAxis.x`). This
    /// draws the same bare linear mapping by hand instead, so the same
    /// `scrubTime` reads as visually the same position in both places.
    private func scrubTrack(fraction: Binding<Double>) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            // The line/fill use `x` unclamped — that's the exact mapping
            // the top graph's marker uses, and it's the whole point of this
            // view over a plain Slider. But the thumb is a wide (13pt) disc,
            // not a 1.5pt line: centering it on an unclamped `x` at either
            // extreme lets half of it bleed outside the track entirely — at
            // the very start of a night (the default position now), right
            // into the play button sitting next to it, the two same-colour
            // circles overlapping into what read as one missing button.
            let x = CGFloat(fraction.wrappedValue) * width
            let thumbX = min(max(x, 6.5), max(6.5, width - 6.5))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 4)
                Capsule()
                    .fill(Palette.accent.opacity(0.85))
                    .frame(width: max(4, x), height: 4)
                Circle()
                    .fill(Palette.accent)
                    .frame(width: 13, height: 13)
                    .offset(x: thumbX - 6.5)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        fraction.wrappedValue = clamp(Double(value.location.x / max(1, width)), 0, 1)
                    }
            )
        }
        .frame(height: 20)
    }

    private var playPauseButton: some View {
        Button {
            if isPlaying {
                isPlaying = false
            } else {
                // Starting from outside tonight's own window at all — not
                // just past its end — snaps back to the start first. The
                // fraction below is clamped to 0...1 against this window, so
                // a `scrubTime` sitting outside it (run off the end, or left
                // over from whatever night was last open) would otherwise
                // read back as a slider pinned at one end while the actual
                // clock quietly ticks toward — or already past — the window
                // it's supposedly scrubbing.
                if !plan.chartWindow.contains(scrubTime) {
                    scrubTime = plan.chartWindow.start
                }
                // Every tick projects forward from this pair rather than
                // from wherever the last tick happened to land, so it has
                // to be recaptured on each fresh start — resuming after a
                // pause is exactly that, a fresh start from the paused spot.
                playbackAnchorWallClock = Date()
                playbackAnchorScrubTime = scrubTime
                isPlaying = true
            }
        } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.scaled(.caption, scale: uiTextScale).weight(.semibold))
                .frame(width: 22, height: 22)
                // Without this, only the glyph's own opaque pixels are
                // tappable — the surrounding filled circle is purely a
                // `.background`, not part of the button's hit-test region,
                // so most of a visually "big enough" button did nothing.
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(Palette.accent, in: Circle())
        // The Slider beside it is the one genuinely flexible view in this
        // row — without this, a narrow window can let the HStack compress
        // this fixed-size button down toward nothing to give the slider
        // more room, rather than shrinking the slider (which has plenty of
        // room to give) first.
        .fixedSize()
    }

    /// "Track Selected" holds the current selection fixed while time scrubs;
    /// "Cycle Plan" hands selection off from one planned target to the next
    /// as playback crosses into each slot's own window, so the detail pane
    /// follows the plan rather than staring at one object all night.
    private var playbackModeToggle: some View {
        HStack(spacing: 6) {
            playbackModeChip(.trackSelected)
            playbackModeChip(.cycleThroughPlan)
        }
    }

    private func playbackModeChip(_ mode: PlaybackMode) -> some View {
        let isActive = playbackMode == mode
        return Button {
            playbackMode = mode
        } label: {
            Text(mode.label)
                .font(.scaled(.caption2, scale: uiTextScale).weight(.semibold))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(isActive ? Palette.accent.opacity(0.22) : Color.clear, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.accent.opacity(isActive ? 0.55 : 0.3)))
        .foregroundStyle(isActive ? Palette.accent : .secondary)
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
