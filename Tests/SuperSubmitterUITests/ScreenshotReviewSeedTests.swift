import Foundation
import Testing
@testable import SubmitKit
@testable import SuperSubmitter

/// The one part of the app that has been tested and never seen.
///
/// Everything a version under review changes — the Summary banner, the held
/// row, the mark beside the app in the sidebar, the locked listing — hangs off
/// `actualState.apple.versionState`, and that only ever arrives from a live
/// store read. The app caches no `ActualState` to disk, so no fixture on disk
/// reaches the screen and no screenshot of it exists. The rules were under
/// test; the drawing of them was not.
///
/// This seeds the read, and only the read. Everything below it is the app's own
/// answer to that state, so a picture taken this way is the screen a developer
/// with a version in review really gets.
@MainActor
@Suite(.serialized) struct ScreenshotReviewSeedTests {

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func source(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appending(path: path), encoding: .utf8)
    }

    /// An app with a store, which is what the fixture the script passes has.
    /// Without one there is nothing for a review to hold.
    private func state() -> AppState {
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        state.manifest.apps.apple = Manifest.Apps.Apple(
            appId: "1234567890", platforms: [.ios], bundleId: "com.example.billsplit")
        return state
    }

    // MARK: - What the seed reaches

    @Test func theSeedPutsTheAppWhereOnlyALiveReadCouldPutIt() throws {
        let state = state()
        ScreenshotMode.seedReview(state, versionState: "WAITING_FOR_REVIEW")

        let answer = try #require(state.reviewOutcome)
        #expect(answer.outcome == .waiting)
        #expect(state.appleHoldsAVersion)
        // The banner names the version, so the seed has to carry one. "This
        // version is with App Store review" is a sentence about nothing.
        #expect(answer.line.contains(state.manifest.release?.versionName ?? "3.2.0"))
    }

    /// The sidebar reads the per-app cache and never `actualState`, so a seed
    /// that stopped at the open app's read would light the banner and leave the
    /// row beside the app blank.
    @Test func theSeedReachesTheSidebarAndNotOnlyTheOpenTab() {
        let state = state()
        ScreenshotMode.seedReview(state, versionState: "IN_REVIEW")

        #expect(state.appReviewMark(appKey: state.currentAppKey)?.text == "In review")
        #expect(state.isAppLocked(appKey: state.currentAppKey))
    }

    /// The picture has to be the app's own answer to the seeded read and not a
    /// drawing of one. The plan comes from `Planner`, so the held row on screen
    /// is the row the validator really produces for that state.
    @Test func theHeldRowComesFromTheValidatorAndNotFromTheSeed() throws {
        let state = state()
        ScreenshotMode.seedReview(state, versionState: "IN_REVIEW")

        let plan = try #require(state.plan)
        let held = try #require(plan.findings.first { $0.id == Validator.appleVersionFindingID })
        #expect(held.severity == .held)
        // It stops the apply without joining the errors. This manifest is a
        // bare one and carries errors of its own, so the claim is about the
        // hold itself rather than about the plan being otherwise clean.
        #expect(plan.isBlocked)
        #expect(!plan.errors.contains { $0.id == Validator.appleVersionFindingID })
    }

    /// The seeded plan is also what keeps the seed alive. The Summary tab reads
    /// the stores when it appears unless a plan is already there, and that read
    /// finds no credentials in a screenshot run, answers an empty `ActualState`
    /// and would wipe the version state a moment after it was written.
    @Test func theSeededPlanIsWhatStopsTheTabReadingOverIt() throws {
        let state = state()
        ScreenshotMode.seedReview(state, versionState: "IN_REVIEW")
        #expect(state.plan != nil)

        let tab = try source("Sources/SuperSubmitter/Tabs/PlanTab.swift")
        #expect(tab.contains("state.plan == nil"))
    }

    /// Apple's three answers. One run per state shows the whole feature, and
    /// each of the three draws a different banner, a different row and a
    /// different mark.
    @Test func everyOutcomeIsReachableFromTheFlag() {
        let wanted: [(String, AppleVersionState.Outcome)] = [
            ("WAITING_FOR_REVIEW", .waiting),
            ("PENDING_DEVELOPER_RELEASE", .approved),
            ("METADATA_REJECTED", .refused),
        ]
        for (versionState, outcome) in wanted {
            let app = state()
            ScreenshotMode.seedReview(app, versionState: versionState)
            #expect(app.reviewOutcome?.outcome == outcome, "\(versionState) never arrived")
        }
    }

    // MARK: - Where the script asks for it

    @Test func theScriptCanAskForItAndTheShippedBuildCarriesNoneOfIt() throws {
        let mode = try source("Sources/SuperSubmitter/ScreenshotMode.swift")

        #expect(mode.contains("--review"))
        #expect(mode.contains("seedReview"))
        // The same rule the rest of this file follows: a launch argument is a
        // debug affordance, and the notarized build has no way to reach it.
        #expect(mode.contains("#if DEBUG"))
    }
}
