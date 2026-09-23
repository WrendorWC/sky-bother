import SwiftUI

struct TargetDetailView: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var state: AppState
    var plan: NightPlan
    var targetPlan: TargetPlan
    /// Set in the planner, where the panel can put the target into the plan
    /// being built. Nil on Home, which only ever reads the plan.
    var onAddToPlan: (() -> Void)? = nil
    var framingHeight: CGFloat = 250
    /// Off in the planner, whose window title says what the whole window is.
    var setsWindowTitle = true

    /// True once the full headline card has scrolled past the top of the
    /// column — the trigger for showing the compact sticky replacement.
    @State private var isHeaderCollapsed = false
    @State private var isShowingScore = true
    @State private var isShowingTechnical = false

    private var target: Target { targetPlan.target }

    var body: some View {
        ZStack(alignment: .top) {
            scrollContent
                .spaceBackground()

            if isHeaderCollapsed {
                compactHeader
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.16), value: isHeaderCollapsed)
        .modifier(WindowTitle(title: setsWindowTitle ? target.displayName : nil))
    }

    /// Three levels: the practical conclusion first, then why it scored what
    /// it did, then the numbers for anyone who wants them.
    private var scrollBody: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader("Selected target")
                headline
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: ScrollOffsetKey.self,
                                value: geometry.frame(in: .named("targetDetailScroll")).maxY)
                        }
                    )
                planStatus
                altitude
                framing
            }
            // Directly under the overview: these change what you'd do.
            if targetPlan.verdict == .marginal || targetPlan.verdict == .poor { whyNot }
            if !targetPlan.warnings.isEmpty { warnings }

            DisclosureGroup(isExpanded: $isShowingScore) {
                scoring.padding(.top, 8)
            } label: {
                disclosureLabel("Why this score", isExpanded: $isShowingScore)
            }

            DisclosureGroup(isExpanded: $isShowingTechnical) {
                VStack(alignment: .leading, spacing: 22) {
                    facts
                    if let info = TargetFactCatalog.info(for: target.designation) { funFact(info) }
                }
                .padding(.top, 8)
            } label: {
                disclosureLabel("Technical details", isExpanded: $isShowingTechnical)
            }
        }
        .padding(20)
    }

    private func disclosureLabel(_ title: String, isExpanded: Binding<Bool>) -> some View {
        SectionHeader(title)
            // DisclosureGroup only toggles on its own triangle by default.
            .contentShape(Rectangle())
            .onTapGesture { isExpanded.wrappedValue.toggle() }
    }

    // MARK: - Plan status

    private var plannedBlocks: [PlanSegment] { state.plannedBlocks(for: targetPlan.id, in: plan) }

    /// Whether this target is in the plan, and where — the difference
    /// between the target you're looking at and the ones you'll shoot.
    @ViewBuilder
    private var planStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            if targetPlan.usableMinutes <= 0 {
                unavailableNote
            }
            if !plannedBlocks.isEmpty {
                Label {
                    Text("Planned · " + plannedBlocks.map {
                        "\(Format.time($0.window.start, in: plan.timeZone))–\(Format.time($0.window.end, in: plan.timeZone))"
                    }.joined(separator: ", "))
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .font(.scaled(.callout, scale: uiTextScale).weight(.medium))
                .foregroundStyle(Palette.accent)
            } else {
                Label("Not in the plan", systemImage: "circle.dashed")
                    .font(.scaled(.callout, scale: uiTextScale))
                    .foregroundStyle(.secondary)
            }
            Button {
                state.openSkyView(for: plan)
            } label: {
                Label("Show in Sky View", systemImage: "circle.dashed.inset.filled")
            }
            .buttonStyle(.link)
            .font(.scaled(.callout, scale: uiTextScale))
            .help("Where \(target.displayName) is through the night, with your frame on it")
            if let onAddToPlan {
                Button(action: onAddToPlan) {
                    Label(plannedBlocks.isEmpty ? "Add to plan" : "Add another block", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .help(plannedBlocks.isEmpty
                      ? "Put a block for this target in the longest free stretch of the night"
                      : "The same target can take more than one block — this adds another in the longest free stretch")
            }
        }
    }

    /// No usable time on this night: say why, and when would work instead.
    @ViewBuilder
    private var unavailableNote: some View {
        let reason = whyNotBullets(factors: targetPlan.factors, limit: 1).first
            ?? "it isn't up, dark and clear at the same time"
        WarningRow(text: "No usable time this night — \(reason)")
        if let other = state.nearestUsefulNight(for: targetPlan.id, after: plan) {
            let label = "Try \(Format.weekday(other.night.date, in: other.night.timeZone)) \(Format.dayAndMonth(other.night.date, in: other.night.timeZone)) · \(Int(other.target.score.rounded())) · \(other.target.usableHoursText)"
            if state.mainView == .home {
                Button(label) { state.selectedNightID = other.night.id }
                    .buttonStyle(.link)
                    .font(.scaled(.callout, scale: uiTextScale))
                    .help("Open that night")
            } else {
                Text(label)
                    .font(.scaled(.callout, scale: uiTextScale))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // `onScrollGeometryChange` (macOS 15+) reads the ScrollView's real content
    // offset directly — no coordinate-space bookkeeping, so nothing to get
    // subtly wrong. The `GeometryReader`-in-`.background()` + named
    // coordinate space technique used in the macOS 14 fallback below is the
    // standard workaround for OSes without it, kept only for that fallback.
    @ViewBuilder
    private var scrollContent: some View {
        if #available(macOS 15.0, *) {
            ScrollView {
                scrollBody
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, offset in
                isHeaderCollapsed = offset > 90
            }
        } else {
            ScrollView {
                scrollBody
            }
            .coordinateSpace(name: "targetDetailScroll")
            .onPreferenceChange(ScrollOffsetKey.self) { maxY in
                isHeaderCollapsed = maxY < 36
            }
        }
    }

    // MARK: - Sticky header

    /// Retains just enough of the headline to keep the target identified —
    /// name, catalog number, score, verdict — once the full card above has
    /// scrolled out of view, the same identity a glance at the headline gives
    /// you, without needing to scroll back up to remember what you're looking at.
    private var compactHeader: some View {
        HStack(spacing: 9) {
            ScoreBadge(score: targetPlan.score, size: 26)
            Text(target.displayName)
                .font(.scaled(.callout, scale: uiTextScale).weight(.semibold))
                .lineLimit(1)
            if target.commonName != nil {
                Text("·").foregroundStyle(.tertiary)
                Text(target.designation)
                    .font(.scaled(.callout, scale: uiTextScale))
                    .foregroundStyle(.secondary)
            }
            Text("·").foregroundStyle(.tertiary)
            Text("\(Int(targetPlan.score.rounded()))")
                .font(.scaled(.callout, scale: uiTextScale).monospacedDigit().weight(.semibold))
                .foregroundStyle(Palette.score(targetPlan.score))
            Text("·").foregroundStyle(.tertiary)
            Text(targetPlan.verdict.rawValue)
                .font(.scaled(.callout, scale: uiTextScale).weight(.semibold))
                .foregroundStyle(Palette.verdict(targetPlan.verdict))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Palette.spaceTop, in: Rectangle())
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - Sections

    private var headline: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(target.displayName)
                        .font(.scaled(.title2, scale: uiTextScale).weight(.semibold))
                    Text("\(target.designation) · \(target.type.displayName) in \(target.constellationName)")
                        .font(.scaled(.callout, scale: uiTextScale))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ScoreBadge(score: targetPlan.score, size: 50)
            }
            HStack(spacing: 9) {
                VerdictTag(verdict: targetPlan.verdict)
                Text(recommendation)
                    .font(.scaled(.body, scale: uiTextScale))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(verdictSentence)
                .font(.scaled(.callout, scale: uiTextScale).weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One sentence for the main reason it is or isn't recommended.
    private var verdictSentence: String {
        if let primary = primaryFactorResult, primary.impact > 1 {
            return "\(targetPlan.verdict.rawValue) — held back most by \(limitationPhrase(for: primary.factor))."
        }
        return "\(targetPlan.verdict.rawValue) — nothing in particular holds it back."
    }

    private var compassPoint: String {
        HorizontalCoordinate(altitude: targetPlan.altitudeAtBest,
                             azimuth: targetPlan.azimuthAtBest).compassPoint
    }

    private var recommendation: String {
        var parts: [String] = ["\(targetPlan.usableHoursText) usable"]
        if let best = targetPlan.bestTime {
            let time = Format.time(best, in: plan.timeZone)
            let altitude = Format.degrees(targetPlan.altitudeAtBest)
            parts.append("best around \(time) at \(altitude) in the \(compassPoint)")
        }
        return parts.joined(separator: ", ")
    }

    private var framing: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionHeader("In your frame")
            // Shrunk from 300 — the framing preview was consuming most of the
            // right column's vertical space while "Through the night" and
            // "Why this score" got pushed below the fold. Same geometry, just
            // less of it.
            FramingPreview(target: target, rig: state.rig)
                .frame(height: framingHeight)
                .contentShape(Rectangle())
                .onTapGesture { openWindow(id: "sky", value: target.designation) }
                .help("Open this patch of sky in its own window — pan, zoom and search")
            Text(targetPlan.fit.framingNote)
                .font(.scaled(.callout, scale: uiTextScale))
            if let sampling = targetPlan.fit.samplingNote {
                Text(sampling)
                    .font(.scaled(.caption, scale: uiTextScale))
                    .foregroundStyle(.secondary)
            }
            Text("\(state.rig.name) · \(state.rig.fieldOfViewSummary) · \(state.rig.opticalSummary)")
                .font(.scaled(.caption, scale: uiTextScale))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            // Required by the survey's own terms, not optional politeness.
            if let url = URL(string: SkyCutoutClient.attributionURL) {
                Link(destination: url) {
                    Label(SkyCutoutClient.attribution, systemImage: "camera.metering.matrix")
                }
                .font(.scaled(.caption, scale: uiTextScale))
                .foregroundStyle(.tertiary)
            }
            if let info = TargetImageCatalog.info(for: target.designation),
                   let source = info.sourceURL, let url = URL(string: source) {
                Link(destination: url) {
                    Label("Photo: \(info.sourceTitle ?? target.designation) via Wikipedia", systemImage: "link")
                }
                .font(.scaled(.caption, scale: uiTextScale))
                .foregroundStyle(Palette.accent)
            }
        }
    }

    private var altitude: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionHeader("Through the night")
            if let transit = targetPlan.transitTime {
                Text("Highest at \(Format.time(transit, in: plan.timeZone)) · \(Format.degrees(targetPlan.maximumAltitude))")
                    .font(.scaled(.callout, scale: uiTextScale))
                    .foregroundStyle(.secondary)
            }
            if let best = targetPlan.bestWindow, !best.isEmpty {
                if let risk = targetPlan.bestWindowZenithRisk {
                    ZenithRiskWindowBar(window: best, risk: risk, timeZone: plan.timeZone)
                } else {
                    Text("Best window \(Format.time(best.start, in: plan.timeZone))–\(Format.time(best.end, in: plan.timeZone))")
                        .font(.scaled(.callout, scale: uiTextScale))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Why this score

    private var primaryFactorResult: (factor: ScoreFactor, impact: Double)? {
        primaryFactor(in: targetPlan.factors, actualScore: targetPlan.score)
    }

    private var scoring: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The main limitation is already the overview's one sentence;
            // this is the breakdown behind it.
            VStack(alignment: .leading, spacing: 7) {
                ForEach(targetPlan.factors) { factor in
                    FactorBar(factor: factor, impact: scoreImpact(of: factor, in: targetPlan.factors, actualScore: targetPlan.score))
                }
            }
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var warnings: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionHeader("Worth knowing")
            ForEach(targetPlan.warnings, id: \.self) { warning in
                WarningRow(text: warning)
            }
        }
    }

    private var whyNot: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionHeader("Why not recommended")
            ForEach(whyNotBullets(factors: targetPlan.factors), id: \.self) { bullet in
                WarningRow(text: bullet)
            }
        }
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionHeader("Numbers")
            factRow("Coordinates", Format.coordinates(target.coordinate))
            factRow("Magnitude", String(format: "%.1f", target.magnitude))
            factRow("Apparent size", target.sizeSummary)
            if !target.type.isStarField {
                factRow("Surface brightness", String(format: "%.1f mag/arcsec²", target.surfaceBrightness))
            }
            factRow("Peak altitude", Format.degrees(targetPlan.maximumAltitude))
            factRow("Air mass at peak", String(format: "%.2f", SkyCoordinates.airMass(altitude: targetPlan.maximumAltitude)))
            factRow("Moon separation", Format.degrees(targetPlan.minimumMoonSeparation))
            if state.rig.mountType.rotatesField && targetPlan.maximumFieldRotation > 0 {
                factRow("Peak field rotation", String(format: "%.1f°/h", targetPlan.maximumFieldRotation))
            }
            if let window = targetPlan.bestWindow {
                factRow("Longest window",
                        "\(Format.time(window.start, in: plan.timeZone))–\(Format.time(window.end, in: plan.timeZone))")
            }
        }
    }

    /// A little of what makes this an actual object out there rather than
    /// just a row of numbers — real, Wikipedia-sourced trivia (discovery
    /// history, what it's notable for) where it exists. Most targets, and
    /// especially most of the extended catalogue, don't have one.
    private func funFact(_ info: TargetFactInfo) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionHeader("About")
            Text(info.fact)
                .font(.scaled(.callout, scale: uiTextScale))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let url = URL(string: info.sourceURL) {
                Link(destination: url) {
                    Label("\(info.sourceTitle) via Wikipedia", systemImage: "link")
                }
                .font(.scaled(.caption, scale: uiTextScale))
                .foregroundStyle(Palette.accent)
            }
        }
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

