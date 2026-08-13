import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// The delete of a draft version belongs to the read, not to a run.
///
/// It stood under the run section, so a developer with a draft already in App
/// Store Connect had to send writes they did not want in order to be offered
/// the way out of it. The read is what finds the draft, and every failure on
/// the path lands in `releaseError`, which no screen on that tab printed: a
/// refused delete looked exactly like one that worked.
@MainActor
@Suite(.serialized) struct DeleteDraftFromSummaryTests {

    private func workspace() throws -> (state: AppState, folder: URL) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("draft-delete-\(UUID().uuidString)")
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
        apple.versionId = "ver-1"
        apple.versionString = "1.4.1"
        apple.versionState = "PREPARE_FOR_SUBMISSION"
        actual.apple = apple
        state.actualState = actual
        return (state, folder)
    }

    /// A read is enough. Nothing has to be applied first.
    @Test func aReadAloneOffersTheDelete() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(!state.showsRun)
        #expect(state.deletableAppleVersion?.id == "ver-1")
        #expect(state.deletableAppleVersion?.number == "1.4.1")
    }

    /// The run is writing to this very version. Taking it out from under a
    /// request in flight leaves half a listing behind.
    @Test func aRunInFlightRefusesTheDelete() async throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }

        state.runIndex = 0
        #expect(state.isRunning)
        await state.deleteAppleDraftVersion()
        // It never started, so it never reached the store and never failed.
        #expect(state.releasing == nil)
        #expect(state.releaseError == nil)
    }

    /// The panel moved to the Summary, and the run section no longer carries a
    /// copy of it.
    @Test func thePanelStandsOnTheSummary() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        func source(_ path: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        }
        let tab = try source("Sources/SuperSubmitter/Tabs/PlanTab.swift")
        let run = try source("Sources/SuperSubmitter/Tabs/RunSection.swift")

        #expect(tab.contains("deleteDraftPanel"))
        #expect(tab.contains("await state.deleteAppleDraftVersion()"))
        #expect(!run.contains("deleteAppleDraftVersion"))
        // One printer for the store's answer, and one only. Two panels reading
        // the same field printed the same sentence twice.
        #expect(tab.components(separatedBy: "state.releaseError").count - 1 == 1)
    }

    /// The delete says whether it worked, and the panel says it is working.
    @Test func theOutcomeIsCheckedAndTheWaitIsShown() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let run = try String(
            contentsOf: root.appendingPathComponent("Sources/SuperSubmitter/AppStateRun.swift"),
            encoding: .utf8)
        let tab = try String(
            contentsOf: root.appendingPathComponent("Sources/SuperSubmitter/Tabs/PlanTab.swift"),
            encoding: .utf8)

        // The read after the delete is compared, not assumed.
        #expect(run.contains("if actualState.apple?.versionId == version.id"))
        // And the panel says the call is with Apple while it is.
        #expect(tab.contains("let busy = state.releasing == .apple"))
        #expect(tab.contains("if busy {"))
    }

    /// A read is the developer asking what the store holds now, so an error
    /// about a call that is over does not survive it.
    @Test func aReadClearsTheLastStoreFailure() async throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }

        state.releaseError = "App Store: something failed a while ago."
        await state.readStores()
        #expect(state.releaseError == nil)
    }
}
