import SwiftUI

struct TargetDetailView: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @EnvironmentObject private var state: AppState
    var plan: NightPlan
    var targetPlan: TargetPlan

    /// True once the full headline card has scrolled past the top of the
    /// column — the trigger for showing the compact sticky replacement.
    @State private var isHeaderCollapsed = false

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
        .navigationTitle(target.displayName)
    }

    private var scrollBody: some View {
        VStack(alignment: .leading, spacing: 22) {
            headline
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ScrollOffsetKey.self,
                            value: geometry.frame(in: .named("targetDetailScroll")).maxY)
                    }
                )
            if targetPlan.verdict == .marginal || targetPlan.verdict == .poor { whyNot }
            framing
            altitude
            scoring
            if !targetPlan.warnings.isEmpty { warnings }
            facts
            if let info = TargetFactCatalog.info(for: target.designation) { funFact(info) }
        }
        .padding(20)
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
        }
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
                .frame(height: 250)
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
            if let info = TargetImageCatalog.info(for: target.designation), let url = URL(string: info.sourceURL) {
                Link(destination: url) {
                    Label("Photo: \(info.sourceTitle) via Wikipedia", systemImage: "link")
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
            Text("Traced live on tonight's main timeline — this target is selected there too.")
                .font(.scaled(.caption, scale: uiTextScale))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Why this score

    private var primaryFactorResult: (factor: ScoreFactor, impact: Double)? {
        primaryFactor(in: targetPlan.factors, actualScore: targetPlan.score)
    }

    private var scoring: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                SectionHeader("Why this score")
                Image(systemName: "info.circle")
                    .font(.scaled(.caption2, scale: uiTextScale))
                    .foregroundStyle(.tertiary)
                    .hoverTooltip("Each impact is the real model re-run with that one factor made perfect — how many points you'd gain, not an invented share of the total.")
            }

            if let primary = primaryFactorResult, primary.impact > 1 {
                Label {
                    Text("Main limitation: \(primary.factor.name) — \(limitationPhrase(for: primary.factor))")
                } icon: {
                    Image(systemName: "arrow.down.circle.fill")
                }
                .font(.scaled(.callout, scale: uiTextScale).weight(.medium))
                .foregroundStyle(Palette.marginal)
            }

            VStack(alignment: .leading, spacing: 7) {
                ForEach(targetPlan.factors) { factor in
                    FactorBar(factor: factor, impact: scoreImpact(of: factor, in: targetPlan.factors, actualScore: targetPlan.score))
                }
            }
            Text("Impact shows how many score points this factor costs under tonight's conditions.")
                .font(.scaled(.caption, scale: uiTextScale))
                .foregroundStyle(.tertiary)
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

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
            guard frameWidth > 0, frameHeight > 0 else { return }

            // A faint starfield and grid so this reads as a finished sky
            // visualization rather than an empty technical diagram — drawn
            // first, well under the target ellipse and frame in opacity, and
            // before anything else so it never competes with them.
            drawBackgroundField(context: context, size: size, seed: target.designation)

            // Fit whichever is larger — the frame or the object — with a margin,
            // so an oversized target visibly spills past the frame edges.
            let extentX = max(frameWidth, objectWidth) * 1.18
            let extentY = max(frameHeight, objectHeight) * 1.18
            let scale = min(size.width / extentX, size.height / extentY)
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)

            let objectRect = CGRect(x: centre.x - objectWidth * scale / 2,
                                    y: centre.y - objectHeight * scale / 2,
                                    width: objectWidth * scale,
                                    height: objectHeight * scale)

            if let photo = TargetImageCatalog.nsImage(for: target.designation) {
                context.drawLayer { layer in
                    layer.clip(to: Path(ellipseIn: objectRect))
                    layer.draw(Image(nsImage: photo), in: aspectFilled(photo.size, into: objectRect))
                    layer.fill(Path(ellipseIn: objectRect), with: .color(.black.opacity(0.1)))
                }
                context.stroke(Path(ellipseIn: objectRect),
                               with: .color(Palette.worthwhile.opacity(0.9)), lineWidth: 2)
            } else {
                context.fill(Path(ellipseIn: objectRect),
                             with: .color(Palette.worthwhile.opacity(0.38)))
                context.stroke(Path(ellipseIn: objectRect),
                               with: .color(Palette.worthwhile.opacity(0.85)), lineWidth: 1.5)
            }

            let frameRect = CGRect(x: centre.x - frameWidth * scale / 2,
                                   y: centre.y - frameHeight * scale / 2,
                                   width: frameWidth * scale,
                                   height: frameHeight * scale)
            context.stroke(Path(frameRect),
                           with: .color(fits ? Palette.go : Palette.marginal),
                           style: StrokeStyle(lineWidth: 2, dash: fits ? [] : [5, 4]))

            context.draw(Text(target.sizeSummary)
                            .font(.system(size: 14 * uiTextScale, weight: .semibold, design: .rounded))
                            .foregroundColor(.white),
                         at: CGPoint(x: centre.x, y: min(size.height - 11, objectRect.maxY + 13)),
                         anchor: .center)
            }
            .background(Palette.spaceTop, in: RoundedRectangle(cornerRadius: 10))
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

    /// The rect an image should be drawn in to fill `bounds` while preserving
    /// its own aspect ratio (and spilling past the bounds on one axis), the way
    /// `.aspectRatio(contentMode: .fill)` would for a SwiftUI `Image`.
    private func aspectFilled(_ imageSize: CGSize, into bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let imageAspect = imageSize.width / imageSize.height
        let boundsAspect = bounds.width / bounds.height
        if imageAspect > boundsAspect {
            let width = bounds.height * imageAspect
            return CGRect(x: bounds.midX - width / 2, y: bounds.minY, width: width, height: bounds.height)
        } else {
            let height = bounds.width / imageAspect
            return CGRect(x: bounds.minX, y: bounds.midY - height / 2, width: bounds.width, height: height)
        }
    }

    /// A sparse starfield plus a faint alignment grid, so the panel reads as
    /// a finished sky visualization rather than an empty diagram. Stars are
    /// seeded from the target's designation rather than `Double.random`, so
    /// they're stable across the many redraws a `Canvas` does on every hover
    /// and scrub — unseeded randomness would visibly flicker.
    private func drawBackgroundField(context: GraphicsContext, size: CGSize, seed: String) {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        for fraction: CGFloat in [0.25, 0.45, 0.68] {
            let r = min(size.width, size.height) / 2 * fraction
            context.stroke(Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)),
                           with: .color(.white.opacity(0.045)), lineWidth: 1)
        }
        var cross = Path()
        cross.move(to: CGPoint(x: 0, y: centre.y))
        cross.addLine(to: CGPoint(x: size.width, y: centre.y))
        cross.move(to: CGPoint(x: centre.x, y: 0))
        cross.addLine(to: CGPoint(x: centre.x, y: size.height))
        context.stroke(cross, with: .color(.white.opacity(0.04)), lineWidth: 1)

        // Shared with TargetThumbnail's "no photo" placeholder (Components.swift)
        // so the app has one starfield visual language rather than two.
        drawStarfield(context: context, size: size, seed: seed)
    }
}

