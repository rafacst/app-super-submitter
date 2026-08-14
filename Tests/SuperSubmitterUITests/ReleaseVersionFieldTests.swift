import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// The one version box on a one-store app shows the number the store answered
/// with.
///
/// The box read `release.versionName` and nothing else. Every writer that names
/// a store writes `release.apple.versionName` and clears the shared key, which
/// is right for two stores that number apart and left the single box empty on
/// an app with one store: the fetch read 1.6 off App Store Connect, wrote it,
/// and the field went back to showing its own "1.0" placeholder. The developer
/// then had no number to go up from, while the build under it went on saying
/// 1.6 because it asks the manifest the other way.
@MainActor
@Suite(.serialized) struct ReleaseVersionFieldTests {

    private func workspace(google: Bool = false) throws -> (state: AppState, folder: URL) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("version-field-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(ManifestFile.defaultName)
        var manifest = Manifest()
        manifest.setAppleApp(appID: "1", bundleID: "com.example.app")
        if google { manifest.setGoogleApp(packageName: "com.example.app") }
        try ManifestFile.save(manifest, to: url)
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        try state.load(from: url)
        return (state, folder)
    }

    /// The bug, in the shape the developer meets it: fetch, then read the box.
    @Test func theFetchedNumberReachesTheBox() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }

        var imported = ImportedStoreListing()
        imported.versionName = "1.6"
        state.manifest.mergeAppleImport(imported)

        #expect(state.manifest.versionName(for: .apple) == "1.6")
        #expect(state.releaseVersionBinding.wrappedValue == "1.6")
    }

    /// Typing in the box moves the number to the shared key, and the box keeps
    /// showing what was typed.
    @Test func theBoxStillWrites() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }

        state.releaseVersionBinding.wrappedValue = "1.7"
        #expect(state.manifest.release?.versionName == "1.7")
        #expect(state.releaseVersionBinding.wrappedValue == "1.7")
    }

    /// Two stores that number apart keep their own numbers, and the shared box
    /// claims neither of them. The tab draws a field per store for that case.
    @Test func twoStoresAreNeverCollapsedIntoOne() throws {
        let (state, folder) = try workspace(google: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        state.manifest.setReleaseVersionName("1.6", for: .apple)
        state.manifest.setReleaseVersionName("1.0", for: .google)

        #expect(state.showsVersionPerStore)
        #expect(state.releaseVersionBinding.wrappedValue == "")
        #expect(state.releaseVersionBinding(for: .apple).wrappedValue == "1.6")
        #expect(state.releaseVersionBinding(for: .google).wrappedValue == "1.0")
    }

    /// The shared key still wins wherever there is one.
    @Test func oneNumberForBothStoresStillReads() throws {
        let (state, folder) = try workspace(google: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        state.manifest.setReleaseVersionName("2.0")
        #expect(state.sharesOneVersion)
        #expect(state.releaseVersionBinding.wrappedValue == "2.0")
    }
}
