import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// The Build tab used to open on nothing.
///
/// `resetRunState` empties `actualState` every time an app is opened or
/// switched, so the live version, the next free version and the highest build
/// number were all absent until the developer found "Fetch from store" in the
/// header and agreed to a confirmation warning about overwriting their work.
/// The one fact a developer opens this tab to learn was the one thing the tab
/// would not tell them without being asked.
///
/// Two halves. The version the store holds fills a box the file leaves empty,
/// and it never touches a box the developer has answered.
@Suite(.serialized)
@MainActor
struct BuildTabOpensReadyTests {

    private func folder() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ss-build-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// An app whose App Store record is already read.
    private func state(_ root: URL, draft: String?, live: String?) -> AppState {
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        state.manifestURL = root.appendingPathComponent("store.yaml")
        state.manifest.setStore(.apple, enabled: true)
        state.manifest.setAppleApp(appID: "1234567890", bundleID: "com.example.app",
                                   platforms: [.ios])
        state.syncStoreFieldsFromManifest()
        var apple = ActualState.Apple()
        apple.versionString = draft
        apple.liveVersionString = live
        state.actualState.apple = apple
        return state
    }

    @Test func theStoreVersionFillsAnEmptyBox() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = state(root, draft: "2.1", live: "2.0")

        #expect(state.manifest.versionName(for: .apple) == nil)
        state.adoptStoreVersionWhereEmpty()
        #expect(state.manifest.versionName(for: .apple) == "2.1")
    }

    /// A live app with no draft version yet. The store holds nothing to write
    /// to, so the smallest number that clears what is on sale is the answer —
    /// the same one the "Use 2.1" button offers.
    @Test func aLiveAppWithNoDraftTakesTheNextNumber() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = state(root, draft: nil, live: "2.0")

        state.adoptStoreVersionWhereEmpty()
        #expect(state.manifest.versionName(for: .apple) == state.nextAppleVersion)
        #expect(state.manifest.versionName(for: .apple) == "2.0.1")
    }

    @Test func aVersionTheDeveloperWroteIsNeverTouched() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = state(root, draft: "2.1", live: "2.0")
        state.manifest.setReleaseVersionName("3.0")

        state.adoptStoreVersionWhereEmpty()
        #expect(state.manifest.versionName(for: .apple) == "3.0")
    }

    /// Nothing is invented. A store that answered with no version at all
    /// leaves the box for the developer, exactly as before.
    @Test func aStoreWithNoAnswerWritesNothing() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = state(root, draft: nil, live: nil)

        state.adoptStoreVersionWhereEmpty()
        #expect(state.manifest.versionName(for: .apple) == nil)
    }

    /// No key, no read. A store with no credential answers with a failure, and
    /// a failure nobody asked for is a red line on a tab that has not been
    /// used yet.
    @Test func theTabAsksNothingWithoutACredential() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = state(root, draft: "2.1", live: "2.0")
        #expect(!state.hasCredential(for: .apple))

        await state.fetchBuildTabFromStore()
        #expect(state.plan == nil)
        #expect(state.planReadFailures.isEmpty)
        #expect(state.manifest.versionName(for: .apple) == nil)
        // And it did not mark the app as asked, so the read still happens on
        // the visit after the key arrives.
        #expect(!state.buildTabAskedTheStores)
    }

    /// Once per app, not once per visit.
    ///
    /// Every edit calls `invalidatePlan`, so a guard on `plan == nil` would
    /// send a fresh read of both stores each time a developer edited a field
    /// and came back to Build. Opening the app again is what asks again.
    @Test func theReadHappensOncePerAppAndNotPerVisit() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = state(root, draft: "2.1", live: "2.0")

        state.buildTabAskedTheStores = true
        state.invalidatePlan()
        #expect(state.plan == nil)
        // The plan is gone and the app is still marked as asked, so returning
        // to the tab reads nothing.
        #expect(state.buildTabAskedTheStores)

        // Opening an app clears it, and `resetRunState` is what every door
        // runs on the way in.
        state.resetRunState()
        #expect(!state.buildTabAskedTheStores)
    }

    /// One key is enough. The guard used to be `allSatisfy`, so an app that
    /// goes to both stores with only the App Store key connected opened on
    /// nothing at all.
    @Test func oneConnectedStoreIsEnoughToRead() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = state(root, draft: "2.1", live: "2.0")
        state.manifest.setStore(.google, enabled: true)
        state.manifest.setGoogleApp(packageName: "com.example.app")
        state.syncStoreFieldsFromManifest()
        state.applePrivateKeyPEM = "-----BEGIN PRIVATE KEY-----"

        #expect(state.stores == [.apple, .google])
        #expect(state.connectedStores == [.apple])
    }

    /// And the store nobody asked about says nothing. It answers every read
    /// with an authorization failure, and the identity row above already says
    /// it is not connected.
    @Test func anUnconnectedStoreReportsNoFailure() {
        let read = ["App Store: the key was refused",
                    "Google Play: the caller has no permission",
                    "Provider: the token expired"]

        let quiet = AppState.failures(read, hiding: [.google])
        #expect(quiet == ["App Store: the key was refused", "Provider: the token expired"])

        // A deliberate fetch hides nothing.
        #expect(AppState.failures(read, hiding: []) == read)
    }

    /// The advanced switch is the developer's standing answer, so it outlives
    /// the launch that set it.
    @Test func theAdvancedSwitchSurvivesALaunch() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let account = "test-\(UUID().uuidString)"
        let first = AppState(defaults: defaults, storeAccount: account)
        #expect(!first.showsAdvancedBuildOptions)
        first.showsAdvancedBuildOptions = true

        let second = AppState(defaults: defaults, storeAccount: account)
        #expect(second.showsAdvancedBuildOptions)
    }
}
