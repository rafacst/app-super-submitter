import AppKit
import Foundation
import Testing
@testable import SuperSubmitter

/// No open or save panel may be wide enough to cost the developer their
/// sidebar.
///
/// The bug this guards: AppKit lays a panel's `message` out on one line and
/// widens the panel to fit it, then gives that width to the file list. The
/// sidebar keeps the width it had, so every location truncates. The project
/// picker carried a 173 character warning and opened wider than the window,
/// with "Macintosh HD", "Applications" and both Documents entries all cut to
/// six letters and an ellipsis.
///
/// Two rules, because one alone does not hold. The cap in `explain` protects a
/// message carrying an app name, whose length is the developer's business. The
/// scan protects the next panel somebody writes, which is where this came from.

private let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func sources() throws -> [(path: String, text: String)] {
    let folder = root.appending(path: "Sources/SuperSubmitter")
    let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?
        .compactMap { $0 as? URL }
        .filter { $0.pathExtension == "swift" } ?? []
    return try files.sorted { $0.path < $1.path }.map {
        (path: $0.lastPathComponent, text: try String(contentsOf: $0, encoding: .utf8))
    }
}

/// Every panel goes through `explain`, so the cap is not optional.
@Test func noPanelSetsItsMessageDirectly() throws {
    for file in try sources() {
        #expect(!file.text.contains("panel.message = "),
                "\(file.path) sets a panel message without the length cap. Use panel.explain.")
        #expect(!file.text.contains(".message = \"") || !file.text.contains("NSOpenPanel"),
                "\(file.path) sets a message on a panel directly. Use panel.explain.")
    }
}

/// And no sentence written into the app is long enough to need the cut. The cap
/// is a backstop for a name the app does not choose; a literal that trips it is
/// a mistake to fix where it is written.
@Test func noPanelMessageIsLongEnoughToWidenThePanel() throws {
    // `panel.explain("…")` up to the closing quote. Interpolations count as
    // their source text, which over-counts rather than under-counts.
    let pattern = try NSRegularExpression(pattern: #"\.explain\("((?:[^"\\]|\\.)*)"\)"#)
    var checked = 0
    for file in try sources() {
        let text = file.text
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range(at: 1), in: text) else { continue }
            let message = String(text[range])
            checked += 1
            #expect(message.count <= NSSavePanel.messageLimit,
                    "\(file.path) has a \(message.count) character panel message: \(message)")
        }
    }
    // The scan proves nothing if it found nothing to scan.
    #expect(checked >= 5)
}

/// The cut itself, for the message that carries an app name.
///
/// Against the rule and never against a panel. `NSOpenPanel()` wants a running
/// application and takes the whole test run down with it, which is why the
/// length rule is a function of its own.
@Test func aMessageCarryingALongNameIsCutAtAWord() {
    let name = String(repeating: "Receitório ", count: 12)
    let message = NSSavePanel.shortened("Choose the folder of \(name). store.yaml goes inside it.")

    #expect(message.count <= NSSavePanel.messageLimit + 1)
    #expect(message.hasSuffix("…"))
    // At a word, so the cut does not land in the middle of the name.
    #expect(!message.contains("Receitó…"))
}

@Test func aShortMessageIsLeftExactlyAsWritten() {
    let written = "Choose the store.yaml file of the app you want to continue."
    #expect(NSSavePanel.shortened(written) == written)
}

/// upload-spec 7.1 and the 17.1 checklist: the developer is told that building
/// runs code the project supplies, before they choose the folder. Shortening
/// the sentence may not quietly drop the warning.
@Test func theProjectPickerStillWarnsThatABuildRunsProjectCode() throws {
    let flow = try sources().first { $0.path == "BuildFlow.swift" }
    let text = try #require(flow?.text)
    let pattern = try NSRegularExpression(pattern: #"\.explain\("([^"]*)"\)"#)
    let range = NSRange(text.startIndex..., in: text)
    let messages = pattern.matches(in: text, range: range)
        .compactMap { Range($0.range(at: 1), in: text).map { String(text[$0]) } }

    let warning = try #require(messages.first { $0.lowercased().contains("build") })
    #expect(warning.lowercased().contains("runs"))
    #expect(warning.lowercased().contains("code"))
    #expect(warning.lowercased().contains("project"))
}
