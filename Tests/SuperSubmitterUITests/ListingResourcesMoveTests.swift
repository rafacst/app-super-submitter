import Foundation
import Testing
@testable import SuperSubmitter

/// The two legal blocks belong to the listing, and the boxes that take typing
/// close.
///
/// The licence agreement and the accessibility declaration sat on Marketing,
/// which answers "how does the store sell it?". Neither one sells anything:
/// one is the contract the customer accepts and the other is what the app can
/// do for a customer who cannot see it. Both describe the app, so both belong
/// with the rest of the description.
@MainActor
@Suite struct ListingResourcesMoveTests {

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func source(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appending(path: path), encoding: .utf8)
    }

    private func details() throws -> String {
        try source("Sources/SuperSubmitter/Tabs/DetailsTab.swift")
    }

    private func marketing() throws -> String {
        try source("Sources/SuperSubmitter/Tabs/MarketingTab.swift")
    }

    // MARK: - Where the two blocks live

    @Test func theLicenceAndTheDeclarationStandOnDetails() throws {
        let details = try details()
        #expect(details.contains("Licence agreement"))
        #expect(details.contains("Accessibility declaration"))

        // And nowhere else. A block drawn on two tabs is two boxes writing one
        // manifest key, and the second one to be edited wins silently.
        let marketing = try marketing()
        #expect(!marketing.contains("Licence agreement"))
        #expect(!marketing.contains("Accessibility declaration"))
    }

    /// Every field they carried survives the move. A rearrangement is never a
    /// subtraction: the text, the territories, the length count and every one
    /// of Apple's accessibility toggles still have a control.
    @Test func nothingTheTwoBlocksEditedLeftTheApp() throws {
        let details = try details()

        #expect(details.contains("state.eulaTextBinding"))
        #expect(details.contains("state.eulaTerritoriesBinding"))
        #expect(details.contains("StoreValues.appleTerritories"))
        #expect(details.contains("/ 10000"))
        #expect(details.contains("StoreValues.accessibilityFeatures"))
        #expect(details.contains("state.accessibilityBinding"))
    }

    /// The search has to follow them. A label that opens the wrong tab and
    /// scrolls to nothing is the exact rot `FieldIndexTests` exists to catch,
    /// and moving a block is when it happens.
    @Test func theSearchSendsBothToDetails() throws {
        for id in ["details.eula", "details.accessibility"] {
            let entry = try #require(FieldIndex.all.first { $0.id == id },
                                     "\(id) is not in the index")
            #expect(entry.tab == .details)
        }
        // The old ids are gone rather than left pointing at an empty tab.
        #expect(!FieldIndex.all.contains { $0.id == "marketing.eula" })
        #expect(!FieldIndex.all.contains { $0.id == "marketing.accessibility" })
    }

    // MARK: - The boxes close

    /// Every box that takes typing folds, the way the developer credentials
    /// card in Stores folds.
    ///
    /// A tab of open editors is a tab a developer scrolls past to reach the one
    /// block they came for. `Section_` already folds, so this is the flag and
    /// not a new control.
    @Test func everyBoxThatTakesTypingCloses() throws {
        let sources = try [details(), marketing(),
                           source("Sources/SuperSubmitter/Tabs/MoneyTab.swift")]

        for anchor in ["details.eula", "details.accessibility",
                       "marketing.events", "marketing.routing",
                       "marketing.nomination", "marketing.appClip"] {
            let holder = try #require(sources.first { $0.contains("\"\(anchor)\"") },
                                      "\(anchor) is drawn by no tab")
            let section = try #require(sectionCall(for: anchor, in: holder),
                                       "\(anchor) is not on a Section_")
            #expect(section.contains("folds: true"), "\(anchor) does not fold")
        }
    }

    /// A folding `Section_` draws its own box. A call site that wraps its whole
    /// content in a second one puts a panel inside a panel, which is the one
    /// mistake this component documents.
    @Test func aFoldingSectionDoesNotWrapItsContentInASecondBox() throws {
        let details = try details()
        for anchor in ["details.eula", "details.accessibility"] {
            let call = try #require(sectionCall(for: anchor, in: details))
            #expect(call.contains("folds: true"))
        }
    }

    /// No accordion inside an accordion.
    ///
    /// The two lists hold rows that already open onto their own editors, so a
    /// fold on the section put a field three clicks from the tab. They draw
    /// their own card and their header row carries the count, which is the
    /// summary a shut fold would have been standing in for.
    @Test func theListsThatOpenTheirOwnRowsDoNotFoldAsWell() throws {
        let marketing = try marketing()

        for anchor in ["marketing.customPages", "marketing.experiments"] {
            let call = try #require(sectionCall(for: anchor, in: marketing))
            #expect(!call.contains("folds: true"), "\(anchor) folds around folding rows")
        }
        // A row still opens. The nesting went, not the accordion.
        #expect(marketing.contains("openPages.contains(index)"))
        #expect(marketing.contains("openExperiments.contains(index)"))
        // And a section that draws no box of its own still gets one.
        #expect(marketing.contains(".storePanel(padding: 0)"))
    }

    /// The text of one `Section_(...)` call, from its name to the brace that
    /// opens its content.
    private func sectionCall(for anchor: String, in source: String) -> String? {
        guard let anchorRange = source.range(of: "\"\(anchor)\"") else { return nil }
        let before = source[source.startIndex..<anchorRange.lowerBound]
        guard let start = before.range(of: "Section_(", options: .backwards)
        else { return nil }
        guard let end = source.range(of: "{", range: anchorRange.upperBound..<source.endIndex)
        else { return nil }
        return String(source[start.lowerBound..<end.upperBound])
    }
}
