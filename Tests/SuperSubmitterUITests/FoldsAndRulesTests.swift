import Foundation
import Testing
@testable import SuperSubmitter

/// Two rules the whole shell obeys: a fold moves, and a group has an edge.
@Suite struct FoldsAndRulesTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func source(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appending(path: path), encoding: .utf8)
    }

    // MARK: - Every fold animates

    /// Left to itself, whether a `DisclosureGroup` animates depends on which
    /// control moved the binding, so two folds on one screen opened two
    /// different ways: one slid, one appeared. `Fold` and `Section_` settle it,
    /// and every group with a binding of its own says the same thing next to it.
    @Test func everyDisclosureGroupCarriesItsOwnAnimation() throws {
        for path in ["Sources/SuperSubmitter/Tabs/PlanTab.swift",
                     "Sources/SuperSubmitter/Tabs/AndroidArtifactsSection.swift",
                     "Sources/SuperSubmitter/Tabs/SigningIdentitiesPanel.swift",
                     "Sources/SuperSubmitter/Build/BuildFromProjectView.swift"] {
            let file = try source(path)
            guard file.contains("DisclosureGroup") else { continue }
            #expect(file.contains(".motion("), "\(path) folds without moving")
        }
    }

    /// The two that held no binding at all. A group SwiftUI opens for itself
    /// cannot be animated from outside it, so they are `Fold`s now.
    @Test func theUnboundGroupsAreFolds() throws {
        for path in ["Sources/SuperSubmitter/Tabs/MoneyTab.swift",
                     "Sources/SuperSubmitter/Tabs/StoreDiagnosticsPanel.swift"] {
            let file = try source(path)
            #expect(!file.contains("DisclosureGroup(\""), "\(path) still opens without moving")
        }
        #expect(try source("Sources/SuperSubmitter/Design/Section.swift")
            .contains("struct Fold<Content: View>"))
    }

    /// The card's own guide is a fold inside a fold, and it was the one that
    /// opened in a single frame while the card around it slid.
    @Test func theCredentialGuideMovesWithTheCard() throws {
        let card = try source("Sources/SuperSubmitter/Design/CredentialCard.swift")

        #expect(card.contains("value: open)"))
        #expect(card.contains("value: guideOpen)"))
    }

    // MARK: - The sidebar

    /// Four headings in the quietest tier the app has, separated by nothing:
    /// a group that folded shut left its neighbour's rows sitting directly
    /// under its title. The footer already drew this rule.
    @Test func theSidebarGroupsAreDivided() throws {
        let sidebar = try source("Sources/SuperSubmitter/Shell/Sidebar.swift")
        let header = try #require(sidebar.range(of: "private struct GroupHeader"))
        let group = String(sidebar[header.lowerBound...])

        #expect(group.contains("Divider()"))
        // The first group has the mode switch and its own rule above it.
        #expect(sidebar.contains("rule: false"))
        // And the fold itself moves, which a bare binding set from a tap does
        // not do on its own.
        #expect(group.contains("withMotion"))
    }

    // MARK: - The credential header

    /// The folded row carried the key id and the service account address, so
    /// the top of the Stores tab was a line of machine identifiers.
    @Test func theCredentialHeaderIsTheNameAndTheState() throws {
        let card = try source("Sources/SuperSubmitter/Design/CredentialCard.swift")

        #expect(card.contains("Text(\"Developer credentials\")"))
        #expect(!card.contains("let summary: String"))
        #expect(!card.contains("Text(summary)"))
        for path in ["Sources/SuperSubmitter/Tabs/StoresTab.swift",
                     "Sources/SuperSubmitter/Overlays/ExistingAppImportSheet.swift"] {
            #expect(try !source(path).contains("summary:"), "\(path) still passes one")
        }
    }
}
