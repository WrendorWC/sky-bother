import SwiftUI
import AppKit

/// Threaded from `Preferences.textScale` at the root of every scene.
/// SwiftUI's own Dynamic Type (`.dynamicTypeSize`) was tried first as the
/// mechanism for scaling semantic-style text (`.title2`, `.callout`,
/// `.caption`…) but proved not to reliably grow this app's text in practice —
/// verified by hand against a running build, not just in theory — so every
/// font in the app, semantic styles included, is scaled explicitly through
/// this one multiplier instead. `Font.scaled(_:scale:)` below is the
/// semantic-style half of that; a `.font(.system(size: 11 * uiTextScale))`
/// read directly is the fixed-point half, for chart labels, badges and
/// hand-drawn Canvas text that were never expressed as a style to begin with.
private struct UITextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var uiTextScale: CGFloat {
        get { self[UITextScaleKey.self] }
        set { self[UITextScaleKey.self] = newValue }
    }
}

extension View {
    func appTextScale(_ scale: Double) -> some View {
        self.environment(\.uiTextScale, CGFloat(scale))
    }
}

// MARK: - Fitting the UI to the window

/// How much room the tightest must-fit row has, as a ratio of what it
/// needs: 1 is an exact fit, under 1 means something is being cut off or
/// wrapped. Every row that reports contributes, and the smallest wins.
struct OneLineFitKey: PreferenceKey {
    static let defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

/// Compares the width a row is given with the width it would take laid out
/// on one line with nothing cut off, measured on a hidden copy of itself.
private struct OneLineFitProbe: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            GeometryReader { given in
                content
                    .fixedSize()
                    .hidden()
                    .background(
                        GeometryReader { wanted in
                            Color.clear.preference(key: OneLineFitKey.self,
                                                   value: given.size.width / max(1, wanted.size.width))
                        }
                    )
            }
        )
    }
}

extension View {
    /// Marks a row the automatic UI scale must keep on one line and uncut.
    func reportsOneLineFit() -> some View {
        modifier(OneLineFitProbe())
    }

    /// Reports this column's tightest must-fit row to the automatic UI
    /// scale. Once per column, not once for the window: a split view's
    /// columns are hosted separately, and what's measured inside one never
    /// reaches a modifier on the split view itself.
    func reportsFitsToAutoScale(_ state: AppState, column: String) -> some View {
        onPreferenceChange(OneLineFitKey.self) { ratio in
            state.reportOneLineFit(ratio, column: column)
        }
    }
}

extension GraphicsContext {
    /// Draws a label centred in a block, shortened with an ellipsis when the
    /// whole thing wouldn't fit. Canvas text isn't clipped to anything, so a
    /// long name drawn centred in a narrow block ran out over its neighbours
    /// and the two names overlapped into nonsense.
    func drawLabel(_ string: String, font: Font, color: Color = .white,
                   in rect: CGRect, padding: CGFloat = 6) {
        let available = rect.width - padding * 2
        // Narrower than this there is no room for even a word and an
        // ellipsis, and a block that small reads as its colour alone.
        guard available > 24 else { return }
        func resolved(_ text: String) -> ResolvedText {
            resolve(Text(text).font(font).foregroundColor(color))
        }
        func width(_ text: String) -> CGFloat {
            resolved(text).measure(in: CGSize(width: .greatestFiniteMagnitude, height: rect.height)).width
        }

        var label = string
        if width(label) > available {
            var characters = Array(string)
            while characters.count > 1 && width(String(characters) + "\u{2026}") > available {
                characters.removeLast()
            }
            guard characters.count > 1 else { return }
            label = String(characters).trimmingCharacters(in: .whitespaces) + "\u{2026}"
        }
        draw(resolved(label), at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
    }
}

/// Lays its items out left to right and starts a new row when the next one
/// won't fit, so nothing is ever cut short — whole items move down instead.
struct FlowLayout: Layout {
    var spacing: CGFloat = 16
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y),
                          proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

extension Font {
    /// A semantic style's usual macOS point size, multiplied by the app's
    /// text-size preference. Callers keep chaining `.weight(...)`,
    /// `.monospacedDigit()` and the like onto the result exactly as they did
    /// onto the bare style before — only the base size changed, e.g.
    /// `.callout.weight(.semibold)` becomes
    /// `.scaled(.callout, scale: uiTextScale).weight(.semibold)`.
    static func scaled(_ style: TextStyle, scale: CGFloat) -> Font {
        .system(size: basePointSize(for: style) * scale)
    }

