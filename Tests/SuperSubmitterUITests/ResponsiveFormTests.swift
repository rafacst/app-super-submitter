import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

private let responsiveFormRepositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func responsiveFormSource(_ relativePath: String) throws -> String {
    try String(contentsOf: responsiveFormRepositoryRoot.appendingPathComponent(relativePath),
               encoding: .utf8)
}

/// Build keeps the store tools reachable without giving them a permanent
/// inspector that squeezes the two artifact columns.
@Test func theBuildToolsStayInsideTheResponsiveBuildScreen() throws {
    let shell = try responsiveFormSource("Sources/SuperSubmitter/Shell/RootView.swift")
    let build = try responsiveFormSource("Sources/SuperSubmitter/Tabs/BuildTab.swift")

    #expect(build.contains("private var storeTools"))
    #expect(build.contains("ViewThatFits(in: .horizontal)"))
    #expect(!shell.contains("case .build: BuildInspector()"))
}

@Test func theBuildRedesignKeepsEveryExistingStoreAction() throws {
    let build = try responsiveFormSource("Sources/SuperSubmitter/Tabs/BuildTab.swift")

    for marker in ["This app in the stores", "App Store takes", "Google Play takes",
                   "StoreDiagnosticsPanel()", "XcodeCloudPanel()",
                   "SigningIdentitiesPanel()", "InternalSharingPanel()"] {
        #expect(build.contains(marker), "Build lost \(marker)")
    }
    #expect(build.contains("accept: state.importPackages"))
    #expect(build.contains("BuildFromProjectView()"))
    #expect(build.contains("TestFlightSection()"))
    #expect(build.contains("AndroidArtifactsSection()"))
    #expect(build.contains("GoogleTracksSection()"))
}

@Test func theWideBuildScreenKeepsBothStoreCardsInOneRow() throws {
    let build = try responsiveFormSource("Sources/SuperSubmitter/Tabs/BuildTab.swift")
    let start = try #require(build.range(of: "private var storeBuildColumns"))
    let end = try #require(build.range(of: "private var appleBuildCard"))
    let columns = String(build[start.lowerBound..<end.lowerBound])

    #expect(columns.contains("HStack(alignment: .top, spacing: 14)"))
    #expect(!columns.contains("ViewThatFits"))
}

/// Selecting Build also presents its saved inspector. That presentation must
/// not animate the whole split view wider and briefly push the sidebar offscreen.
@Test func selectingATabDoesNotAnimateTheWholeSplitView() throws {
    let sidebar = try responsiveFormSource("Sources/SuperSubmitter/Shell/Sidebar.swift")
    let start = try #require(sidebar.range(of: "private var selection:"))
    let end = try #require(sidebar.range(of: "private func isOpen"))
    let selection = String(sidebar[start.lowerBound..<end.lowerBound])

    #expect(selection.contains("withTransaction"))
    #expect(selection.contains("disablesAnimations = true"))
}

/// A vertically growing TextField asks the entire Details scroll view to
/// remeasure after each character. The native editor keeps a stable viewport.
@Test func multilineListingTextUsesAStableEditor() throws {
    let details = try responsiveFormSource("Sources/SuperSubmitter/Tabs/DetailsTab.swift")

    #expect(details.contains("TextEditor(text: $draft.text.limited(to: limit))"))
    #expect(!details.contains("axis: .vertical"))
}

/// A base amount is an App Store price point, never arbitrary text. Currency
/// comes first because it determines which monetary values make sense.
@Test func basePriceIsCurrencyThenPricePicker() throws {
    let money = try responsiveFormSource("Sources/SuperSubmitter/Tabs/MoneyTab.swift")
    let start = try #require(money.range(of: "private var priceSection"))
    let end = try #require(money.range(of: "private var resolvedPoint"))
    let section = String(money[start.lowerBound..<end.lowerBound])

    let currency = try #require(section.range(of: "LabeledField(\"Currency\""))
    let amount = try #require(section.range(of: "LabeledField(\"Amount\""))
    #expect(currency.lowerBound < amount.lowerBound)
    #expect(!section.contains("TextField(\"0.00\""))
    #expect(section.contains(".disabled(points.isEmpty)"))
}

// The Build row reflects the run even while the developer works on another
// tab. It reports the archive and the upload apart, so
// `BuildScreenReviewTests` owns those assertions now.
