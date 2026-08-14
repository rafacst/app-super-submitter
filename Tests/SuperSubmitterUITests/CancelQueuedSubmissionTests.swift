import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// The Summary offers the cancel exactly where the cancel works.
///
/// The apply is held while Apple has an open submission, and the developer
/// standing on the tab is the only person who can end it. The button therefore
/// takes the Apply slot, and it takes it for one state: the queue. Apple
/// refuses a cancel from the moment a reviewer opens the submission, so the
/// same button on `IN_REVIEW` is a button built to be refused.
@MainActor
@Suite(.serialized) struct CancelQueuedSubmissionTests {

    private func workspace() throws -> (state: AppState, folder: URL) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("queued-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(ManifestFile.defaultName)
        var manifest = Manifest()
        manifest.setAppleApp(appID: "1", bundleID: "com.example.app")
        try ManifestFile.save(manifest, to: url)
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        try state.load(from: url)
        return (state, folder)
    }

    private func read(_ state: AppState, submission: String?, version: String?) {
        var actual = ActualState()
        var apple = ActualState.Apple()
        apple.versionId = "v1"
        apple.versionString = "1.5"
        apple.versionState = version
        apple.openReviewSubmission = submission
        actual.apple = apple
        state.actualState = actual
    }

    /// The case the tab was built for. The version being written is a draft,
    /// and the submission holding the apply back is the previous version's, so
    /// the version state answers nothing about it.
    @Test func aDraftWithAQueuedSubmissionOffersTheCancel() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }

        read(state, submission: "WAITING_FOR_REVIEW", version: "PREPARE_FOR_SUBMISSION")
        #expect(state.appleSubmissionInQueue)
    }

    /// A reviewer has it. Apple takes no cancel now, and the button says so by
    /// not being there.
    @Test func aSubmissionUnderReviewOffersNothing() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }

        read(state, submission: "IN_REVIEW", version: "IN_REVIEW")
        #expect(!state.appleSubmissionInQueue)
    }

    @Test func anAppWithNoOpenSubmissionOffersNothing() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }

        read(state, submission: nil, version: "PREPARE_FOR_SUBMISSION")
        #expect(!state.appleSubmissionInQueue)
        #expect(state.actualState.apple?.hasOpenReviewSubmission == false)
    }

    /// Apple's queue says nothing about a Google Play app, and the Summary of
    /// one must never trade its apply for a cancel.
    @Test func aPlayOnlyAppKeepsItsApply() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }

        read(state, submission: "WAITING_FOR_REVIEW", version: nil)
        state.manifest.apps.apple = nil
        #expect(!state.appleSubmissionInQueue)
    }

    /// The read keeps which submission is open, and not only that one is.
    @Test func theReaderKeepsTheSubmissionState() {
        var apple = ActualState.Apple()
        apple.openReviewSubmission = "UNRESOLVED_ISSUES"
        #expect(apple.hasOpenReviewSubmission)
    }

    /// Two questions before anything reaches Apple, and the second one names
    /// what cannot be undone.
    @Test func theCancelAsksTwice() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let tab = try String(
            contentsOf: root.appendingPathComponent("Sources/SuperSubmitter/Tabs/PlanTab.swift"),
            encoding: .utf8)

        let first = try #require(tab.range(of: "isPresented: $askingCancel"))
        let second = try #require(tab.range(of: "isPresented: $confirmingCancel"))
        #expect(first.lowerBound < second.lowerBound)
        // The first question opens the second, and only the second acts.
        #expect(tab.contains("Button(\"Continue\") { confirmingCancel = true }"))
        #expect(tab.contains("await state.cancelReviewQueueSubmission()"))
        #expect(tab.contains("This cannot be undone. Cancel the submission?"))
    }
}
