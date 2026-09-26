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

/// Keep the artifact and stop ends the run from the upload question. The move
/// was refused in silence, so the button did nothing.
@Test func keepingTheArtifactEndsTheRunFromTheUploadQuestion() {
    var run = UploadRun(platform: .ios, state: .needsUploadConfirmation)
    let kept = run.move(to: .complete)
    #expect(kept)
    #expect(run.state == .complete)
    #expect(run.finishedAt != nil)
}

/// The check right before the send found a conflict, and nothing was sent. The
/// run goes back to the question; it stayed on "Upload" with a spinner.
@Test func aConflictFoundBeforeTheSendReturnsToTheQuestion() {
    var run = UploadRun(platform: .ios, state: .needsUploadConfirmation)
    let sending = run.move(to: .uploading)
    let back = run.move(to: .needsUploadConfirmation)
    #expect(sending)
    #expect(back)
    #expect(!run.state.isActive)
}

/// A cancel that arrived after Google committed the bundle ends complete. It
/// stayed `cancelling`, which is active, so the app read as busy for good.
@Test func aLateCancelThatFoundTheUploadOnTheStoreEndsComplete() {
    var run = UploadRun(platform: .android, state: .uploading)
    let cancelling = run.move(to: .cancelling)
    let landed = run.move(to: .complete)
    #expect(cancelling)
    #expect(landed)
    #expect(!run.state.isActive)
}

// MARK: - A relaunch

/// A poll after a relaunch has the run and not the artifact, so the run names
/// the build it sent. **Resume checking** did nothing there before.
@Test func aRunNamesTheBuildItSentForAPollAfterARelaunch() {
    var run = UploadRun(platform: .macos)
    #expect(run.sentVersions?.build == nil)

    run.sentMarketingVersion = "1.6"
    run.sentBuildVersion = "215"
    #expect(run.sentVersions?.marketing == "1.6")
    #expect(run.sentVersions?.build == "215")
}

/// A record saved before the two fields existed still answers, out of the
/// identity it has always carried.
@Test func anOlderRecordReadsItsBuildOutOfTheIdentity() {
    var run = UploadRun(platform: .ios)
    run.candidateIdentity = "ios+com.example.app+1.2.0+42+abc"
    #expect(run.sentVersions?.marketing == "1.2.0")
    #expect(run.sentVersions?.build == "42")

    run.candidateIdentity = "ios+com.example.app++42+abc"
    #expect(run.sentVersions?.build == nil)
}

/// A run the developer stopped tracking stays on disk and stops coming back.
@Test func aRunSetAsideIsNoLongerResumed() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("set-aside-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = BuildStorage(root: root)

    var waiting = UploadRun(platform: .ios, state: .recoveryRequired)
    try storage.save(waiting)
    #expect(storage.unfinishedRuns().map(\.id) == [waiting.id])

    waiting.setAsideAt = Date()
    try storage.save(waiting)
    #expect(storage.unfinishedRuns().isEmpty)
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

@Test func theNextBuildDoesNotInheritTheLastOnesFinishTime() {
    var run = UploadRun(platform: .android)
    run.move(to: .discovering)
    run.move(to: .failed)
    // The same run is reused for the next build. A finish left over from the
    // last one made the Build tab read the new build as already over, and the
    // elapsed time sat at 0:00 for as long as it ran.
    run.moveToPreflight()
    #expect(run.finishedAt == nil)
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

@Test func everyDynamicDiagnosticFieldIsRedacted() {
    let secret = "SUPERSECRETVALUE12345"
    let failure = BuildFailure(
        category: .upload,
        stage: "Upload \(secret)",
        message: "Message \(secret)",
        underlying: "Underlying \(secret)",
        diagnostics: "Diagnostics \(secret)",
        recovery: "Recovery \(secret)",
        retainedArtifact: "/tmp/\(secret).xcarchive",
        retainedRemoteEdit: "edit-\(secret)")

    let report = failure.report(redactor: Redactor(literals: [secret]))

    #expect(!report.contains(secret))
    #expect(report.contains("«redacted»"))
}
