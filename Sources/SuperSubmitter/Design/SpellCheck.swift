import AppKit
import SwiftUI

/// Red underlines under a misspelt word, in the boxes that hold prose.
///
/// AppKit has the switch and SwiftUI does not expose it: every `TextEditor` on
/// this platform is an `NSTextView`, and `isContinuousSpellCheckingEnabled` is
/// off on a new one. So a description written here was the only text in a
/// release nobody checked. App Store Connect checks its own boxes, and the
/// point of this app is that nobody has to open App Store Connect.
///
/// Spelling only. `isAutomaticSpellingCorrectionEnabled` stays off on purpose:
/// a description is full of product names, and a box that quietly rewrites
/// "DeckDeckDeck" while somebody types is worse than one that checks nothing.
/// The mark is a suggestion, and the right-click menu is where the correction
/// lives, which is how every other Mac text box behaves.
@MainActor
enum SpellCheck {

    /// The text view one attachment belongs to.
    ///
    /// Up from the attachment and never down from the window. The first level
    /// that holds a text view is the box this modifier was written on; a search
    /// from the top would hand every box on the tab the first text view it
    /// found, which on a tab of six boxes is five wrong answers.
    ///
    /// Three levels, because SwiftUI wraps a background in a container or two
    /// and no further. Nil is a normal answer: the hierarchy inside a
    /// `TextEditor` belongs to SwiftUI and can change with the OS, and a miss
    /// costs the spelling nobody was getting before this existed.
    static func textView(near view: NSView, levels: Int = 3) -> NSTextView? {
        var node = view.superview
        var climbed = 0
        while let current = node, climbed < levels {
            if let found = first(in: current) { return found }
            node = current.superview
            climbed += 1
        }
        return nil
    }

    private static func first(in view: NSView) -> NSTextView? {
        if let text = view as? NSTextView { return text }
        for child in view.subviews {
            if let found = first(in: child) { return found }
        }
        return nil
    }
}

/// A view of no size whose only job is to be somewhere in the box's own part of
/// the AppKit tree, so the text view above it can be found and switched on.
private struct SpellCheckAttachment: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ view: NSView, context: Context) {
        // After this layout pass. During one the attachment has no superview
        // yet, so there is nothing above it to find.
        DispatchQueue.main.async {
            guard let text = SpellCheck.textView(near: view),
                  !text.isContinuousSpellCheckingEnabled else { return }
            text.isContinuousSpellCheckingEnabled = true
        }
    }
}

extension View {
    /// Marks misspelt words in this prose box.
    ///
    /// It goes on boxes that hold sentences and on nothing else. A bundle id, a
    /// URL and a version number are not prose, and underlining
    /// `com.rafacst.deckdeckdeck` in red teaches a developer to ignore the mark
    /// everywhere it means something.
    func spellChecked() -> some View {
        background(SpellCheckAttachment().frame(width: 0, height: 0))
    }
}
