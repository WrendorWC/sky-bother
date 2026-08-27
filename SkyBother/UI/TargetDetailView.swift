import SwiftUI

struct TargetDetailView: View {
    @EnvironmentObject private var state: AppState
    var plan: NightPlan
    var targetPlan: TargetPlan

    private var target: Target { targetPlan.target }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headline
                framing
                altitude
                scoring
                if !targetPlan.warnings.isEmpty { warnings }
                facts
            }
            .padding(16)
        }
        .navigationTitle(target.displayName)
    }

    // MARK: - Sections

    private var headline: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.displayName)
                        .font(.title3.weight(.semibold))
                    Text("\(target.designation) · \(target.type.displayName) in \(target.constellation)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ScoreBadge(score: targetPlan.score, size: 42)
            }
            HStack(spacing: 8) {
                VerdictTag(verdict: targetPlan.verdict)
                Text(recommendation)
                    .font(.callout)
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
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("In your frame")
            FramingPreview(target: target, rig: state.rig)
                .frame(height: 148)
            Text(targetPlan.fit.framingNote)
                .font(.caption)
            if let sampling = targetPlan.fit.samplingNote {
                Text(sampling)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("\(state.rig.name) · \(state.rig.fieldOfViewSummary) · \(state.rig.opticalSummary)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var altitude: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("Through the night")
            TargetAltitudeChart(plan: plan, targetPlan: targetPlan,
                                minimumAltitude: max(plan.site.horizonAltitude,
                                                     state.preferences.minimumUsefulAltitude))
                .frame(height: 132)
            HStack {
                if let transit = targetPlan.transitTime {
                    Text("Highest at \(Format.time(transit, in: plan.timeZone)) · \(Format.degrees(targetPlan.maximumAltitude))")
                }
                Spacer()
                Text("dashed line = your minimum altitude")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var scoring: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Why this score")
            ForEach(targetPlan.factors) { factor in
                FactorBar(factor: factor)
            }
            Text("Factors combine as a weighted geometric mean, so one bad factor pulls the score down rather than being averaged away.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var warnings: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("Worth knowing")
            ForEach(targetPlan.warnings, id: \.self) { warning in
                WarningRow(text: warning)
            }
        }
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
        }
    }
}

struct SectionHeader: View {
    var title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .kerning(0.6)
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

            let objectWidth = max(0.2, target.majorAxisArcminutes)
            let objectHeight = max(0.2, target.minorAxisArcminutes)

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
            context.fill(Path(ellipseIn: objectRect),
                         with: .color(Palette.worthwhile.opacity(0.38)))
            context.stroke(Path(ellipseIn: objectRect),
                           with: .color(Palette.worthwhile.opacity(0.85)), lineWidth: 1)

            let frameRect = CGRect(x: centre.x - frameWidth * scale / 2,
                                   y: centre.y - frameHeight * scale / 2,
                                   width: frameWidth * scale,
                                   height: frameHeight * scale)
            let fits = objectWidth <= frameWidth * 0.9 && objectHeight <= frameHeight * 0.9
            context.stroke(Path(frameRect),
                           with: .color(fits ? Palette.go : Palette.marginal),
                           style: StrokeStyle(lineWidth: 1.5, dash: fits ? [] : [4, 3]))

            context.draw(Text(String(format: "%.2f° × %.2f°", frameWidth / 60, frameHeight / 60))
                            .font(.system(size: 9, design: .rounded))
                            .foregroundColor(fits ? Palette.go : Palette.marginal),
                         at: CGPoint(x: frameRect.minX + 2, y: max(7, frameRect.minY - 7)),
                         anchor: .topLeading)

            context.draw(Text(target.sizeSummary)
                            .font(.system(size: 9, design: .rounded))
                            .foregroundColor(Palette.worthwhile),
                         at: CGPoint(x: centre.x, y: min(size.height - 7, objectRect.maxY + 8)),
                         anchor: .center)
        }
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
    }
}

