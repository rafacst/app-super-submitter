import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// The bug this guards: `mediaURL` asked a `URL` whether it was absolute.
/// `URL(fileURLWithPath:)` resolves a relative path against the working
/// directory of the process, so the answer was yes for every path, and a
/// relative path — which is what the app itself writes — pointed at the
/// working directory instead of the app folder. Every tile on the Media tab
/// then drew an empty box with no size under it.
@MainActor
@Test func aRelativeMediaPathResolvesAgainstTheManifestFolder() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("media-url-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("assets"),
                                            withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let shot = folder.appendingPathComponent("assets/shot.png")
    try Data("png".utf8).write(to: shot)
    let manifestURL = folder.appendingPathComponent("store.yaml")
    try ManifestFile.save(Manifest(), to: manifestURL)

    let state = AppState()
    try state.load(from: manifestURL)

    #expect(state.mediaURL(for: "assets/shot.png").standardizedFileURL
        == shot.standardizedFileURL)
    #expect(FileManager.default.fileExists(atPath: state.mediaURL(for: "assets/shot.png").path))
    // An absolute path belongs to whoever wrote it.
    #expect(state.mediaURL(for: "/tmp/other.png").path == "/tmp/other.png")
}

/// A drag across the row is a reorder, not a trade.
///
/// `moveMediaPath` used to call `swapAt`. Over one place a swap and a move are
/// the same thing, so the two arrow buttons never showed the difference, and
/// dragging the first tile onto the fifth sent the fifth back to the front.
@MainActor
@Test func draggingATileReordersInsteadOfSwapping() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("media-move-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let manifestURL = folder.appendingPathComponent("store.yaml")
    try ManifestFile.save(Manifest(), to: manifestURL)

    let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                         storeAccount: "media-move-\(UUID().uuidString)")
    try state.load(from: manifestURL)
    state.manifest.addLocale("en-US")
    state.locale = "en-US"
    state.manifest.addMediaPaths(["a.png", "b.png", "c.png", "d.png"],
                                 locale: "en-US", deviceClass: .phone)

    state.moveMedia("a.png", before: "d.png", deviceClass: .phone)
    #expect(state.mediaPaths(deviceClass: .phone) == ["b.png", "c.png", "d.png", "a.png"])

    // The arrow buttons keep their one-place behaviour.
    state.moveMedia("a.png", by: -1, deviceClass: .phone)
    #expect(state.mediaPaths(deviceClass: .phone) == ["b.png", "c.png", "a.png", "d.png"])

    // A tile dropped on itself changes nothing.
    state.moveMedia("a.png", before: "a.png", deviceClass: .phone)
    #expect(state.mediaPaths(deviceClass: .phone) == ["b.png", "c.png", "a.png", "d.png"])
}
