import AppKit
import SwiftUI

/// Moves the three standard window buttons in by the panel inset.
///
/// AppKit pins the lights to the window's own corner. The sidebar is a panel
/// inset from that corner, so the lights land about two points inside its
/// edge and read as stuck to it. Shifting them by the same inset gives them
/// the margin against the panel that they would have had against the window.
///
/// AppKit lays the titlebar out again whenever it likes: on the first pass
/// after the window is built, on a resize, on a full-screen round trip, and
/// after a sheet. Each of those put the lights back on its own corner, which
/// is two points inside the panel's rounded edge, and they stayed there until
/// something happened to re-run the SwiftUI body. So the entry screen looked
/// right, because the onboarding sheet closing re-ran it, and every tab looked
/// wrong. The buttons are watched now, and a move that this view did not make
/// is the signal to inset again.
///
/// ponytail: the frames are set directly, because there is no API for this.
/// Whatever AppKit last chose is re-read as the baseline, so applying twice
/// cannot walk the buttons across the titlebar.
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
            // The buttons themselves, which is the only signal that catches
            // every re-layout. The window notifications above fire for three
            // of the causes; this one fires for all of them, including the
            // first layout pass after the window is built.
            for type in Self.buttons {
                guard let button = window.standardWindowButton(type) else { continue }
                button.postsFrameChangedNotifications = true
                observers.tokens.append(NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification, object: button,
                    queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.apply() }
                })
            }
            apply()
        }

        /// Where a button sits once it is inset.
        private func target(_ origin: CGPoint) -> CGPoint {
            CGPoint(x: origin.x + inset, y: origin.y - inset)
        }

        /// Puts each button back at its inset position, and re-reads the
        /// baseline whenever AppKit has moved it.
        ///
        /// This method is what the frame observer calls, so it has to settle.
        /// It writes only when the button is somewhere other than its target,
        /// and its own write lands exactly on that target, so the notification
        /// that write causes finds nothing to do and the loop ends there.
        private func apply() {
            guard let window, !window.styleMask.contains(.fullScreen) else { return }
            for type in Self.buttons {
                guard let button = window.standardWindowButton(type) else { continue }
                let current = button.frame.origin
                // This view is the only other thing that moves these buttons,
                // and it only ever moves them onto the target. So a position
                // that is not the target is one AppKit just chose, and that is
                // the baseline to inset from.
                if origins[type].map(target) != current { origins[type] = current }
                guard let origin = origins[type], target(origin) != current else { continue }
                button.setFrameOrigin(target(origin))
            }
        }
    }
}
