import SwiftUI

/// The night at a glance: sky darkness as the background, cloud coming down from
/// the top, moonlight washing over it, and the twilight boundaries marked. This
/// is the chart the whole app is arranged around — every target bar below it
/// shares the same time axis, so you can read straight down a column.
struct NightTimelineView: View {
    @EnvironmentObject private var state: AppState

    var plan: NightPlan
    var height: CGFloat = 152
    var showsHourLabels: Bool = true
    /// When set, the target's altitude curve and usable/optimal windows are
    /// overlaid directly on this chart — the centerpiece view answering
    /// "why is this target best at this particular time?" without needing a
    /// second chart to compare against.
    var selectedTarget: TargetPlan? = nil

    @State private var hoverLocation: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            let axis = TimeAxis(window: plan.chartWindow, width: geometry.size.width)

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    drawSky(context: context, size: size)
                    drawCloud(context: context, size: size)
                    drawMoonTrace(context: context, size: size)
                    if let selectedTarget {
                        drawSelectedTarget(context: context, size: size, axis: axis, target: selectedTarget)
                    }
                    drawBoundaries(context: context, size: size, axis: axis)
                    if showsHourLabels {
                        drawHourTicks(context: context, size: size, axis: axis)
                    }
                    drawNowMarker(context: context, size: size, axis: axis)
                }

                if let hoverLocation {
                    hoverReadout(at: hoverLocation, axis: axis, size: geometry.size)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): hoverLocation = location
                case .ended: hoverLocation = nil
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.panelBorder))
    }

    // MARK: - Layers

    private func drawSky(context: GraphicsContext, size: CGSize) {
        let samples = plan.samples
        guard samples.count > 1 else {
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.astronomical))
            return
        }
        let stepX = size.width / CGFloat(samples.count - 1)

        for (index, sample) in samples.enumerated() {
            let x = CGFloat(index) * stepX
            let rect = CGRect(x: x - stepX / 2, y: 0, width: stepX + 1, height: size.height)
            context.fill(Path(rect), with: .color(Palette.sky(sunAltitude: sample.sunAltitude)))

            // Moonlight lifts the background wherever the moon is above the
            // horizon, in proportion to how much light it is actually throwing.
            if sample.moonAltitude > 0 && sample.moonBrightness > 0.01 {
                let wash = 0.34 * sample.moonBrightness
                context.fill(Path(rect), with: .color(Palette.moonlight.opacity(wash)))
            }
        }
    }

    private func drawCloud(context: GraphicsContext, size: CGSize) {
        guard plan.hasWeather else { return }
        let samples = plan.samples
        guard samples.count > 1 else { return }
        let stepX = size.width / CGFloat(samples.count - 1)
        let maximumDepth = size.height * 0.68

        // The chart samples every few minutes, but the forecast itself only
        // actually changes at hourly boundaries — everything between two
        // hours is already a straight line, so a smooth curve through every
        // dense sample barely rounds anything (neighbouring samples are
        // colinear). Threading it through roughly one point per hour, where
        // the real direction changes are, is what actually rounds the
        // zig-zag instead of leaving it looking the same at a glance.
        let intervalMinutes = max(1.0, samples[1].date.timeIntervalSince(samples[0].date) / 60)
        let samplesPerHour = max(1, Int((60 / intervalMinutes).rounded()))
        var hourIndices = Array(stride(from: 0, to: samples.count, by: samplesPerHour))
        if hourIndices.last != samples.count - 1 { hourIndices.append(samples.count - 1) }

        let points = hourIndices.map { index -> CGPoint in
            let x = CGFloat(index) * stepX
            let depth = CGFloat(clamp(samples[index].cloudCover / 100, 0, 1)) * maximumDepth
            return CGPoint(x: x, y: depth)
        }

        var path = Path.smoothLine(through: points)
        path.addLine(to: CGPoint(x: size.width, y: 0))
        path.addLine(to: CGPoint(x: 0, y: 0))
        path.closeSubpath()

        context.fill(path, with: .linearGradient(
            Gradient(colors: [Palette.cloud.opacity(0.72), Palette.cloud.opacity(0.34)]),
            startPoint: .zero,
            endPoint: CGPoint(x: 0, y: maximumDepth)))

        // A crisp lower edge makes the cloud line readable against dark sky.
        context.stroke(Path.smoothLine(through: points), with: .color(Palette.cloud.opacity(0.85)), lineWidth: 1)
    }

    /// A thin arc showing the moon's altitude through the night, drawn only over
    /// the part of the night where it is actually up.
    private func drawMoonTrace(context: GraphicsContext, size: CGSize) {
        let samples = plan.samples
        guard samples.count > 1 else { return }
        let stepX = size.width / CGFloat(samples.count - 1)
        let baseline = size.height - 4.0

        var path = Path()
        var started = false
        for (index, sample) in samples.enumerated() {
            let x = CGFloat(index) * stepX
            guard sample.moonAltitude > 0 else { started = false; continue }
            let y = baseline - CGFloat(clamp(sample.moonAltitude / 90, 0, 1)) * (size.height * 0.42)
            if started {
                path.addLine(to: CGPoint(x: x, y: y))
            } else {
                path.move(to: CGPoint(x: x, y: y))
                started = true
            }
        }
        context.stroke(path, with: .color(Palette.moonlight.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
    }

    /// The selected target's own altitude curve, its usable windows, and its
    /// single best window — laid on the same axis as everything else, so you
    /// can read straight up from "best window" to "why": what the sky and
    /// moon are doing at that exact moment.
    /// Everything selection-related uses the app's one accent colour rather
    /// than the target's own score colour — score colour means quality
    /// everywhere else in the app (the badges, the factor bars), and reusing
    /// it here would blur that meaning. Violet reads unambiguously as "this
    /// is the thing you picked," and it's the same colour selection uses in
    /// the sidebar and target list, so the whole app agrees on one selection
    /// language instead of each view inventing its own.
    private func drawSelectedTarget(context: GraphicsContext, size: CGSize, axis: TimeAxis, target: TargetPlan) {
        let color = Palette.accent
        func y(for altitude: Double) -> CGFloat {
            size.height - CGFloat(clamp(altitude / 90, 0, 1)) * (size.height - 16)
        }

        for window in target.windows {
            let startX = axis.x(for: window.start)
            let endX = axis.x(for: window.end)
            let rect = CGRect(x: startX, y: 0, width: max(1, endX - startX), height: size.height)
            context.fill(Path(rect), with: .color(color.opacity(0.08)))
        }

        if let best = target.bestWindow, !best.isEmpty {
            let startX = axis.x(for: best.start)
            let endX = axis.x(for: best.end)
            let rect = CGRect(x: startX, y: 0, width: max(1, endX - startX), height: size.height)
            // A translucent fill with a thin, solid edge reads as "this
            // window" without the heavier dashed box competing for attention.
            context.fill(Path(rect), with: .color(color.opacity(0.16)))
            context.stroke(Path(rect), with: .color(color.opacity(0.5)), lineWidth: 1)
        }

        for altitude in [30.0, 60.0] {
            var grid = Path()
            grid.move(to: CGPoint(x: 0, y: y(for: altitude)))
            grid.addLine(to: CGPoint(x: size.width, y: y(for: altitude)))
            context.stroke(grid, with: .color(.white.opacity(0.08)), lineWidth: 1)
        }

        // Highest-priority element on the whole chart: the selected target's
        // altitude, so it needs to visibly outrank the moon trace and cloud
        // silhouette rather than compete with them as just another line.
        let trace = target.altitudeTrace
        if trace.count > 1 {
            let stepX = size.width / CGFloat(trace.count - 1)
            var path = Path()
            for (index, altitude) in trace.enumerated() {
                let point = CGPoint(x: CGFloat(index) * stepX, y: y(for: altitude))
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(color),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }

        if let best = target.bestTime, plan.chartWindow.contains(best) {
            let x = axis.x(for: best)
            var mark = Path()
            mark.move(to: CGPoint(x: x, y: 0))
            mark.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(mark, with: .color(color), lineWidth: 1.5)
            context.draw(Text(target.target.displayName)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.white),
                         at: CGPoint(x: min(size.width - 6, x + 6), y: 12),
                         anchor: .topLeading)
        }
    }

    private func drawBoundaries(context: GraphicsContext, size: CGSize, axis: TimeAxis) {
        let style = StrokeStyle(lineWidth: 1, dash: [3, 3])
        let markers: [(Date?, String)] = [
            (plan.astronomicalDusk, "dark"),
            (plan.astronomicalDawn, "dawn")
        ]
        for (date, label) in markers {
            guard let date, plan.chartWindow.contains(date) else { continue }
            let x = axis.x(for: date)
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(path, with: .color(.white.opacity(0.42)), style: style)
            context.draw(Text(label).font(.system(size: 9)).foregroundColor(.white.opacity(0.7)),
                         at: CGPoint(x: x + 15, y: 10))
        }
    }

    private func drawHourTicks(context: GraphicsContext, size: CGSize, axis: TimeAxis) {
        let ticks = axis.hourTicks(timeZone: plan.timeZone)
        guard !ticks.isEmpty else { return }
        // Thin the labels out when the chart is narrow.
        let spacing = size.width / CGFloat(max(1, ticks.count))
        let step = spacing < 34 ? 2 : 1

        for (index, tick) in ticks.enumerated() {
            let x = axis.x(for: tick)
            var path = Path()
            path.move(to: CGPoint(x: x, y: size.height - 14))
            path.addLine(to: CGPoint(x: x, y: size.height - 10))
            context.stroke(path, with: .color(.white.opacity(0.35)), lineWidth: 1)

            guard index % step == 0 else { continue }
            context.draw(Text(Format.time(tick, in: plan.timeZone))
                            .font(.system(size: 9, design: .rounded))
                            .foregroundColor(.white.opacity(0.75)),
                         at: CGPoint(x: x, y: size.height - 5))
        }
    }

    private func drawNowMarker(context: GraphicsContext, size: CGSize, axis: TimeAxis) {
        let now = Date()
        guard plan.chartWindow.contains(now) else { return }
        let x = axis.x(for: now)
        var path = Path()
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(path, with: .color(Palette.skip.opacity(0.9)), lineWidth: 1.5)
        context.draw(Text("now").font(.system(size: 9, weight: .semibold)).foregroundColor(Palette.skip),
                     at: CGPoint(x: x + 15, y: size.height - 24))
    }

    // MARK: - Hover

    @ViewBuilder
    private func hoverReadout(at location: CGPoint, axis: TimeAxis, size: CGSize) -> some View {
        let fraction = clamp(Double(location.x / max(1, size.width)), 0, 1)
        let date = plan.chartWindow.start.addingTimeInterval(plan.chartWindow.duration * fraction)
        if let sample = nearestSample(to: date) {
            let x = axis.x(for: date)
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 1, height: size.height)
                    .offset(x: x)
                readoutCard(sample: sample)
                    .offset(x: min(max(0, x - 70), max(0, size.width - 150)), y: 8)
            }
            .allowsHitTesting(false)
        }
    }

    private func readoutCard(sample: NightSample) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(Format.time(sample.date, in: plan.timeZone))
                .font(.callout.weight(.semibold).monospacedDigit())
            if sample.hasWeather {
                Text("\(Int(sample.cloudCover))% cloud · \(Format.temperature(celsius: sample.temperature, imperial: state.preferences.usesImperialUnits))")
                    .font(.caption)
            }
            Text("darkness \(Int(sample.darkness * 100))%")
                .font(.caption)
            if sample.moonAltitude > 0 {
                Text("moon \(Format.degrees(sample.moonAltitude)) up")
                    .font(.caption)
            }
        }
        .foregroundStyle(.white)
        .padding(8)
        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 6))
        .frame(width: 170, alignment: .leading)
    }

    private func nearestSample(to date: Date) -> NightSample? {
        plan.samples.min { a, b in
            abs(a.date.timeIntervalSince(date)) < abs(b.date.timeIntervalSince(date))
        }
    }
}

