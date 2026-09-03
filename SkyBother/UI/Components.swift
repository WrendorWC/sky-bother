import SwiftUI
import AppKit

/// The app's colour vocabulary. Everything is tuned for a dark room: the chart
/// backgrounds go genuinely black at astronomical darkness so the timeline reads
/// the way the night actually looks.
enum Palette {
    static let daylight = Color(red: 0.42, green: 0.62, blue: 0.86)
    static let civil = Color(red: 0.18, green: 0.24, blue: 0.45)
    static let nautical = Color(red: 0.07, green: 0.10, blue: 0.22)
    static let astronomical = Color(red: 0.025, green: 0.03, blue: 0.075)
    static let moonlight = Color(red: 0.98, green: 0.93, blue: 0.74)
    static let cloud = Color(red: 0.86, green: 0.89, blue: 0.94)
    /// The Milky Way band in the sky view — dim and cool so it reads as
    /// structure in the background rather than competing with targets.
    static let milkyWay = Color(red: 0.80, green: 0.84, blue: 0.92)
    /// A camera's framed field of view in the sky view — a clean,
    /// near-white "viewfinder" line, a distinct category from quality
    /// colours, selection violet, the Core's warm accent and the Milky
    /// Way's dim off-white.
    static let cameraFrame = Color(red: 0.95, green: 0.97, blue: 0.98)

    static let go = Color(red: 0.24, green: 0.78, blue: 0.47)
    static let worthwhile = Color(red: 0.30, green: 0.66, blue: 0.90)
    static let marginal = Color(red: 0.95, green: 0.70, blue: 0.24)
    static let skip = Color(red: 0.85, green: 0.36, blue: 0.34)

    /// The two verdict tiers `go`/`worthwhile`/`marginal`/`skip` don't cover.
    /// Both sit on the same red→green ladder as the other three rather than
    /// introducing an unrelated hue — gold or teal read as "caution" or
    /// "neutral" out of context, breaking the red-is-bad/green-is-good
    /// instinct the whole scheme depends on. `good` is the yellow-green step
    /// between `marginal` (amber) and `go` (green); `exceptional` is a
    /// brighter, more saturated green than `go` — still unmistakably "great",
    /// just further along the same ladder — with a glow to make it pop.
    static let good = Color(red: 0.70, green: 0.80, blue: 0.28)
    static let exceptional = Color(red: 0.20, green: 0.92, blue: 0.55)

    // MARK: - App chrome

    /// The app's own accent — a nebula violet, used for the tint and for
    /// anything that isn't already carrying a verdict colour.
    static let accent = Color(red: 0.62, green: 0.52, blue: 0.98)
    static let accentWarm = Color(red: 0.98, green: 0.55, blue: 0.62)

    /// Deep-space background, applied behind every window so the app reads as
    /// one dark, colour-tinted surface instead of the flat system background.
    static let spaceTop = Color(red: 0.055, green: 0.05, blue: 0.11)
    static let spaceBottom = Color(red: 0.10, green: 0.07, blue: 0.16)
    static let spaceBackground = LinearGradient(colors: [spaceTop, spaceBottom],
                                                startPoint: .top, endPoint: .bottom)

    /// A slightly raised panel on top of the space background, for cards and rows.
    static let panel = Color(red: 0.14, green: 0.12, blue: 0.20)
    static let panelBorder = Color(red: 0.62, green: 0.52, blue: 0.98).opacity(0.18)

    static func verdict(_ verdict: Verdict) -> Color {
        switch verdict {
        case .exceptional: return exceptional
        case .excellent: return go
        case .good: return good
        case .marginal: return marginal
        case .poor: return skip
        }
    }

    static func score(_ score: Double) -> Color {
        verdict(Verdict.forScore(score))
    }

    /// Sky colour for a given solar altitude, matching the twilight boundaries.
    static func sky(sunAltitude: Double) -> Color {
        switch sunAltitude {
        case 0...: return daylight
        case -6..<0: return blend(daylight, civil, smoothstep(0, -6, sunAltitude))
        case -12..<(-6): return blend(civil, nautical, smoothstep(-6, -12, sunAltitude))
        case -18..<(-12): return blend(nautical, astronomical, smoothstep(-12, -18, sunAltitude))
        default: return astronomical
        }
    }

