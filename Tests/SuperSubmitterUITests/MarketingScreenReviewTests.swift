import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// A one-store tab, and the column that says so.
///
/// The tab was one long column of open editors: every custom product page and
/// every experiment drew all of its fields at once, and none of them said what
/// the store already held. The read has always carried the answer, so a page
/// that has shipped and a page that has never existed looked identical.
@MainActor
@Suite struct MarketingScreenReviewTests {

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func source(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appending(path: path), encoding: .utf8)
    }

    private func actual(pages: [String: String] = [:],
                        experiments: [String: ActualState.Apple.Experiment] = [:],
                        events: [String: String] = [:]) -> ActualState {
        var state = ActualState()
        var apple = ActualState.Apple()
        apple.customProductPageNames = pages
        apple.experiments = experiments
        apple.appEventNames = events
        state.apple = apple
        return state
    }

    // MARK: - What the store already holds

    /// Apple holds one name and the manifest holds two words for it.
    ///
    /// The apply creates a page named after the key and then renames it to the
    /// name, so a page that exists can be sitting under either spelling. A
    /// status that checked one of them called a live page missing.
    @Test func aPageTheStoreHoldsUnderEitherSpellingIsLive() {
        let byKey = actual(pages: ["dinner": "1"])
        let byName = actual(pages: ["Dinner with friends": "1"])

        #expect(MarketingTab.pageStatus(key: "dinner", name: "Dinner with friends",
                                        actual: byKey).text == "Live")
        #expect(MarketingTab.pageStatus(key: "dinner", name: "Dinner with friends",
                                        actual: byName).text == "Live")
    }

    @Test func aPageTheStoreHasNeverSeenWillBeAdded() {
        #expect(MarketingTab.pageStatus(key: "travel", name: "Travel and trips",
                                        actual: actual(pages: ["dinner": "1"])).text == "Will add")
    }

    /// Before a read there is nothing to compare against, and "Will add" would
    /// be a claim about a store nobody has asked.
    @Test func anUnreadStoreClaimsNothingAboutAPage() {
        #expect(MarketingTab.pageStatus(key: "travel", name: "Travel and trips",
                                        actual: ActualState()).text == "Not read")
    }

    // MARK: - The pictures a page carries

    /// The manifest has always held these and the tab drew no control for
    /// them, so the only way to see one was the raw YAML editor. The apply
    /// uploads them.
    @Test func theScreenshotCountIsThePicturesOfThatLocale() {
        var page = Manifest.Marketing.CustomProductPage(key: "dinner", name: "Dinner")
        page.locales = [
            "en-US": .init(screenshots: ["phone": ["a.png", "b.png"], "tablet10": ["c.png"]]),
            "pt-BR": .init(screenshots: ["phone": ["d.png"]]),
        ]

        #expect(MarketingTab.screenshotCount(page, locale: "en-US") == 3)
        #expect(MarketingTab.screenshotCount(page, locale: "pt-BR") == 1)
        #expect(MarketingTab.screenshotCount(page, locale: "fr-FR") == 0)
    }

    // MARK: - The experiments

    /// Apple's own state word, not one this app invented for it.
    @Test func theExperimentPrintsTheStateAppleReturned() {
        let running = actual(experiments: ["icon-2026": .init(state: "ACCEPTED")])
        #expect(MarketingTab.experimentStatus(key: "icon-2026", name: "Rounded icon",
                                              actual: running).text == "Accepted")
        #expect(MarketingTab.experimentStatus(key: "icon-2026", name: "Rounded icon",
                                              actual: ActualState()).text == "Not read")
    }

    /// The run so far, from the dates Apple returns with the experiment.
    @Test func theExperimentPrintsItsDayOfTheRun() {
        let formatter = ISO8601DateFormatter()
        let start = formatter.date(from: "2026-08-01T00:00:00Z")!
        let end = formatter.date(from: "2026-08-31T00:00:00Z")!
        let today = formatter.date(from: "2026-08-09T12:00:00Z")!

        #expect(MarketingTab.dayOfRun(start: start, end: end, now: today) == "day 9 of 30")
    }

    /// A prepared experiment has no start date, and inventing a day one would
    /// report a run that has not begun.
    @Test func anExperimentThatHasNotStartedPrintsNoDay() {
        #expect(MarketingTab.dayOfRun(start: nil, end: nil, now: Date()) == nil)
    }

    // MARK: - What the columns hold

    @Test func theTwoColumnsAndEveryBlockAreOnTheTab() throws {
        let tab = try source("Sources/SuperSubmitter/Tabs/MarketingTab.swift")

        // The Play column, which is the point of the screen.
        #expect(tab.contains("Play has none of this"))
        #expect(tab.contains("Open Play Console"))
        // The App Store column, as rows rather than open editors.
        #expect(tab.contains("private func pageRow"))
        #expect(tab.contains("private func experimentRow"))
        #expect(tab.contains("of 35"))
        // Every block that answers "how does the store sell it?" is still on
        // the tab. A rearrangement is never a subtraction, and the design's
        // card draws only four of these.
        #expect(tab.contains("marketing.customPages"))
        #expect(tab.contains("marketing.experiments"))
        #expect(tab.contains("marketing.events"))
        #expect(tab.contains("marketing.routing"))
        #expect(tab.contains("marketing.nomination"))
        #expect(tab.contains("marketing.appClip"))
        // The licence agreement and the accessibility declaration left for
        // Details. Neither one sells the app: both describe it. See
        // `ListingResourcesMoveTests`.
        #expect(!tab.contains("marketing.eula"))
        #expect(!tab.contains("marketing.accessibility"))
        // The editors survive the rows: a row opens onto them.
        #expect(tab.contains("Add a custom product page"))
        #expect(tab.contains("Add an experiment"))
        #expect(tab.contains("Add an in-app event"))
        #expect(tab.contains("PromoteTreatment()"))
    }

    /// The design's App Store column says "writes to the live page, not a
    /// draft". The apply POSTs a page version, never starts an experiment, and
    /// creates the nomination as a draft, so that line is false here.
    @Test func theTabNeverClaimsToWriteStraightToTheLivePage() throws {
        let tab = try source("Sources/SuperSubmitter/Tabs/MarketingTab.swift")
        #expect(!tab.contains("not a draft"))
        #expect(!tab.contains("straight to the live listing"))
    }
}