/// A single target's availability across the same time axis as the night chart.
struct TargetAvailabilityBar: View {
    var plan: NightPlan
    var targetPlan: TargetPlan
    var height: CGFloat = 26

    var body: some View {
        GeometryReader { geometry in
            let axis = TimeAxis(window: plan.chartWindow, width: geometry.size.width)
            Canvas { context, size in
                // Track.
                context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 3),
                             with: .color(Color.primary.opacity(0.07)))

                // Altitude trace, so you can see it climb and set even outside
                // the usable window.
                drawAltitude(context: context, size: size)

                // Usable windows.
                for window in targetPlan.windows {
                    let startX = axis.x(for: window.start)
                    let endX = axis.x(for: window.end)
                    let rect = CGRect(x: startX, y: 0, width: max(2, endX - startX), height: size.height)
                    context.fill(Path(roundedRect: rect, cornerRadius: 3),
                                 with: .color(Palette.score(targetPlan.score).opacity(0.55)))
                }

                // Where it is highest.
                if let best = targetPlan.bestTime, plan.chartWindow.contains(best) {
                    let x = axis.x(for: best)
                    var mark = Path()
                    mark.move(to: CGPoint(x: x, y: 0))
                    mark.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(mark, with: .color(Palette.score(targetPlan.score)), lineWidth: 1.5)
                }
            }
        }
        .frame(height: height)
    }

    private func drawAltitude(context: GraphicsContext, size: CGSize) {
        let trace = targetPlan.altitudeTrace
        guard trace.count > 1 else { return }
        let stepX = size.width / CGFloat(trace.count - 1)
        var path = Path()
        for (index, altitude) in trace.enumerated() {
            let x = CGFloat(index) * stepX
            let y = size.height - CGFloat(clamp(altitude / 90, 0, 1)) * size.height
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        context.stroke(path, with: .color(Color.primary.opacity(0.28)), lineWidth: 1)
    }
}
