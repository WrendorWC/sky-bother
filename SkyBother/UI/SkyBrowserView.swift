import AppKit
import SwiftUI

/// A window onto the real sky: pan, zoom, search, with your rig's frame drawn
/// over it so you can see what any part of it would give you.
///
/// The imagery is fetched as a cutout per view rather than streamed as HiPS
/// tiles. Tiles would pan and zoom without ever pausing, but they need HEALPix
/// indexing, a tile scheduler and a cache of their own; a cutout is one
/// request for exactly the patch on screen. The cost is that a new patch takes
/// about a second to arrive, which is covered by keeping the previous image on
/// screen and transforming it to match wherever you have moved to — so the
/// view responds instantly and then sharpens, rather than going blank.
struct SkyBrowserView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.uiTextScale) private var uiTextScale

    /// Which target the window opens on. Nil centres on whatever the app has
    /// selected, or the first catalogue entry.
    var designation: String?

    @State private var centre = EquatorialCoordinate(rightAscension: 10.6847, declination: 41.269)
    @State private var fieldOfViewDegrees: Double = 2.0
    @State private var searchText = ""
    @State private var label: String = ""
    @State private var isIdentifying = false

    /// Bumped whenever a tile arrives, purely to ask the canvas to repaint.
    @State private var tileEpoch = 0
    /// Tiles already asked for, so a redraw doesn't queue the same fetch again.
    @State private var requested: Set<String> = []

    /// Live gesture offsets, applied on top of `centre` without committing to
    /// it, so a drag can be followed continuously and resolved once.
    @GestureState private var dragOffset: CGSize = .zero

    private static let minimumFieldOfView = 0.05
    private static let maximumFieldOfView = 60.0

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            GeometryReader { geometry in
                skyCanvas(size: geometry.size)
            }
            Divider()
            footer
        }
        .background(Palette.spaceBackground)
        // Keyed rather than `onAppear`, so a window that is handed a target
        // after it has already appeared still centres on it instead of sitting
        // wherever it opened.
        .task(id: designation) { startingPoint() }
    }

    // MARK: - Chrome

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find an object", text: $searchText)
                .textFieldStyle(.plain)
                .font(.scaled(.body, scale: uiTextScale))
                .onSubmit { if let first = matches.first { go(to: first) } }
                .frame(maxWidth: 280)

            if !label.isEmpty {
                Text(label)
                    .font(.scaled(.callout, scale: uiTextScale).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                isIdentifying.toggle()
            } label: {
                Label("What's this?", systemImage: isIdentifying ? "tag.fill" : "tag")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(isIdentifying ? Palette.accent : .secondary)
            .font(.scaled(.caption, scale: uiTextScale).weight(.semibold))
            .help("Name everything in view that the catalogue knows about")

            Text(fieldOfViewSummary)
                .font(.scaled(.caption, scale: uiTextScale).monospacedDigit())
                .foregroundStyle(.secondary)
            Button { zoom(by: 1 / 1.6) } label: { Image(systemName: "plus.magnifyingglass") }
                .buttonStyle(.borderless)
            Button { zoom(by: 1.6) } label: { Image(systemName: "minus.magnifyingglass") }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("Drag to pan · scroll to zoom")
                .font(.scaled(.caption, scale: uiTextScale))
                .foregroundStyle(.tertiary)
            Spacer()
            Text("\(state.rig.name) · \(state.rig.fieldOfViewSummary)")
                .font(.scaled(.caption, scale: uiTextScale))
                .foregroundStyle(.tertiary)
            if let url = URL(string: SkyCutoutClient.attributionURL) {
                Link(SkyCutoutClient.attribution, destination: url)
                    .font(.scaled(.caption, scale: uiTextScale))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    // MARK: - The sky

    private func skyCanvas(size: CGSize) -> some View {
        Rectangle()
            .fill(Palette.spaceTop)
            .frame(width: size.width, height: size.height)
            .overlay {
                // `tileEpoch` is read here, in the body, so that a tile
                // landing actually invalidates the view — reading it inside
                // the drawing closure would not, since that runs at paint
                // time rather than when the body is evaluated.
                let epoch = tileEpoch
                Canvas { context, canvasSize in
                    _ = epoch
                    drawTiles(context: context, size: canvasSize)
                }
            }
            .overlay { frameOverlay(size: size) }
            .overlay { if isIdentifying { identifications(size: size) } }
            .overlay(alignment: .topLeading) {
                if searchResultsVisible { searchResults }
            }
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .updating($dragOffset) { value, offset, _ in offset = value.translation }
                    .onEnded { value in pan(by: value.translation, viewWidth: size.width) }
            )
            // Scrolling away from you zooms in, as it does in every map: a
            // positive delta has to *shrink* the field of view, and multiplying
            // by 1.12 grew it, so the wheel worked backwards.
            .onScroll { delta in zoom(by: delta > 0 ? 1 / 1.12 : 1.12) }
    }

    // MARK: - Tiles

    /// The order to draw at: fine enough that tiles aren't visibly upscaled,
    /// coarse enough that a wide view isn't a thousand of them. Capped at the
    /// survey's own resolution, below which there is nothing more to have.
    private var drawOrder: Int {
        min(SkyTileStore.nativeOrder, Healpix.order(forFieldOfViewDegrees: fieldOfViewDegrees))
    }

    /// Which tiles cover the window, found by sampling the view rather than by
    /// solving the region analytically. Tiles are chosen to be roughly a third
    /// of the field across, so a grid sampled more finely than that cannot
    /// miss one, and the margin covers a drag in progress.
    private func visibleTiles(size: CGSize) -> [Int] {
        let order = drawOrder
        var pixels: Set<Int> = []
        let steps = 10
        for row in -1...(steps + 1) {
            for column in -1...(steps + 1) {
                let x = (Double(column) / Double(steps) - 0.5) * Double(size.width) - Double(dragOffset.width)
                let y = (Double(row) / Double(steps) - 0.5) * Double(size.height) - Double(dragOffset.height)
                let coordinate = skyCoordinate(atScreenOffset: CGSize(width: x, height: y), size: size)
                pixels.insert(Healpix.pixel(rightAscensionDegrees: coordinate.rightAscension,
                                            declinationDegrees: coordinate.declination,
                                            order: order))
            }
        }
        // Discard anything that isn't plausibly in view. The inverse
        // projection is a small-angle approximation and at the far corners of
        // the sample grid it can wander onto another face of the sky
        // altogether — a handful of tiles from completely the wrong place,
        // fetched for nothing and drawn who knows where. A tile whose centre
        // is further off than the field itself was never on screen.
        let reach = fieldOfViewDegrees * 1.2
        return pixels.filter { pixel in
            SkyCoordinates.separation(Healpix.centre(ofPixel: pixel, order: order), centre) <= reach
        }
    }

    /// Inverse of `screenOffset`.
    private func skyCoordinate(atScreenOffset offset: CGSize, size: CGSize) -> EquatorialCoordinate {
        let pointsPerDegree = Double(size.width) / fieldOfViewDegrees
        let declination = clamp(centre.declination - Double(offset.height) / pointsPerDegree, -89.99, 89.99)
        let cosDec = max(0.02, cosDeg(declination))
        let rightAscension = normalize360(
            centre.rightAscension - Double(offset.width) / pointsPerDegree / cosDec)
        return EquatorialCoordinate(rightAscension: rightAscension, declination: declination)
    }

    /// Each tile is drawn into the quadrilateral its own corners project to.
    ///
    /// A HEALPix tile is a diamond on the sky, not a rectangle, so it cannot
    /// simply be blitted into a frame. Three of its corners give the affine
    /// transform that maps the square image onto the sky where it belongs —
    /// exact for a parallelogram, and at these scales a tile is close enough
    /// to one that the error is far under a pixel.
    private func drawTiles(context: GraphicsContext, size: CGSize) {
        let order = drawOrder
        let centreOffset = CGPoint(x: size.width / 2 + dragOffset.width,
                                   y: size.height / 2 + dragOffset.height)

        // Sorted into two passes. A coarser ancestor covers four times the
        // area of the tile it stands in for, so drawing it in amongst its
        // sharp neighbours paints over them — which is what turned the view
        // into a patchwork of mismatched diamonds. Every stand-in goes down
        // first, as a base layer, and the real tiles cover it.
        var base: [Int: (order: Int, image: NSImage)] = [:]
        var sharp: [(pixel: Int, image: NSImage)] = []

        for pixel in visibleTiles(size: size) {
            if let image = SkyTileStore.shared.cachedImage(order: order, pixel: pixel) {
                sharp.append((pixel, image))
                continue
            }
            request(order: order, pixel: pixel)
            var coarser = order - 1
            var ancestor = pixel / 4
            while coarser >= 0 {
                if let image = SkyTileStore.shared.cachedImage(order: coarser, pixel: ancestor) {
                    // Keyed by the ancestor, so one standing in for four
                    // children is drawn once rather than four times.
                    base[ancestor] = (coarser, image)
                    break
                }
                request(order: coarser, pixel: ancestor)
                coarser -= 1
                ancestor /= 4
            }
        }

        for (pixel, entry) in base {
            draw(entry.image, pixel: pixel, order: entry.order,
                 context: context, size: size, centreOffset: centreOffset)
        }
        for entry in sharp {
            draw(entry.image, pixel: entry.pixel, order: order,
                 context: context, size: size, centreOffset: centreOffset)
        }
    }

    /// One tile, into the quadrilateral its own corners project to.
    ///
    /// A HEALPix tile is a diamond on the sky, not a rectangle, so it cannot
    /// simply be blitted into a frame. Three of its corners give the affine
    /// transform that maps the square image onto the sky where it belongs —
    /// exact for a parallelogram, and at these scales a tile is close enough
    /// to one that the error is far under a pixel.
    private func draw(_ image: NSImage, pixel: Int, order: Int,
                      context: GraphicsContext, size: CGSize, centreOffset: CGPoint) {
        let corners = Healpix.corners(ofPixel: pixel, order: order).map { coordinate -> CGPoint in
            let offset = screenOffset(of: coordinate, size: size)
            return CGPoint(x: centreOffset.x + offset.width, y: centreOffset.y + offset.height)
        }
        guard corners.count == 4 else { return }
        let topLeft = corners[0], topRight = corners[1], bottomLeft = corners[3]
        let width = image.size.width, height = image.size.height
        guard width > 0, height > 0 else { return }

        let acrossX = (topRight.x - topLeft.x) / width
        let acrossY = (topRight.y - topLeft.y) / width
        let downX = (bottomLeft.x - topLeft.x) / height
        let downY = (bottomLeft.y - topLeft.y) / height
        guard acrossX.isFinite, acrossY.isFinite, downX.isFinite, downY.isFinite else { return }

        var layer = context
        layer.transform = CGAffineTransform(a: acrossX, b: acrossY, c: downX, d: downY,
                                            tx: topLeft.x, ty: topLeft.y)
        // A whisker of overdraw closes the hairline seams that rounding
        // otherwise leaves between neighbouring tiles.
        layer.draw(Image(nsImage: image),
                   in: CGRect(x: -0.5, y: -0.5, width: width + 1, height: height + 1))
    }

    private func request(order: Int, pixel: Int) {
        let key = "\(order)/\(pixel)"
        guard !requested.contains(key) else { return }
        requested.insert(key)
        Task {
            if await SkyTileStore.shared.image(order: order, pixel: pixel) != nil {
                tileEpoch += 1
            } else {
                // Forget a failure, so a tile lost to a dropped connection is
                // asked for again on the next redraw instead of leaving a hole
                // in the sky for the rest of the session.
                requested.remove(key)
            }
        }
    }

    /// The rig's field of view, centred — the whole reason for looking at any
    /// of this being to decide what to point at.
    private func frameOverlay(size: CGSize) -> some View {
        let pointsPerDegree = size.width / fieldOfViewDegrees
        let width = state.rig.fieldOfViewWidthArcminutes / 60 * pointsPerDegree
        let height = state.rig.fieldOfViewHeightArcminutes / 60 * pointsPerDegree
        return Rectangle()
            .stroke(Palette.go, lineWidth: 2)
            .frame(width: max(2, width), height: max(2, height))
            .allowsHitTesting(false)
    }

    // MARK: - Identifying

    /// Everything the catalogue knows about that falls inside the current
    /// view, marked and named where it actually sits.
    ///
    /// Drawn from the catalogue rather than asked of a name resolver: it is
    /// instant, works with no network, and the 1,100-odd objects in it are
    /// precisely the ones worth pointing a telescope at. Something genuinely
    /// obscure will go unnamed, which is the honest outcome — better than a
    /// label that takes a second to arrive and names a star.
    private func identifications(size: CGSize) -> some View {
        ZStack {
            ForEach(visibleTargets, id: \.id) { target in
                let offset = screenOffset(of: target.coordinate, size: size)
                let radius = max(9.0, target.majorAxisArcminutes / 60
                                 * Double(size.width) / fieldOfViewDegrees / 2)
                ZStack {
                    Circle()
                        .strokeBorder(Palette.accent.opacity(0.85), lineWidth: 1.5)
                        .frame(width: radius * 2, height: radius * 2)
                    Text(target.displayName)
                        .font(.scaled(.caption2, scale: uiTextScale).weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 4))
                        .fixedSize()
                        .offset(y: radius + 11)
                }
                .offset(offset)
            }
        }
        .allowsHitTesting(false)
    }

    /// Catalogue objects whose centres are inside the window, with the most
    /// prominent first so a crowded field labels its showpieces rather than
    /// whatever happens to come first in the file.
    private var visibleTargets: [Target] {
        let halfWidth = fieldOfViewDegrees / 2
        let halfHeight = halfWidth * 0.85
        return (BuiltInCatalog.all + state.customTargets)
            .filter { target in
                let cosDec = max(0.02, cosDeg(centre.declination))
                var deltaRA = target.coordinate.rightAscension - centre.rightAscension
                if deltaRA > 180 { deltaRA -= 360 }
                if deltaRA < -180 { deltaRA += 360 }
                return abs(deltaRA * cosDec) <= halfWidth
                    && abs(target.coordinate.declination - centre.declination) <= halfHeight
            }
            .sorted { $0.majorAxisArcminutes > $1.majorAxisArcminutes }
            .prefix(25)
            .map { $0 }
    }

    /// Where a sky coordinate lands on screen, in the same convention as
    /// `settledOffset`: east is left, north is up.
    private func screenOffset(of coordinate: EquatorialCoordinate, size: CGSize) -> CGSize {
        let pointsPerDegree = Double(size.width) / fieldOfViewDegrees
        let cosDec = max(0.02, cosDeg(centre.declination))
        var deltaRA = coordinate.rightAscension - centre.rightAscension
        if deltaRA > 180 { deltaRA -= 360 }
        if deltaRA < -180 { deltaRA += 360 }
        return CGSize(width: -deltaRA * cosDec * pointsPerDegree,
                      height: -(coordinate.declination - centre.declination) * pointsPerDegree)
    }

    private var searchResultsVisible: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty && !matches.isEmpty
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(matches.prefix(8), id: \.id) { target in
                Button {
                    go(to: target)
                } label: {
                    HStack(spacing: 9) {
                        TargetThumbnail(designation: target.designation)
                            .frame(width: 30, height: 30)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(target.displayName)
                                .font(.scaled(.callout, scale: uiTextScale).weight(.medium))
                            Text("\(target.designation) · \(target.type.displayName)")
                                .font(.scaled(.caption2, scale: uiTextScale))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 300)
        .background(Color.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.panelBorder))
        .padding(12)
    }

    private var matches: [Target] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return [] }
        return (BuiltInCatalog.all + state.customTargets)
            .filter { $0.searchText.contains(query) }
    }

    // MARK: - Navigation

    private func startingPoint() {
        let catalog = BuiltInCatalog.all + state.customTargets
        let wanted = designation ?? state.selectedTargetID
        if let target = catalog.first(where: { $0.designation == wanted }) ?? catalog.first {
            go(to: target)
        }
    }

    private func go(to target: Target) {
        centre = target.coordinate
        // Enough room for the rig's frame and the object both, so the window
        // opens on something that answers "does this fit?" rather than on an
        // arbitrary magnification.
        let wanted = max(state.rig.fieldOfViewWidthArcminutes,
                         state.rig.fieldOfViewHeightArcminutes,
                         target.majorAxisArcminutes) * 1.6 / 60
        fieldOfViewDegrees = clamp(wanted, Self.minimumFieldOfView, Self.maximumFieldOfView)
        label = "\(target.displayName) · \(target.type.displayName)"
        searchText = ""
    }

    private func zoom(by factor: Double) {
        fieldOfViewDegrees = clamp(fieldOfViewDegrees * factor,
                                   Self.minimumFieldOfView, Self.maximumFieldOfView)
    }

    /// Screen movement to sky movement.
    ///
    /// North is up and east is left in every survey rendering, so dragging the
    /// image to the right brings what was off its left edge into view — sky of
    /// *higher* right ascension. Declination follows the drag directly, since
    /// screen y grows downward and dragging down reveals what was above.
    /// Right ascension is divided by cos(dec) because lines of RA crowd
    /// together towards the poles: the same angular step across the sky is
    /// more degrees of RA the further from the equator you are.
    private func pan(by translation: CGSize, viewWidth: CGFloat) {
        let degreesPerPoint = fieldOfViewDegrees / Double(max(1, viewWidth))
        let declination = clamp(centre.declination + Double(translation.height) * degreesPerPoint, -89.9, 89.9)
        let cosDec = max(0.02, cosDeg(declination))
        let rightAscension = normalize360(
            centre.rightAscension + Double(translation.width) * degreesPerPoint / cosDec)
        centre = EquatorialCoordinate(rightAscension: rightAscension, declination: declination)
        label = ""
    }

    // MARK: - Image

    private var fieldOfViewSummary: String {
        fieldOfViewDegrees < 1
            ? String(format: "%.0f′ across", fieldOfViewDegrees * 60)
            : String(format: "%.2f° across", fieldOfViewDegrees)
    }
}

/// `onScroll` isn't a SwiftUI modifier, and an NSView placed behind the
/// content to catch the wheel never sees it — SwiftUI routes the event to the
/// foreground view, so scrolling the sky did nothing at all.
///
/// A local event monitor sidesteps the hit-testing question entirely: it sees
/// every scroll the app receives and this decides whether it landed inside the
/// view, which it can answer from its own bounds. The view itself stays out of
/// the way, refusing hit tests so drags and clicks reach the SwiftUI gestures
/// underneath.
private struct ScrollCatcher: NSViewRepresentable {
    var onScroll: (Double) -> Void

    func makeNSView(context: Context) -> CatchingView {
        let view = CatchingView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: CatchingView, context: Context) { view.onScroll = onScroll }

    static func dismantleNSView(_ view: CatchingView, coordinator: ()) { view.stopMonitoring() }

    final class CatchingView: NSView {
        var onScroll: ((Double) -> Void)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let local = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(local), event.scrollingDeltaY != 0 else { return event }
                self.onScroll?(Double(event.scrollingDeltaY))
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

private extension View {
    func onScroll(_ action: @escaping (Double) -> Void) -> some View {
        background(ScrollCatcher(onScroll: action))
    }
}
