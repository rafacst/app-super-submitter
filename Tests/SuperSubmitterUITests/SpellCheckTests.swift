import AppKit
import Foundation
import Testing
@testable import SuperSubmitter

/// The spelling mark belongs to the box it was written on.
///
/// The switch is `NSTextView`'s and SwiftUI hides the view, so the attachment
/// climbs to find it. What it must never do is find a neighbour's: a tab holds
/// six of these boxes, and a search that starts at the window would switch on
/// the first one it met and leave the other five as they were.
@MainActor
@Suite struct SpellCheckTests {

    /// One box: a container holding the text view and the attachment beside it,
    /// which is where a SwiftUI background lands.
    private func box() -> (container: NSView, text: NSTextView, attachment: NSView) {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
        let text = NSTextView(frame: container.bounds)
        let attachment = NSView(frame: .zero)
        container.addSubview(text)
        container.addSubview(attachment)
        return (container, text, attachment)
    }

    @Test func theAttachmentFindsItsOwnTextView() {
        let one = box()

        #expect(SpellCheck.textView(near: one.attachment) === one.text)
    }

    /// Two boxes under one form. Each attachment answers with its own.
    @Test func aNeighbourBoxIsNeverTheAnswer() {
        let form = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let first = box()
        let second = box()
        form.addSubview(first.container)
        form.addSubview(second.container)

        #expect(SpellCheck.textView(near: first.attachment) === first.text)
        #expect(SpellCheck.textView(near: second.attachment) === second.text)
    }

    /// A scroll view sits between the two in a real `TextEditor`, so the climb
    /// has to pass through one.
    @Test func theClimbReachesThroughAScrollView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
        let scroll = NSScrollView(frame: container.bounds)
        let text = NSTextView(frame: container.bounds)
        scroll.documentView = text
        let attachment = NSView(frame: .zero)
        container.addSubview(scroll)
        container.addSubview(attachment)

        #expect(SpellCheck.textView(near: attachment) === text)
    }

    /// Nothing to find is a normal answer, not a crash and not a guess. The
    /// hierarchy inside a `TextEditor` belongs to SwiftUI and can change.
    @Test func aBoxWithNoTextViewAnswersNothing() {
        let container = NSView(frame: .zero)
        let attachment = NSView(frame: .zero)
        container.addSubview(attachment)

        #expect(SpellCheck.textView(near: attachment) == nil)
    }

    /// The climb stops. A text view a whole tab away is not this box's.
    @Test func theClimbDoesNotReachTheWholeWindow() {
        let far = NSView(frame: .zero)
        far.addSubview(NSTextView(frame: .zero))
        var node = NSView(frame: .zero)
        let attachment = node
        for _ in 0..<5 {
            let parent = NSView(frame: .zero)
            parent.addSubview(node)
            node = parent
        }
        node.addSubview(far)

        #expect(SpellCheck.textView(near: attachment) == nil)
    }

    /// Spelling, and never the silent rewrite. A description is full of product
    /// names, and autocorrect would change them while somebody types.
    @Test func nothingIsCorrectedAutomatically() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let file = try String(
            contentsOf: root.appending(path: "Sources/SuperSubmitter/Design/SpellCheck.swift"),
            encoding: .utf8)

        #expect(file.contains("isContinuousSpellCheckingEnabled = true"))
        #expect(!file.contains("isAutomaticSpellingCorrectionEnabled = true"))
        #expect(!file.contains("isAutomaticTextReplacementEnabled = true"))
    }

    /// The prose boxes, and only those. A bundle id and a URL are not prose.
    @Test func everyProseBoxIsChecked() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        func source(_ path: String) throws -> String {
            try String(contentsOf: root.appending(path: path), encoding: .utf8)
        }

        for path in ["Sources/SuperSubmitter/Tabs/DetailsTab.swift",
                     "Sources/SuperSubmitter/Tabs/TestFlightSection.swift"] {
            #expect(try source(path).contains(".spellChecked()"), "\(path) checks nothing")
        }
        // The YAML is code. Red under `versionName` would be a mark that means
        // nothing on every line of the file.
        #expect(try !source("Sources/SuperSubmitter/Tabs/YAMLEditor.swift")
            .contains(".spellChecked()"))
    }
}
