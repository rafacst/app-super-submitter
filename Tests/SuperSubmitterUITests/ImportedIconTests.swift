import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// The icon of an app that was imported from a store.
///
/// The bug this guards: the import fetches the icon, downloads it under
/// `Store Import/`, and then dropped the one line that says where it went.
/// `merge(_ imported:store:)` groups assets by device class and an icon has
/// none, so the `guard` threw it away. `removeImportedMedia` clears
/// `media.icon` at the same time, on purpose, because an imported path may not
/// sit in the manifest as something to upload. So nothing anywhere held an
/// icon: every imported app wore its initials in the switcher, and its own
/// store page told it there was no icon to show yet.

private func imported(kind: String, locale: String = "en-US",
                      remote: String) -> ImportedStoreAsset {
    ImportedStoreAsset(locale: locale, kind: kind,
                       url: URL(string: remote)!, fileName: "icon.png")
}

private func listing(_ assets: [ImportedStoreAsset]) -> ImportedStoreListing {
    var result = ImportedStoreListing()
    result.assets = assets
    return result
}

/// A file that is really there, because the badge draws an `NSImage` off the
/// disk and a URL alone proves nothing.
private func downloaded(_ folder: URL, _ name: String) throws -> URL {
    let url = folder.appendingPathComponent(name)
    try Data("png".utf8).write(to: url)
    return url
}

@Test func anImportedAppKeepsTheIconItDownloaded() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("icon-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let local = try downloaded(folder, "icon.png")
    let remote = "https://example.com/icon/512x512.png"

    var snapshot = StoreSnapshot()
    snapshot.rememberLocalCopies([(URL(string: remote)!, local)])
    snapshot.merge(listing([imported(kind: "icon", remote: remote)]), store: .apple)

    // The copy on disk, and not the store's own URL. The badge cannot draw a
    // remote one, and asking for it would fetch a picture already downloaded.
    #expect(snapshot.appleIcon == local)
    #expect(snapshot.localIcon(defaultLocale: "en-US") == local)
    // The store page stops saying there is no icon to show yet.
    #expect(snapshot.icon(.apple, locale: "en-US") == local)
}

@Test func playKeepsItsIconPerLanguageAndItsBanner() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("icon-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let icon = try downloaded(folder, "play-icon.png")
    let banner = try downloaded(folder, "banner.png")
    let iconRemote = "https://play.example.com/icon.png"
    let bannerRemote = "https://play.example.com/banner.png"

    var snapshot = StoreSnapshot()
    snapshot.rememberLocalCopies([(URL(string: iconRemote)!, icon),
                                  (URL(string: bannerRemote)!, banner)])
    snapshot.merge(listing([imported(kind: "icon", locale: "pt-BR", remote: iconRemote),
                            imported(kind: "featureGraphic", locale: "pt-BR",
                                     remote: bannerRemote)]),
                   store: .google)

    #expect(snapshot.icon(.google, locale: "pt-BR") == icon)
    #expect(snapshot.featureGraphic(locale: "pt-BR") == banner)
    // Play keys its icon by language and a switcher row is in no language.
    #expect(snapshot.localIcon(defaultLocale: "pt-BR") == icon)
    #expect(snapshot.localIcon(defaultLocale: nil) == icon)
}

/// A remote URL is not an answer for the row. `captureAppleIcon` stores Apple's
/// own https URL after a submission, and the badge reads the disk.
@Test func aRowNeverPointsAtAPictureThatIsNotOnThisMac() {
    var snapshot = StoreSnapshot()
    snapshot.setAppleIcon(URL(string: "https://example.com/icon.png")!)

    #expect(snapshot.localIcon(defaultLocale: "en-US") == nil)
}

/// The screenshots still go where they went. An icon leaving the loop early
/// must not take the set it was standing next to.
@Test func theScreenshotsAreUnmovedByTheIconLeavingEarly() {
    var snapshot = StoreSnapshot()
    snapshot.merge(listing([
        imported(kind: "icon", remote: "https://example.com/icon.png"),
        imported(kind: "APP_IPHONE_69", remote: "https://example.com/one.png"),
        imported(kind: "APP_IPHONE_69", remote: "https://example.com/two.png"),
    ]), store: .apple)

    let phone = snapshot.screenshots(locale: "en-US", deviceClass: .phone)
    #expect(phone.first { $0.store == .apple }?.urls.count == 2)
}
