import Foundation
import Testing
@testable import SubmitKit
@testable import SuperSubmitter

/// What has to exist before a version may be sent to review.
///
/// The bug this guards: the release button asked `applied`, a flag about this
/// session, to answer a question about the store. Everything was applied, the
/// store held the draft, the checklist was green and the card read **Draft,
/// ready to release**, and the button under it stayed dead saying to run an
/// apply on the Summary. The Summary had nothing to apply, because the store
/// already matched. There was no way out of that screen.
///
/// The status card was taught to ask the store once already. This is the same
/// question, asked by the button.
@MainActor
struct ReleaseNeedsADraftTests {

    private func state(_ build: (inout ActualState.Apple) -> Void) -> AppState {
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        var apple = ActualState.Apple()
        build(&apple)
        var actual = ActualState()
        actual.apple = apple
        state.actualState = actual
        return state
    }

    /// The reported case. A draft the store is holding, and no apply in this
    /// session because the app was relaunched or another app was opened.
    @Test func aDraftTheStoreHoldsCountsWithoutAnApplyThisSession() {
        let state = state { $0.versionState = "PREPARE_FOR_SUBMISSION" }
        state.applied = false

        #expect(state.hasDraft(.apple))
    }

    /// The state the block is for. Nothing has been written, so there is
    /// nothing to send and the advice under the button can be followed.
    @Test func noVersionOnTheStoreIsStillNoDraft() {
        let state = state { _ in }
        state.applied = false

        #expect(!state.hasDraft(.apple))
    }

    /// The read has not run yet, so the store has said nothing. This session's
    /// own apply is then the only evidence there is, and it stands.
    @Test func anApplyThisSessionStillCountsBeforeTheFirstRead() {
        let state = state { _ in }
        state.applied = true

        #expect(state.hasDraft(.apple))
    }

    /// A version already with review is past the draft question entirely. The
    /// button reads `released` for those, and this must not call them empty.
    @Test func aVersionInReviewIsNotMissingADraft() {
        let state = state { $0.versionState = "WAITING_FOR_REVIEW" }
        state.applied = false

        #expect(state.hasDraft(.apple))
    }

    /// A developer-rejected version is a draft again: Apple hands it back for
    /// editing, and sending it once more is exactly the thing to do.
    @Test func aVersionApplePushedBackIsADraftAgain() {
        let state = state { $0.versionState = "DEVELOPER_REJECTED" }
        state.applied = false

        #expect(state.hasDraft(.apple))
    }

    /// The card and the button have to answer alike, or the screen argues with
    /// itself: "Draft, ready to release" over "no draft exists yet".
    @Test func theCardAndTheButtonAgree() {
        let state = state { $0.versionState = "PREPARE_FOR_SUBMISSION" }
        // `stores` is read off the manifest, so an App Store app is one that
        // names an App Store app.
        state.manifest.apps.apple = Manifest.Apps.Apple(
            appId: "123", platforms: [.ios], bundleId: "com.example.app")
        state.refreshDraftStatuses()

        #expect(state.statuses[.apple]?.phase == .draft)
        #expect(state.hasDraft(.apple))
    }
}
