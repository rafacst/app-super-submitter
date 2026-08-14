import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// The keyword pool belongs to one platform, and the panel says which.
///
/// Apple keeps a pool per platform and refuses a read that names none. The app
/// sent no platform at all, so the panel answered "Filter 'platform' is
/// required for this operation" whichever platform the developer wanted, and
/// nothing on the panel said a platform was even part of the question.
@MainActor
@Suite(.serialized) struct KeywordPlatformTests {

    private func workspace(platforms: [Manifest.Platform]) throws -> (AppState, URL) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("keywords-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(ManifestFile.defaultName)
        var manifest = Manifest()
        manifest.setAppleApp(appID: "1", bundleID: "com.example.app", platforms: platforms)
        try ManifestFile.save(manifest, to: url)
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        try state.load(from: url)
        return (state, folder)
    }

    /// The read follows the picker, so the Mac pool is one segment away.
    @Test func theSelectedPlatformIsTheOneTheReadUses() throws {
        let (state, folder) = try workspace(platforms: [.ios, .macOS])
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(state.applePlatform == .ios)
        state.applePlatform = .macOS
        #expect(state.applePlatform.rawValue == "MAC_OS")
        #expect(state.appleplatformChoices == [.ios, .macOS])
    }

    /// An app on one platform is asked nothing. A choice of one is a control
    /// with no second answer.
    @Test func onePlatformOffersNoChoice() throws {
        let (state, folder) = try workspace(platforms: [.ios])
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(state.appleplatformChoices.isEmpty)
        #expect(state.applePlatform == .ios)
    }

    /// The panel carries the picker itself. The same control beside the app id
    /// is a rail away, on a panel about identifiers, which is not where
    /// somebody stands when they want the Mac keywords.
    @Test func thePanelAsksTheQuestionWhereItComesUp() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        func source(_ path: String) throws -> String {
            try String(contentsOf: root.appending(path: path), encoding: .utf8)
        }
        let panel = try source("Sources/SuperSubmitter/Tabs/SearchKeywordsPanel.swift")

        #expect(panel.contains("state.appleplatformChoices.count > 1"))
        #expect(panel.contains("set: { state.applePlatform = $0 }"))
        // A list read for one platform must not survive a switch to the other.
        #expect(panel.contains(".onChange(of: state.applePlatform)"))
        // And the read itself names the platform, or Apple refuses it.
        #expect(try source("Sources/SuperSubmitter/AppStateAppleReads.swift")
            .contains("platform: applePlatform.rawValue"))
    }
}