/// The target's altitude curve over the night, drawn against the same sky
/// background as the main timeline.
struct TargetAltitudeChart: View {
    var plan: NightPlan
    var targetPlan: TargetPlan
    var minimumAltitude: Double

    var body: some View {
        GeometryReader { geometry in
            let axis = TimeAxis(window: plan.chartWindow, width: geometry.size.width)
            Canvas { context, size in
                drawBackground(context: context, size: size)
                drawGrid(context: context, size: size)
                drawUsableWindows(context: context, size: size, axis: axis)
                drawCurve(context: context, size: size)
                drawHourLabels(context: context, size: size, axis: axis)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
    }

    private func y(for altitude: Double, height: CGFloat) -> CGFloat {
        height - CGFloat(clamp(altitude / 90, 0, 1)) * (height - 14)
    }

    private func drawBackground(context: GraphicsContext, size: CGSize) {
        let samples = plan.samples
        guard samples.count > 1 else { return }
        let stepX = size.width / CGFloat(samples.count - 1)
        for (index, sample) in samples.enumerated() {
            let x = CGFloat(index) * stepX
            let rect = CGRect(x: x - stepX / 2, y: 0, width: stepX + 1, height: size.height)
            context.fill(Path(rect), with: .color(Palette.sky(sunAltitude: sample.sunAltitude)))
            if sample.moonAltitude > 0 && sample.moonBrightness > 0.01 {
                context.fill(Path(rect), with: .color(Palette.moonlight.opacity(0.3 * sample.moonBrightness)))
            }
        }
    }

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        for altitude in [30.0, 60.0] {
            var path = Path()
            let lineY = y(for: altitude, height: size.height)
            path.move(to: CGPoint(x: 0, y: lineY))
            path.addLine(to: CGPoint(x: size.width, y: lineY))
            context.stroke(path, with: .color(.white.opacity(0.14)), lineWidth: 1)
            context.draw(Text("\(Int(altitude))°").font(.system(size: 8)).foregroundColor(.white.opacity(0.45)),
                         at: CGPoint(x: 12, y: lineY - 6))
        }

        var threshold = Path()
        let thresholdY = y(for: minimumAltitude, height: size.height)
        threshold.move(to: CGPoint(x: 0, y: thresholdY))
        threshold.addLine(to: CGPoint(x: size.width, y: thresholdY))
        context.stroke(threshold, with: .color(Palette.marginal.opacity(0.75)),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }

    private func drawUsableWindows(context: GraphicsContext, size: CGSize, axis: TimeAxis) {
        for window in targetPlan.windows {
            let startX = axis.x(for: window.start)
            let endX = axis.x(for: window.end)
            let rect = CGRect(x: startX, y: 0, width: max(1, endX - startX), height: size.height)
            context.fill(Path(rect), with: .color(Palette.go.opacity(0.16)))
        }
    }

    private func drawCurve(context: GraphicsContext, size: CGSize) {
        let trace = targetPlan.altitudeTrace
        guard trace.count > 1 else { return }
        let stepX = size.width / CGFloat(trace.count - 1)
        var path = Path()
        for (index, altitude) in trace.enumerated() {
            let point = CGPoint(x: CGFloat(index) * stepX, y: y(for: altitude, height: size.height))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        context.stroke(path, with: .color(.white.opacity(0.92)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    private func drawHourLabels(context: GraphicsContext, size: CGSize, axis: TimeAxis) {
        let ticks = axis.hourTicks(timeZone: plan.timeZone)
        let step = (size.width / CGFloat(max(1, ticks.count))) < 34 ? 2 : 1
        for (index, tick) in ticks.enumerated() where index % step == 0 {
            context.draw(Text(Format.time(tick, in: plan.timeZone))
                            .font(.system(size: 8, design: .rounded))
                            .foregroundColor(.white.opacity(0.6)),
                         at: CGPoint(x: axis.x(for: tick), y: size.height - 5))
        }
    }
}
