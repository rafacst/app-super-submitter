import Foundation
import Testing
@testable import SubmitKit
@testable import SuperSubmitter

/// What the app says about a version Apple already has.
///
/// The bug this guards: the release checklist kept holding a version that had
/// been submitted. Every row in it is advice about a draft, and none of it can
/// be acted on once the version is with review, so the header read "1 thing is
/// stopping 1.6" beside a sidebar chip that said the same 1.6 was in review,
/// with a Re-check button that could never clear it.
@MainActor
struct PastPreparationTests {

    private func state(_ build: (inout ActualState.Apple) -> Void) -> AppState {
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        state.manifest.apps.apple = Manifest.Apps.Apple(
            appId: "123", platforms: [.ios], bundleId: "com.example.app")
        var apple = ActualState.Apple()
        build(&apple)
        var actual = ActualState()
        actual.apple = apple
        state.actualState = actual
        state.consoleRows = [
            ConsoleRow(id: "apple.version", system: "App Store",
                       title: "The submitted version", reason: "No version is prepared.",
                       link: "", state: .needed),
        ]
        return state
    }

    /// The reported case.
    @Test func aVersionWithReviewIsStoppedByNothing() {
        let state = state { $0.versionState = "IN_REVIEW" }

        #expect(state.releaseBlockers(for: .apple).isEmpty)
        #expect(state.blockersEverywhere.isEmpty)
    }

    @Test func aVersionWaitingInTheQueueIsStoppedByNothingEither() {
        let state = state { $0.versionState = "WAITING_FOR_REVIEW" }

        #expect(state.releaseBlockers(for: .apple).isEmpty)
    }

    /// Approved and waiting for the developer to press go. Nothing left to
    /// prepare, and the button it holds is a release and not a submission.
    @Test func anApprovedVersionIsStoppedByNothing() {
        let state = state { $0.versionState = "PENDING_DEVELOPER_RELEASE" }

        #expect(state.releaseBlockers(for: .apple).isEmpty)
    }

    /// The one it must never suppress. Apple handing the version back is
    /// exactly when the checklist starts mattering again.
    @Test func aRefusedVersionGetsItsChecklistBack() {
        let state = state { $0.versionState = "REJECTED" }

        #expect(state.releaseBlockers(for: .apple).count == 1)
    }

    @Test func aDraftKeepsItsChecklist() {
        let state = state { $0.versionState = "PREPARE_FOR_SUBMISSION" }

        #expect(state.releaseBlockers(for: .apple).count == 1)
    }

    /// The state the report was made in: the reader could not name the version
    /// at all, and the status card was the only thing that knew.
    @Test func theStatusCardAnswersWhenTheReaderCannot() {
        let state = state { _ in }
        state.statuses[.apple] = StoreStatus(store: .apple, phase: .inReview, detail: "")

        #expect(state.releaseBlockers(for: .apple).isEmpty)
    }

    @Test func aStatusCardThatSaysRejectedKeepsTheChecklist() {
        let state = state { _ in }
        state.statuses[.apple] = StoreStatus(store: .apple, phase: .rejected, detail: "")

        #expect(state.releaseBlockers(for: .apple).count == 1)
    }

    // MARK: - The chip

    /// Waiting in Apple's queue and being read by a reviewer are days apart,
    /// and they were the same word.
    @Test func theQueueAndTheReviewAreTwoWords() {
        #expect(AppleStanding(state: "WAITING_FOR_REVIEW").label == "In queue")
        #expect(AppleStanding(state: "READY_FOR_REVIEW").label == "Store draft")
        #expect(AppleStanding(state: "IN_REVIEW").label == "In review")
    }

    /// The pulse means a reviewer has it open. Motion that ran for the days a
    /// version sits in a queue would say nothing at all.
    @Test func onlyTheOpenReviewAnimates() {
        #expect(AppleStanding(state: "IN_REVIEW").active)
        #expect(!AppleStanding(state: "WAITING_FOR_REVIEW").active)
        #expect(!AppleStanding(state: "PENDING_DEVELOPER_RELEASE").active)
        #expect(!AppleStanding(state: "READY_FOR_SALE").active)
        #expect(!AppleStanding(state: nil).active)
    }

    /// Processing for distribution is past the answer: Apple is preparing to
    /// ship the version, not reading it.
    @Test func processingForDistributionReadsAsApproved() {
        #expect(AppleStanding(state: "PROCESSING_FOR_DISTRIBUTION").label == "Approved")
    }

    /// Unchanged, and each still one word apart from the rest.
    @Test func theOtherStandingsAreWhatTheyWere() {
        #expect(AppleStanding(state: "READY_FOR_SALE").label == "Live")
        #expect(AppleStanding(state: "PREPARE_FOR_SUBMISSION").label == "Store draft")
        #expect(AppleStanding(state: "REJECTED").label == "Refused")
        // A store that answered and holds no version. Nobody having asked is
        // the other thing, and the two were one word.
        #expect(AppleStanding(state: "").label == "Local only")
        #expect(AppleStanding(state: nil).label == "Unknown")
    }
}
