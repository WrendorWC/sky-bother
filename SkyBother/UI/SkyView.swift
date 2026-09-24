import SwiftUI

/// The night's sky laid flat: zenith at the centre, horizon at the rim,
/// azimuth around the edge like a compass face — a classic planisphere.
/// This is Version 2.0's spatial foundation: the same targets, the same
/// selection, and now the same scrubbed time as the rest of the night view,
/// just answering "where," not only "when."
struct SkyView: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var state: AppState
    var plan: NightPlan
    @Binding var scrubTime: Date
    /// Owned by the screen around this view, so its own controls — Jump to
    /// best window, a click on a plan block — can stop playback before
    /// moving the clock rather than having playback drag it straight back.
    @Binding var isPlaying: Bool
    /// The night's plan as it is shown everywhere else: a Manual plan, the
    /// suggestion, or the planner's unsaved draft. Read only — Sky View
    /// never changes it.
    var planSegments: [PlanSegment] = []
    /// Off for Home's preview: just the dome, no controls, no playback.
    var showsControls = true
    /// Full-size labels, brackets and compass without the controls — the
    /// live dome in Session View. Implied by `showsControls`.
    var showsLabels: Bool? = nil
    private var labelled: Bool { showsLabels ?? showsControls }

    /// Nil until the user picks something other than their active rig —
    /// previewing equipment here never touches `state.rig` itself.
    @State private var framingRigOverride: Rig?
    @State private var cameraRollDegrees: Double = 0

    @State private var playbackMode: PlaybackMode = .cycleThroughPlan
    /// The target being faded out after the selection moved on, and when
    /// that started — so one target dissolves into the next instead of
    /// jumping, most noticeably as playback hands over between plan blocks.
    @State private var fadingOut: TargetPlan?
    @State private var fadeStart: Date = .distantPast
    /// True while any fade — in, out or across — is running.
    @State private var isFading = false
    private static let fadeDuration: TimeInterval = 0.7

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
            case .trackSelected: return "Stay on selected target"
            case .cycleThroughPlan: return "Follow planned targets"
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
        playbackMode = planSegments.contains { $0.targetID == selectedID } ? .cycleThroughPlan : .trackSelected
    }

    private var daysSinceJ2000: Double { scrubTime.daysSinceJ2000 }

    /// Wall-clock time and `scrubTime` at the moment Play was last pressed —
    /// what every tick projects forward from. See `advancePlayback` for why
    /// this replaced accumulating a per-tick delta.
    /// Following the real clock rather than the night: the dome turns as
    /// you watch. Any other move in time leaves it, landing where you moved.
    @State private var isFollowingNow = false
    /// Where the night view was before Now, to go back to.
    @State private var timeBeforeNow: Date?
    private static let nowTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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
        var projected = anchorScrubTime.addingTimeInterval(elapsedReal * simulatedSecondsPerRealSecond)
        // With Reduce Motion on, the sky steps a quarter of an hour at a
        // time instead of gliding.
        if reduceMotion {
            let step: TimeInterval = 15 * 60
            projected = Date(timeIntervalSince1970: (projected.timeIntervalSince1970 / step).rounded(.down) * step)
            if projected == scrubTime { return }
        }
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
        let ordered = planSegments.chronological
        guard let first = ordered.first, scrubTime >= first.window.start else { return }
        if let running = ordered.first(where: { $0.window.contains(scrubTime) }) {
            if state.selectedTargetID != running.targetID {
                state.selectedTargetID = running.targetID
            }
        } else if let selected = state.selectedTargetID,
                  planSegments.contains(where: { $0.targetID == selected }) {
            // In a gap between blocks, or past the last one: nothing is
            // being shot, so the target fades away until the next block.
            state.selectedTargetID = nil
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

    private var sunHorizontal: HorizontalCoordinate { horizontal(of: Sun.position(daysSinceJ2000: daysSinceJ2000)) }

    private var framingRig: Rig { framingRigOverride ?? state.rig }

    /// Where the selected target is right now — tracking it live as time
    /// moves is exactly the point, the same "traced live" idea the main
    /// timeline already uses. Nil with nothing selected: the dome is only
    /// ever about the active target, so there is no frame to draw without one.
    private var cameraFrameCenter: HorizontalCoordinate? {
        selectedTargetPlan.map { horizontal(of: $0.target.coordinate) }
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
        (cameraFrameCenter?.altitude ?? 0) > Self.nearZenithThreshold
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
                              isVisible: position.altitude > plan.site.blockedAltitude(azimuth: position.azimuth),
                              isZenithRisk: isRisk)
        }
    }

    private func horizontal(of coordinate: EquatorialCoordinate) -> HorizontalCoordinate {
        SkyCoordinates.horizontal(coordinate,
                                  daysSinceJ2000: daysSinceJ2000,
                                  latitude: plan.site.latitude,
                                  longitude: plan.site.longitude)
    }

    /// Room outside the drawn rim for the N/E/S/W labels, which sit 14pt past
    /// it and are centred on that point, so about half a line of text again.
    private static let compassLabelInset: CGFloat = 26

    /// The scale and centre that make the visible sky as big as the space
    /// allows. `radius` is that of a *full* 90° hemisphere — the projection's
    /// scale, which every drawing helper here wants.
    ///
    /// What gets fitted is the visible shape itself, not the full hemisphere:
    /// sky below your blocked horizon is never drawn, so sizing for it left
    /// dead margin — worst on the side with the tallest trees, since the
    /// zenith was always put in the middle. Fitting the shape's own bounds
    /// and centring those instead lets a heavily blocked sky fill the view,
    /// with the zenith wherever the shape puts it.
    private func domeFit(in size: CGSize) -> (radius: CGFloat, center: CGPoint) {
        let inset = labelled ? SkyView.compassLabelInset : 2
        let bounds = visibleShapeBounds
        let availableWidth = max(size.width - inset * 2, 1)
        let availableHeight = max(size.height - inset * 2, 1)
        let radius = max(1, min(availableWidth / max(bounds.width, 0.01),
                                availableHeight / max(bounds.height, 0.01)))
        let center = CGPoint(x: size.width / 2 - bounds.midX * radius,
                             y: size.height / 2 - bounds.midY * radius)
        return (radius, center)
    }

    /// The visible sky's outline in projection units — a full hemisphere is
    /// the unit circle — traced the same way `horizonPath` draws it.
    private var visibleShapeBounds: CGRect {
        var minX = CGFloat.infinity, maxX = -CGFloat.infinity
        var minY = CGFloat.infinity, maxY = -CGFloat.infinity
        for sector in Site.horizonDirections.indices {
            let sectorAzimuth = Double(sector) * 45
            let reach = visibleRadius(1, azimuth: sectorAzimuth)
            for step in 0...9 {
                let azimuth = sectorAzimuth - 22.5 + Double(step) * 5
                let point = SkyProjection.project(HorizontalCoordinate(altitude: 0, azimuth: azimuth))
                let x = CGFloat(point.x) * reach, y = CGFloat(point.y) * reach
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard minX.isFinite, maxX > minX, maxY > minY else { return CGRect(x: -1, y: -1, width: 2, height: 2) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsControls { cameraFrameControls }

            GeometryReader { geometry in
                let fit = domeFit(in: geometry.size)
                let radius = fit.radius
                let center = fit.center

                ZStack {
                    // Ticks only while a fade is running.
                    TimelineView(.animation(paused: !isFading)) { timeline in
                        Canvas { context, _ in
                            draw(context: context, center: center, radius: radius, now: timeline.date)
                        }
                    }
                    if labelled { compassLabels(center: center, radius: radius) }
                }
            }
            // All the room there is, in both directions: `domeFit` shapes
            // the sky to it, so no square box is imposed here.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: showsControls ? 320 : 0)

            if showsControls { timeScrubber }
        }
        .onAppear { updatePlaybackModeForSelection() }
        .onChange(of: state.selectedTargetID) { old, _ in
            updatePlaybackModeForSelection()
            startFade(from: old)
        }
        .onDisappear { isPlaying = false }
    }

    /// A rig picker (previewing equipment without touching `state.rig`) and
    /// a roll slider — direct-manipulation drag-to-rotate on a shape that's
    /// curved post-projection isn't worth the complexity here, so a slider
    /// is the pragmatic middle ground.
    private var cameraFrameControls: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                    Label("Frame: \(framingRig.name)", systemImage: "camera.aperture")
                        .font(.scaled(.callout, scale: uiTextScale))
                }
                .scaledMenuStyle(uiTextScale)
                .help("Preview another rig's frame")

                Text(framingRig.fieldOfViewSummary)
                    .font(.scaled(.callout, scale: uiTextScale).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                // The Frame menu's icon, hidden, so this text starts exactly
                // where "Frame:" does at any UI scale.
                Label {
                    Text("Camera roll")
                } icon: {
                    Image(systemName: "camera.aperture").hidden()
                }
                .font(.scaled(.callout, scale: uiTextScale))
                .foregroundStyle(.secondary)
                Slider(value: $cameraRollDegrees, in: 0...359, step: 1)
                    .frame(width: 120)
                    .accessibilityLabel("Camera roll")
                    .accessibilityValue("\(Int(cameraRollDegrees)) degrees")
                // A stepper as well as the slider: exact degrees, and arrow
                // keys once it has focus.
                Stepper(value: $cameraRollDegrees, in: 0...359, step: 1) {
                    Text("\(Int(cameraRollDegrees))°")
                        .font(.scaled(.callout, scale: uiTextScale).monospacedDigit())
                        .frame(minWidth: 38, alignment: .trailing)
                }
                .accessibilityLabel("Camera roll, one degree steps")
            }

            if plan.hasWeather {
                HStack(spacing: 6) {
                    Toggle("Show clouds", isOn: $state.preferences.showsClouds)
                        .toggleStyle(.checkbox)
                    Text("Representative: does not show exact cloud location")
                        .foregroundStyle(.tertiary)
                }
                .font(.scaled(.callout, scale: uiTextScale))
                .help("The amount of each cloud layer comes from the forecast for the time shown, drifting with its wind. The shapes are invented.")
            }
        }
    }

    // MARK: - Drawing

    /// The radius of the sky actually visible from this site looking one
    /// particular way — the full 90° hemisphere shrunk to whatever altitude
    /// trees/houses/hills allow in that direction, the same blocked-altitude
    /// values used everywhere else in the app. This *is* the drawn shape's
    /// boundary, not a dimmed overlay on top of the full hemisphere —
    /// anything below it isn't visible from here, so it isn't shown.
    private func visibleRadius(_ radius: CGFloat, azimuth: Double) -> CGFloat {
        radius * CGFloat(clamp((90 - plan.site.blockedAltitude(azimuth: azimuth)) / 90, 0, 1))
    }

    /// The rim of the visible sky. A circle when the horizon is flat; when
    /// one direction is blocked worse than the rest, the sector that direction
    /// owns steps inward, so the tree to the south reads as a bite taken out
    /// of the dome rather than as the whole sky being smaller.
    ///
    /// Each 45° sector is sampled rather than drawn as a true arc: the flat
    /// case then costs a 72-sided polygon whose deviation from a circle is a
    /// fraction of a pixel at any size this is drawn at, and there is one code
    /// path instead of two.
    private func horizonPath(center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        for sector in Site.horizonDirections.indices {
            let sectorAzimuth = Double(sector) * 45
            let sectorRadius = visibleRadius(radius, azimuth: sectorAzimuth)
            for step in 0...9 {
                let azimuth = sectorAzimuth - 22.5 + Double(step) * 5
                let point = SkyProjection.project(HorizontalCoordinate(altitude: 0, azimuth: azimuth))
                let screen = CGPoint(x: center.x + CGFloat(point.x) * sectorRadius,
                                     y: center.y + CGFloat(point.y) * sectorRadius)
                if path.isEmpty { path.move(to: screen) } else { path.addLine(to: screen) }
            }
        }
        path.closeSubpath()
        return path
    }

    private func draw(context: GraphicsContext, center: CGPoint, radius: CGFloat, now: Date = Date()) {
        guard radius > 0 else { return }
        var context = context
        let rim = horizonPath(center: center, radius: radius)

        context.fill(rim, with: skyShading(center: center, radius: radius))
        context.stroke(rim, with: .color(Palette.panelBorder), lineWidth: 1)

        // Everything from here down is confined to the visible dome, so a
        // path or a frame that only partially clears the blocked horizon is
        // honestly truncated right at the rim instead of spilling out past a
        // boundary that's supposed to mean "can't see past here."
        context.clip(to: rim)

        drawSun(context: context, center: center, radius: radius)

        for altitude in [30.0, 60.0] {
            let r = radius * CGFloat(clamp((90 - altitude) / 90, 0, 1))
            let ringRect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            context.stroke(Path(ellipseIn: ringRect), with: .color(.white.opacity(0.08)), lineWidth: 1)
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

        // The outgoing target fades as the new one comes up, over the same
        // stretch, so the two cross rather than one popping over the other.
        let progress = isFading ? min(1, max(0, now.timeIntervalSince(fadeStart) / Self.fadeDuration)) : 1
        if let fadingOut, progress < 1, fadingOut.id != selectedTargetPlan?.id {
            var outgoing = context
            outgoing.opacity = 1 - progress
            drawSelectedTargetPath(context: outgoing, center: center, radius: radius, targetPlan: fadingOut)
            drawActiveTarget(context: outgoing, center: center, radius: radius, targetPlan: fadingOut)
        }
        if let selectedTargetPlan {
            var incoming = context
            incoming.opacity = progress
            drawSelectedTargetPath(context: incoming, center: center, radius: radius, targetPlan: selectedTargetPlan)
            drawActiveTarget(context: incoming, center: center, radius: radius, targetPlan: selectedTargetPlan)
        }
    }

    /// Fades between the old selection and the new one: across when both
    /// exist, in from nothing, or out to nothing. With Reduce Motion on, the
    /// switch stays instant.
    private func startFade(from oldID: String?) {
        guard !reduceMotion, labelled else {
            fadingOut = nil
            isFading = false
            return
        }
        fadingOut = oldID.flatMap { id in plan.targets.first { $0.id == id } }
        let started = Date()
        fadeStart = started
        isFading = true
        Task {
            try? await Task.sleep(nanoseconds: UInt64(Self.fadeDuration * 1_000_000_000))
            // Only if no newer switch has started its own fade meanwhile.
            if fadeStart == started {
                fadingOut = nil
                isFading = false
            }
        }
    }

    /// The whole-sky map, bundled rather than fetched: the dome should never
    /// be blank, and it is one fixed picture that nothing ever changes.
    static let starMap: Image? = Bundle.main.url(forResource: "StarMap", withExtension: "jpg")
        .flatMap { NSImage(contentsOf: $0) }
        .map { Image(nsImage: $0) }

    /// The real sky for this moment, from `SkyDome.metal`, or the old flat
    /// twilight colour if the map is somehow missing from the bundle.
    private func skyShading(center: CGPoint, radius: CGFloat) -> GraphicsContext.Shading {
        guard let starMap = Self.starMap else { return .color(Palette.sky(sunAltitude: sunAltitude)) }
        let sun = sunHorizontal
        let moon = moonHorizontal
        let lst = SkyCoordinates.localSiderealTime(daysSinceJ2000: daysSinceJ2000, longitude: plan.site.longitude)
        return .shader(ShaderLibrary.skyDome(
            .image(starMap),
            .float2(center),
            .float(radius),
            .float(plan.site.latitude),
            .float(lst),
            .float4(sun.altitude, sun.azimuth, 0, 0),
            .float4(moon.altitude, moon.azimuth, Moon.illuminatedFraction(daysSinceJ2000: daysSinceJ2000), 0),
            .color(Palette.sky(sunAltitude: sun.altitude)),
            .color(Palette.sky(sunAltitude: -90)),
            .float(1.3),
            .float4(clouds.low, clouds.mid, clouds.high, clouds.shown ? 1 : 0),
            .float2(clouds.driftEast, clouds.driftNorth)))
    }

    /// The forecast's cloud at this moment, for the dome's representative
    /// clouds: each layer's cover, and how far the wind has carried them
    /// since the night began, so they drift as time moves.
    private var clouds: (low: Float, mid: Float, high: Float, shown: Bool, driftEast: Float, driftNorth: Float) {
        guard state.preferences.showsClouds, plan.hasWeather,
              let weather = state.forecast.interpolated(at: scrubTime) else {
            return (0, 0, 0, false, 0, 0)
        }
        let drift = cloudDrift(to: scrubTime)
        return (Float(weather.cloudCoverLow / 100), Float(weather.cloudCoverMid / 100),
                Float(weather.cloudCoverHigh / 100), true, Float(drift.east), Float(drift.north))
    }

    /// How far the wind has carried the clouds between the start of the night
    /// and `time`, in km east and north, added up a few minutes at a time.
    ///
    /// Summed rather than "this wind times the hours so far": that swung every
    /// cloud across the sky whenever the wind changed — at half past each
    /// hour, where the forecast's direction flips to the next hour's.
    private func cloudDrift(to time: Date) -> (east: Double, north: Double) {
        let start = plan.chartWindow.start
        let total = time.timeIntervalSince(start)
        guard abs(total) > 1 else { return (0, 0) }
        let steps = max(1, Int(abs(total) / 600))
        let dt = total / Double(steps)
        var east = 0.0, north = 0.0
        for step in 0..<steps {
            let wind = windVector(at: start.addingTimeInterval(dt * (Double(step) + 0.5)))
            east += wind.east * dt / 3600
            north += wind.north * dt / 3600
        }
        return (east, north)
    }

    /// The wind the clouds move with, km/h east and north, blended smoothly
    /// between forecast hours as arrows, so it never jumps.
    private func windVector(at time: Date) -> (east: Double, north: Double) {
        func vector(_ hour: HourlyWeather) -> (east: Double, north: Double) {
            // Meteorological direction is where the wind comes *from*.
            let toward = ((hour.windDirectionDegrees ?? 270) + 180) * .pi / 180
            return (sin(toward) * hour.windSpeedKilometersPerHour, cos(toward) * hour.windSpeedKilometersPerHour)
        }
        let hours = state.forecast.hours
        guard let first = hours.first, let last = hours.last else { return (0, 0) }
        if time <= first.date { return vector(first) }
        if time >= last.date { return vector(last) }
        guard let next = hours.firstIndex(where: { $0.date > time }), next > 0 else { return vector(last) }
        let a = hours[next - 1], b = hours[next]
        let t = time.timeIntervalSince(a.date) / max(1, b.date.timeIntervalSince(a.date))
        let va = vector(a), vb = vector(b)
        return (va.east + (vb.east - va.east) * t, va.north + (vb.north - va.north) * t)
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

    /// The active target, made hard to miss against a photographic sky.
    ///
    /// At the dome's scale a small telescope's field is a few points across —
    /// true to size, and nearly invisible over the Milky Way. So the real
    /// footprint is drawn as it is, and a reticle a comfortable size around
    /// it says where to look, with the target's name underneath. Everything
    /// gets a dark halo first so it holds up over bright sky as well as dark.
    ///
    /// The footprint isn't drawn when it doesn't fully clear the horizon
    /// (partially clipping it would need real polygon clipping against the
    /// horizon, not worth it for a planning overlay) or when it's too close
    /// to the zenith to draw meaningfully on this flat projection (see
    /// `isCameraFrameTooCloseToZenith`). The reticle is square to the screen,
    /// so it has no such problem and is drawn whenever the target is up.
    private func drawActiveTarget(context: GraphicsContext, center: CGPoint, radius: CGFloat, targetPlan: TargetPlan) {
        let frameCenter = horizontal(of: targetPlan.target.coordinate)
        let isCameraFrameTooCloseToZenith = frameCenter.altitude > Self.nearZenithThreshold
        guard
              frameCenter.altitude > plan.site.blockedAltitude(azimuth: frameCenter.azimuth) else { return }
        let middle = screenPoint(for: frameCenter, center: center, radius: radius)
        let halo = Color.black.opacity(0.6)

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
        let footprint = CameraFrame.footprint(centerAltitude: frameCenter.altitude,
                                              centerAzimuth: frameCenter.azimuth,
                                              fieldOfViewWidthDegrees: framingRig.fieldOfViewWidthDegrees,
                                              fieldOfViewHeightDegrees: framingRig.fieldOfViewHeightDegrees,
                                              rollDegrees: cameraRollDegrees,
                                              upReference: upReference)
        var extent: CGFloat = 0
        if !isCameraFrameTooCloseToZenith, !footprint.isEmpty, footprint.allSatisfy({ $0.altitude > 0 }) {
            let points = footprint.map { screenPoint(for: $0, center: center, radius: radius) }
            var path = Path.smoothLine(through: points)
            path.closeSubpath()
            context.fill(path, with: .color(Palette.go.opacity(0.3)))
            context.stroke(path, with: .color(halo), lineWidth: 3.5)
            context.stroke(path, with: .color(Palette.go), lineWidth: 1.5)
            extent = points.map { max(abs($0.x - middle.x), abs($0.y - middle.y)) }.max() ?? 0
        }

        // Corner brackets rather than a closed box, so the sky inside stays
        // visible and they can't be mistaken for the frame itself. Tighter
        // and thinner on Home's small preview, where full-size brackets
        // swamped the dome.
        let half = labelled ? max(extent + 10, 18 * uiTextScale) : max(extent + 4, 7)
        let arm = half * 0.5
        var brackets = Path()
        for (dx, dy) in [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)] {
            let corner = CGPoint(x: middle.x + half * dx, y: middle.y + half * dy)
            brackets.move(to: CGPoint(x: corner.x - arm * dx, y: corner.y))
            brackets.addLine(to: corner)
            brackets.addLine(to: CGPoint(x: corner.x, y: corner.y - arm * dy))
        }
        let weight: CGFloat = labelled ? 2.5 : 1.5
        let round = StrokeStyle(lineWidth: weight, lineCap: .round, lineJoin: .round)
        context.stroke(brackets, with: .color(halo), style: StrokeStyle(lineWidth: weight + 3, lineCap: .round, lineJoin: .round))
        context.stroke(brackets, with: .color(Palette.go), style: round)

        // No name on the preview: there's no room for it, and Home already
        // names the target beside it.
        guard labelled else { return }

        let name = context.resolve(Text(targetPlan.target.displayName)
            .font(.scaled(.caption, scale: uiTextScale).weight(.semibold))
            .foregroundColor(.white))
        let size = name.measure(in: CGSize(width: 400, height: 100))
        let labelCentre = CGPoint(x: middle.x, y: middle.y + half + 6 + size.height / 2 + 2)
        let pill = CGRect(x: labelCentre.x - size.width / 2 - 6, y: labelCentre.y - size.height / 2 - 2,
                          width: size.width + 12, height: size.height + 4)
        context.fill(Path(roundedRect: pill, cornerRadius: 4), with: .color(.black.opacity(0.7)))
        context.draw(name, at: labelCentre)
    }

    private func screenPoint(for horizontal: HorizontalCoordinate, center: CGPoint, radius: CGFloat) -> CGPoint {
        screenPoint(for: SkyProjection.project(horizontal), center: center, radius: radius)
    }

    private func screenPoint(for unit: SkyProjection.UnitPoint, center: CGPoint, radius: CGFloat) -> CGPoint {
        CGPoint(x: center.x + CGFloat(unit.x) * radius, y: center.y + CGFloat(unit.y) * radius)
    }

    /// The Moon's own true angular size converted to points — floored well above its literal
    /// (tiny) size at most zoom levels so it stays a recognisable disc
    /// rather than a near-invisible speck, capped so it can't dominate.
    private func moonDiameter(radius: CGFloat) -> CGFloat {
        let pointsPerDegree = radius / 90
        let realDiameter = CGFloat(moonAngularDiameterDegrees) * pointsPerDegree
        return min(max(realDiameter, 10), 26)
    }

    /// The Sun, when it's up: only ever at the dusk and dawn ends of a night,
    /// or in a daytime look at the sky, but it's what makes the dome blue.
    /// Same size rule as the Moon, which it matches in the sky. Drawn inside
    /// the visible sky's clip like everything else, so behind your trees it
    /// simply isn't there.
    private func drawSun(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let sun = sunHorizontal
        guard sun.altitude > -0.8 else { return }
        let screen = screenPoint(for: sun, center: center, radius: radius)
        let diameter = moonDiameter(radius: radius)
        let disc = Path(ellipseIn: CGRect(x: screen.x - diameter / 2, y: screen.y - diameter / 2,
                                          width: diameter, height: diameter))
        let glow = diameter * 2.2
        context.fill(Path(ellipseIn: CGRect(x: screen.x - glow, y: screen.y - glow, width: glow * 2, height: glow * 2)),
                     with: .radialGradient(Gradient(colors: [Palette.sunlight.opacity(0.55), Palette.sunlight.opacity(0)]),
                                           center: screen, startRadius: diameter / 2, endRadius: glow))
        context.fill(disc, with: .color(Palette.sunlight))
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

    /// Each label sits just outside the rim *in its own direction*, so on an
    /// uneven horizon S tracks the bite the tree takes rather than floating
    /// out where the sky would have ended without it.
    private func compassLabels(center: CGPoint, radius: CGFloat) -> some View {
        let points: [(String, Double)] = [("N", 0), ("E", 90), ("S", 180), ("W", 270)]
        return ForEach(points, id: \.0) { label, azimuth in
            let point = SkyProjection.project(HorizontalCoordinate(altitude: 0, azimuth: azimuth))
            let labelRadius = visibleRadius(radius, azimuth: azimuth) + 14
            Text(label)
                .font(.scaled(.caption, scale: uiTextScale).weight(.semibold))
                .foregroundStyle(.secondary)
                .position(x: center.x + CGFloat(point.x) * labelRadius,
                         y: center.y + CGFloat(point.y) * labelRadius)
        }
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
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                playPauseButton
                nowButton
                Text(isFollowingNow ? "Now · \(Format.time(scrubTime, in: plan.timeZone))" : Format.time(scrubTime, in: plan.timeZone))
                    .font(.scaled(.title3, scale: uiTextScale).monospacedDigit().weight(.semibold))
                    .accessibilityLabel("Sky View time, \(Format.time(scrubTime, in: plan.timeZone))")
                Spacer(minLength: 8)
                if !planSegments.isEmpty {
                    Text("During playback")
                        .font(.scaled(.callout, scale: uiTextScale))
                        .foregroundStyle(.secondary)
                    // Drawn here rather than as a segmented control, which
                    // stays at the system size whatever the UI scale.
                    HStack(spacing: 6) {
                        ForEach(PlaybackMode.allCases) { mode in
                            let isOn = playbackMode == mode
                            Button { playbackMode = mode } label: {
                                Text(mode.label)
                                    .font(.scaled(.callout, scale: uiTextScale).weight(isOn ? .semibold : .regular))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(isOn ? Palette.accent.opacity(0.3) : Color.clear, in: Capsule())
                                    .overlay(Capsule().strokeBorder(isOn ? Palette.accent : Palette.panelBorder))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(isOn ? .isSelected : [])
                        }
                    }
                    .fixedSize()
                    .help("What happens to the selection as playback crosses plan blocks")
                }
            }

            // The track, its labelled marks and the plan all share one time
            // axis, so a block sits directly under the stretch of the night
            // it covers.
            // The night's track means little while following a daytime
            // clock, so it steps back; it's still there to drag.
            Group {
                scrubTrack(fraction: fraction)
                scrubberMarks
            }
            .opacity(isFollowingNow && !window.contains(scrubTime) ? 0.4 : 1)
            if !planSegments.isEmpty {
                PlanStripView(plan: plan, segments: planSegments, isEditing: false,
                              onSelect: { segment in
                                  isPlaying = false
                                  scrubTime = segment.window.midpoint
                              })
                    .frame(height: 26 * max(1, uiTextScale * 0.9))
                    .help("Click a block to jump to the middle of it and select its target")
            }

            Text("Star map: NASA/Goddard Scientific Visualization Studio, from Gaia DR2 (ESA/Gaia/DPAC), Hipparcos and Tycho-2")
                .font(.scaled(.caption2, scale: uiTextScale))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .onReceive(Self.playbackTimer) { _ in advancePlayback() }
        .onReceive(Self.nowTimer) { _ in
            if isFollowingNow { scrubTime = Date() }
        }
        // Dragging, a plan block, Jump to Best Window: anything that moves
        // time away from the clock ends Now there.
        .onChange(of: scrubTime) { _, time in
            if isFollowingNow, abs(time.timeIntervalSinceNow) > 5 {
                isFollowingNow = false
                timeBeforeNow = nil
            }
        }
        .onChange(of: isPlaying) { _, playing in
            if playing { isFollowingNow = false; timeBeforeNow = nil }
        }
    }

    /// Now, and pressed again, back to the night where you were.
    @ViewBuilder
    private var nowButton: some View {
        let label = Label(isFollowingNow ? "Back to Night" : "Now",
                          systemImage: isFollowingNow ? "moon.stars" : "clock")
            .font(.scaled(.callout, scale: uiTextScale).weight(.semibold))
        Group {
            if isFollowingNow {
                Button(action: toggleNow) { label }.buttonStyle(.borderedProminent)
            } else {
                Button(action: toggleNow) { label }.buttonStyle(.bordered)
            }
        }
        .fixedSize()
        .help(isFollowingNow ? "Back to the night, where you were" : "Show the sky as it is right now, and keep it turning with the clock")
    }

    private func toggleNow() {
        if isFollowingNow {
            isFollowingNow = false
            let back = timeBeforeNow.map { plan.chartWindow.contains($0) ? $0 : plan.chartWindow.start }
            timeBeforeNow = nil
            scrubTime = back ?? plan.chartWindow.start
        } else {
            isPlaying = false
            timeBeforeNow = scrubTime
            isFollowingNow = true
            scrubTime = Date()
        }
    }

    /// Evening, dark, midnight, the selected target's peak, dawn and morning
    /// under the track — whichever fit without overlapping, most important
    /// first.
    private var scrubberMarks: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let axis = TimeAxis(window: plan.chartWindow, width: width)
            let inset = 26 * uiTextScale
            ForEach(visibleMarks(axis: axis), id: \.date) { mark in
                Text(mark.label)
                    .font(.scaled(.caption, scale: uiTextScale).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .position(x: min(max(axis.x(for: mark.date), inset), max(inset, width - inset)),
                              y: geometry.size.height / 2)
            }
        }
        .frame(height: 16 * uiTextScale)
        .accessibilityHidden(true)
    }

    private func visibleMarks(axis: TimeAxis) -> [SkyViewTimeline.Mark] {
        let spacing = 78 * uiTextScale
        var kept: [SkyViewTimeline.Mark] = []
        for mark in SkyViewTimeline.marks(for: plan, target: selectedTargetPlan).sorted(by: { $0.priority < $1.priority }) {
            let x = axis.x(for: mark.date)
            if kept.allSatisfy({ abs(axis.x(for: $0.date) - x) >= spacing }) { kept.append(mark) }
        }
        return kept
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
            Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                .font(.scaled(.callout, scale: uiTextScale).weight(.semibold))
                .frame(minWidth: 64)
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.space, modifiers: [])
        .help(isPlaying ? "Pause (Space)" : "Play the night (Space)")
        .fixedSize()
    }

}