    static func blend(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let clamped = clamp(t, 0, 1)
        let first = NSColor(a).usingColorSpace(.sRGB) ?? .black
        let second = NSColor(b).usingColorSpace(.sRGB) ?? .black
        return Color(red: first.redComponent + (second.redComponent - first.redComponent) * clamped,
                     green: first.greenComponent + (second.greenComponent - first.greenComponent) * clamped,
                     blue: first.blueComponent + (second.blueComponent - first.blueComponent) * clamped)
    }
}

extension View {
    /// The deep-space gradient every window sits on, so lists and forms read as
    /// part of one coloured surface instead of the flat system background.
    func spaceBackground() -> some View {
        background(Palette.spaceBackground.ignoresSafeArea())
    }

    /// A raised card on top of the space background — used for anything that
    /// would otherwise be a plain system-coloured row or box.
    func panelStyle(cornerRadius: CGFloat = 10) -> some View {
        background(Palette.panel, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Palette.panelBorder))
    }

    /// `.toolbarBackground(_:for:)` alone renders the default translucent
    /// grey toolbar material on top of the colour rather than replacing it —
    /// `.toolbarBackgroundVisibility(.visible, ...)` is what actually forces
    /// it, but that call only exists on macOS 15+. This applies it on the
    /// deployment targets that have it and falls back gracefully otherwise.
    @ViewBuilder
    func forcedToolbarBackground(_ color: Color) -> some View {
        if #available(macOS 15.0, *) {
            self.toolbarBackground(color, for: .windowToolbar)
                .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        } else {
            self.toolbarBackground(color, for: .windowToolbar)
        }
    }

}

/// SwiftUI's toolbar content claims nearly the full height of the title bar
/// for hit-testing on this app's layout — the custom sidebar-toggle and
/// refresh buttons, and the inline title item, are all sized to the toolbar's
/// full height — which leaves only the sliver right next to the traffic
/// lights as the OS's native double-click-to-zoom/drag territory. This
/// installs an invisible view behind everything else already in the window's
/// title bar container, so double-clicking or dragging any part of the header
/// that isn't literally on top of a button reaches the window the same way it
/// would with a plain, chrome-only title bar.
struct TitleBarZoomAndDragFix: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let probe = NSView(frame: .zero)
        DispatchQueue.main.async { install(from: probe) }
        return probe
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private func install(from probe: NSView) {
        guard let window = probe.window, let container = titlebarContainer(in: window) else { return }
        let markerID = NSUserInterfaceItemIdentifier("com.skybother.titlebarZoomFix")
        guard !container.subviews.contains(where: { $0.identifier == markerID }) else { return }

        // Pinned with real constraints, not a frame + autoresizingMask: at
        // the moment this runs, the toolbar hasn't necessarily finished
        // laying out yet (the sidebar toggle, title, and buttons further
        // right can all still be arriving), and this container manages its
        // own children with Auto Layout — a legacy autoresizing mask on a
        // sibling doesn't track that. A fixed frame captured this early
        // only ever covered whatever narrow width existed at that instant,
        // which is exactly why double-click/drag only worked in the sliver
        // near the traffic lights and stopped dead at the refresh button.
        let catcher = ZoomAndDragCatcherView(frame: .zero)
        catcher.identifier = markerID
        catcher.translatesAutoresizingMaskIntoConstraints = false
        if let frontmost = container.subviews.first {
            container.addSubview(catcher, positioned: .below, relativeTo: frontmost)
        } else {
            container.addSubview(catcher)
        }
        NSLayoutConstraint.activate([
            catcher.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            catcher.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            catcher.topAnchor.constraint(equalTo: container.topAnchor),
            catcher.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    /// The traffic lights' immediate superview is the classic title bar
    /// strip; its superview is the container that also holds the toolbar,
    /// spanning the full height of what reads on screen as "the header".
    private func titlebarContainer(in window: NSWindow) -> NSView? {
        window.standardWindowButton(.closeButton)?.superview?.superview
    }
}

private final class ZoomAndDragCatcherView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.isMovableByWindowBackground = true
        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick))
        doubleClick.numberOfClicksRequired = 2
        addGestureRecognizer(doubleClick)
    }

    @objc private func handleDoubleClick() {
        window?.performZoom(nil)
    }

    override var mouseDownCanMoveWindow: Bool { true }
}

