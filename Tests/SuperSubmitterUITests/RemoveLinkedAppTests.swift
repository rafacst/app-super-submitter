import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// Writes two workspaces in a temporary folder and links both. The suite and
/// the Keychain account belong to the test, so a run touches neither the real
/// app list nor the real store key.
@MainActor
private func stateWithTwoLinkedApps(
    defaults: UserDefaults = UserDefaults(suiteName: UUID().uuidString)!
) throws -> (AppState, [URL]) {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("remove-\(UUID().uuidString)")
    var urls: [URL] = []
    for name in ["Alpha", "Beta"] {
        let folder = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var manifest = Manifest()
        manifest.setAppleApp(appID: "1", bundleID: "com.example.\(name.lowercased())")
        manifest.addLocale("en-US", name: name)
        let url = folder.appendingPathComponent(ManifestFile.defaultName)
        try ManifestFile.save(manifest, to: url)
        urls.append(url)
    }
    let state = AppState(defaults: defaults, storeAccount: "test-\(UUID().uuidString)")
    for url in urls { state.link(manifestAt: url) }
    return (state, urls)
}

@MainActor
@Test func removingAnAppUnlinksItAndKeepsItsFile() throws {
    let (state, urls) = try stateWithTwoLinkedApps()
    #expect(state.linkedApps.count == 2)

    state.askToRemoveApp(at: 0)
    #expect(state.removalName == "Alpha")
    state.removePendingApp()

    #expect(state.linkedApps.map(\.name) == ["Beta"])
    #expect(state.manifestURL == urls[1])
    // Removal is a list edit. Both files stay on disk.
    #expect(FileManager.default.fileExists(atPath: urls[0].path))
    #expect(FileManager.default.fileExists(atPath: urls[1].path))
}

@MainActor
@Test func removingTheLastAppReturnsToTheEntryScreen() throws {
    let (state, _) = try stateWithTwoLinkedApps()

    state.removeLinkedApp(at: 1)
    state.removeLinkedApp(at: 0)

    #expect(state.linkedApps.isEmpty)
    // The content area shows the two entry cards while this is nil.
    #expect(state.manifestURL == nil)
    #expect(state.stores.isEmpty)
}

/// The user continues where they stopped. A launch opens the app they worked
/// on last, and not the first app of the list.
@MainActor
@Test func aLaunchOpensTheAppTheUserWorkedOnLast() throws {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let (state, urls) = try stateWithTwoLinkedApps(defaults: defaults)
    // The second app, because index 0 is also what a lost choice falls back to.
    state.selectApp(at: 1)
    #expect(state.manifestURL == urls[1])

    let relaunched = AppState(defaults: defaults, storeAccount: "test-\(UUID().uuidString)")

    #expect(relaunched.manifestURL == urls[1])
    #expect(relaunched.linkedApps.count == 2)
    // Every edit writes the file, so the work of that app is already there.
    #expect(relaunched.manifest.apps.apple?.bundleId == "com.example.beta")
}

@MainActor
@Test func removingAnAppOutsideTheListChangesNothing() throws {
    let (state, _) = try stateWithTwoLinkedApps()

    state.removeLinkedApp(at: 7)
    state.askToRemoveApp(at: -1)

    #expect(state.linkedApps.count == 2)
    #expect(state.appPendingRemoval == nil)
}