    private static func basePointSize(for style: TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 26
        case .title: return 22
        case .title2: return 17
        case .title3: return 15
        case .headline: return 13
        case .body: return 13
        case .callout: return 12
        case .subheadline: return 11
        case .footnote: return 10
        case .caption: return 10
        case .caption2: return 10
        @unknown default: return 13
        }
    }
}

/// The app's colour vocabulary. Everything is tuned for a dark room: the chart
/// backgrounds go genuinely black at astronomical darkness so the timeline reads
/// the way the night actually looks.
enum Palette {
    static let daylight = Color(red: 0.42, green: 0.62, blue: 0.86)
    static let civil = Color(red: 0.18, green: 0.24, blue: 0.45)
    static let nautical = Color(red: 0.07, green: 0.10, blue: 0.22)
    static let astronomical = Color(red: 0.025, green: 0.03, blue: 0.075)
    static let moonlight = Color(red: 0.98, green: 0.93, blue: 0.74)
    /// Warmer and brighter than moonlight, so the two discs never read as the same thing.
    static let sunlight = Color(red: 1.0, green: 0.86, blue: 0.45)
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

    /// Green, yellow, orange, red — the order everyone already reads a risk
    /// scale in, so the dots under the night chart need no key.
    static func dewRisk(_ level: DewRiskLevel) -> Color {
        switch level {
        case .low: return go
        case .moderate: return Color(red: 0.93, green: 0.84, blue: 0.30)
        case .high: return Color(red: 0.96, green: 0.56, blue: 0.22)
        case .veryHigh: return skip
        }
    }

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

extension Scene {
    /// Lets a secondary window — settings, the catalog, help, the sky browser — open
    /// over a full-screen main window instead of as a full-screen space of
    /// its own.
    ///
    /// A plain window group's windows are full-screen primaries, so with the
    /// main window in full screen SwiftUI opened the catalog as a second
    /// full-screen space — the main window vanished into another Space and
    /// the catalog had no title bar to close it by — or, for Help, put it on
    /// the ordinary desktop in a Space the user wasn't looking at. Marking
    /// the NSWindow from inside its content came too late: SwiftUI has
    /// already put the window on screen by then. An associated role is set
    /// on the scene, before any window exists, and keeps these windows with
    /// the main one. It only exists from macOS 15; on 14 they behave as before.
    func associatedWindow() -> some Scene {
        if #available(macOS 15.0, *) {
            return windowManagerRole(.associated)
        } else {
            return self
        }
    }
}

/// SwiftUI's inline toolbar title is an `NSToolbarTitleView` that spans the
/// whole strip between the leading toolbar buttons and the trailing ones, at
/// the full height of the header, and it swallows mouse-downs instead of
/// letting them reach the window. That left the sliver between the traffic
/// lights and the first toolbar button as the only part of the header that
/// still dragged or double-clicked like a title bar — everything from the
/// site name across to the buttons on the right was dead.
///
/// This puts a transparent catcher in front of the entire header that drags
/// and zooms the window itself, and hit-tests itself out of the way wherever
/// something real lives: a toolbar item, a traffic light, or the sidebar's
/// draggable split separator.
struct TitleBarZoomAndDragFix: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { TitleBarFixProbe(frame: .zero) }

    /// Re-checked on updates as well as on the way into a window: leaving
    /// and returning from full screen rebuilds the title bar's view tree,
    /// and the catcher has to be put back when it does.
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? TitleBarFixProbe)?.installIfNeeded()
    }
}

/// A zero-sized view living in the window's content, there only to get a
/// handle on the window so the catcher can be installed in its title bar.
private final class TitleBarFixProbe: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installIfNeeded()
    }

    func installIfNeeded() {
        // The traffic lights' immediate superview is the classic title bar
        // strip; its superview is the container that also holds the toolbar,
        // spanning the full height of what reads on screen as "the header".
        guard let container = window?.standardWindowButton(.closeButton)?.superview?.superview,
              !container.subviews.contains(where: { $0 is TitleBarDragCatcherView }) else { return }

        // In front of everything, not behind it: the views that eat the
        // mouse-down (the title view chief among them) are themselves in
        // front of anything a sibling could be slipped behind. Pinned with
        // real constraints rather than a frame, because this container lays
        // its children out with Auto Layout and the toolbar hasn't
        // necessarily finished arriving when this runs.
        let catcher = TitleBarDragCatcherView(frame: .zero)
        catcher.owner = window
        catcher.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(catcher, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            catcher.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            catcher.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            catcher.topAnchor.constraint(equalTo: container.topAnchor),
            catcher.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }
}

