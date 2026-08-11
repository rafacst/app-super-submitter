import AppKit
import SwiftUI

/// A text box the developer can drag taller, and that stays where it was put.
///
/// The height is a number and not the contents, on purpose. A box that grows as
/// it is typed into remeasures the scroll view around it on every keystroke,
/// which is why every one of these has carried a fixed height. A drag changes
/// it once, when the person typing asks for it, so the cost is paid on the
/// gesture and never on a key.
///
/// Four lines is right for a subtitle and wrong for four thousand characters of
/// release notes, and the box that holds both was the compact one. Nothing on
/// screen could open it: the only way to read what you had written was to
/// scroll a viewport six lines tall, or to leave for a text editor.
///
/// The height outlives the window. Somebody who drags a description open means
/// it for the next app as well as this one, and being asked again at every
/// launch is the same complaint one launch later.
private struct ResizableHeight: ViewModifier {
    @AppStorage private var stored: Double
    /// The height during a drag. `stored` only moves when the mouse comes up,
    /// so a drag that is interrupted leaves the box as it was.
    @State private var live: Double?
    /// Whether this box owns a cursor push. `NSCursor` is a stack and every
    /// push owes exactly one pop: see `MediaTab.hover` for what a leaked one
    /// does to the rest of the app.
    @State private var pushed = false

    /// The height it starts at, and the shortest it goes. Shrinking below the
    /// default buys nothing: the default is already the compact one.
    private let smallest: Double
    /// Past this the box is taller than the window it sits in, and the scroll
    /// view around it can no longer reach the rest of the tab.
    private let tallest: Double = 800

    init(key: String, base: Double) {
        // The stored value is the height on screen, already scaled, so a drag
        // of forty points moves the edge forty points. Scaling it again at use
        // would multiply whatever the developer dragged by the type scale.
        let floor = Double(Theme.scaled(CGFloat(base)))
        smallest = floor
        _stored = AppStorage(wrappedValue: floor, "boxHeight.\(key)")
    }

    private var height: Double { min(max(live ?? stored, smallest), tallest) }

    func body(content: Content) -> some View {
        content
            .frame(height: CGFloat(height))
            .overlay(alignment: .bottom) { grip }
    }

    /// The handle. A wider hit area than the mark it draws, because a three
    /// point target is one nobody can hit on purpose.
    private var grip: some View {
        Capsule()
            .fill(Theme.text3)
            .frame(width: 24, height: 3)
            .frame(width: 68, height: 13)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { live = stored + $0.translation.height }
                // `height` clamps, so what is kept is what was drawn and never
                // a number from beyond either end of the drag.
                .onEnded { _ in stored = height; live = nil })
            .onHover { hover($0) }
            .onDisappear { hover(false) }
            .accessibilityElement()
            .accessibilityLabel("Box height")
            .accessibilityValue("\(Int(height)) points")
            // A drag is the obvious way and it must not be the only way.
            .accessibilityAdjustableAction { direction in
                let step: Double = direction == .increment ? 40 : -40
                stored = min(max(stored + step, smallest), tallest)
            }
    }

    private func hover(_ inside: Bool) {
        guard inside != pushed else { return }
        pushed = inside
        if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
    }
}

extension View {
    /// Lets a text box be dragged taller from its bottom edge, and remembers
    /// how tall under `key`. `base` is the height it starts at and its floor.
    func resizableHeight(_ key: String, base: Double) -> some View {
        modifier(ResizableHeight(key: key, base: base))
    }
}