extension Path {
    /// A smooth curve threaded through every point, rather than the sharp
    /// zig-zag straight `addLine` between them produces — used for the
    /// timeline's cloud outline, whose underlying samples only really change
    /// at hourly forecast boundaries, so a straight-line path reads as a
    /// series of harsh angular kinks next to the chart's other, smoother
    /// elements. Converts each span into a cubic Bézier using the classic
    /// Catmull-Rom construction (each segment's control points are derived
    /// from its neighbours), so the curve still passes exactly through the
    /// real data — this only changes how the gaps between points are drawn.
    static func smoothLine(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 1 else { return path }
        guard points.count > 2 else {
            path.addLine(to: points[1])
            return path
        }

        for i in 0..<(points.count - 1) {
            let p0 = i == 0 ? points[i] : points[i - 1]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = i + 2 < points.count ? points[i + 2] : points[i + 1]

            let control1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let control2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: control1, control2: control2)
        }
        return path
    }
}

/// A hand-built hover tooltip, standing in for the system `.help()` —
/// `.help()` isn't showing up reliably anywhere in this app, while the night
/// timeline's own hand-rolled hover readout (built the same way, off
/// `onHover`/`onContinuousHover`) does. This follows that same proven pattern
/// rather than continuing to fight the system tooltip.
private struct HoverTooltip: ViewModifier {
    var text: String
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .overlay(alignment: .top) {
                if isHovering {
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 6))
                        .frame(maxWidth: 260, alignment: .leading)
                        // `.overlay(alignment:)` proposes the tooltip its
                        // anchor's own width — often a small icon or badge,
                        // just a few points wide — which made Text wrap into
                        // a near-vertical column of single characters.
                        // `.fixedSize()` (both axes) makes it use its natural
                        // width instead, capped at 260 by the frame above,
                        // wrapping only once the text is actually that long.
                        .fixedSize()
                        .offset(y: -26)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .zIndex(10)
                }
            }
            .animation(.easeInOut(duration: 0.1), value: isHovering)
    }
}

extension View {
    /// A custom hover tooltip — see `HoverTooltip`. Use this instead of
    /// `.help()` anywhere in this app; `.help()` does not reliably appear.
    func hoverTooltip(_ text: String) -> some View {
        modifier(HoverTooltip(text: text))
    }
}

/// Reports how far a view's bottom edge has scrolled, within a named
/// coordinate space — used by the target inspector's collapsing sticky
/// header to know when the full headline has scrolled out of view.
struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Maps dates onto horizontal positions for every chart in the app, so the night
/// timeline and each target's availability bar share one time axis.
struct TimeAxis {
    var window: TimeWindow
    var width: CGFloat

    func x(for date: Date) -> CGFloat {
        let span = window.duration
        guard span > 0 else { return 0 }
        let fraction = clamp(date.timeIntervalSince(window.start) / span, 0, 1)
        return CGFloat(fraction) * width
    }

    /// Inverse of `x(for:)` — the date at a given horizontal position, for
    /// turning a click or drag location back into a point in time.
    func date(for x: CGFloat) -> Date {
        let fraction = clamp(Double(x / max(1, width)), 0, 1)
        return window.start.addingTimeInterval(window.duration * fraction)
    }

    /// Whole-hour tick marks inside the window, in the site's local time.
    func hourTicks(timeZone: TimeZone) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard var cursor = calendar.nextDate(after: window.start,
                                             matching: DateComponents(minute: 0),
                                             matchingPolicy: .nextTime) else { return [] }
        var ticks: [Date] = []
        while cursor < window.end && ticks.count < 40 {
            ticks.append(cursor)
            guard let next = calendar.date(byAdding: .hour, value: 1, to: cursor) else { break }
            cursor = next
        }
        return ticks
    }
}

/// A radial gauge rather than a flat badge — the ring itself reads as a
/// fraction of 100 before you even look at the number, and an exceptional
/// score gets a soft glow so it's unmistakable next to an ordinary one.
struct ScoreBadge: View {
    var score: Double
    var size: CGFloat = 40

    private var color: Color { Palette.score(score) }
    private var isExceptional: Bool { Verdict.forScore(score) == .exceptional }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.09), lineWidth: max(2, size * 0.1))
            Circle()
                .trim(from: 0, to: max(0.015, min(1, score / 100)))
                .stroke(color, style: StrokeStyle(lineWidth: max(2, size * 0.1), lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(score.rounded()))")
                .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
        .shadow(color: isExceptional ? color.opacity(0.75) : .clear, radius: isExceptional ? size * 0.2 : 0)
        .animation(.easeInOut(duration: 0.35), value: score)
    }
}

struct VerdictTag: View {
    var verdict: Verdict

    private var color: Color { Palette.verdict(verdict) }
    private var isExceptional: Bool { verdict == .exceptional }