private final class TitleBarDragCatcherView: NSView {
    /// Room around each control that still belongs to the control rather
    /// than to the bar, so a click just off a button's edge doesn't start
    /// dragging the window out from under it.
    private static let passthroughSlop: CGFloat = 4

    /// We want the mouse-down ourselves rather than having AppKit move the
    /// window for us, so that a double click can be told apart from the
    /// start of a drag. `performDrag(with:)` then does exactly what a
    /// background drag would have done anyway.
    override var mouseDownCanMoveWindow: Bool { false }

    /// So an inactive window can be dragged with a single click, the way a
    /// plain title bar can.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The window whose title bar this is. In full screen AppKit moves the
    /// title bar into a separate toolbar window, so `window` stops being it.
    weak var owner: NSWindow?

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Out of the way entirely in full screen. There is no window to drag
        // or zoom there, and the title bar has moved into a toolbar window of
        // its own whose `toolbar` is nil — so no toolbar buttons were found
        // to let through, and every click on Settings, Catalog and Help was
        // swallowed.
        if owner?.styleMask.contains(.fullScreen) ?? false { return nil }
        guard let superview, let window else { return nil }
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        let inWindow = convert(local, to: nil)

        for view in passthroughViews(in: window) {
            let rect = view.convert(view.bounds, to: nil)
                .insetBy(dx: -Self.passthroughSlop, dy: -Self.passthroughSlop)
            if rect.contains(inWindow) { return nil }
        }
        return self
    }

    /// Every click goes to `performDrag(with:)`, including the second of a
    /// double click, because it already implements the whole standard title
    /// bar gesture — the drag *and* the System Settings double-click action.
    ///
    /// This used to intercept `clickCount == 2` and perform that action
    /// itself. The first click's `performDrag` went on to recognise the very
    /// same double click and act on it too, so a double click zoomed the
    /// window and immediately un-zoomed it. Letting AppKit own the gesture
    /// end to end is what keeps it happening exactly once, and honours the
    /// Minimize/None/Zoom preference without this having to read it.
    override func mouseDown(with event: NSEvent) {
        guard let window else { return super.mouseDown(with: event) }
        window.performDrag(with: event)
    }

    /// Everything in the header the catcher must stay out of the way of.
    /// `visibleItems` covers the toolbar buttons, whose own views report
    /// that they'd happily move the window; the walk covers the traffic
    /// lights and the sidebar's split separator, which instead announce
    /// themselves by refusing to. Anything unrecognised is left alone
    /// rather than claimed, so a future AppKit layout at worst brings back
    /// the dead strip instead of swallowing clicks on a real control.
    private func passthroughViews(in window: NSWindow) -> [NSView] {
        var result = (window.toolbar?.visibleItems ?? []).compactMap(\.view)
        guard let container = superview else { return result }

        func collect(_ view: NSView) {
            guard view !== self else { return }
            if isInteractive(view) { result.append(view) }
            view.subviews.forEach(collect)
        }
        container.subviews.forEach(collect)
        return result
    }

    private func isInteractive(_ view: NSView) -> Bool {
        // The inline title is an `NSTextField`, and a window has always been
        // draggable by its own title — so a label that can't be typed in or
        // selected is part of the bar, not something to stay clear of.
        if let field = view as? NSTextField { return field.isEditable || field.isSelectable }
        return view is NSControl || !view.mouseDownCanMoveWindow
    }
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
    @Environment(\.uiTextScale) private var uiTextScale

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .overlay(alignment: .top) {
                if isHovering {
                    Text(text)
                        .font(.scaled(.caption, scale: uiTextScale))
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

    @Environment(\.uiTextScale) private var uiTextScale

    private var color: Color { Palette.score(score) }
    private var isExceptional: Bool { Verdict.forScore(score) == .exceptional }
    // Scaled as a whole, not just the number inside it — a badge is a fixed
    // pixel size, not text SwiftUI can reflow on its own, so Dynamic Type
    // alone would leave the ring the old size around a bigger digit.
    private var scaledSize: CGFloat { size * uiTextScale }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.09), lineWidth: max(2, scaledSize * 0.1))
            Circle()
                .trim(from: 0, to: max(0.015, min(1, score / 100)))
                .stroke(color, style: StrokeStyle(lineWidth: max(2, scaledSize * 0.1), lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(score.rounded()))")
                .font(.system(size: scaledSize * 0.36, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(width: scaledSize, height: scaledSize)
        .shadow(color: isExceptional ? color.opacity(0.75) : .clear, radius: isExceptional ? scaledSize * 0.2 : 0)
        .animation(.easeInOut(duration: 0.35), value: score)
    }
}

struct VerdictTag: View {
    @Environment(\.uiTextScale) private var uiTextScale
    var verdict: Verdict

    private var color: Color { Palette.verdict(verdict) }
    private var isExceptional: Bool { verdict == .exceptional }

    var body: some View {
        Text(verdict.rawValue)
            .font(.scaled(.callout, scale: uiTextScale).weight(.semibold))
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
    @Environment(\.uiTextScale) private var uiTextScale
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
                    .font(.scaled(.callout, scale: uiTextScale))
                Text(factorVerdict.rawValue)
                    .font(.scaled(.caption2, scale: uiTextScale).weight(.semibold))
                    .foregroundStyle(color)
                Spacer()
                // The impact number is the thing worth scanning for — bigger
                // and bolder than the bar itself, not a footnote next to it.
                Text(roundedImpact >= 1 ? "−\(roundedImpact)" : "0")
                    .font(.scaled(.callout, scale: uiTextScale).monospacedDigit().weight(roundedImpact >= 3 ? .bold : .semibold))
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
                .font(.scaled(.caption2, scale: uiTextScale))
                .foregroundStyle(.secondary)
        }
    }
}

