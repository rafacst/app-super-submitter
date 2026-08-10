import CryptoKit
import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// Nothing leaves this machine while Apple holds a version.
///
/// The apply already refused, and it was the only door that did. A binary
/// could still be uploaded and a release could still be sent, so the one
/// state App Store Connect refuses outright was reachable from two other
/// screens. Editing stays open the whole time: a draft in `store.yaml` reaches
/// no store, and the wait is exactly when the next version gets written.
@MainActor
@Suite(.serialized) struct SendWhileInReviewTests {

    private func workspace(versionState: String?) throws -> (state: AppState, folder: URL) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("in-review-\(UUID().uuidString)")
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

    // MARK: - The artifact

    @Test func noBinaryGoesUpWhileAppleHoldsTheVersion() throws {
        let (state, folder) = try workspace(versionState: "WAITING_FOR_REVIEW")
        defer { try? FileManager.default.removeItem(at: folder) }

        let flow = BuildFlow(app: state)
        flow.run.platform = .ios
        #expect(flow.uploadBlockedByReview != nil)
    }

    /// A version the developer may still write to blocks nothing.
    @Test func aVersionInPreparationBlocksNoUpload() throws {
        let (state, folder) = try workspace(versionState: "PREPARE_FOR_SUBMISSION")
        defer { try? FileManager.default.removeItem(at: folder) }

        let flow = BuildFlow(app: state)
        flow.run.platform = .ios
        #expect(flow.uploadBlockedByReview == nil)
    }

    /// Google runs its own queue and Apple's review says nothing about it.
    @Test func anAndroidBundleIsNotHeldByApplesQueue() throws {
        let (state, folder) = try workspace(versionState: "IN_REVIEW")
        defer { try? FileManager.default.removeItem(at: folder) }

        let flow = BuildFlow(app: state)
        flow.run.platform = .android
        #expect(flow.uploadBlockedByReview == nil)
    }

    // MARK: - The release

    @Test func noReleaseIsSentWhileAppleHoldsTheVersion() throws {
        let (state, folder) = try workspace(versionState: "IN_REVIEW")
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(state.sendBlockedByReview(.apple) != nil)
        #expect(state.sendBlockedByReview(.google) == nil)
    }

    /// The one case that is a release and not a submission. Apple has already
    /// approved it and is waiting for the developer to press go, so holding
    /// this back would strand an approved version.
    @Test func anApprovedVersionWaitingOnTheDeveloperStillGoes() throws {
        let (state, folder) = try workspace(versionState: "PENDING_DEVELOPER_RELEASE")
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(state.sendBlockedByReview(.apple) == nil)
    }

    // MARK: - The draft

    /// The whole point of the wait: the next version gets written during it.
    @Test func theManifestStillSavesWhileAppleHoldsTheVersion() throws {
        let (state, folder) = try workspace(versionState: "WAITING_FOR_REVIEW")
        defer { try? FileManager.default.removeItem(at: folder) }

        state.listingBinding(.name, locale: "en-US").wrappedValue = "Fast Bill Split"
        state.flushSave()

        let reloaded = try ManifestFile.load(from: folder
            .appendingPathComponent(ManifestFile.defaultName))
        #expect(reloaded.listingText(locale: "en-US", field: .name) == "Fast Bill Split")
    }
}
