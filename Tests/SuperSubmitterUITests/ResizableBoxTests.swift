import Foundation
import Testing
@testable import SuperSubmitter

/// One rule for every box that holds more than a line: it opens.
///
/// The bug this guards: a listing description takes four thousand characters
/// and the box drawing it was six lines tall, with nothing on screen to open
/// it. Reading back what you had written meant scrolling a viewport, or
/// leaving for a text editor. A fixed `frame(height:)` on a `TextEditor` is
/// how that happens, so the rule is that none of them carry one.
@Suite struct ResizableBoxTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func source(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appending(path: path), encoding: .utf8)
    }

    /// Every box a developer writes prose into. The YAML editor is not here on
    /// purpose: it carries `minHeight` and grows with the window already.
    private static let boxes = [
        "Sources/SuperSubmitter/Tabs/DetailsTab.swift",
        "Sources/SuperSubmitter/Tabs/TestFlightSection.swift",
    ]

    @Test func noProseBoxIsPinnedToAFixedHeight() throws {
        for path in Self.boxes {
            let file = try source(path)
            #expect(file.contains("TextEditor"), "\(path) holds no box any more")
            #expect(!file.contains(".frame(height:"),
                    "\(path) pins a box to a height nobody can change")
        }
    }

    @Test func everyProseBoxCanBeDraggedTaller() throws {
        for path in Self.boxes {
            let file = try source(path)
            #expect(file.contains(".resizableHeight("),
                    "\(path) has a box that does not open")
        }
    }

    /// The height has to outlive the window, or the drag is asked for again at
    /// every launch. And it is keyed, so a description and a subtitle do not
    /// share one answer.
    @Test func theHeightIsRememberedUnderAKeyOfItsOwn() throws {
        let box = try source("Sources/SuperSubmitter/Design/ResizableBox.swift")

        #expect(box.contains("@AppStorage"))
        #expect(box.contains("boxHeight.\\(key)"))
        #expect(try source("Sources/SuperSubmitter/Tabs/DetailsTab.swift")
            .contains("listing.\\(field.rawValue)"))
    }

    /// A drag is the obvious way to resize and it must not be the only one.
    /// A grip that answers to the mouse alone is a control half the people
    /// using it cannot reach.
    @Test func theGripAnswersToSomethingOtherThanAMouse() throws {
        let box = try source("Sources/SuperSubmitter/Design/ResizableBox.swift")

        #expect(box.contains(".accessibilityAdjustableAction"))
        #expect(box.contains(".accessibilityLabel"))
    }

    /// The grip stands under the box and never over it.
    ///
    /// A `TextEditor` is an `NSTextView`, which takes every mouse event inside
    /// its own bounds before SwiftUI sees it, so the handle drawn on the bottom
    /// edge of one was a mark that could not be dragged, could not be hovered,
    /// and was half covered by the border painted after it.
    @Test func theGripIsNotDrawnOverTheTextView() throws {
        let box = try source("Sources/SuperSubmitter/Design/ResizableBox.swift")

        #expect(!box.contains(".overlay(alignment: .bottom) { grip }"),
                "The grip is back over the text view, where no drag reaches it.")
        #expect(box.contains("VStack(spacing: 2) {"))
    }

    /// And the modifier runs after the box is painted, so the handle is not
    /// inside the field's own border.
    @Test func theGripComesAfterTheBorder() throws {
        for path in Self.boxes {
            let file = try source(path)
            let border = try #require(file.range(of: ".background(Theme."))
            let grip = try #require(file.range(of: ".resizableHeight("))
            #expect(border.lowerBound < grip.lowerBound,
                    "\(path) sizes the box before it paints it")
        }
    }

    /// `NSCursor` is a stack and every push owes one pop. A grip that pushes
    /// the resize cursor and never pops it leaves that cursor over the whole
    /// app, which is what `MediaTab` had to be taught once already.
    @Test func theResizeCursorIsGivenBack() throws {
        let box = try source("Sources/SuperSubmitter/Design/ResizableBox.swift")

        #expect(box.contains("NSCursor.pop()"))
        #expect(box.contains(".onDisappear { hover(false) }"))
    }
}