private struct WindowTitle: ViewModifier {
    var title: String?

    func body(content: Content) -> some View {
        if let title { content.navigationTitle(title) } else { content }
    }
}

struct SectionHeader: View {
    @Environment(\.uiTextScale) private var uiTextScale
    var title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.scaled(.caption, scale: uiTextScale).weight(.semibold))
            .foregroundStyle(Palette.accent)
            .kerning(0.7)
    }
}

/// Draws the target's catalogued ellipse against the rig's field of view, to
/// scale. This is the fastest way to answer "will it actually fill the frame".
struct FramingPreview: View {
    var target: Target
    var rig: Rig

    @Environment(\.uiTextScale) private var uiTextScale

    /// Real sky for this patch, once it has arrived. Until then the panel
    /// shows a placeholder: it used to draw an invented star field with the
    /// catalogued size as an ellipse over it, which looked like a finished
    /// picture of something it wasn't and disagreed with the real sky that
    /// replaced it a second later.
    @State private var skyImage: NSImage?
    /// Set when the fetch came back with nothing — offline, most likely —
    /// so the placeholder can say so instead of waiting forever.
    @State private var skyUnavailable = false
    @State private var measured: CGSize = .zero

    private var frameWidth: Double { rig.fieldOfViewWidthArcminutes }
    private var frameHeight: Double { rig.fieldOfViewHeightArcminutes }

