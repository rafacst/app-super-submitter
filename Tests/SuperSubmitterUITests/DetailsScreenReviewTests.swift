import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

private let detailsReviewRepositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func detailsReviewSource(_ relativePath: String) throws -> String {
    try String(contentsOf: detailsReviewRepositoryRoot.appendingPathComponent(relativePath),
               encoding: .utf8)
}

// MARK: - The text stands in store columns

/// The listing is written for two stores that take different words, and the
/// tab asked the developer to hold both in their head: one column of fields,
/// each carrying whichever store's limit was the smaller of the two.
@Test func theListingStandsInOneColumnPerStore() throws {
    let tab = try detailsReviewSource("Sources/SuperSubmitter/Tabs/DetailsTab.swift")

    #expect(tab.contains("private func pair"))
    #expect(tab.contains("storeColumnHeader"))
    #expect(tab.contains("BindingLimits.limit(for:"))
}

/// A column layout is a rearrangement, never a subtraction. Every field the
/// single column edited still has a box on this tab, and the two Google
/// overrides still have the control that turns them on.
@Test func noListingFieldLeftTheTab() throws {
    let tab = try detailsReviewSource("Sources/SuperSubmitter/Tabs/DetailsTab.swift")

    for field: ListingTextField in [.name, .subtitle, .description, .whatsNew,
                                    .keywords, .promotionalText, .supportURL,
                                    .marketingURL, .privacyPolicyURL,
                                    .privacyPolicyText, .privacyChoicesURL,
                                    .googleShortDescription, .googleWhatsNew] {
        #expect(tab.contains(".\(field.rawValue)"), "\(field.rawValue) left the tab")
    }
    #expect(tab.contains("googleOverrideBinding"))
    #expect(tab.contains("ConsoleStepsPanel"))
    #expect(tab.contains("SearchKeywordsPanel"))
    #expect(tab.contains("AppTagsPanel"))
    #expect(tab.contains("DirectApplyBar(target: .listing)"))
}

/// What the tab is worth reading for before any field is read: what blocks it,
/// what only the console can answer, and how much of it will be written.
@Test func theDetailsBarCountsWhatTheTabOwns() throws {
    let tab = try detailsReviewSource("Sources/SuperSubmitter/Tabs/DetailsTab.swift")

    #expect(tab.contains("consoleRows.filter(\\.onEditingTab)"))
    #expect(tab.contains("readStores()"))
    #expect(tab.contains("writeCount"))
}

/// One value drawn in two columns is still one value, and a window too narrow
/// for two columns has to be able to stand them on top of each other.
@MainActor
@Test func theColumnsMergeOnDemand() {
    let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                         storeAccount: "test-\(UUID().uuidString)")
    #expect(!state.detailsMerged)
    state.detailsMerged = true
    #expect(state.detailsMerged)
}