struct LabelledValue: View {
    @Environment(\.uiTextScale) private var uiTextScale
    var label: String
    var value: String
    var systemImage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.scaled(.caption, scale: uiTextScale))
                        .foregroundStyle(Palette.accent)
                }
                Text(label)
                    .font(.scaled(.callout, scale: uiTextScale))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            // One line, whole: the statistics row flows, so an item that
            // doesn't fit moves to the next row instead of being squeezed
            // until its value wraps or its label is cut short.
            Text(value)
                .font(.scaled(.title3, scale: uiTextScale).weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

/// A time window with its zenith-risk portion marked directly on it, rather
/// than the risk living only in a warning string elsewhere — a segmented bar
/// plus inline labels, e.g. "21:18 ━━━ ⚠ Zenith risk 23:15 ━━━━━ 03:53".
struct ZenithRiskWindowBar: View {
    @Environment(\.uiTextScale) private var uiTextScale
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
            .font(.scaled(.caption, scale: uiTextScale).monospacedDigit())
        }
    }
}

struct WarningRow: View {
    @Environment(\.uiTextScale) private var uiTextScale
    var text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.scaled(.caption, scale: uiTextScale))
                .foregroundStyle(Palette.marginal)
            Text(text)
                .font(.scaled(.callout, scale: uiTextScale))
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

/// This target's actual patch of sky, from the Digitized Sky Survey.
///
/// Prefers the thumbnail built into the app, and falls back to fetching one —
/// which is the case for every target that *does* have a Wikipedia photo,
/// since the build script only fills the gaps. Those are worth fetching on
/// demand rather than bundling: the catalogue sheet is opened one target at a
/// time, and the client caches what it gets.
struct TargetSkyView: View {
    @Environment(\.uiTextScale) private var uiTextScale
    var target: Target
    var contentMode: ContentMode = .fit

    @State private var fetched: NSImage?

    /// The same framing rule the build script uses, so a bundled thumbnail
    /// and a fetched one show the same amount of sky.
    private var cutout: SkyCutout {
        let arcminutes = max(3.0, min(300.0, target.majorAxisArcminutes * 2.2))
        return SkyCutout(rightAscensionDegrees: target.coordinate.rightAscension,
                         declinationDegrees: target.coordinate.declination,
                         widthDegrees: arcminutes / 60,
                         pixelWidth: 512, pixelHeight: 512)
    }

    var body: some View {
        Group {
            if let image = TargetImageCatalog.skyThumbnail(for: target.designation) ?? fetched {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                ZStack {
                    Palette.spaceTop
                    ProgressView().controlSize(.small)
                }
            }
        }
        .task(id: target.designation) {
            guard TargetImageCatalog.skyThumbnail(for: target.designation) == nil else { return }
            let request = cutout
            if let ready = SkyCutoutClient.shared.cachedImage(for: request) {
                fetched = ready
                return
            }
            let image = await SkyCutoutClient.shared.image(for: request)
            // Same rule as the framing preview: a superseded fetch comes back
            // nil, and writing that back would clear a picture a newer task
            // had already resolved.
            guard !Task.isCancelled, let image else { return }
            fetched = image
        }
    }
}

/// A target's picture, filling and cropping its space.
///
/// Wikipedia photo first where one exists: a colour image from a real
/// telescope, which simply looks better than a photographic-plate scan. Where
/// there isn't one — about 600 of the ~1150 catalogue objects — a Digitized
/// Sky Survey thumbnail of that patch of sky stands in. The starry
/// placeholder underneath both is now genuinely rare rather than the common
/// case it used to be, and means only that a target is outside the survey or
/// was added by hand.
struct TargetThumbnail: View {
    @Environment(\.uiTextScale) private var uiTextScale
    var designation: String
    var contentMode: ContentMode = .fill

