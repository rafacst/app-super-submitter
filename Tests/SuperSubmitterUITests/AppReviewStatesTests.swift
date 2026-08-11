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
            "5555": "READY_FOR_DISTRIBUTION",
            "6666": "DEVELOPER_REJECTED",
        ]

        #expect(state.appMark(appKey: "1111").label == "In review")
        // Apple said yes and nobody can buy it yet. The release is still a
        // button somebody has to press.
        #expect(state.appMark(appKey: "2222").label == "Approved")
        #expect(state.appMark(appKey: "3333").label == "Refused")
        // A draft is the ordinary state, and it is the answer for most of the
        // apps in the list on most days. It said nothing at all before.
        #expect(state.appMark(appKey: "4444").label == "Draft")
        // The one the column exists for: on sale, and not merely approved.
        #expect(state.appMark(appKey: "5555").label == "Live")
        // The developer withdrew it. Apple never refused it, so it is a draft
        // and not a refusal. See `AppleVersionState.outcome`.
        #expect(state.appMark(appKey: "6666").label == "Draft")
    }

    /// A read that never happened claims nothing, and says so in a word.
    ///
    /// A blank was the answer before, and a blank is not a claim being
    /// withheld: the row read as an app with nothing to say, beside rows that
    /// all wore a word. It is also the state every app is in between being
    /// linked and its first read answering, which is a moment the developer is
    /// looking straight at.
    @Test func anAppNobodyReadSaysSo() {
        let state = state()
        state.appReviewStates = ["1111": ""]

        #expect(state.appMark(appKey: "1111").label == "Unknown")
        #expect(state.appMark(appKey: "9999").label == "Unknown")
    }

    /// Google Play publishes no review state at all, so a Play app has one fact
    /// to wear: whether the store has ever had it. A read that answered is a
    /// word either way, and only a read that never happened is "Unknown".
    @Test func anAppWithNoAppleStateWearsWhatTheStoresAnswered() {
        let state = state()
        state.appLiveStates = ["com.example.live": true, "com.example.draft": false]

        #expect(state.appMark(appKey: "com.example.live").label == "Live")
        #expect(state.appMark(appKey: "com.example.draft").label == "Not on the store")
        #expect(state.appMark(appKey: "com.example.unread").label == "Unknown")
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

    @Test func theSweepRunsAtLaunchAndOnEveryAppChange() throws {
        let review = try source("Sources/SuperSubmitter/AppStateReview.swift")
        #expect(review.contains("func refreshReviewStates"))
        // Every linked app, not the open one.
        #expect(review.contains("linkedApps"))

        // Picking an app is one moment the answer is needed.
        let appState = try source("Sources/SuperSubmitter/AppState.swift")
        #expect(appState.contains("await refreshReviewStates()"))

        // Opening the app is the other, and it is the one that was missing:
        // the status column drew nothing until something had been clicked.
        let shell = try source("Sources/SuperSubmitter/SuperSubmitterApp.swift")
        #expect(shell.contains("await state.refreshReviewStates()"))

        let sidebar = try source("Sources/SuperSubmitter/Shell/Sidebar.swift")
        #expect(sidebar.contains("appMark"))
    }

    /// The keys are in the Keychain at launch, so the app asks the stores about
    /// them itself. It used to open on "not connected" beside a filled-in key
    /// id and wait to be told what it could have found out.
    @Test func theStoredKeysAreCheckedAtLaunch() throws {
        let appState = try source("Sources/SuperSubmitter/AppState.swift")
        #expect(appState.contains("func verifyStoredConnections"))
        // Google's OAuth route opens a browser window to connect, and a window
        // that opens itself at launch is an interruption and not a check.
        #expect(appState.contains("googleCredentialChoice == .serviceAccount"))

        let shell = try source("Sources/SuperSubmitter/SuperSubmitterApp.swift")
        #expect(shell.contains("state.verifyStoredConnections()"))
    }
}