    // There's no way to know the real position angle on sky at imaging time —
    // that depends on the moment's field rotation, not just the target — so
    // this orients the target's long axis along whichever of the frame's two
    // dimensions is actually longer, the best-case assumption. Hardcoding
    // that to the frame's *width* (the old behaviour) looks right for every
    // landscape sensor but is 90° wrong for a portrait one, like the Seestar
    // S50 Pro's 6.26mm × 11.14mm chip.
    private var frameIsPortrait: Bool { frameHeight > frameWidth }
    private var objectWidth: Double {
        max(0.2, frameIsPortrait ? target.minorAxisArcminutes : target.majorAxisArcminutes)
    }
    private var objectHeight: Double {
        max(0.2, frameIsPortrait ? target.majorAxisArcminutes : target.minorAxisArcminutes)
    }
    private var fits: Bool {
        objectWidth <= frameWidth * 0.9 && objectHeight <= frameHeight * 0.9
    }

    /// The patch of sky this preview is showing, in the units the cutout
    /// service wants. Derived from the same scale the Canvas draws with, so
    /// the fetched image lands pixel-for-pixel on the geometry over it.
    private func cutout(for size: CGSize) -> SkyCutout? {
        guard frameWidth > 0, frameHeight > 0, size.width > 1, size.height > 1 else { return nil }
        let scale = self.scale(for: size)
        guard scale > 0 else { return nil }
        let pixelScale = NSScreen.main?.backingScaleFactor ?? 2
        return SkyCutout(rightAscensionDegrees: target.coordinate.rightAscension,
                         declinationDegrees: target.coordinate.declination,
                         widthDegrees: Double(size.width) / scale / 60,
                         pixelWidth: Int(size.width * pixelScale),
                         pixelHeight: Int(size.height * pixelScale))
    }

