import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// A store the developer never picked used to wear a red cross in the
/// sidebar, which says "this is wrong" about a choice they made on purpose.
/// An app that goes to one store shows one logo.
@MainActor
@Test func theSidebarNamesOnlyTheStoresAnAppGoesTo() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("row-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent(ManifestFile.defaultName)

    var manifest = Manifest()
    manifest.setAppleApp(appID: "1", bundleID: "com.example.app", platforms: [.macOS])
    try ManifestFile.save(manifest, to: url)

    let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                         storeAccount: "test-\(UUID().uuidString)")
    state.link(manifestAt: url)
    let row = try #require(state.appRows.first)

    #expect(row.apple != nil)
    #expect(row.google == nil, "Google Play is not part of this app, so it is not shown.")
    #expect(row.storeSummary == "App Store has changes")

    // Adding the second store brings its logo back.
    state.setStore(.google, enabled: true)
    #expect(state.appRows.first?.google != nil)
}
