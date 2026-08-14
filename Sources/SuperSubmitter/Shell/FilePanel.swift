import AppKit

/// The sentence above the file list of an open or save panel.
///
/// AppKit lays `message` out on one line and widens the panel to fit it, and it
/// gives that width to the file list alone. The sidebar keeps the width it had,
/// so every location truncated: "Macintosh HD" read "Macint…", "Applications"
/// read "Applic…", and the two Documents entries were both "Docum…". The
/// project picker carried a 173 character warning and opened a panel wider than
/// the window behind it, with a column of locations that could not be told
/// apart.
///
/// So the length is enforced here rather than trusted to whoever writes the
/// next panel. `NSOpenPanel` is an `NSSavePanel`, so one extension covers the
/// open panels and the save panels both.
extension NSSavePanel {

    /// What fits beside the panel's own furniture without pushing the width
    /// out. Measured against the system font at default size on a panel at its
    /// natural width, with room to spare.
    ///
    /// `// ponytail: a character count, not a text measurement. The panel is
    /// // system-drawn and its metrics are not ours to read; when a translation
    /// // needs more room, measure once and change this number.`
    static let messageLimit = 90

    /// Sets the sentence, and keeps it short enough that the panel stays the
    /// size the system chose.
    func explain(_ message: String) {
        self.message = Self.shortened(message)
    }

    /// The rule, apart from the panel, because a panel cannot be built in a
    /// test process: `NSOpenPanel()` needs a running application and takes the
    /// whole test run down with it.
    ///
    /// A static message that runs long is a mistake to fix at the call site,
    /// and `noPanelMessageIsLongEnoughToWidenThePanel` fails for it. The cut
    /// here is for the ones that carry a name: an app called something long may
    /// not cost the developer their sidebar.
    static func shortened(_ message: String) -> String {
        guard message.count > messageLimit else { return message }
        let cut = message.prefix(messageLimit)
        // At a word, so the cut does not land mid-name.
        let stop = cut.lastIndex(of: " ").map(cut.prefix(upTo:)) ?? cut
        return stop.trimmingCharacters(in: .whitespaces) + "…"
    }
}
