import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// The app offered a version the App Store had already published.
///
/// `store.yaml` named 1.6, the project built 1.7, and the Build card offered
/// "Build version 1.6 instead" over an app whose customers were reading 1.6.
/// Apple takes no version that does not climb, so the offer was a whole archive
/// spent to be refused.
///
/// Two halves. The number the app suggests is the live one with its patch
/// component raised, and the card stops offering anything at or below what is
/// on sale, whether or not the project and the manifest agree.
@Suite(.serialized)
@MainActor
struct LiveVersionSuggestionTests {

    private func folder() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ss-live-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func state(_ root: URL) -> AppState {
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)",
                             buildStorage: BuildStorage(
                                root: root.appendingPathComponent("Storage")))
        state.manifestURL = root.appendingPathComponent("store.yaml")
        return state
    }

    /// An app live at `live`, whose project builds `building`.
    private func card(root: URL, live: String, building: String,
                      manifest: String?) -> (BuildFlow, AppState) {
        let state = state(root)
        var apple = ActualState.Apple()
        apple.liveVersionString = live
        state.actualState.apple = apple
        state.manifest.setAppleApp(appID: "1234567890", bundleID: "com.example.app",
                                   platforms: [.macOS])
        if let manifest { state.manifest.setReleaseVersionName(manifest) }
        let flow = state.buildFlow
        flow.run = UploadRun(platform: .macos, linkedProjectID: UUID(), state: .readyToBuild)
        flow.snapshot.marketingVersion = building
        return (flow, state)
    }

    // MARK: - The number itself

    @Test(arguments: [("1.6", "1.6.1"), ("1.6.1", "1.6.2"), ("2.0.9", "2.0.10"),
                      ("1", "1.0.1"), ("1.6.1.3", "1.6.2")])
    func theSuggestionRaisesTheThirdComponent(live: String, next: String) {
        #expect(Validator.nextVersion(above: live) == next)
    }

    /// Whatever it answers has to clear the number it was given, or the whole
    /// point of it is gone.
    @Test(arguments: ["1", "1.6", "1.6.1", "2.0.9", "10.4.11", "1.6.1.3"])
    func everySuggestionClearsTheLiveVersion(live: String) throws {
        let next = try #require(Validator.nextVersion(above: live))
        #expect(Validator.isVersion(next, above: live),
                "\(next) does not climb past \(live)")
    }

    /// The Build tab's own offer moves the patch component too. It raised the
    /// last one, so a live 1.6 was answered with 1.7: a feature number offered
    /// for what is usually a fix.
    @Test func theBuildTabOffersThePatchAndNotTheMinor() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = state(root)
        var apple = ActualState.Apple()
        apple.liveVersionString = "1.6"
        state.actualState.apple = apple

        #expect(state.nextAppleVersion == "1.6.1")
    }

    // MARK: - The card

    /// The reported bug, in full.
    @Test func aVersionAlreadyOnSaleIsNeverOffered() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let (flow, _) = card(root: root, live: "1.6", building: "1.7", manifest: "1.6")

        #expect(flow.versionAlreadyLive == "1.6")
        #expect(flow.versionAboveLive == "1.6.1")
    }

    /// The quieter half: the project and `store.yaml` agree on 1.6, so nothing
    /// disagrees and the old card said nothing at all. The upload is refused
    /// just the same.
    @Test func twoNumbersThatAgreeAreStillCaught() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let (flow, _) = card(root: root, live: "1.6", building: "1.6", manifest: "1.6")

        #expect(flow.versionFromManifest == nil, "nothing disagrees here")
        #expect(flow.versionAlreadyLive == "1.6")
        #expect(flow.versionAboveLive == "1.6.1")
    }

    /// A version above the live one is the usual state and says nothing.
    @Test func aVersionAboveTheLiveOneIsLeftAlone() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let (flow, _) = card(root: root, live: "1.6", building: "1.7", manifest: "1.7")

        #expect(flow.versionAlreadyLive == nil)
    }

    /// No read, no judgement. The store read fails often enough to matter, and
    /// it had failed on the card that reported this.
    @Test func anUnknownLiveVersionJudgesNothing() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = state(root)
        state.manifest.setReleaseVersionName("1.6")
        let flow = state.buildFlow
        flow.run = UploadRun(platform: .macos, linkedProjectID: UUID(), state: .readyToBuild)
        flow.snapshot.marketingVersion = "1.7"

        #expect(state.liveAppleVersion == nil)
        #expect(flow.versionAlreadyLive == nil)
    }

    /// Taking the offer settles both numbers. Either alone leaves `store.yaml`
    /// and the archive disagreeing, which is the other way this upload is
    /// refused, so a button that fixed one would have moved the developer from
    /// one refusal to the next.
    @Test func takingTheOfferSetsTheReleaseAndTheBuild() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let (flow, state) = card(root: root, live: "1.6", building: "1.7", manifest: "1.6")
        flow.project = LinkedSourceProject(
            platform: .macos, rootPath: root.path,
            containerPath: root.appendingPathComponent("App.xcodeproj").path,
            containerKind: .project,
            manifestPath: root.appendingPathComponent("store.yaml").path)

        flow.useVersionAboveLive()

        #expect(state.manifest.versionName(for: .apple) == "1.6.1")
        #expect(flow.project?.selection.marketingVersionOverride == "1.6.1")
        flow.task?.cancel()
    }

    /// Google Play numbers by version code and takes a repeated name, so the
    /// App Store's live version decides nothing there.
    @Test func androidIsNotJudgedByTheAppleVersion() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let (flow, _) = card(root: root, live: "1.6", building: "1.6", manifest: "1.6")
        flow.run = UploadRun(platform: .android, linkedProjectID: UUID(), state: .readyToBuild)

        #expect(flow.versionAlreadyLive == nil)
    }
}