    /// Points per arcminute. Fits whichever is larger — the frame or the
    /// object — with a margin, so an oversized target visibly spills past the
    /// frame edges.
    private func scale(for size: CGSize) -> CGFloat {
        let extentX = max(frameWidth, objectWidth) * 1.18
        let extentY = max(frameHeight, objectHeight) * 1.18
        return min(size.width / extentX, size.height / extentY)
    }

    var body: some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { measured = geometry.size }
                        .onChange(of: geometry.size) { _, size in measured = size }
                }
            )
            .task(id: "\(target.designation)@\(Int(measured.width))x\(Int(measured.height))") {
                guard let request = cutout(for: measured) else { return }
                // Already on disk: show it on this pass rather than a beat
                // later in place of the placeholder.
                if let ready = SkyCutoutClient.shared.cachedImage(for: request) {
                    skyImage = ready
                    return
                }
                let image = await SkyCutoutClient.shared.image(for: request)
                // Nothing is cleared on the way in, and nothing is written on
                // the way out unless this task is still the current one.
                //
                // Laying out the pane starts a fetch, and the pane settling to
                // its final width supersedes it. The superseded fetch is
                // cancelled, which surfaces as a nil image — and writing that
                // nil back wiped whatever the newer task had already resolved,
                // so the preview sat on the drawn star field with a perfectly
                // good picture in the cache. A failure should leave what is on
                // screen alone rather than replace it with nothing.
                guard !Task.isCancelled else { return }
                guard let image else {
                    if skyImage == nil { skyUnavailable = true }
                    return
                }
                skyImage = image
                skyUnavailable = false
            }
    }

    private var content: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
            guard frameWidth > 0, frameHeight > 0 else { return }

            let scale = self.scale(for: size)
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)

            if let skyImage {
                // Real sky, filling the whole panel: the cutout was requested
                // for exactly this angular width, so it needs no fitting.
                context.draw(Image(nsImage: skyImage),
                             in: CGRect(origin: .zero, size: size))

                // A centre tick, because the survey is shallow and a faint
                // target can be nearly invisible in it. That marks where to
                // look without claiming how far it extends — the catalogued
                // axes describe something far smaller than the part worth
                // photographing for a great many objects.
                let tick: CGFloat = 7
                let gap: CGFloat = 4
                var marks = Path()
                marks.move(to: CGPoint(x: centre.x - gap - tick, y: centre.y))
                marks.addLine(to: CGPoint(x: centre.x - gap, y: centre.y))
                marks.move(to: CGPoint(x: centre.x + gap, y: centre.y))
                marks.addLine(to: CGPoint(x: centre.x + gap + tick, y: centre.y))
                marks.move(to: CGPoint(x: centre.x, y: centre.y - gap - tick))
                marks.addLine(to: CGPoint(x: centre.x, y: centre.y - gap))
                marks.move(to: CGPoint(x: centre.x, y: centre.y + gap))
                marks.addLine(to: CGPoint(x: centre.x, y: centre.y + gap + tick))
                context.stroke(marks, with: .color(Palette.worthwhile.opacity(0.8)), lineWidth: 1.5)
            }

            let frameRect = CGRect(x: centre.x - frameWidth * scale / 2,
                                   y: centre.y - frameHeight * scale / 2,
                                   width: frameWidth * scale,
                                   height: frameHeight * scale)
            context.stroke(Path(frameRect),
                           with: .color(fits ? Palette.go : Palette.marginal),
                           style: StrokeStyle(lineWidth: 2, dash: fits ? [] : [5, 4]))
            }
            .background(Palette.spaceTop, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                if skyImage == nil {
                    VStack(spacing: 8) {
                        if skyUnavailable {
                            Image(systemName: "wifi.slash")
                                .font(.system(size: 20 * uiTextScale))
                            Text("Sky image unavailable")
                        } else {
                            ProgressView().controlSize(.small)
                            Text("Fetching sky\u{2026}")
                        }
                    }
                    .font(.system(size: 12 * uiTextScale))
                    .foregroundStyle(.tertiary)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.panelBorder, lineWidth: 1.5))

            // Pinned to the panel corner rather than the (scaled, variable-position)
            // frame rectangle, but a wide field of view can still put the
            // frame's own top-left corner right underneath this label — and a
            // bigger Text Size setting only makes that more likely, since the
            // label itself grows while the frame geometry doesn't. A solid
            // backing (the same chip style as the timeline's hover readout)
            // keeps it legible regardless of what the frame line does behind it.
            if frameWidth > 0, frameHeight > 0 {
                Text(String(format: "%.2f° × %.2f°", frameWidth / 60, frameHeight / 60))
                    .font(.system(size: 14 * uiTextScale, weight: .medium, design: .rounded))
                    .foregroundColor(fits ? Palette.go : Palette.marginal)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 6))
                    .padding(8)
            }
        }
    }

}


