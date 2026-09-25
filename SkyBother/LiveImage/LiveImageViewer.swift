import SwiftUI
import AppKit

/// The telescope's live stack in a window of its own, to zoom into. Follows
/// the connection Session View opened, so each new stack replaces the
/// picture here too, keeping the zoom and position. Nothing is saved.
struct LiveImageViewer: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @EnvironmentObject private var state: AppState
    @ObservedObject var telescope: LiveTelescope
    @State private var zoom = ZoomCommand()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let frame = telescope.frame {
                ZoomableImage(image: frame.image, command: zoom)
                    .background(WindowShapedToImage(size: CGSize(width: frame.image.width, height: frame.image.height)))
            } else {
                EmptyStateView(title: "No picture yet",
                               message: "Connect to your telescope in Session View; its live stack appears here.",
                               systemImage: "dot.radiowaves.left.and.right")
            }
        }
        .background(Color.black)
        .navigationTitle("Live Stack")
        .frame(minWidth: 340, minHeight: 360)
    }

    private var toolbar: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            HStack(spacing: 10) {
                if let frame = telescope.frame {
                    Text("Updated \(Self.age(frame.receivedAt, context.date)) ago")
                        .foregroundStyle(.secondary)
                        .help("\(frame.image.width) × \(frame.image.height) pixels. Pinch, scroll or double-click to zoom; drag to move.")
                    if let progress = telescope.downloadProgress {
                        Label("\(Int(progress * 100))%", systemImage: "arrow.down.circle")
                            .foregroundStyle(.secondary)
                            .help("The next stack, on its way")
                    }
                }
                Spacer(minLength: 8)
                Button { zoom = ZoomCommand(kind: .out) } label: { Image(systemName: "minus.magnifyingglass") }
                    .help("Zoom out")
                Button { zoom = ZoomCommand(kind: .in) } label: { Image(systemName: "plus.magnifyingglass") }
                    .help("Zoom in")
                Button { zoom = ZoomCommand(kind: .fit) } label: { Image(systemName: "arrow.down.right.and.arrow.up.left") }
                    .help("Show the whole picture")
                Button { zoom = ZoomCommand(kind: .actual) } label: { Image(systemName: "1.magnifyingglass") }
                    .help("100%: one screen pixel per camera pixel")
            }
            .font(.scaled(.callout, scale: uiTextScale))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Palette.spaceTop)
        }
    }

    private static func age(_ date: Date, _ now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        return seconds < 60 ? "\(seconds)s" : Format.duration(minutes: Double(seconds) / 60)
    }
}

/// A button press for the zoomable view: a new value each time, so the same
/// button twice still counts.
struct ZoomCommand: Equatable {
    enum Kind { case none, `in`, out, fit, actual }
    var kind: Kind = .none
    var id = UUID()
}