    var body: some View {
        if let image = TargetImageCatalog.nsImage(for: designation)
            ?? TargetImageCatalog.skyThumbnail(for: designation) {
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
                            .font(.scaled(.title3, scale: uiTextScale))
                            .foregroundStyle(.tertiary)
                        // Only worth the label where there's room to read it —
                        // this same view renders at everything from a 56pt row
                        // icon up to a 300pt detail sheet.
                        if geometry.size.height > 90 {
                            Text("No Photo Available")
                                .font(.scaled(.caption2, scale: uiTextScale).weight(.medium))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }
}

/// Escape as Cancel, for editors that live inside a window rather than in a
/// sheet. `.keyboardShortcut(.cancelAction)` alone never fired in the plan
/// editor: SwiftUI puts focus in the window's first text field, and the field
/// swallows Escape even when it has nothing to clear. So this watches the
/// window itself, and lets Escape through only to a text field that still has
/// text in it — clearing that first is what Escape does there anyway.
private struct EscapeCatcher: NSViewRepresentable {
    var isEnabled: Bool
    var action: () -> Void

    func makeNSView(context: Context) -> CatchingView {
        let view = CatchingView()
        view.isEnabled = isEnabled
        view.action = action
        return view
    }

    func updateNSView(_ view: CatchingView, context: Context) {
        view.isEnabled = isEnabled
        view.action = action
    }

    static func dismantleNSView(_ view: CatchingView, coordinator: ()) { view.stopMonitoring() }

    final class CatchingView: NSView {
        var isEnabled = false
        var action: (() -> Void)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isEnabled, event.keyCode == 53,
                      event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                      let window = self.window, event.window === window
                else { return event }
                if let editor = window.firstResponder as? NSTextView, !editor.string.isEmpty {
                    return event
                }
                self.action?()
                return nil
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { stopMonitoring() }
    }
}

extension View {
    /// Runs `action` when Escape is pressed anywhere in this view's window
    /// while `isEnabled` — see `EscapeCatcher`.
    func onEscapeKey(isEnabled: Bool = true, perform action: @escaping () -> Void) -> some View {
        background(EscapeCatcher(isEnabled: isEnabled, action: action))
    }
}

/// Two panes side by side with a draggable divider, the trailing one at a
/// width the caller keeps (usually in `@AppStorage`, so it's remembered).
/// `HSplitView` would do the dragging, but it ignores an ideal width and
/// opened the side panel at its maximum, splitting the window in half.
struct ResizableSplit<Leading: View, Trailing: View>: View {
    @Binding var trailingWidth: Double
    var trailingRange: ClosedRange<CGFloat>
    /// The leading pane never gets narrower than this; the trailing one gives
    /// way first when the window shrinks.
    var leadingMinimum: CGFloat
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    @State private var dragStartWidth: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            let upper = max(trailingRange.lowerBound, min(trailingRange.upperBound, geometry.size.width - leadingMinimum))
            let width = min(max(CGFloat(trailingWidth), trailingRange.lowerBound), upper)
            HStack(spacing: 0) {
                leading
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                divider(currentWidth: width, upper: upper)
                trailing
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private func divider(currentWidth: CGFloat, upper: CGFloat) -> some View {
        Rectangle()
            .fill(Palette.panelBorder)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            // A wider invisible strip to grab than the line itself.
            .overlay(
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let start = dragStartWidth ?? currentWidth
                                dragStartWidth = start
                                let proposed = start - value.translation.width
                                trailingWidth = Double(min(max(proposed, trailingRange.lowerBound), upper))
                            }
                            .onEnded { _ in dragStartWidth = nil }
                    )
            )
            .accessibilityHidden(true)
    }
}

extension View {
    /// A menu whose label SwiftUI draws itself, so it follows the UI scale.
    /// The borderless menu style hands its label to AppKit, which keeps it at
    /// the system size however large everything around it has grown.
    func scaledMenuStyle(_ scale: CGFloat) -> some View {
        menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.visible)
            .foregroundStyle(Palette.accent)
            .font(.scaled(.callout, scale: scale))
            .fixedSize()
    }
}

/// Makes the window this view sits in resizable. SwiftUI's Settings window
/// is created fixed-size, and `windowResizability` doesn't change that.
struct ResizableWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            view.window?.styleMask.insert(.resizable)
        }
    }
}
