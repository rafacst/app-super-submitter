import Foundation
import Testing
@testable import SubmitKit

// MARK: - The state machine

@Test func theHappyPathIsTheOnlyForwardPath() {
    let path: [UploadState] = [
        .unlinked, .discovering, .preflight, .readyToBuild, .building,
        .inspectingArtifact, .needsUploadConfirmation, .uploading,
        .processingOrValidating, .complete,
    ]
    for (index, state) in path.dropLast().enumerated() {
        #expect(state.canMove(to: path[index + 1]),
                "\(state.rawValue) must reach \(path[index + 1].rawValue)")
    }
}

@Test func aBuildCanNeverSkipTheArtifactInspection() {
    #expect(!UploadState.building.canMove(to: .uploading))
    #expect(!UploadState.building.canMove(to: .needsUploadConfirmation))
    #expect(!UploadState.readyToBuild.canMove(to: .uploading))
    #expect(UploadState.building.canMove(to: .inspectingArtifact))
}

@Test func anUploadNeverStartsWithoutAConfirmation() {
    for state in UploadState.allCases where state.canMove(to: .uploading) {
        #expect([.needsUploadConfirmation, .recoveryRequired, .failed].contains(state),
                "\(state.rawValue) must not start an upload")
    }
}

@Test func anyStateMayFailAndOnlyActiveWorkMayCancel() {
    for state in UploadState.allCases {
        #expect(state.canMove(to: .failed))
        #expect(state.canMove(to: .cancelling) == state.isActive)
    }
}

@Test func anUncertainRemoteResultEntersRecoveryAndNotFailure() {
    #expect(UploadState.uploading.canMove(to: .recoveryRequired))
    #expect(UploadState.processingOrValidating.canMove(to: .recoveryRequired))
    // A local phase has nothing remote to reconcile.
    #expect(!UploadState.building.canMove(to: .recoveryRequired))
    #expect(!UploadState.preflight.canMove(to: .recoveryRequired))
}

@Test func anIllegalMoveIsRefusedInsteadOfApplied() {
    var run = UploadRun(platform: .ios)
    let legal = run.move(to: .discovering)
    let illegal = run.move(to: .uploading)
    #expect(legal)
    #expect(!illegal)
    #expect(run.state == .discovering)
}

@Test func aTerminalStateStampsTheFinishTime() {
    var run = UploadRun(platform: .android)
    run.move(to: .discovering)
    run.move(to: .failed)
    #expect(run.finishedAt != nil)
    #expect(run.state.isTerminal)
}

// MARK: - Run identity

@Test func theLogicalIdentityHoldsEveryDistinguishingField() {
    let candidate = BuildCandidate(
        platform: .ios, productName: "Example", productIdentifier: "com.example.app",
        marketingVersion: "1.2.0", buildVersion: "42", artifactPath: "/tmp/a.xcarchive",
        artifactSize: 10, sha256: "abc")

    #expect(candidate.logicalIdentity == "ios+com.example.app+1.2.0+42+abc")
}

// MARK: - Mismatches

@Test func onlyAnIdentityOrSignatureDifferenceBlocksAnUpload() {
    var candidate = BuildCandidate(
        platform: .ios, productName: "Example", productIdentifier: "com.example.app",
        marketingVersion: "1.2.0", buildVersion: "42", artifactPath: "/tmp/a",
        artifactSize: 1, sha256: "x")
    candidate.mismatches = [
        .init(field: "Build number", expected: "41", actual: "42", blocksUpload: false),
        .init(field: "Bundle identifier", expected: "com.example.app",
              actual: "com.other.app", blocksUpload: true),
    ]

    #expect(candidate.blockingMismatches.count == 1)
    #expect(candidate.blockingMismatches[0].field == "Bundle identifier")
}

// MARK: - Polling

@Test func thePollBacksOffWithJitterAndNeverExceedsTheCap() {
    var previous = 0.0
    for attempt in 1...12 {
        let delay = UploadService.pollDelay(attempt: attempt)
        #expect(delay > 0)
        #expect(delay <= 360)
        if attempt < 9 { #expect(delay >= previous * 0.7) }
        previous = delay
    }
    #expect(UploadService.pollDelay(attempt: 1) < 20)
}

// MARK: - The error taxonomy

@Test func anAmbiguousResultAsksForReconciliationAndOthersDoNot() {
    #expect(BuildErrorCategory.remoteAmbiguous.needsReconciliation)
    #expect(BuildErrorCategory.cleanup.needsReconciliation)
    #expect(!BuildErrorCategory.build.needsReconciliation)
    #expect(!BuildErrorCategory.signing.needsReconciliation)
}

@Test func theCopiedDiagnosticIsRedactedAndNamesWhatWasRetained() {
    let failure = BuildFailure(
        category: .upload, stage: "Upload",
        message: "The upload failed.",
        diagnostics: "Authorization: Bearer eyJhbGciOiJI\nKEYSTORE_PASSWORD=hunter2000",
        recovery: "Try again.",
        retainedArtifact: "/tmp/App.xcarchive",
        retainedRemoteEdit: "edit-123")

    let report = failure.report()
    #expect(!report.contains("eyJhbGciOiJI"))
    #expect(!report.contains("hunter2000"))
    #expect(report.contains("/tmp/App.xcarchive"))
    #expect(report.contains("edit-123"))
    #expect(report.contains("Try again."))
}
