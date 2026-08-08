import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// The App Clip card holds three values per locale, and one writer owns all
/// three.
///
/// The subtitle binding used to build a fresh `ClipLocale` on every keystroke,
/// so typing a subtitle threw away the title beside it. Once the header image
/// joined them on the same locale, the same keystroke would have thrown away a
/// picture the run had already uploaded.
@Suite(.serialized)
@MainActor
struct AppClipLocaleTests {
    private func workspace() throws -> (state: AppState, folder: URL) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("appclip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(ManifestFile.defaultName)
        var manifest = Manifest()
        manifest.setAppleApp(appID: "1", bundleID: "org.super.submitter")
        try ManifestFile.save(manifest, to: url)
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        try state.load(from: url)
        return (state, folder)
    }

    @Test func writingOneClipFieldKeepsTheOthersOnThatLocale() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }

        state.appClipHeaderImageBinding(locale: "en-GB").wrappedValue = "assets/clip.png"
        state.appClipLocaleBinding(locale: "en-GB", field: .title).wrappedValue = "Order"
        state.appClipSubtitleBinding(locale: "en-GB").wrappedValue = "Table for two"

        let entry = try #require(state.marketing.appClip?.locales?["en-GB"])
        #expect(entry.headerImage == "assets/clip.png")
        #expect(entry.title == "Order")
        #expect(entry.subtitle == "Table for two")
    }

    @Test func theLocaleGoesOnlyWhenItsLastFieldIsEmptied() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }

        state.appClipSubtitleBinding(locale: "en-GB").wrappedValue = "Table for two"
        state.appClipHeaderImageBinding(locale: "en-GB").wrappedValue = "assets/clip.png"

        // Emptying one field leaves the locale, because the other still holds
        // something the run has to write.
        state.appClipSubtitleBinding(locale: "en-GB").wrappedValue = ""
        #expect(state.marketing.appClip?.locales?["en-GB"]?.headerImage == "assets/clip.png")

        // Emptying the last one drops the locale, so the run writes no locale
        // made only of nulls.
        state.appClipHeaderImageBinding(locale: "en-GB").wrappedValue = ""
        #expect(state.marketing.appClip == nil)
    }
}