    var body: some View {
        Text(verdict.rawValue)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(isExceptional ? 0.32 : 0.2), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(isExceptional ? 0.7 : 0)))
            .foregroundStyle(color)
            .shadow(color: isExceptional ? color.opacity(0.5) : .clear, radius: isExceptional ? 6 : 0)
            .animation(.easeInOut(duration: 0.25), value: verdict)
    }
}

/// A labelled 0-100% bar, used for score factors and conditions.
struct FactorBar: View {
    var factor: ScoreFactor
    /// Points the overall score would gain if this factor were perfect. See
    /// `scoreImpact(of:in:actualScore:)` — this is always the real
    /// counterfactual, never a display-only estimate, and is shown even when
    /// it rounds to zero so every factor carries the same kind of indicator
    /// and a glance at the column tells you which ones actually cost you
    /// points versus which were along for the ride.
    var impact: Double = 0

    private var factorVerdict: Verdict { Verdict.forScore(Double(factor.percentage)) }
    private var color: Color { Palette.verdict(factorVerdict) }
    private var roundedImpact: Int { Int(impact.rounded()) }

    /// Severity-scaled rather than a flat colour, so a factor that's actually
    /// costing points jumps out instead of reading the same as every other
    /// mostly-green bar.
    private var impactColor: Color {
        switch roundedImpact {
        case 8...: return Palette.skip
        case 3...7: return Palette.marginal
        case 1...2: return .secondary
        default: return .secondary.opacity(0.55)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(factor.name)
                    .font(.callout)
                Text(factorVerdict.rawValue)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color)
                Spacer()
                // The impact number is the thing worth scanning for — bigger
                // and bolder than the bar itself, not a footnote next to it.
                Text(roundedImpact >= 1 ? "−\(roundedImpact)" : "0")
                    .font(.callout.monospacedDigit().weight(roundedImpact >= 3 ? .bold : .semibold))
                    .foregroundStyle(impactColor)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(color)
                        .frame(width: max(2, geometry.size.width * factor.value))
                        .animation(.easeOut(duration: 0.45), value: factor.value)
                }
            }
            .frame(height: 5)
            Text(factor.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct LabelledValue: View {
    var label: String
    var value: String
    var systemImage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption)
                        .foregroundStyle(Palette.accent)
                }
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            // This row's item count varies (weather data isn't always
            // available), so its available width per item does too. Two
            // lines' worth of height is always reserved, whether the value
            // needs it or not, so a narrower item never wraps and grows the
            // whole statistics row's height — and on the rare value that
            // still doesn't fit even across two lines, it trails off with an
            // ellipsis rather than growing further, with the untruncated
            // text one hover away instead of just being lost.
            Text(value)
                .font(.title3.weight(.medium))
                .monospacedDigit()
                .lineLimit(2, reservesSpace: true)
                .hoverTooltip(value)
        }
    }
}

/// A time window with its zenith-risk portion marked directly on it, rather
/// than the risk living only in a warning string elsewhere — a segmented bar
/// plus inline labels, e.g. "21:18 ━━━ ⚠ Zenith risk 23:15 ━━━━━ 03:53".
struct ZenithRiskWindowBar: View {
    var window: TimeWindow
    var risk: TimeWindow
    var timeZone: TimeZone

    private var beforeFraction: Double {
        guard window.duration > 0 else { return 0 }
        return clamp(risk.start.timeIntervalSince(window.start) / window.duration, 0, 1)
    }
    private var riskFraction: Double {
        guard window.duration > 0 else { return 0 }
        return clamp(risk.duration / window.duration, 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.accent.opacity(0.4))
                    Capsule()
                        .fill(Palette.marginal)
                        .frame(width: max(2, width * riskFraction))
                        .offset(x: width * beforeFraction)
                }
            }
            .frame(height: 5)
            HStack(spacing: 5) {
                Text(Format.time(window.start, in: timeZone))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Label {
                    Text("Zenith risk \(Format.time(risk.start, in: timeZone))")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .imageScale(.small)
                }
                .foregroundStyle(Palette.marginal)
                Spacer(minLength: 4)
                Text(Format.time(window.end, in: timeZone))
                    .foregroundStyle(.secondary)
            }
            .font(.caption.monospacedDigit())
        }
    }
}

struct WarningRow: View {
    var text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Palette.marginal)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// An actual rendered phase disc rather than a flat SF Symbol — the real
