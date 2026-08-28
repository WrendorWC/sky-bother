import SwiftUI

struct TargetDetailView: View {
    @EnvironmentObject private var state: AppState
    var plan: NightPlan
    var targetPlan: TargetPlan

    private var target: Target { targetPlan.target }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                headline
                if targetPlan.verdict == .marginal || targetPlan.verdict == .poor { whyNot }
                framing
                altitude
                scoring
                if !targetPlan.warnings.isEmpty { warnings }
                facts
            }
            .padding(20)
        }
        .spaceBackground()
        .navigationTitle(target.displayName)
    }

    // MARK: - Sections

    private var headline: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(target.displayName)
                        .font(.title2.weight(.semibold))
                    Text("\(target.designation) · \(target.type.displayName) in \(target.constellation)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ScoreBadge(score: targetPlan.score, size: 50)
            }
            HStack(spacing: 9) {
                VerdictTag(verdict: targetPlan.verdict)
                Text(recommendation)
                    .font(.body)
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
            FramingPreview(target: target, rig: state.rig)
                .frame(height: 300)
            Text(targetPlan.fit.framingNote)
                .font(.callout)
            if let sampling = targetPlan.fit.samplingNote {
                Text(sampling)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(state.rig.name) · \(state.rig.fieldOfViewSummary) · \(state.rig.opticalSummary)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            if let info = TargetImageCatalog.info(for: target.designation), let url = URL(string: info.sourceURL) {
                Link(destination: url) {
                    Label("Photo: \(info.sourceTitle) via Wikipedia", systemImage: "link")
                }
                .font(.caption)
                .foregroundStyle(Palette.accent)
            }
        }
    }

    private var altitude: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionHeader("Through the night")
            HStack {
                if let transit = targetPlan.transitTime {
                    Text("Highest at \(Format.time(transit, in: plan.timeZone)) · \(Format.degrees(targetPlan.maximumAltitude))")
                }
                Spacer()
                if let best = targetPlan.bestWindow, !best.isEmpty {
                    Text("best window \(Format.time(best.start, in: plan.timeZone))–\(Format.time(best.end, in: plan.timeZone))")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            Text("Traced live on tonight's main timeline — this target is selected there too.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Why this score

    private var primaryFactorResult: (factor: ScoreFactor, impact: Double)? {
        primaryFactor(in: targetPlan.factors, actualScore: targetPlan.score)
    }

    private var scoring: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Why this score")

            if let primary = primaryFactorResult, primary.impact > 1 {
                Label {
                    Text("Main limitation: \(primary.factor.name) — \(limitationPhrase(for: primary.factor))")
                } icon: {
                    Image(systemName: "arrow.down.circle.fill")
                }
                .font(.callout.weight(.medium))
                .foregroundStyle(Palette.marginal)
            }

            ForEach(targetPlan.factors) { factor in
                FactorBar(factor: factor, impact: scoreImpact(of: factor, in: targetPlan.factors, actualScore: targetPlan.score))
            }
            Text("Each impact is the real model re-run with that one factor made perfect — how many points you'd gain, not an invented share of the total.")
                .font(.caption)
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

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout.monospacedDigit())
        }
    }
}

struct SectionHeader: View {
    var title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.accent)
            .kerning(0.7)
    }
}

/// Draws the target's catalogued ellipse against the rig's field of view, to
/// scale. This is the fastest way to answer "will it actually fill the frame".
struct FramingPreview: View {
    var target: Target
    var rig: Rig

    var body: some View {
        Canvas { context, size in
            let frameWidth = rig.fieldOfViewWidthArcminutes
            let frameHeight = rig.fieldOfViewHeightArcminutes
            guard frameWidth > 0, frameHeight > 0 else { return }

            // There's no way to know the real position angle on sky at
            // imaging time — that depends on the moment's field rotation, not
            // just the target — so this orients the target's long axis along
            // whichever of the frame's two dimensions is actually longer, the
            // best-case assumption. Hardcoding that to the frame's *width*
            // (the old behaviour) looks right for every landscape sensor but
            // is 90° wrong for a portrait one, like the Seestar S50 Pro's
            // 6.26mm × 11.14mm chip.
            let frameIsPortrait = frameHeight > frameWidth
            let objectWidth = max(0.2, frameIsPortrait ? target.minorAxisArcminutes : target.majorAxisArcminutes)
            let objectHeight = max(0.2, frameIsPortrait ? target.majorAxisArcminutes : target.minorAxisArcminutes)

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
            let fits = objectWidth <= frameWidth * 0.9 && objectHeight <= frameHeight * 0.9
            context.stroke(Path(frameRect),
                           with: .color(fits ? Palette.go : Palette.marginal),
                           style: StrokeStyle(lineWidth: 2, dash: fits ? [] : [5, 4]))

            context.draw(Text(String(format: "%.2f° × %.2f°", frameWidth / 60, frameHeight / 60))
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(fits ? Palette.go : Palette.marginal),
                         at: CGPoint(x: frameRect.minX + 4, y: max(11, frameRect.minY - 11)),
                         anchor: .topLeading)

            context.draw(Text(target.sizeSummary)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white),
                         at: CGPoint(x: centre.x, y: min(size.height - 11, objectRect.maxY + 13)),
                         anchor: .center)
        }
        .background(Palette.spaceTop, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.panelBorder, lineWidth: 1.5))
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
}