/// AppKit's own magnifying scroll view: pinch and scroll-wheel zoom, and
/// panning, as in Preview.
private struct ZoomableImage: NSViewRepresentable {
    var image: CGImage
    var command: ZoomCommand

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        // No space kept for a title bar over it: the toolbar sits above.
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets()
        scroll.contentView = CenteringClipView()
        scroll.allowsMagnification = true
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.backgroundColor = .black
        scroll.drawsBackground = true
        scroll.maxMagnification = 8
        let view = DoubleClickImageView()
        view.imageScaling = .scaleAxesIndependently
        view.onDoubleClick = { [weak scroll] point in
            guard let scroll else { return }
            scroll.setMagnification(min(scroll.maxMagnification, scroll.magnification * 2), centeredAt: point)
        }
        scroll.documentView = view
        context.coordinator.scroll = scroll
        // Still showing the whole picture when the window changes size?
        // Keep showing the whole picture.
        scroll.postsFrameChangedNotifications = true
        context.coordinator.resizeObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: scroll, queue: .main) { [weak scroll] _ in
            guard let scroll else { return }
            MainActor.assumeIsolated {
                if scroll.magnification <= scroll.minMagnification + 0.0001 { Self.fit(scroll) }
            }
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSImageView else { return }
        let size = NSSize(width: image.width, height: image.height)
        let isFirst = view.image == nil
        if context.coordinator.shown !== image {
            context.coordinator.shown = image
            // A new stack replaces the old one in place: same size, so the
            // zoom and position carry over.
            view.image = NSImage(cgImage: image, size: size)
            if view.frame.size != size { view.frame = NSRect(origin: .zero, size: size) }
        }
        if isFirst { DispatchQueue.main.async { fit(scroll) } }
        if context.coordinator.lastCommand != command.id {
            context.coordinator.lastCommand = command.id
            let centre = NSPoint(x: scroll.documentVisibleRect.midX, y: scroll.documentVisibleRect.midY)
            switch command.kind {
            case .in: scroll.setMagnification(min(scroll.maxMagnification, scroll.magnification * 1.5), centeredAt: centre)
            case .out: scroll.setMagnification(max(scroll.minMagnification, scroll.magnification / 1.5), centeredAt: centre)
            case .fit: fit(scroll)
            case .actual:
                let scale = scroll.window?.backingScaleFactor ?? 2
                scroll.setMagnification(1 / scale, centeredAt: centre)
            case .none: break
            }
        }
    }

    /// The whole picture in view, and no smaller than that.
    private func fit(_ scroll: NSScrollView) { Self.fit(scroll) }

    private static func fit(_ scroll: NSScrollView) {
        guard let document = scroll.documentView, document.frame.width > 0, document.frame.height > 0 else { return }
        let bounds = scroll.contentSize
        let scale = min(bounds.width / document.frame.width, bounds.height / document.frame.height)
        scroll.minMagnification = scale
        scroll.magnification = scale
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator {
        weak var scroll: NSScrollView?
        var shown: CGImage?
        var lastCommand: UUID?
        var resizeObserver: NSObjectProtocol?
        deinit { resizeObserver.map(NotificationCenter.default.removeObserver) }
    }
}

/// Keeps a picture smaller than the window in the middle of it, rather than
/// in a corner.
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView else { return rect }
        if rect.width > document.frame.width { rect.origin.x = (document.frame.width - rect.width) / 2 }
        if rect.height > document.frame.height { rect.origin.y = (document.frame.height - rect.height) / 2 }
        return rect
    }
}

private final class DoubleClickImageView: NSImageView {
    var onDoubleClick: ((NSPoint) -> Void)?
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?(convert(event.locationInWindow, from: nil))
        } else {
            super.mouseDown(with: event)
        }
    }
    // Dragging the picture moves it, as in Preview.
    override func mouseDragged(with event: NSEvent) {
        guard let scroll = enclosingScrollView else { return }
        var origin = scroll.contentView.bounds.origin
        origin.x -= event.deltaX / scroll.magnification
        origin.y += event.deltaY / scroll.magnification
        scroll.contentView.scroll(to: scroll.contentView.constrainBoundsRect(NSRect(origin: origin, size: scroll.contentView.bounds.size)).origin)
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}

/// Shapes the viewer window to the picture the first time one shows: as tall
/// as the screen allows and as wide as the picture's shape then needs, so a
/// portrait stack isn't a strip down one side of a wide window.
private struct WindowShapedToImage: NSViewRepresentable {
    var size: CGSize

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        guard !context.coordinator.done, size.width > 0, size.height > 0 else { return }
        DispatchQueue.main.async {
            guard !context.coordinator.done, let window = view.window,
                  !window.styleMask.contains(.fullScreen),
                  let screen = window.screen ?? NSScreen.main else { return }
            context.coordinator.done = true
            let available = screen.visibleFrame
            // Everything that isn't picture: title bar and toolbar.
            let chrome = window.frame.height - view.frame.height
            var height = available.height * 0.94
            var width = (height - chrome) * size.width / size.height
            let widest = available.width * 0.9
            if width > widest {
                width = widest
                height = width * size.height / size.width + chrome
            }
            width = max(width, 340)
            let frame = NSRect(x: available.midX - width / 2, y: available.maxY - height - available.height * 0.03,
                               width: width, height: height)
            window.setFrame(frame, display: true, animate: false)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var done = false }
}