/// terminator shape, so a glance tells you crescent from gibbous and which
/// way it's heading, not just "there's a moon icon here".
struct MoonPhaseDisc: View {
    var illuminatedFraction: Double
    var isWaxing: Bool
    var diameter: CGFloat = 20
    var litColor: Color = Palette.moonlight
    var darkColor: Color = Color.black.opacity(0.55)

    var body: some View {
        Canvas { context, size in
            let r = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let discRect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            let discPath = Path(ellipseIn: discRect)

            context.fill(discPath, with: .color(darkColor))

            let f = clamp(illuminatedFraction, 0, 1)
            if f > 0.01 {
                let limbRight = isWaxing
                let limbRect = CGRect(x: limbRight ? center.x : discRect.minX, y: discRect.minY,
                                      width: r, height: discRect.height)
                let otherRect = CGRect(x: limbRight ? discRect.minX : center.x, y: discRect.minY,
                                       width: r, height: discRect.height)

                context.drawLayer { outer in
                    outer.clip(to: discPath)
                    outer.fill(Path(limbRect), with: .color(litColor))

                    if f < 0.5 {
                        // Crescent: the limb half, minus a central cap that
                        // shrinks to nothing as the sliver grows toward quarter.
                        let rx = r * (1 - 2 * f)
                        let capRect = CGRect(x: center.x - rx, y: discRect.minY, width: rx * 2, height: discRect.height)
                        outer.drawLayer { inner in
                            inner.clip(to: Path(limbRect))
                            inner.fill(Path(ellipseIn: capRect), with: .color(darkColor))
                        }
                    } else if f < 0.99 {
                        // Gibbous: the limb half plus a growing cap bulging
                        // into the other half from the centre line outward.
                        let rx = r * (2 * f - 1)
                        let capRect = CGRect(x: center.x - rx, y: discRect.minY, width: rx * 2, height: discRect.height)
                        outer.drawLayer { inner in
                            inner.clip(to: Path(otherRect))
                            inner.fill(Path(ellipseIn: capRect), with: .color(litColor))
                        }
                    } else {
                        outer.fill(Path(otherRect), with: .color(litColor))
                    }
                }
            }

            context.stroke(discPath, with: .color(.white.opacity(0.22)), lineWidth: 1)
        }
        .frame(width: diameter, height: diameter)
    }
}

/// A minimal deterministic xorshift generator — `Double.random`/`CGFloat.random`
/// still work with it via the `RandomNumberGenerator` protocol, but the
/// sequence only depends on the seed, not on when it's called. Used anywhere
/// a `Canvas` redraws often (hover, scrub) and needs a starfield that doesn't
/// visibly flicker, which plain unseeded randomness would.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: Int) {
        let bits = UInt64(bitPattern: Int64(seed))
        state = bits == 0 ? 0x9E3779B97F4A7C15 : bits
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

/// Draws a sparse, stable starfield into `context` — seeded from `seed` so
/// it's the same on every redraw for a given target rather than flickering.
/// Shared by the framing preview's background and the "no photo" placeholder,
/// so the app has one visual language for "here's some sky" rather than two.
func drawStarfield(context: GraphicsContext, size: CGSize, seed: String) {
    var generator = SeededGenerator(seed: seed.hashValue)
    let starCount = Int((size.width * size.height) / 900)
    for _ in 0..<starCount {
        let x = CGFloat.random(in: 0...size.width, using: &generator)
        let y = CGFloat.random(in: 0...size.height, using: &generator)
        let radius = CGFloat.random(in: 0.4...1.3, using: &generator)
        let opacity = Double.random(in: 0.12...0.45, using: &generator)
        context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                     with: .color(.white.opacity(opacity)))
    }
}

/// A target's reference photo, if the built-in catalog has one, filling and
/// cropping its space. Falls back to a starry "no photo" placeholder so
/// callers never have to branch on whether a given target has art — most of
/// the ~1000 extended-catalog objects don't have a Wikipedia photo to draw
/// from, so this is the common case, not a rare edge case.
struct TargetThumbnail: View {
    var designation: String
    var contentMode: ContentMode = .fill

    var body: some View {
        if let image = TargetImageCatalog.nsImage(for: designation) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            GeometryReader { geometry in
                ZStack {
                    Palette.spaceTop
                    Canvas { context, size in
                        drawStarfield(context: context, size: size, seed: designation)
                    }
                    VStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.title3)
                            .foregroundStyle(.tertiary)
                        // Only worth the label where there's room to read it —
                        // this same view renders at everything from a 56pt row
                        // icon up to a 300pt detail sheet.
                        if geometry.size.height > 90 {
                            Text("No Photo Available")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }
}
