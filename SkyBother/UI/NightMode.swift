import SwiftUI
import AppKit
import CoreImage

/// Red-light night mode: every window drawn in shades of red only, so
/// glancing at the screen at the scope doesn't cost your dark adaptation.
///
/// Done as a filter over the whole window rather than a second palette.
/// A palette swap would leave the sky cutouts, the live stack, the cloud map
/// and every SF Symbol in full colour, and each new colour anyone adds later
/// would be another place to forget. The filter keeps brightness and throws
/// the colour away: each pixel's luminance goes to the red channel, green and
/// blue go to zero. Title bar and toolbar included, since it sits on the
/// window's frame view rather than on the SwiftUI content.
extension View {
    func nightMode(_ isOn: Bool) -> some View {
        background(NightModeFilter(isOn: isOn))
    }
}

private struct NightModeFilter: NSViewRepresentable {
    var isOn: Bool

    func makeNSView(context: Context) -> NightModeProbe { NightModeProbe(frame: .zero) }

    func updateNSView(_ nsView: NightModeProbe, context: Context) {
        nsView.isOn = isOn
        nsView.apply()
    }
}

/// A zero-sized view that hands the setting to `NightModeController`.
private final class NightModeProbe: NSView {
    var isOn = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }

    func apply() {
        NightModeController.shared.isOn = isOn
    }
}

/// Filters every window the app has, not just the ones whose content asked
/// for it. Sheets (a target's details from Sky View, the Moon card) and
/// popovers are windows of their own that SwiftUI creates out of reach of
/// any modifier on the parent, so they came up in full colour. Checking each
/// window as it updates catches them the moment they appear, and whatever
/// kind of window gets added later too.
@MainActor
final class NightModeController {
    static let shared = NightModeController()

    var isOn = false {
        didSet {
            guard isOn != oldValue else { return }
            NSApp.windows.forEach(apply)
        }
    }

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didUpdateNotification, object: nil, queue: .main
        ) { note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated { NightModeController.shared.apply(to: window) }
        }
    }

    private func apply(to window: NSWindow) {
        guard let frameView = window.contentView?.superview else { return }
        // Posted on every pass of the event loop, so only touch the view
        // when it's actually out of step.
        guard frameView.contentFilters.isEmpty == isOn else { return }
        frameView.wantsLayer = true
        frameView.contentFilters = isOn ? Self.filters() : []
    }

    /// Luminance into red, less a black point, then a gamma lift. Straight
    /// luminance left the dim greys (secondary text, the sky dome's faint
    /// grid) hard to read once only a third of the colour was left to carry
    /// them; a gamma below 1 raises those midtones while leaving black black.
    ///
    /// The black point is for the deep-space background, which is only
    /// there for the look and would otherwise glow a dull red across the
    /// whole window. Measured on screen, it comes to about 0.006–0.009 here
    /// (Core Image works in linear light) and the raised panels about 0.016,
    /// so subtracting 0.009 takes the background to nearly black and leaves
    /// the panels a dim red you can still tell apart.
    private static func filters() -> [CIFilter] {
        let red = CIFilter(name: "CIColorMatrix")!
        red.setDefaults()
        red.setValue(CIVector(x: 0.36, y: 0.71, z: 0.13, w: 0), forKey: "inputRVector")
        red.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
        red.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
        red.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        red.setValue(CIVector(x: -0.009, y: 0, z: 0, w: 0), forKey: "inputBiasVector")

        let lift = CIFilter(name: "CIGammaAdjust")!
        lift.setDefaults()
        lift.setValue(0.75, forKey: "inputPower")
        return [red, lift]
    }
}

/// Menu command and toolbar button share this, so they read the same.
struct NightModeToggleLabel: View {
    var isOn: Bool

    var body: some View {
        Label(isOn ? "Day Mode" : "Night Mode", systemImage: isOn ? "sun.max" : "moon.fill")
    }
}
