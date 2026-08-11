import Foundation
import Testing
@testable import SubmitKit
@testable import SuperSubmitter

/// "Can I ship today?" is asked from every screen.
///
/// The answer stood at the head of the Release tab, which is the tab you reach
/// after you have already decided to send. These hold the list that the header
/// band now opens from anywhere, and hold it to the same source the two release
/// buttons obey: a panel that disagreed with the button it describes would be
/// worse than no panel.
@MainActor
@Suite struct BlockersEverywhereTests {

    private func app(stores: Set<Store> = [.apple, .google]) -> AppState {
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        // `stores` is the manifest's own answer to "which stores is this app
        // in", so the app is what a test sets and never the set itself.
        if stores.contains(.apple) {
            state.manifest.apps.apple = Manifest.Apps.Apple(
                appId: "1234567890", platforms: [.ios], bundleId: "com.example.billsplit")
        }
        if stores.contains(.google) {
            state.manifest.apps.google = Manifest.Apps.Google(
                packageName: "com.example.billsplit")
        }
        state.consoleRows = [
            ConsoleRow(id: "apple.privacy", system: "App Store", title: "App privacy",
                       reason: "The App Store will not review an app with no privacy answers.",
                       link: "https://appstoreconnect.apple.com/privacy", state: .needed),
            ConsoleRow(id: "apple.ageRating", system: "App Store", title: "Age rating",
                       reason: "Apple asks the questionnaire once per app.",
                       link: "https://appstoreconnect.apple.com/age", state: .done),
            ConsoleRow(id: "google.dataSafety", system: "Google Play", title: "Data safety",
                       reason: "Play holds the release until the form is answered.",
                       link: "https://play.google.com/console", state: .needed),
        ]
        return state
    }

    // MARK: - What it counts

    /// Only the rows that hold a button back, and both stores' worth of them.
    @Test func itCarriesEveryStoresBlockers() {
        #expect(app().blockersEverywhere.map(\.id) == ["apple.privacy", "google.dataSafety"])
    }

    /// A store this app does not use has no button to hold back, so its rows
    /// are not stopping anything.
    @Test func aStoreThisAppDoesNotUseStopsNothing() {
        #expect(app(stores: [.apple]).blockersEverywhere.map(\.id) == ["apple.privacy"])
    }

    /// The panel and the two release buttons read one list. This is the whole
    /// reason the header panel exists rather than a second count of its own.
    @Test func thePanelAndTheReleaseButtonsReadOneList() {
        let state = app()

        let perStore = Store.allCases.flatMap { state.releaseBlockers(for: $0) }

        #expect(state.blockersEverywhere.map(\.id).sorted() == perStore.map(\.id).sorted())
    }

    /// Nothing needed, nothing said. The header control draws itself off this
    /// count, and a control that reads zero for weeks is furniture.
    ///
    /// The rows are answered rather than marked. A hand mark only carries the
    /// rows no API can read, and one that overrode a `needed` the store just
    /// reported would let a developer tick their way past a real refusal.
    @Test func aClearReleaseBlocksNothing() {
        let state = app()
        state.consoleRows = state.consoleRows.map {
            ConsoleRow(id: $0.id, system: $0.system, title: $0.title, reason: $0.reason,
                       link: $0.link, state: .done)
        }

        #expect(state.blockersEverywhere.isEmpty)
    }

    /// And a hand mark cannot clear one. This is the rule that keeps the header
    /// count honest: a tick is the answer for a step nothing can read, never a
    /// way past a refusal the store has just given.
    @Test func aHandMarkCannotClearAStoresRefusal() {
        let state = app()
        state.consoleMarks = ["apple.privacy", "google.dataSafety"]

        #expect(state.blockersEverywhere.count == 2)
    }

    // MARK: - What it says

    @Test func theHeadlineCountsInTheAppsOwnWords() {
        let state = app()
        state.manifest.release = Manifest.Release(versionName: "2.4.1")

        #expect(state.blockersHeadline(1) == "1 thing is stopping 2.4.1")
        #expect(state.blockersHeadline(2) == "2 things are stopping 2.4.1")
    }

    /// A manifest with no version still has to name what it is stopping.
    @Test func aReleaseWithNoVersionIsStillNamed() {
        #expect(app().blockersHeadline(1) == "1 thing is stopping this release")
    }

    // MARK: - Where it opens from

    /// The header band, on every tab, and the panel behind it.
    @Test func theShellOpensItFromTheHeader() throws {
        let shell = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "Sources/SuperSubmitter/Shell/RootView.swift"),
            encoding: .utf8)

        #expect(shell.contains("BlockersButton()"),
                "the header band lost the way in")
        #expect(shell.contains(".sheet(isPresented: $state.showBlockers)"),
                "the shell does not present the panel")
    }
}
