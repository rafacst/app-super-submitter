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
    #expect(!shell.contains("case .build: BuildInspector()"))
}

@Test func theBuildRedesignKeepsEveryExistingStoreAction() throws {
    let build = try responsiveFormSource("Sources/SuperSubmitter/Tabs/BuildTab.swift")

    for marker in ["This app in the stores", "App Store takes", "Google Play takes",
                   "StoreDiagnosticsPanel()", "XcodeCloudPanel()",
                   "SigningIdentitiesPanel()"] {
        #expect(build.contains(marker), "Build lost \(marker)")
    }
    #expect(build.contains("accept: state.importPackages"))
    #expect(build.contains("BuildFromProjectView()"))
    #expect(build.contains("AndroidArtifactsSection()"))
    #expect(build.contains("GoogleTracksSection()"))
}

/// Everything a tester meets is on one tab, and none of it is left behind on
/// the tab that makes the package.
///
/// The three moved from three different places: TestFlight from a fold beside
/// the drop wells, the track testers from the foot of the Google track block,
/// and internal app sharing from inside the tooling fold. A copy left behind
/// in either file is one screen writing what another screen owns.
@Test func everyBetaSurfaceIsOnTheBetaTestingTab() throws {
    let beta = try responsiveFormSource("Sources/SuperSubmitter/Tabs/BetaTestingTab.swift")
    let build = try responsiveFormSource("Sources/SuperSubmitter/Tabs/BuildTab.swift")
    let tracks = try responsiveFormSource(
        "Sources/SuperSubmitter/Tabs/AndroidArtifactsSection.swift")

    for marker in ["TestFlightSection()", "GoogleTestersSection()",
                   "InternalSharingPanel()"] {
        #expect(beta.contains(marker), "Beta testing lost \(marker)")
    }
    #expect(!build.contains("TestFlightSection()"))
    #expect(!build.contains("InternalSharingPanel()"))
    #expect(!tracks.contains("googleTestersBinding"))
}

/// The store page is a whole tab like every other, and it has a row of its own.
///
/// It used to have none: the app list sat at the head of the sidebar and
/// pressing an app's name opened it, so a row beside that name would have put
/// one destination in the column twice. The apps are the tab bar across the top
/// of the window now and pressing one keeps the screen you are reading, so
/// nothing opened the store page any more and it needs its row back.
@Test func theStorePageHasARowOfItsOwn() throws {
    let content = try responsiveFormSource("Sources/SuperSubmitter/Tabs/TabContent.swift")
    let bar = try responsiveFormSource("Sources/SuperSubmitter/Shell/AppTabBar.swift")

    #expect(content.contains("case .storePage: StorePage()"))
    #expect(Tab.storePage.isListed)
    // Under Publish, where the developer looks at the page their draft makes,
    // and under Manage, where they look at the page the store is serving.
    #expect(Destination.rows(in: .publish, hasApp: true).contains { $0.tab == .storePage })
    #expect(Destination.rows(in: .manage, hasApp: true).contains { $0.tab == .storePage })

    // And the bar changes app without moving off the screen you are on. It is
    // the whole reason the row came back.
    #expect(bar.contains("state.selectApp(at: index)"))
    #expect(!bar.contains("selectedTab = .storePage"))
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
    // The price of the app is the Availability tab's. It was the top panel of
    // Monetization, over the products it has nothing to do with.
    let money = try responsiveFormSource("Sources/SuperSubmitter/Tabs/AvailabilityTab.swift")
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
