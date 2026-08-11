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

/// A store refuses a listing that is missing a field it needs, and the tab said
/// nothing about which fields those were until the refusal arrived.
@Test func theRequiredFieldsNameTheStoreThatWantsThem() {
    #expect(DetailsTab.requiring(.name, newApp: true) == [.apple, .google])
    #expect(DetailsTab.requiring(.description, newApp: true) == [.apple, .google])
    #expect(DetailsTab.requiring(.privacyPolicyURL, newApp: true) == [.apple, .google])
    // Play reads the subtitle as its short description, which it needs.
    #expect(DetailsTab.requiring(.subtitle, newApp: true) == [.google])
    #expect(DetailsTab.requiring(.googleShortDescription, newApp: true) == [.google])
    #expect(DetailsTab.requiring(.supportURL, newApp: true) == [.apple])
    // Apple wants release notes on an update and takes none on a first submit.
    #expect(DetailsTab.requiring(.whatsNew, newApp: true).isEmpty)
    #expect(DetailsTab.requiring(.whatsNew, newApp: false) == [.apple])
    // Nothing else is refused for being empty.
    #expect(DetailsTab.requiring(.keywords, newApp: false).isEmpty)
    #expect(DetailsTab.requiring(.promotionalText, newApp: false).isEmpty)
    #expect(DetailsTab.requiring(.marketingURL, newApp: false).isEmpty)
}

/// The mark names the store when only one of the two asks, and says nothing
/// extra when both do.
@Test func theRequiredMarkIsOnTheTab() throws {
    let tab = try detailsReviewSource("Sources/SuperSubmitter/Tabs/DetailsTab.swift")

    #expect(tab.contains("RequiredTag"))
    #expect(tab.contains("requirement"))
}

/// The identifiers belong to the store and are required, and those two facts
/// pull opposite ways. They were drawn as values, so that a box you can type in
/// would not invite somebody to invent an App id. What that cost was the only
/// way in: an import or a picker over apps a credential can see, and neither is
/// available to a developer whose credential cannot list the app or who has not
/// connected one. The screen exists so a wrong bundle id is fixable without the
/// YAML editor, and it sent them to the YAML editor.
///
/// So they are typed, the picker stays because it is the safer way when it is
/// there, and the paragraph above them is what warns.
@Test func theIdentifiersCanBeTypedAndStillOfferThePicker() throws {
    let panel = try detailsReviewSource("Sources/SuperSubmitter/Tabs/AppIdentifiers.swift")

    #expect(panel.contains("TextField(placeholder, text: $value)"))
    #expect(panel.contains("commit: state.updateAppleAppFields"))
    #expect(panel.contains("commit: state.updateGoogleAppFields"))
    // The safer way in has to survive the change that made typing possible.
    #expect(panel.contains("Choose visible app"))
    #expect(panel.contains("an id that names another app writes to it"))
}

/// The reference column moves nothing but itself.
///
/// `.inspector` resizes something the developer did not ask to resize wherever
/// it hangs: inside the detail column it pushed the sidebar off the left edge,
/// and on the split view it widened the window itself. The column is drawn by
/// hand instead, so showing it takes width from the page and leaves the window
/// where it is.
@Test func theReferenceColumnNeverResizesTheWindow() throws {
    let root = try detailsReviewSource("Sources/SuperSubmitter/Shell/RootView.swift")

    #expect(!root.contains(".inspector(isPresented:"))
    #expect(!root.contains("inspectorColumnWidth"))
    #expect(root.contains("private var showsInspector"))
    #expect(root.contains("DetailsInspector()"))
}
