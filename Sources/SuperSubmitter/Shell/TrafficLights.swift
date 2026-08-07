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
/// after a sheet. Each of those puts the buttons back, so the inset has to be
/// re-applied rather than set once.
///
/// The trap is that re-applying and re-measuring cannot both happen. A baseline
/// read from a button this view has already moved is a baseline that already
/// includes the inset, and insetting it again walks the button across the
/// titlebar one pass at a time. Watching the buttons for frame changes made
/// exactly that loop: the write posted the notification that caused the next
/// write, each light drifted by its own number of passes, and the three came
/// apart into a staircase.
///
/// So the baseline is read once, before this view has touched anything, and
/// never again. Every apply after that is the same arithmetic on the same
/// numbers, and writes only when the button is not already there. Repeating it
/// a thousand times lands in the same place as repeating it once.
///
/// ponytail: the frames are set directly, because there is no API for this.
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
        /// Where AppKit puts the buttons when nothing has moved them. Read once
        /// per window and never re-derived. See the type's note.
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
            // Every moment AppKit may have re-laid the titlebar out. None of
            // them is caused by this view, so none of them can feed itself.
            // `didUpdate` is the catch-all: it fires after the window
            // processes an update, which is where a fresh titlebar layout
            // lands. The rest are cheap and cover the cases that skip it.
            for name in [NSWindow.didUpdateNotification,
                         NSWindow.didResizeNotification,
                         NSWindow.didMoveNotification,
                         NSWindow.didBecomeKeyNotification,
                         NSWindow.didResignKeyNotification,
                         NSWindow.didEnterFullScreenNotification,
                         NSWindow.didExitFullScreenNotification] {
                observers.tokens.append(NotificationCenter.default.addObserver(
                    forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.apply() }
                })
            }
            apply()
        }

        /// Puts each button at its inset position, and nothing else.
        ///
        /// Idempotent by construction: the target is a pure function of a
        /// baseline that never changes, and a button already on its target is
        /// left alone.
        private func apply() {
            guard let window, !window.styleMask.contains(.fullScreen) else { return }
            if origins.isEmpty { record(from: window) }
            for type in Self.buttons {
                guard let button = window.standardWindowButton(type),
                      let origin = origins[type] else { continue }
                let target = CGPoint(x: origin.x + inset, y: origin.y - inset)
                guard button.frame.origin != target else { continue }
                button.setFrameOrigin(target)
            }
        }

        /// AppKit's own layout, taken before this view has moved anything.
        ///
        /// It refuses a layout that is not finished. A titlebar mid-build
        /// answers with zeroes, or with three buttons stacked on one x, and a
        /// baseline read there would be wrong for the life of the window with
        /// nothing able to correct it. A refusal costs one update pass, and
        /// the next one asks again.
        private func record(from window: NSWindow) {
            let frames = Self.buttons.compactMap {
                window.standardWindowButton($0)?.frame.origin
            }
            guard frames.count == Self.buttons.count else { return }
            // Laid out means: on the titlebar, left to right, evenly spaced.
            guard frames[0].x > 0,
                  frames[0].y > 0,
                  frames[1].x > frames[0].x,
                  frames[2].x > frames[1].x,
                  abs((frames[1].x - frames[0].x) - (frames[2].x - frames[1].x)) < 0.5,
                  frames.allSatisfy({ abs($0.y - frames[0].y) < 0.5 }) else { return }
            for (type, origin) in zip(Self.buttons, frames) { origins[type] = origin }
        }
    }
}
