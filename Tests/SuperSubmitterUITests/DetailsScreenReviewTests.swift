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

/// The merged column is where the tab opens. Two columns are the study, and a
/// developer who wants them asks for them.
@MainActor
@Test func theTabOpensMerged() {
    let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                         storeAccount: "test-\(UUID().uuidString)")
    #expect(state.detailsMerged)
    state.detailsMerged = false
    #expect(!state.detailsMerged)
}

/// One value is one box. Merged, the two columns of a shared field collapsed
/// into two boxes of the same text stacked on each other: Name over Name,
/// Description over Description, both writing the same manifest key.
@Test func aMergedRowDrawsOneBoxPerValue() throws {
    let tab = try detailsReviewSource("Sources/SuperSubmitter/Tabs/DetailsTab.swift")

    #expect(tab.contains("private func sharedRow"))
    #expect(tab.contains("private func limits"))
}

/// A limit the developer cannot see is a limit they find out about from the
/// store. Every field that has one prints it, and a merged row says whose it
/// is, because Apple cuts the subtitle at 30 and Play cuts it at 80.
@Test func everyBudgetIsPrintedAndNamed() throws {
    let editor = try detailsReviewSource("Sources/SuperSubmitter/Tabs/DetailsTab.swift")

    #expect(editor.contains("struct FieldLimit"))
    #expect(editor.contains("limit.store"))
    // The counter used to wait until the text passed half the budget.
    #expect(!editor.contains("> 0.5"))
}

/// The identifiers belong to the store, and a box you can type in says the
/// opposite. The Build tab already draws them as values; so does this one.
@Test func theIdentifiersAreNotTypedIn() throws {
    let panel = try detailsReviewSource("Sources/SuperSubmitter/Tabs/AppIdentifiers.swift")

    #expect(!panel.contains("TextField("))
    #expect(panel.contains("Choose visible app"))
}

/// The inspector is a column of the window, not a column inside the tab.
///
/// Opening it from inside the detail column grew that column by the width of
/// the inspector, so the split view laid all three out wider than the window
/// and the sidebar slid off the left edge until the animation settled.
@Test func theInspectorIsAColumnOfTheWindow() throws {
    let root = try detailsReviewSource("Sources/SuperSubmitter/Shell/RootView.swift")
    let start = try #require(root.range(of: "private struct ContentArea"))
    let contentArea = String(root[start.lowerBound...])

    #expect(!contentArea.contains(".inspector(isPresented:"))
    #expect(root.contains(".inspector(isPresented:"))
}
