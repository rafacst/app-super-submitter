import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// The two ways forward from a version Apple is holding.
///
/// The app knew the state and refused the apply, and that was the whole of it.
/// A developer who met it had two real questions and no way to ask either
/// inside the app: what did I actually send, and how do I start the next one?
@MainActor
@Suite(.serialized) struct ReviewChoiceTests {

    private func workspace(versionState: String?) throws -> (state: AppState, folder: URL) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("review-choice-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(ManifestFile.defaultName)
        var manifest = Manifest()
        manifest.setAppleApp(appID: "1", bundleID: "com.example.app")
        try ManifestFile.save(manifest, to: url)
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        try state.load(from: url)
        var actual = ActualState()
        var apple = ActualState.Apple()
        apple.versionId = "v1"
        apple.versionString = "3.2.0"
        apple.versionState = versionState
        actual.apple = apple
        state.actualState = actual
        return (state, folder)
    }

    // MARK: - When the question is asked at all

    @Test func theQuestionIsAskedOnlyWhileAppleHoldsTheVersion() throws {
        let (waiting, one) = try workspace(versionState: "WAITING_FOR_REVIEW")
        defer { try? FileManager.default.removeItem(at: one) }
        #expect(waiting.reviewNeedsAChoice)

        let (draft, two) = try workspace(versionState: "PREPARE_FOR_SUBMISSION")
        defer { try? FileManager.default.removeItem(at: two) }
        #expect(!draft.reviewNeedsAChoice)
    }

    /// The choice belongs to one version. The next one asks again, because
    /// "I looked at 3.2.0" says nothing about 3.3.0.
    @Test func theChoiceIsRememberedPerVersion() throws {
        let (state, folder) = try workspace(versionState: "WAITING_FOR_REVIEW")
        defer { try? FileManager.default.removeItem(at: folder) }

        state.chooseReviewPath(.inspect)
        #expect(state.reviewPath == .inspect)
        #expect(!state.reviewNeedsAChoice)

        state.actualState.apple?.versionString = "3.3.0"
        #expect(state.reviewPath == nil)
        #expect(state.reviewNeedsAChoice)
    }

    // MARK: - Looking at what was sent

    /// Inspecting locks the listing. Apple holds it, so a box that took
    /// characters would be a box whose characters can never be sent.
    @Test func inspectingLocksEveryFieldApplePinned() throws {
        let (state, folder) = try workspace(versionState: "IN_REVIEW")
        defer { try? FileManager.default.removeItem(at: folder) }

        state.chooseReviewPath(.inspect)

        #expect(state.isListingLocked(.name))
        #expect(state.isListingLocked(.description))
        // Apple takes this one on a version it is already reviewing.
        #expect(!state.isListingLocked(.promotionalText))
    }

    /// Starting the next version unlocks everything, because the writes then
    /// land on a version the developer owns and not on the one under review.
    @Test func startingTheNextVersionUnlocksTheListing() throws {
        let (state, folder) = try workspace(versionState: "IN_REVIEW")
        defer { try? FileManager.default.removeItem(at: folder) }

        state.chooseReviewPath(.next)

        #expect(!state.isListingLocked(.name))
        #expect(!state.isListingLocked(.description))
    }

    /// Nothing is locked before the question is answered, and nothing is
    /// locked on a version nobody has sent.
    @Test func anUnaskedOrUnsentVersionLocksNothing() throws {
        let (waiting, one) = try workspace(versionState: "WAITING_FOR_REVIEW")
        defer { try? FileManager.default.removeItem(at: one) }
        #expect(!waiting.isListingLocked(.name))

        let (draft, two) = try workspace(versionState: "PREPARE_FOR_SUBMISSION")
        defer { try? FileManager.default.removeItem(at: two) }
        draft.chooseReviewPath(.inspect)
        #expect(!draft.isListingLocked(.name))
    }

    // MARK: - What Apple answered

    @Test func theOutcomeBannerNamesTheAnswerAndNeverInventsAReason() throws {
        let (approved, one) = try workspace(versionState: "PENDING_DEVELOPER_RELEASE")
        defer { try? FileManager.default.removeItem(at: one) }
        #expect(approved.reviewOutcome?.outcome == .approved)

        let (refused, two) = try workspace(versionState: "METADATA_REJECTED")
        defer { try? FileManager.default.removeItem(at: two) }
        let answer = try #require(refused.reviewOutcome)
        #expect(answer.outcome == .refused)
        #expect(answer.line.contains("the metadata"))
        // The sentence Apple wrote is in no endpoint, so the app sends the
        // developer to the one place that has it.
        #expect(answer.line.contains("App Store Connect"))
    }

    @Test func aWithdrawnVersionIsNoAnswerFromApple() throws {
        let (state, folder) = try workspace(versionState: "DEVELOPER_REJECTED")
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(state.reviewOutcome == nil)
    }
}
