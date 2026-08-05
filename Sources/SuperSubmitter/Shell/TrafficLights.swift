import AppKit
import SwiftUI

/// Moves the three standard window buttons in by the panel inset.
///
/// AppKit pins the lights to the window's own corner. The sidebar is a panel
/// inset from that corner, so the lights land about two points inside its
/// edge and read as stuck to it. Shifting them by the same inset gives them
/// the margin against the panel that they would have had against the window.
///
/// ponytail: the frames are set directly, because there is no API for this.
/// The original origins are kept, so applying twice cannot walk the buttons
/// across the titlebar, and a full-screen round trip puts them back.
struct TrafficLightInset: NSViewRepresentable {
    let inset: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(inset: inset) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // The window is not attached while the view is being made.
        DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
    }

    /// The tokens, in something a nonisolated deinit is allowed to touch.
    /// A `@MainActor` coordinator cannot clean them up in its own deinit.
    private final class ObserverBag: @unchecked Sendable {
        var tokens: [NSObjectProtocol] = []
        deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
    }

    @MainActor
    final class Coordinator {
        private let inset: CGFloat
        private var origins: [NSWindow.ButtonType: CGPoint] = [:]
        private let observers = ObserverBag()
        private weak var window: NSWindow?

        private static let buttons: [NSWindow.ButtonType] =
            [.closeButton, .miniaturizeButton, .zoomButton]

        init(inset: CGFloat) { self.inset = inset }

        func attach(to window: NSWindow?) {
            guard let window, window !== self.window else { apply(); return }
            self.window = window
            origins = [:]
            // A full-screen round trip rebuilds the titlebar and puts the
            // buttons back where AppKit wants them.
            for name in [NSWindow.didExitFullScreenNotification,
                         NSWindow.didEnterFullScreenNotification,
                         NSWindow.didResizeNotification] {
                observers.tokens.append(NotificationCenter.default.addObserver(
                    forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.apply() }
                })
            }
            apply()
        }

        private func apply() {
            guard let window, !window.styleMask.contains(.fullScreen) else { return }
            for type in Self.buttons {
                guard let button = window.standardWindowButton(type) else { continue }
                // Remember where AppKit put it, so the shift is absolute and
                // repeating it is free.
                let origin = origins[type] ?? button.frame.origin
                origins[type] = origin
                button.setFrameOrigin(CGPoint(x: origin.x + inset,
                                              y: origin.y - inset))
            }
        }
    }
}
