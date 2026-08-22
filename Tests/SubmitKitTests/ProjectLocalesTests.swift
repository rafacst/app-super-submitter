import Foundation
import Testing
@testable import SubmitKit

/// The languages a folder already states. Without them a new app's manifest
/// carries no listing, and three tabs open on "Add the first locale" for a
/// question the project answered in the file the identifier came from.
@Suite struct ProjectLocalesTests {

    // MARK: - Apple

    private let pbxproj = """
        developmentRegion = en;
        hasScannedForEncodings = 0;
        knownRegions = (
            en,
            Base,
            "pt-BR",
            ja,
        );
        """

    @Test func xcodeAnswersWithItsRegionAndItsKnownOnes() {
        let found = ProjectLocales.parseApple(pbxproj)
        #expect(found.defaultLocale == "en")
        // Base is the unlocalised interface and never a language.
        #expect(found.locales == ["en", "ja", "pt-BR"])
    }

    @Test func aProjectThatStatesNothingAnswersNothing() {
        let found = ProjectLocales.parseApple("buildSettings = { SDKROOT = iphoneos; };")
        #expect(found.defaultLocale == nil)
        #expect(found.locales.isEmpty)
        #expect(found.isEmpty)
    }

    /// A region the project names but never localises still belongs in the
    /// list, because it is the language the listing is written in first.
    @Test func theDevelopmentRegionIsAlwaysInTheList() {
        let found = ProjectLocales.parseApple("developmentRegion = \"pt-BR\";")
        #expect(found.defaultLocale == "pt-BR")
        #expect(found.locales == ["pt-BR"])
    }

    // MARK: - Android

    @Test func localesConfigAnswersInItsOwnOrder() {
        let xml = """
            <?xml version="1.0" encoding="utf-8"?>
            <locale-config xmlns:android="http://schemas.android.com/apk/res/android">
                <locale android:name="pt-BR"/>
                <locale android:name="en"/>
                <locale android:name="de"/>
            </locale-config>
            """
        let listed = ProjectLocales.parseLocalesConfig(xml)
        // The order is the file's, because the first entry is the default.
        #expect(listed == ["pt-BR", "en", "de"])
    }

    // MARK: - The qualifier grammar

    @Test func resourceQualifiersBecomeStoreLocales() {
        // Android's region form. The `r` is a marker and never part of it.
        #expect(ProjectLocales.storeLocale(for: "pt-rBR") == "pt-BR")
        // Android's BCP 47 form, which is the only one that can say a script.
        #expect(ProjectLocales.storeLocale(for: "b+sr+Latn") == "sr-Latn")
        #expect(ProjectLocales.storeLocale(for: "b+zh+Hans") == "zh-Hans")
        // Xcode's, which is already the store's.
        #expect(ProjectLocales.storeLocale(for: "zh-Hans") == "zh-Hans")
        #expect(ProjectLocales.storeLocale(for: "en") == "en")
    }

    /// A `res` folder holds far more than languages, and every one of those
    /// names arrives here from the same directory listing.
    @Test func configurationQualifiersAreNotLanguages() {
        #expect(ProjectLocales.storeLocale(for: "Base") == nil)
        #expect(ProjectLocales.storeLocale(for: "") == nil)
        #expect(ProjectLocales.storeLocale(for: "sw600dp") == nil)
        #expect(ProjectLocales.storeLocale(for: "v21") == nil)
        // A language with a qualifier after it keeps the language and drops
        // the qualifier: `values-en-night` is English.
        #expect(ProjectLocales.storeLocale(for: "en-night") == "en")
    }

    // MARK: - On disk

    @Test func anAndroidModuleAnswersFromItsResourceFolders() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let res = root.appendingPathComponent("src/main/res")
        for name in ["values", "values-de", "values-pt-rBR", "values-night"] {
            try FileManager.default.createDirectory(
                at: res.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: root) }

        let found = ProjectLocales.android(module: root)
        #expect(found.locales == ["de", "pt-BR"])
        // Android states no language for the unqualified `values` folder, so
        // nothing here claims to know which one the listing is written in.
        #expect(found.defaultLocale == nil)
    }

    @Test func localesConfigWinsOverTheFolders() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let res = root.appendingPathComponent("src/main/res")
        try FileManager.default.createDirectory(
            at: res.appendingPathComponent("values-de"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: res.appendingPathComponent("xml"), withIntermediateDirectories: true)
        try """
            <locale-config><locale android:name="ja"/><locale android:name="de"/></locale-config>
            """.write(to: res.appendingPathComponent("xml/locales_config.xml"),
                      atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let found = ProjectLocales.android(module: root)
        #expect(found.defaultLocale == "ja")
        #expect(found.locales == ["de", "ja"])
    }
}
