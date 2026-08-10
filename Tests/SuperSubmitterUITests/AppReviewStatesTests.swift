import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// Which of the linked apps App Store review is holding.
///
/// Every rule about a version under review read `actualState`, and
/// `actualState` only ever describes the app that happens to be open. A
/// developer with six linked apps had to open each one to learn which of them
/// were frozen, and the sidebar that lists all six said nothing.
@MainActor
@Suite(.serialized) struct AppReviewStatesTests {

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func source(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appending(path: path), encoding: .utf8)
    }

    private func state() -> AppState {
        AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                 storeAccount: "test-\(UUID().uuidString)")
    }

    // MARK: - What one cached state means

    @Test func anAppAppleIsHoldingIsLockedAndOneInPreparationIsNot() {
        let state = state()
        state.appReviewStates = [
            "1111": "WAITING_FOR_REVIEW",
            "2222": "PREPARE_FOR_SUBMISSION",
            "3333": "METADATA_REJECTED",
        ]

        #expect(state.isAppLocked(appKey: "1111"))
        #expect(!state.isAppLocked(appKey: "2222"))
        // Apple handed it back. It takes new text and a new build under the
        // same number, so it is the opposite of locked.
        #expect(!state.isAppLocked(appKey: "3333"))
    }

    /// An app nobody has read is not an app that is free. Claiming either way
    /// about a store nobody asked is the thing this whole feature exists to
    /// stop, so an unread app says "unknown" and locks nothing.
    @Test func anUnreadAppClaimsNothing() {
        let state = state()
        #expect(!state.isAppLocked(appKey: "9999"))
        #expect(state.appReviewStates["9999"] == nil)
    }

    /// The words the sidebar puts beside a row.
    @Test func eachStateGetsTheWordApplesOwnStateEarns() {
        let state = state()
        state.appReviewStates = [
            "1111": "IN_REVIEW",
            "2222": "PENDING_DEVELOPER_RELEASE",
            "3333": "REJECTED",
            "4444": "PREPARE_FOR_SUBMISSION",
        ]

        #expect(state.appReviewMark(appKey: "1111")?.text == "In review")
        #expect(state.appReviewMark(appKey: "2222")?.text == "Approved")
        #expect(state.appReviewMark(appKey: "3333")?.text == "Refused")
        // A draft is the ordinary state and earns no mark at all: a column
        // where every row wears a badge is a column with no signal in it.
        #expect(state.appReviewMark(appKey: "4444") == nil)
    }

    // MARK: - The open app agrees with the sweep

    /// The open app is read twice, by the full plan read and by this sweep,
    /// and the two may never disagree about it.
    @Test func theOpenAppTakesItsStateFromTheReadItAlreadyHas() throws {
        let state = state()
        var actual = ActualState()
        var apple = ActualState.Apple()
        apple.versionState = "IN_REVIEW"
        actual.apple = apple
        state.actualState = actual

        state.rememberOpenAppReviewState()

        #expect(state.appReviewStates[state.currentAppKey] == "IN_REVIEW")
    }

    // MARK: - Where it runs and where it shows

    @Test func theSweepRunsWhenTheAppListIsOpenedAndOnEveryAppChange() throws {
        let review = try source("Sources/SuperSubmitter/AppStateReview.swift")
        #expect(review.contains("func refreshReviewStates"))
        // Every linked app, not the open one.
        #expect(review.contains("linkedApps"))

        // Picking an app is the moment the answer is needed.
        let appState = try source("Sources/SuperSubmitter/AppState.swift")
        #expect(appState.contains("await refreshReviewStates()"))

        let sidebar = try source("Sources/SuperSubmitter/Shell/Sidebar.swift")
        #expect(sidebar.contains("appReviewMark"))
    }
}
