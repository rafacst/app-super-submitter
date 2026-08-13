import Foundation
import Testing
@testable import SubmitKit

/// A version that is already with Apple.
///
/// The app knew this state and did one thing with it: it refused the apply and
/// said so twice. A developer meeting that had no way forward inside the app.
/// There are two ways forward, and which one is right depends on what they
/// want: look at what was sent, or start the version after it.
@Suite struct VersionInReviewTests {

    // MARK: - The vocabulary

    /// Apple's own words, sorted once, because six files had their own list and
    /// one of them disagreed.
    @Test func aVersionWithApplePermitsNoWrite() {
        for state in ["WAITING_FOR_REVIEW", "IN_REVIEW", "WAITING_FOR_EXPORT_COMPLIANCE"] {
            #expect(AppleVersionState.withApple.contains(state))
            #expect(!AppleVersionState.editable.contains(state))
        }
        #expect(AppleVersionState.editable.contains("READY_FOR_REVIEW"))
        #expect(!AppleVersionState.withApple.contains("READY_FOR_REVIEW"))
    }

    /// Apple answered. The two answers are not the same event and the app may
    /// not report one as the other.
    @Test func appleSaysYesOrNoInItsOwnWords() {
        #expect(AppleVersionState.outcome(of: "READY_FOR_DISTRIBUTION") == .approved)
        #expect(AppleVersionState.outcome(of: "PENDING_DEVELOPER_RELEASE") == .approved)
        #expect(AppleVersionState.outcome(of: "REJECTED") == .refused)
        #expect(AppleVersionState.outcome(of: "METADATA_REJECTED") == .refused)
        #expect(AppleVersionState.outcome(of: "INVALID_BINARY") == .refused)
        #expect(AppleVersionState.outcome(of: "IN_REVIEW") == .waiting)
        #expect(AppleVersionState.outcome(of: "READY_FOR_REVIEW") == nil)
        #expect(AppleVersionState.outcome(of: "PREPARE_FOR_SUBMISSION") == nil)
    }

    /// The developer withdrew it. That is not Apple refusing it, and calling it
    /// a refusal sends somebody looking for a reason nobody wrote.
    @Test func aWithdrawalIsNotARefusal() {
        #expect(AppleVersionState.outcome(of: "DEVELOPER_REJECTED") == nil)
        #expect(AppleVersionState.editable.contains("DEVELOPER_REJECTED"))
    }

    /// What kind of refusal it was, which is as far as the API goes. The
    /// sentence Apple wrote lives in the Resolution Center and in no endpoint.
    @Test func theKindOfRefusalIsKnownAndTheReasonIsNot() {
        #expect(AppleVersionState.refusalKind("METADATA_REJECTED") == "the metadata")
        #expect(AppleVersionState.refusalKind("INVALID_BINARY") == "the binary")
        #expect(AppleVersionState.refusalKind("REJECTED") == "the submission")
        #expect(AppleVersionState.refusalKind("IN_REVIEW") == nil)
    }

    // MARK: - What is locked while Apple holds it

    /// Store policy, not the schema. Apple takes a promotional text change on
    /// a version it is already reviewing, and nothing else on the listing.
    @Test func onlyThePromotionalTextSurvivesTheLock() {
        #expect(!AppleVersionState.isLocked(.promotionalText))
        for field in [ListingTextField.name, .subtitle, .description, .whatsNew,
                      .keywords, .supportURL, .marketingURL] {
            #expect(AppleVersionState.isLocked(field), "\(field) has to be locked")
        }
    }
}
