import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// The screenshots of a custom product page.
///
/// Apple's `appCustomProductPageLocalizations` carries an `appScreenshotSets`
/// relationship, the apply has always uploaded to it, and the manifest has
/// always held the paths. No control ever wrote one, so the only way in was the
/// raw YAML editor, and the one control that touched the same locale threw them
/// away on every keystroke.
@MainActor
@Suite(.serialized) struct CustomPageMediaTests {

    private func workspace() throws -> (state: AppState, folder: URL) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("cpp-media-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(ManifestFile.defaultName)
        var manifest = Manifest()
        manifest.setAppleApp(appID: "1", bundleID: "com.example.app")
        var marketing = Manifest.Marketing()
        marketing.customProductPages = [.init(key: "dinner", name: "Dinner with friends")]
        manifest.marketing = marketing
        var media = Manifest.Media()
        media.screenshots = ["en-US": ["phone": ["assets/phone-1.png", "assets/phone-2.png"],
                                       "tablet10": ["assets/tablet-1.png"]]]
        manifest.media = media
        try ManifestFile.save(manifest, to: url)
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        try state.load(from: url)
        return (state, folder)
    }

    private func seedScreenshots(_ state: AppState) {
        state.setPageScreenshots(index: 0, locale: "en-US", device: "phone",
                                 paths: ["assets/dinner-1.png"])
    }

    // MARK: - The field that was eating them

    /// `customProductPageTextBinding` rebuilt the whole locale from the text
    /// alone, so one keystroke in the promotional text dropped every screenshot
    /// the page carried.
    @Test func typingThePromotionalTextKeepsTheScreenshots() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        seedScreenshots(state)

        state.customProductPageTextBinding(index: 0, locale: "en-US").wrappedValue = "Split the tab"

        #expect(state.marketing.customProductPages?[0].locales?["en-US"]?
            .screenshots?["phone"] == ["assets/dinner-1.png"])
        #expect(state.marketing.customProductPages?[0].locales?["en-US"]?
            .promotionalText == "Split the tab")
    }

    /// Emptying the text removed the locale outright. The pictures are not the
    /// text, and a page that carries pictures still has a locale.
    @Test func clearingThePromotionalTextKeepsTheScreenshots() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        seedScreenshots(state)
        let binding = state.customProductPageTextBinding(index: 0, locale: "en-US")
        binding.wrappedValue = "Split the tab"

        binding.wrappedValue = ""

        #expect(state.marketing.customProductPages?[0].locales?["en-US"]?
            .screenshots?["phone"] == ["assets/dinner-1.png"])
        #expect(state.marketing.customProductPages?[0].locales?["en-US"]?
            .promotionalText == nil)
    }

    /// A locale that ends up holding neither is not a locale.
    @Test func aLocaleWithNeitherTextNorPicturesGoesAway() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        let binding = state.customProductPageTextBinding(index: 0, locale: "en-US")
        binding.wrappedValue = "Split the tab"

        binding.wrappedValue = ""

        #expect(state.marketing.customProductPages?[0].locales?["en-US"] == nil)
    }

    // MARK: - Taking them from the Media tab

    /// The Media tab already holds the App Store's screenshots for this locale,
    /// so a page starts from them rather than from an empty box.
    @Test func aPageCanTakeTheAppStoreScreenshots() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }

        state.takeMediaScreenshots(intoPage: 0, locale: "en-US")

        let held = state.customProductPageScreenshots(index: 0, locale: "en-US")
        #expect(held["phone"] == ["assets/phone-1.png", "assets/phone-2.png"])
        #expect(held["tablet10"] == ["assets/tablet-1.png"])
    }

    /// Apple's own per-store list wins, the same rule the Media tab reads by.
    @Test func theAppleOverrideIsWhatAPageTakes() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        state.manifest.media?.appleScreenshots = ["en-US": ["phone": ["assets/apple-1.png"]]]

        state.takeMediaScreenshots(intoPage: 0, locale: "en-US")

        #expect(state.customProductPageScreenshots(index: 0, locale: "en-US")["phone"]
                == ["assets/apple-1.png"])
    }

    /// Nothing held is the page inheriting the default product page, which is
    /// what an empty map has always meant to the apply: it uploads nothing.
    @Test func clearingThePicturesReturnsThePageToTheDefaultOne() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        state.takeMediaScreenshots(intoPage: 0, locale: "en-US")

        state.clearPageScreenshots(index: 0, locale: "en-US")

        #expect(state.customProductPageScreenshots(index: 0, locale: "en-US").isEmpty)
    }

    /// An emptied device class is removed rather than written as an empty list,
    /// because the two mean different things elsewhere in the manifest.
    @Test func anEmptiedSizeIsRemovedAndNotWrittenEmpty() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        seedScreenshots(state)

        state.setPageScreenshots(index: 0, locale: "en-US", device: "phone", paths: [])

        #expect(state.customProductPageScreenshots(index: 0, locale: "en-US")["phone"] == nil)
    }

    // MARK: - Where the developer meets them

    @Test func thePageEditorDrawsThePicturesAndTheWayToTheMediaTab() throws {
        let tab = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "Sources/SuperSubmitter/Tabs/MarketingTab.swift"),
            encoding: .utf8)

        #expect(tab.contains("takeMediaScreenshots"))
        #expect(tab.contains("clearPageScreenshots"))
        #expect(tab.contains("selectedTab = .media"))
        #expect(tab.contains("inherits the default product page"))
    }
}
