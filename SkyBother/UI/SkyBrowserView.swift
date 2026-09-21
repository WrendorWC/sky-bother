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
    /// What sits at the centre of the view, once asked for.
    @State private var centreName: String?
    @State private var isResolving = false

    /// The cutout currently on screen, with where it was taken, so it can be
    /// re-projected while a new one is in flight. Used only when nothing has
    /// been downloaded — see `usesTiles`.
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
        .task(id: IdentifyKey(identifying: isIdentifying, centre: centre, fov: fieldOfViewDegrees)) {
            await identifyCentre()
        }
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

            // While identifying, the centre wins: the whole point of pressing
            // the button is to ask about where you have moved to, so a name
            // left over from wherever you started would be answering the wrong
            // question — which is exactly what it did.
            if isIdentifying {
                HStack(spacing: 6) {
                    if isResolving { ProgressView().controlSize(.small) }
                    Text(centreName ?? (isResolving ? "Looking…" : "Nothing catalogued here"))
                        .font(.scaled(.callout, scale: uiTextScale).weight(.semibold))
                        .foregroundStyle(centreName == nil ? .secondary : Palette.accent)
                        .lineLimit(1)
                }
            } else if !label.isEmpty {
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
                    .font(.scaled(.caption, scale: uiTextScale).weight(.semibold))
            }
            // A real button rather than bare text: it toggles a mode, and
            // nothing about the old styling said it could be pressed.
            .buttonStyle(.bordered)
            .tint(isIdentifying ? Palette.accent : .secondary)
            .help("Name what's at the centre of the view, and everything around it the catalogue knows")

            if isLoading { ProgressView().controlSize(.small) }
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
                if let shown {
                    Image(nsImage: shown.image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: size.width * previewScale(shown),
                               height: size.height * previewScale(shown))
                        .offset(previewOffset(shown, size: size))
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
            ForEach(markers(size: size)) { marker in
                ZStack {
                    Circle()
                        .strokeBorder(Palette.accent.opacity(0.85), lineWidth: 1.5)
                        .frame(width: marker.radius * 2, height: marker.radius * 2)
                    if marker.showsLabel {
                        Text(marker.name)
                            .font(.scaled(.caption2, scale: uiTextScale).weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 4))
                            .fixedSize()
                            .offset(y: marker.radius + 11)
                    }
                }
                .offset(marker.offset)
            }
        }
        .allowsHitTesting(false)
    }

    private struct Marker: Identifiable {
        var id: String
        var name: String
        var offset: CGSize
        var radius: Double
        var showsLabel: Bool
    }

    /// Works out where each mark goes, and which of them can carry a name.
    ///
    /// Two things this fixes. A mark whose centre is off the edge used to be
    /// drawn anyway, so its label appeared sliced in half against the top of
    /// the view. And nothing stopped two labels landing on top of each other —
    /// "NGC 1893" and "Tadpoles Nebula" were printed over one another and
    /// neither could be read. A mark that cannot have a legible label keeps
    /// its circle and loses the text, which still says something is there.
    private func markers(size: CGSize) -> [Marker] {
        let middle = CGPoint(x: size.width / 2, y: size.height / 2)
        var claimed: [CGRect] = []
        var result: [Marker] = []

        for target in visibleTargets {
            let offset = screenOffset(of: target.coordinate, size: size)
            let position = CGPoint(x: middle.x + offset.width, y: middle.y + offset.height)
            // Inside the view with room for the label underneath, rather than
            // straddling an edge.
            guard position.x > 10, position.x < size.width - 10,
                  position.y > 10, position.y < size.height - 28
            else { continue }

            let radius = max(9.0, target.majorAxisArcminutes / 60
                             * Double(size.width) / fieldOfViewDegrees / 2)
            // Close enough for a collision test; the exact width depends on
            // the font, but labels only need to not be drawn over each other.
            let width = Double(target.displayName.count) * 6.5 * Double(uiTextScale) + 14
            let label = CGRect(x: position.x - width / 2,
                               y: position.y + radius + 3,
                               width: width, height: 18 * Double(uiTextScale))
            let free = !claimed.contains { $0.intersects(label) }
            if free { claimed.append(label) }
            result.append(Marker(id: target.id, name: target.displayName,
                                 offset: offset, radius: radius, showsLabel: free))
        }
        return result
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

    /// Identity of a lookup. Panning or zooming asks the question again;
    /// turning the mode off stops asking.
    private struct IdentifyKey: Hashable {
        var identifying: Bool
        var ra: Double, dec: Double, fov: Double
        init(identifying: Bool, centre: EquatorialCoordinate, fov: Double) {
            self.identifying = identifying
            self.ra = (centre.rightAscension * 1000).rounded()
            self.dec = (centre.declination * 1000).rounded()
            self.fov = (fov * 1000).rounded()
        }
    }

    /// The catalogue first, then Simbad.
    ///
    /// The catalogue is instant and offline but holds about eleven hundred
    /// objects, so panning onto an ordinary galaxy finds nothing in it — and
    /// answering "nothing" when the sky plainly contains something is the
    /// complaint this exists to fix. Scoring by separation against the
    /// object's own size rather than raw distance is what lets a big nebula
    /// you are sitting inside beat a small cluster whose centre happens to be
    /// nearer.
    private func identifyCentre() async {
        guard isIdentifying else { centreName = nil; return }

        let nearby = (BuiltInCatalog.all + state.customTargets)
            .map { target -> (Target, Double) in
                let separation = SkyCoordinates.separation(target.coordinate, centre)
                let reach = max(target.majorAxisArcminutes / 60 / 2, 0.02)
                return (target, separation / reach)
            }
            .filter { $0.1 <= 1.5 }
            .min { $0.1 < $1.1 }

        if let match = nearby?.0 {
            centreName = "\(match.displayName) · \(match.type.displayName)"
            return
        }

        isResolving = true
        // Cleared however this leaves, including when the view moves and this
        // lookup is cancelled part-way — otherwise the spinner kept turning
        // next to an answer that had already arrived.
        defer { isResolving = false }
        let resolved = await SkyResolver.name(rightAscensionDegrees: centre.rightAscension,
                                              declinationDegrees: centre.declination,
                                              radiusArcminutes: fieldOfViewDegrees * 60 / 8)
        guard !Task.isCancelled else { return }
        centreName = resolved
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

    /// Fetched patches cover half again as much sky as the window shows.
    ///
    /// Every zoom step used to be a round trip — a second of staring at a
    /// stretched image for a 12% change — because the fetch matched the view
    /// exactly, so the smallest movement left it short. With margin in hand,
    /// several steps of zoom and a decent pan are served by re-projecting what
    /// is already there, and the network is only involved once the view really
    /// has left what the image covers.
    private static let fetchMargin = 1.8

    /// Whether what's on screen still covers the view well enough to leave
    /// alone: not stretched past legibility, not zoomed out past its edges,
    /// and not panned so far that an edge would show.
    private func isCovered(_ shown: (image: NSImage, centre: EquatorialCoordinate, fov: Double),
                           size: CGSize) -> Bool {
        let showing = fieldOfViewDegrees / shown.fov
        guard showing <= 0.98, showing >= 0.4 else { return false }
        let magnification = shown.fov / fieldOfViewDegrees
        // How far past each edge of the window the image reaches.
        let slackX = size.width * (magnification - 1) / 2
        let slackY = size.height * (magnification - 1) / 2
        let offset = settledOffset(shown, size: size)
        return abs(offset.width) <= slackX && abs(offset.height) <= slackY
    }

    /// Fields of view worth fetching at. Requests land on one of these rather
    /// than on whatever the window happens to be showing, so that zooming
    /// settles onto a handful of sizes instead of a continuum of one-offs.
    private static let fieldLadder: [Double] = [
        0.05, 0.075, 0.11, 0.17, 0.25, 0.38, 0.56, 0.84, 1.3, 1.9, 2.8, 4.2, 6.3, 9.5, 14, 21, 32, 48, 60,
    ]

    /// The patch to ask for: snapped to the ladder, and centred on a grid
    /// point rather than on the view.
    ///
    /// This is the whole of the speed problem. Asking for exactly what is on
    /// screen means every position is a different request, so the cache filled
    /// with dozens of near-identical pictures and essentially never hit — pan
    /// a pixel and the last second and a half of waiting was wasted. Snapping
    /// makes neighbouring views ask for the *same* patch, which is then drawn
    /// offset, so a pan within a cell costs nothing, a pan back to somewhere
    /// visited is instant, and only genuinely new sky goes to the network.
    private func snappedRequest(size: CGSize) -> (cutout: SkyCutout, centre: EquatorialCoordinate, fov: Double) {
        let wanted = fieldOfViewDegrees * Self.fetchMargin
        let fov = Self.fieldLadder.first { $0 >= wanted } ?? Self.maximumFieldOfView

        // A quarter of the fetched field: fine enough that the snapped patch
        // still comfortably covers the view wherever inside the cell you are.
        let step = fov / 4
        let declination = clamp((centre.declination / step).rounded() * step, -89, 89)
        // Lines of right ascension crowd together near the poles, so the grid
        // has to widen in RA by the same factor to stay square on the sky.
        let raStep = step / max(0.05, cosDeg(declination))
        let rightAscension = normalize360((centre.rightAscension / raStep).rounded() * raStep)

        let (pixelWidth, pixelHeight) = Self.pixels(for: size, magnification: fov / max(fieldOfViewDegrees, 0.0001))
        let snapped = EquatorialCoordinate(rightAscension: rightAscension, declination: declination)
        return (SkyCutout(rightAscensionDegrees: rightAscension,
                          declinationDegrees: declination,
                          widthDegrees: fov,
                          pixelWidth: pixelWidth,
                          pixelHeight: pixelHeight),
                snapped, fov)
    }

    /// How many pixels to ask the renderer for.
    ///
    /// This is what made a cold view take the better part of twenty seconds.
    /// Asking at retina resolution *and* for the wider patch that the margin
    /// needs multiplied out to well past two thousand pixels a side, and the
    /// service's cost climbs steeply with area: measured against it, 600×400
    /// comes back in 1.8s, 1024×800 in 3.0s, 1600×1250 in 6.4s and 2048×2048
    /// in 12.9s. The old code asked for the last of those every time.
    ///
    /// So there is a budget on total area instead of a cap per side, spent in
    /// whatever shape the window is. Slightly soft beats waiting.
    private static func pixels(for size: CGSize, magnification: Double, budget: Double = 900_000) -> (Int, Int) {
        let scale = Double(NSScreen.main?.backingScaleFactor ?? 2)
        var width = Double(size.width) * scale * magnification
        var height = Double(size.height) * scale * magnification
        let area = max(1, width * height)
        if area > budget {
            let shrink = (budget / area).squareRoot()
            width *= shrink
            height *= shrink
        }
        return (max(64, Int(width)), max(64, Int(height)))
    }

    private func load(size: CGSize) async {
        guard size.width > 32, size.height > 32 else { return }
        if let shown, isCovered(shown, size: size) { return }

        let request = snappedRequest(size: size)

        if let ready = SkyCutoutClient.shared.cachedImage(for: request.cutout) {
            shown = (ready, request.centre, request.fov)
            prefetchNeighbours(of: request, size: size)
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
        // Something on screen quickly, then the real thing. The service's
        // floor is about a second and a half however small the request, so a
        // quarter-area version lands in roughly that and the full one follows
        // — which reads as "loading" rather than "broken".
        if shown == nil {
            let (coarseWidth, coarseHeight) = Self.pixels(
                for: size, magnification: request.fov / max(fieldOfViewDegrees, 0.0001), budget: 200_000)
            let coarse = SkyCutout(rightAscensionDegrees: request.centre.rightAscension,
                                   declinationDegrees: request.centre.declination,
                                   widthDegrees: request.fov,
                                   pixelWidth: coarseWidth, pixelHeight: coarseHeight)
            if let quick = await SkyCutoutClient.shared.image(for: coarse),
               generation == fetchGeneration, shown == nil {
                shown = (quick, request.centre, request.fov)
            }
        }

        let image = await SkyCutoutClient.shared.image(for: request.cutout)
        isLoading = false
        // Nothing is written back unless this is still the current request —
        // a superseded fetch is cancelled and comes back nil, and writing that
        // would clear a perfectly good picture.
        guard generation == fetchGeneration, let image else { return }
        shown = (image, request.centre, request.fov)
        prefetchNeighbours(of: request, size: size)
    }

    /// Quietly fetches the four cells around this one.
    ///
    /// Panning is overwhelmingly sideways into the next cell, and having it
    /// already in hand turns the commonest move from a wait into nothing at
    /// all. These never touch `shown`; they only warm the cache.
    private func prefetchNeighbours(of request: (cutout: SkyCutout, centre: EquatorialCoordinate, fov: Double),
                                    size: CGSize) {
        let step = request.fov / 4
        let raStep = step / max(0.05, cosDeg(request.centre.declination))
        let around = [(raStep, 0.0), (-raStep, 0.0), (0.0, step), (0.0, -step)]
        for (deltaRA, deltaDec) in around {
            let declination = clamp(request.centre.declination + deltaDec, -89, 89)
            let neighbour = SkyCutout(
                rightAscensionDegrees: normalize360(request.centre.rightAscension + deltaRA),
                declinationDegrees: declination,
                widthDegrees: request.fov,
                pixelWidth: request.cutout.pixelWidth,
                pixelHeight: request.cutout.pixelHeight)
            guard SkyCutoutClient.shared.cachedImage(for: neighbour) == nil else { continue }
            Task.detached(priority: .background) {
                _ = await SkyCutoutClient.shared.image(for: neighbour)
            }
        }
    }

    /// How much bigger the image on screen has to be drawn than it was taken,
    /// which is simply the ratio of the two fields of view.
    private func previewScale(_ shown: (image: NSImage, centre: EquatorialCoordinate, fov: Double)) -> CGFloat {
        CGFloat(clamp(shown.fov / fieldOfViewDegrees, 0.05, 20))
    }

    /// Where the image sits once the view has moved on from where it was
    /// taken, ignoring any drag in progress.
    ///
    /// Both terms are negated, and that sign is the whole of what made panning
    /// feel inverted. Right ascension grows *eastward*, which is to the left
    /// in every survey rendering, and declination grows upward while screen y
    /// grows down — so a patch of sky whose coordinates are greater than the
    /// view's centre sits at a *smaller* screen coordinate, on both axes.
    /// Getting that backwards meant that on releasing a drag the image jumped
    /// to the mirror image of where the finger had left it, which reads
    /// exactly like panning the wrong way.
    private func settledOffset(_ shown: (image: NSImage, centre: EquatorialCoordinate, fov: Double),
                               size: CGSize) -> CGSize {
        let pointsPerDegree = size.width / fieldOfViewDegrees
        let cosDec = max(0.02, cosDeg(centre.declination))
        var deltaRA = shown.centre.rightAscension - centre.rightAscension
        // The short way round, so crossing 0h doesn't fling the image away.
        if deltaRA > 180 { deltaRA -= 360 }
        if deltaRA < -180 { deltaRA += 360 }
        return CGSize(width: -deltaRA * cosDec * pointsPerDegree,
                      height: -(shown.centre.declination - centre.declination) * pointsPerDegree)
    }

    /// The same, plus whatever the finger is currently doing.
    private func previewOffset(_ shown: (image: NSImage, centre: EquatorialCoordinate, fov: Double),
                               size: CGSize) -> CGSize {
        let settled = settledOffset(shown, size: size)
        return CGSize(width: settled.width + dragOffset.width,
                      height: settled.height + dragOffset.height)
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
