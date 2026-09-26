import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

private func source(_ path: String) throws -> String {
    try String(contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: path), encoding: .utf8)
}

// MARK: - The language switch

/// The flag is read before the letters are. A code that names no country
/// takes the country its language is most spoken in, and a region that is not
/// a country takes no flag at all rather than a wrong one.
@MainActor
@Test func aLanguageShowsTheFlagOfItsCountry() {
    #expect(LocaleFlag.emoji(for: "en-US") == "🇺🇸")
    #expect(LocaleFlag.emoji(for: "pt-BR") == "🇧🇷")
    #expect(LocaleFlag.emoji(for: "ja") == "🇯🇵")
    #expect(LocaleFlag.emoji(for: "zh-Hans") == "🇨🇳")
    #expect(LocaleFlag.emoji(for: "es-419") == nil)
}

/// Five languages came out as five columns one letter wide, "e" over an
/// ellipsis. The switch is one button with the flag and the code of the
/// language being edited, and the languages open in a list under it.
@Test func theLanguageSwitchIsOneButtonThatOpensAList() throws {
    let root = try source("Sources/SuperSubmitter/Shell/RootView.swift")
    let start = try #require(root.range(of: "private struct LocalePicker"))
    let end = try #require(root.range(of: "struct AppMessage"))
    let picker = String(root[start.lowerBound..<end.lowerBound])

    #expect(picker.contains("LocaleFlag(code: state.locale"))
    #expect(picker.contains(".popover(isPresented: $open"))
    #expect(picker.contains("LocaleFlag(code: code"))
    // Choosing a language closes the list.
    #expect(picker.contains("state.locale = code\n            open = false"))
    // Adding a language is still its own command, beside the list.
    #expect(picker.contains("state.showAddLocale = true"))
}

// MARK: - The build wells

@MainActor
private func appWithBuilds() throws -> (state: AppState, folder: URL) {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("build-well-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("ipa".utf8).write(to: folder.appendingPathComponent("App.ipa"))
    try Data("aab".utf8).write(to: folder.appendingPathComponent("app.aab"))
    let url = folder.appendingPathComponent("store.yaml")
    try ManifestFile.save(Manifest(), to: url)
    let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                         storeAccount: "build-well-\(UUID().uuidString)")
    try state.load(from: url)
    state.manifest.release = Manifest.Release(
        build: Manifest.Release.Build(ios: "App.ipa", android: "app.aab"))
    state.resetUndo()
    return (state, folder)
}

/// A wrong pick could only be replaced by dropping another build over it. The
/// trash takes it off the release, and the file stays where it is.
@MainActor
@Test func theTrashTakesTheBuildOffAndLeavesTheFile() throws {
    let (state, folder) = try appWithBuilds()
    defer { try? FileManager.default.removeItem(at: folder) }
    #expect(state.linkedBuildName(.ipa) == "App.ipa")

    state.removeBuild(.ipa)

    #expect(state.linkedBuildPath(.ipa) == nil)
    #expect(state.linkedBuildName(.ipa) == nil)
    #expect(state.linkedBuildPath(.aab) == "app.aab")
    #expect(FileManager.default.fileExists(
        atPath: folder.appendingPathComponent("App.ipa").path))
}

/// The last build out leaves no empty block behind, and undo puts it back.
@MainActor
@Test func removingTheLastBuildLeavesNoEmptyBlockAndUndoes() throws {
    let (state, folder) = try appWithBuilds()
    defer { try? FileManager.default.removeItem(at: folder) }
    state.manifest.release?.build?.ios = nil
    state.resetUndo()

    state.removeBuild(.aab)
    #expect(state.manifest.release?.build == nil)

    state.undoEdit()
    #expect(state.linkedBuildPath(.aab) == "app.aab")
}

/// A build named by an earlier session is on the well, so it can be removed
/// after a relaunch as well.
@MainActor
@Test func aBuildFromAnEarlierSessionIsNamedOnItsWell() throws {
    let (state, folder) = try appWithBuilds()
    defer { try? FileManager.default.removeItem(at: folder) }

    #expect(state.packages[.aab] == nil)
    #expect(state.linkedBuildName(.aab) == "app.aab")
    #expect(state.linkedBuildName(.pkg) == nil)
}

@Test func everyBuildWellCarriesTheTrash() throws {
    let tab = try source("Sources/SuperSubmitter/Tabs/BuildTab.swift")

    for kind in ["ipa", "pkg", "aab"] {
        #expect(tab.contains("remove: removal(.\(kind)))"))
        #expect(tab.contains("title: state.linkedBuildName(.\(kind))"))
    }
    #expect(tab.contains("Image(systemName: \"trash\")"))
}
