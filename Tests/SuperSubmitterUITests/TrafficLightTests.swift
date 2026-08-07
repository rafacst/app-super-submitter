import AppKit
import Testing
@testable import SuperSubmitter

/// The inset has to survive being applied again, and it has to be applied
/// again, and those two pull against each other.
///
/// AppKit re-lays the titlebar out on its own, so a single shift at launch
/// does not hold: the lights go back to the window corner, two points inside
/// the panel's rounded edge. Re-applying fixes that and opens the other hole.
/// A baseline re-read from a button this app has already moved already
/// contains the inset, and insetting it again walks the button one gap
/// further every pass. Each light then drifts by its own number of passes and
/// the three come apart into a staircase, which is what shipped twice.
///
/// So this asserts the property that makes both true at once: applying fifty
/// times lands exactly where applying once does.
@MainActor
@Suite(.serialized)
struct TrafficLightTests {
    private static let types: [NSWindow.ButtonType] =
        [.closeButton, .miniaturizeButton, .zoomButton]

    private func window() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.layoutIfNeeded()
        return window
    }

    private func origins(_ window: NSWindow) -> [CGPoint] {
        Self.types.compactMap { window.standardWindowButton($0)?.frame.origin }
    }

    @Test func theInsetIsAppliedOnceHoweverOftenItRuns() throws {
        let window = window()
        let before = origins(window)
        try #require(before.count == 3, "The test window has no traffic lights.")

        let inset: CGFloat = 8
        let coordinator = TrafficLightInset(inset: inset).makeCoordinator()
        // The first call attaches and applies. The other forty-nine are the
        // re-applies that AppKit's own notifications cause in the real window.
        for _ in 0..<50 { coordinator.attach(to: window) }

        let after = origins(window)
        for (index, origin) in after.enumerated() {
            #expect(abs(origin.x - (before[index].x + inset)) < 0.01,
                    "Light \(index) drifted horizontally.")
            #expect(abs(origin.y - (before[index].y - inset)) < 0.01,
                    "Light \(index) drifted vertically.")
        }
    }

    /// The staircase, stated directly: whatever the shift is, all three take
    /// the same one, so the gaps between them never change.
    @Test func theThreeLightsKeepTheirSpacing() throws {
        let window = window()
        let before = origins(window)
        try #require(before.count == 3)
        let gapsBefore = [before[1].x - before[0].x, before[2].x - before[1].x]

        let coordinator = TrafficLightInset(inset: 8).makeCoordinator()
        for _ in 0..<50 { coordinator.attach(to: window) }

        let after = origins(window)
        let gapsAfter = [after[1].x - after[0].x, after[2].x - after[1].x]
        #expect(abs(gapsAfter[0] - gapsBefore[0]) < 0.01)
        #expect(abs(gapsAfter[1] - gapsBefore[1]) < 0.01)
        // And they stay on one line.
        #expect(abs(after[1].y - after[0].y) < 0.01)
        #expect(abs(after[2].y - after[0].y) < 0.01)
    }

    /// AppKit putting the buttons back is the case that made re-applying
    /// necessary in the first place. The inset has to return, and return once.
    @Test func aLayoutThatResetsTheButtonsIsInsetAgain() throws {
        let window = window()
        let before = origins(window)
        try #require(before.count == 3)

        let inset: CGFloat = 8
        let coordinator = TrafficLightInset(inset: inset).makeCoordinator()
        coordinator.attach(to: window)

        // What AppKit does on its own: every button back where it started.
        for (type, origin) in zip(Self.types, before) {
            window.standardWindowButton(type)?.setFrameOrigin(origin)
        }
        coordinator.attach(to: window)

        let after = origins(window)
        for (index, origin) in after.enumerated() {
            #expect(abs(origin.x - (before[index].x + inset)) < 0.01)
            #expect(abs(origin.y - (before[index].y - inset)) < 0.01)
        }
    }
}
