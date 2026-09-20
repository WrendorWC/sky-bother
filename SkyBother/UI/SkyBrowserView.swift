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

    /// The image currently on screen, together with where it was taken —
    /// which is what lets it be re-projected while a sharper one is fetched.
    @State private var shown: (image: NSImage, centre: EquatorialCoordinate, fov: Double)?
    @State private var isLoading = false
    @State private var fetchGeneration = 0

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
                    .task(id: FetchKey(centre: centre, fov: fieldOfViewDegrees, size: geometry.size)) {
                        await load(size: geometry.size)
                    }
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
            Text(fieldOfViewSummary)
                .font(.scaled(.caption, scale: uiTextScale).monospacedDigit())
                .foregroundStyle(.secondary)
            Button { zoom(by: 1 / 1.6) } label: { Image(systemName: "plus.magnifyingglass") }
                .buttonStyle(.borderless)
            Button { zoom(by: 1.6) } label: { Image(systemName: "minus.magnifyingglass") }
                .buttonStyle(.borderless)
            if isLoading { ProgressView().controlSize(.small) }
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
        ZStack {
            Palette.spaceTop
            if let shown {
                Image(nsImage: shown.image)
                    .resizable()
                    .interpolation(.high)
                    // Re-projected rather than redrawn: the placement below is
                    // what makes a drag or a zoom feel immediate while the
                    // matching cutout is still in flight.
                    .frame(width: size.width * previewScale(shown),
                           height: size.height * previewScale(shown))
                    .offset(previewOffset(shown, size: size))
                    .clipped()
            }
            frameOverlay(size: size)
            if searchResultsVisible { searchResults }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, offset, _ in offset = value.translation }
                .onEnded { value in pan(by: value.translation, viewWidth: size.width) }
        )
        .onScroll { delta in zoom(by: delta > 0 ? 1.08 : 1 / 1.08) }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    /// Identity of a fetch: changing any of these means a different picture.
    private struct FetchKey: Hashable {
        var ra: Double, dec: Double, fov: Double, width: Int, height: Int
        init(centre: EquatorialCoordinate, fov: Double, size: CGSize) {
            self.ra = (centre.rightAscension * 1000).rounded()
            self.dec = (centre.declination * 1000).rounded()
            self.fov = (fov * 10000).rounded()
            self.width = Int(size.width)
            self.height = Int(size.height)
        }
    }

    private func load(size: CGSize) async {
        guard size.width > 32, size.height > 32 else { return }
        let request = SkyCutout(rightAscensionDegrees: centre.rightAscension,
                                declinationDegrees: centre.declination,
                                widthDegrees: fieldOfViewDegrees,
                                pixelWidth: Int(size.width * (NSScreen.main?.backingScaleFactor ?? 2)),
                                pixelHeight: Int(size.height * (NSScreen.main?.backingScaleFactor ?? 2)))

        if let ready = SkyCutoutClient.shared.cachedImage(for: request) {
            shown = (ready, centre, fieldOfViewDegrees)
            return
        }

        // A short pause before going to the network: panning or zooming a few
        // steps in a row shouldn't fire a request for every intermediate view
        // nobody looked at.
        fetchGeneration += 1
        let generation = fetchGeneration
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard generation == fetchGeneration else { return }

        isLoading = true
        let image = await SkyCutoutClient.shared.image(for: request)
        isLoading = false
        guard generation == fetchGeneration, let image else { return }
        shown = (image, centre, fieldOfViewDegrees)
    }

    /// How much bigger the image on screen has to be drawn than it was taken,
    /// which is simply the ratio of the two fields of view.
    private func previewScale(_ shown: (image: NSImage, centre: EquatorialCoordinate, fov: Double)) -> CGFloat {
        CGFloat(clamp(shown.fov / fieldOfViewDegrees, 0.05, 20))
    }

    /// Where that image sits, given the view has since moved. Inverse of
    /// `pan`: the sky offset between where the picture was taken and where we
    /// are now, converted back into points, plus whatever the finger is
    /// currently doing.
    private func previewOffset(_ shown: (image: NSImage, centre: EquatorialCoordinate, fov: Double),
                               size: CGSize) -> CGSize {
        let pointsPerDegree = size.width / fieldOfViewDegrees
        let cosDec = max(0.02, cosDeg(centre.declination))
        var deltaRA = shown.centre.rightAscension - centre.rightAscension
        // The short way round, so crossing 0h doesn't fling the image away.
        if deltaRA > 180 { deltaRA -= 360 }
        if deltaRA < -180 { deltaRA += 360 }
        let x = deltaRA * cosDec * pointsPerDegree + Double(dragOffset.width)
        let y = (shown.centre.declination - centre.declination) * pointsPerDegree + Double(dragOffset.height)
        return CGSize(width: x, height: y)
    }

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
