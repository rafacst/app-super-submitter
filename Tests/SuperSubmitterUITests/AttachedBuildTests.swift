import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// Which build the tabs attach to, and when a store write is held back.
///
/// The rule this guards: a store write attaches its changes to a build, so an
/// app with no build named in `store.yaml` (and none built this session) keeps
/// every change on this Mac. The implicit "highest processed build" is not an
/// attachment; the developer has to name one. See `AppState.attachedBuild(for:)`.

@MainActor
private func appleApp() throws -> (state: AppState, folder: URL) {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("attach-\(UUID().uuidString)")
    let app = folder.appendingPathComponent("app")
    try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
    var manifest = Manifest()
    manifest.setAppleApp(appID: "100000000", bundleID: "com.example.app")
    let url = app.appendingPathComponent("store.yaml")
    try ManifestFile.save(manifest, to: url)
    let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                         storeAccount: "attach-\(UUID().uuidString)")
    state.link(manifestAt: url)
    state.selectApp(at: 0)
    return (state, folder)
}

@MainActor
@Test func noBuildLeavesChangesLocal() throws {
    let (state, folder) = try appleApp()
    defer { try? FileManager.default.removeItem(at: folder) }

    #expect(state.buildAttachApplies)
    #expect(!state.hasAttachedBuild(for: .apple))
    #expect(state.attachedBuild(for: .apple) == nil)
    #expect(state.storesMissingBuild == [.apple])
}

@MainActor
@Test func aChosenStoreBuildIsAttached() throws {
    let (state, folder) = try appleApp()
    defer { try? FileManager.default.removeItem(at: folder) }

    state.manifest.release = Manifest.Release(
        apple: Manifest.Release.AppleRelease(buildNumber: "42"))

    #expect(state.hasAttachedBuild(for: .apple))
    #expect(state.attachedBuild(for: .apple)?.label == "build 42")
    #expect(state.storesMissingBuild.isEmpty)
}

@MainActor
@Test func anAndroidBundlePathIsAttached() throws {
    let (state, folder) = try appleApp()
    defer { try? FileManager.default.removeItem(at: folder) }

    // The same app, now going to Google as well, with its App Bundle named.
    state.manifest.setGoogleApp(packageName: "com.example.app")
    state.manifest.release = Manifest.Release(
        build: Manifest.Release.Build(android: "/tmp/app-release.aab"))

    #expect(state.hasAttachedBuild(for: .google))
    #expect(state.attachedBuild(for: .google)?.label == "app-release.aab")
    // Apple still has none, so the app is not clear to upload everywhere.
    #expect(state.storesMissingBuild == [.apple])
}

/// The gate only ever reaches a store, never the provider.
@Test func onlyStoresCarryABuild() {
    #expect(PlanSystem.apple.store == .apple)
    #expect(PlanSystem.google.store == .google)
    #expect(PlanSystem.provider.store == nil)
}
