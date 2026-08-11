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

/// What the Media tab may assume the developer still has to supply.
///
/// The two flows want opposite sentences. An update carries its screenshots
/// forward and needs none; a first submission is refused without them. Getting
/// this backwards costs a first-time developer a rejection, so the default
/// when nothing is known has to be "required".
@MainActor
@Test func aFirstSubmissionIsNeverToldItsScreenshotsAreOptional() {
    let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                         storeAccount: "test-\(UUID().uuidString)")
    #expect(!state.isUpdatingLiveApp)
    #expect(!state.hasLiveScreenshots)

    var apple = ActualState.Apple()
    apple.liveVersionString = "1.2.0"
    var actual = ActualState()
    actual.apple = apple
    state.actualState = actual
    #expect(state.isUpdatingLiveApp)
    // A released app whose pictures nobody read. The tab has to tell the two
    // empties apart, so this stays false and the note says why the grid is
    // bare instead of leaving it silent.
    #expect(!state.hasLiveScreenshots)
}

/// The sizes behind the ⓘ come from the catalog the upload validates against,
/// so the popover can never name a size the app would then refuse.
@Test func theAcceptedSizesAreTheOnesTheUploadChecks() {
    let phone = AssetInspector.appleSizeLabels(for: .phone)
    #expect(phone.contains("1290 × 2796"))
    #expect(phone.contains("1320 × 2868"))
    #expect(AssetInspector.appleSizeLabels(for: .desktop).contains("2880 × 1800"))
    // Google's own class. The App Store has no size for it and the popover
    // then shows Google's rule alone.
    #expect(AssetInspector.appleSizeLabels(for: .tablet7).isEmpty)
}

/// A draft the store holds is not an app that has shipped.
///
/// `isUpdatingLiveApp` used to read `!storeSnapshot.isEmpty`, and the snapshot
/// fills from `infoLocales` and `versionLocales`, which a draft carries. An app
/// record created in App Store Connect and never submitted has a name, a
/// subtitle and a description, so every unpublished app read as an update: the
/// Details tab put a red **Required** on What is new, over a version with no
/// previous version to be new against.
@MainActor
@Test func aDraftListingIsNotAShippedApp() {
    let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                         storeAccount: "test-\(UUID().uuidString)")

    // The listing of an app record that exists and has never been submitted.
    var apple = ActualState.Apple()
    apple.infoLocales["en-US"] = {
        var locale = ActualState.Apple.InfoLocale()
        locale.name = "Artisan View"
        locale.subtitle = "Costs and stock"
        return locale
    }()
    apple.versionLocales["en-US"] = {
        var locale = ActualState.Apple.VersionLocale()
        locale.description = "A long description."
        return locale
    }()
    var actual = ActualState()
    actual.apple = apple
    state.actualState = actual
    state.storeSnapshot.merge(actual)

    #expect(!state.storeSnapshot.isEmpty)
    #expect(!state.isUpdatingLiveApp)
    #expect(state.showsNewAppFields)

    // The live listing is what tells the two apart, and only a shipped version
    // puts anything there.
    apple.liveVersionLocales["en-US"] = {
        var locale = ActualState.Apple.VersionLocale()
        locale.description = "The description the customers are reading."
        return locale
    }()
    actual.apple = apple
    state.storeSnapshot.merge(actual)
    #expect(state.isUpdatingLiveApp)
}
