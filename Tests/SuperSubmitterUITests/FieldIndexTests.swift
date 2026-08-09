import Foundation
import Testing

@testable import SuperSubmitter

/// Keeps `FieldIndex` from rotting.
///
/// The index is a static list beside the views it describes, so nothing in the
/// compiler connects the two. The first person to rename a label ships a search
/// result that opens the right tab and scrolls to nothing. These are the cheap
/// checks that catch it.
@MainActor
struct FieldIndexTests {
    /// The repository root, found from this file rather than from the working
    /// directory, which differs between `swift test` and `xcodebuild test`.
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // SuperSubmitterUITests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // the repository

    /// Every `.swift` file that draws a tab, joined into one string.
    ///
    /// `ManifestEditing.swift` joins them, because the listing labels moved
    /// into it. The Details columns draw a field's name from that one table
    /// rather than repeating the words per column, so the words a search has
    /// to match live there now and a rename there still has to reach the
    /// index.
    private static let tabSources: String = {
        let directory = root.appending(path: "Sources/SuperSubmitter/Tabs")
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        let labels = (try? String(
            contentsOf: root.appending(path: "Sources/SubmitKit/Manifest/ManifestEditing.swift"),
            encoding: .utf8)) ?? ""
        return (files
            .filter { $0.pathExtension == "swift" }
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            + [labels])
            .joined(separator: "\n")
    }()

    @Test func theIndexIsNotEmptyAndTheSourcesWereFound() {
        #expect(!FieldIndex.all.isEmpty)
        // A path that resolved to nothing would pass every label check below
        // by never running one, so the fixture proves itself first.
        #expect(Self.tabSources.contains("struct MoneyTab"))
    }

    @Test func everyIdIsUnique() {
        var seen: Set<String> = []
        for entry in FieldIndex.all {
            #expect(seen.insert(entry.id).inserted, "\(entry.id) appears twice")
        }
    }

    @Test func everyTabStillExists() {
        for entry in FieldIndex.all {
            #expect(Tab.allCases.contains(entry.tab),
                    "\(entry.id) points at a tab that is gone")
        }
    }

    /// The one that matters. A label edited on the screen and not here leaves
    /// a search result whose words nobody can find.
    @Test func everyLabelStillAppearsInTheSourceOfATab() {
        for entry in FieldIndex.all {
            #expect(Self.tabSources.contains("\"\(entry.label)\""),
                    "\(entry.id): no tab draws the text \"\(entry.label)\"")
        }
    }

    /// An anchor with no `.fieldAnchor` on any view scrolls nowhere, which
    /// looks exactly like a tab that simply opened at the top.
    @Test func everyIdIsAnchoredOnAView() {
        let sources = Self.tabSources
        for entry in FieldIndex.all {
            #expect(sources.contains("\"\(entry.id)\""),
                    "\(entry.id) is in the index and on no view")
        }
    }

    // MARK: - The matcher

    @Test func anEmptyQueryMatchesNothing() {
        #expect(FieldIndex.matches("").isEmpty)
        #expect(FieldIndex.matches("   ").isEmpty)
    }

    @Test func aPrefixOfALabelComesBeforeAMerelyContainedOne() {
        let hits = FieldIndex.matches("Privacy policy")
        #expect(hits.first?.id == "details.privacyPolicyURL")
    }

    @Test func aKeywordFindsAFieldItsLabelDoesNotName() {
        // The example from the brief: nothing on screen says "gdpr".
        let hits = FieldIndex.matches("gdpr")
        #expect(hits.contains { $0.id == "details.privacyPolicyURL" })
    }

    @Test func theMatchIgnoresCaseAndAccents() {
        #expect(FieldIndex.matches("KEYWORDS").contains { $0.id == "details.keywords" })
        #expect(FieldIndex.matches("licence").contains { $0.id == "marketing.eula" })
    }
}
