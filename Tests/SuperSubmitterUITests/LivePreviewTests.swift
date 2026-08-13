import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

private let livePreviewRepositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func livePreviewSource(_ relativePath: String) throws -> String {
    try String(contentsOf: livePreviewRepositoryRoot.appendingPathComponent(relativePath),
               encoding: .utf8)
}

private func scratchFolder() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("live-preview-\(UUID().uuidString)", isDirectory: true)
}

// MARK: - The route a press takes

/// A store screenshot is an `https` address, and the panel used to refuse every
/// one of them: the file check at the top of `show` returned before anything
/// happened, so the press did nothing at all and said nothing about it.
@Test func aStoreScreenshotIsFetchedRatherThanRefused() {
    let remote = URL(string: "https://is1-ssl.mzstatic.com/image/thumb/a/b/1290x2796bb.png")!

    #expect(QuickLook.route(remote) == .fetch(remote))
}

/// The local files this panel was built for still open straight off the disk.
/// No download, no cache, no change of behaviour for the Media tab's own tiles.
@Test func aLocalScreenshotStillOpensDirectly() throws {
    let folder = scratchFolder()
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("shot.png")
    try Data("png".utf8).write(to: file)

    #expect(QuickLook.route(file) == .present(file))
}

/// A path naming nothing is neither a preview nor a download.
@Test func aMissingFileIsNeitherShownNorFetched() {
    let absent = URL(fileURLWithPath: "/nowhere/at/all/shot.png")

    #expect(QuickLook.route(absent) == .missing)
}

// MARK: - Turning a store address into a file Quick Look can read

/// The conversion, proved without the live internet behind it.
@Test func aRemoteAddressBecomesALocalFile() async throws {
    let folder = scratchFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let remote = URL(string: "https://is1-ssl.mzstatic.com/image/thumb/a/b/1290x2796bb.png")!
    let bytes = Data("a screenshot".utf8)

    let file = try await RemotePreview.localItem(for: remote, in: folder) { _ in bytes }

    #expect(file.isFileURL)
    #expect(try Data(contentsOf: file) == bytes)
    // Quick Look picks its renderer off the extension, so the address's own
    // one is carried over.
    #expect(file.pathExtension == "png")
}

/// The same address twice is one download. A developer clicking along a strip
/// of ten screenshots asks for each of them more than once.
@Test func aSecondPressReusesTheDownloadedFile() async throws {
    let folder = scratchFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let remote = URL(string: "https://example.com/a/shot.jpg")!
    var fetches = 0

    let first = try await RemotePreview.localItem(for: remote, in: folder) { _ in
        fetches += 1
        return Data("one".utf8)
    }
    let second = try await RemotePreview.localItem(for: remote, in: folder) { _ in
        fetches += 1
        return Data("two".utf8)
    }

    #expect(first == second)
    #expect(fetches == 1)
    #expect(try Data(contentsOf: second) == Data("one".utf8))
}

/// The name is a digest of the whole address and not of its last component, so
/// two screenshots that both end in `1290x2796bb.png` stay two files.
@Test func twoAddressesEndingTheSameWayAreTwoFiles() {
    let folder = URL(fileURLWithPath: "/tmp/previews")
    let first = URL(string: "https://store.example/app-one/1290x2796bb.png")!
    let second = URL(string: "https://store.example/app-two/1290x2796bb.png")!

    #expect(RemotePreview.cacheURL(for: first, in: folder)
            != RemotePreview.cacheURL(for: second, in: folder))
    // And the same address is the same file on the next launch, which a
    // per-process `Hasher` value could not promise.
    #expect(RemotePreview.cacheURL(for: first, in: folder)
            == RemotePreview.cacheURL(for: first, in: folder))
}

/// An address carrying no usable extension still previews. Quick Look shows a
/// blank page for a type it cannot name, and both stores answer pictures here.
@Test func anAddressWithNoExtensionIsTreatedAsAPicture() {
    let folder = URL(fileURLWithPath: "/tmp/previews")
    let bare = URL(string: "https://store.example/image/thumb/abc123")!

    #expect(RemotePreview.cacheURL(for: bare, in: folder).pathExtension == "png")
}

/// A refused request is a failure and not an empty picture. Writing a 403 page
/// into the cache as a `.png` would open the panel on nothing, which is the
/// silent no-op this whole fix removes.
@Test func aFailedDownloadThrowsRatherThanCachingTheRefusal() async {
    let folder = scratchFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let remote = URL(string: "https://store.example/forbidden.png")!

    await #expect(throws: RemotePreview.Failure.self) {
        try await RemotePreview.localItem(for: remote, in: folder) { _ in
            throw RemotePreview.Failure.notAPicture(403)
        }
    }
    #expect(!FileManager.default.fileExists(
        atPath: RemotePreview.cacheURL(for: remote, in: folder).path))
}

// MARK: - The strip that draws them

/// The live strip carried `.allowsHitTesting(false)` across everything in it,
/// so the one press worth having on a live screenshot was swallowed with the
/// drags and the drops it was there to stop.
@Test func theLiveStripNoLongerSwallowsEveryPress() throws {
    let tab = try livePreviewSource("Sources/SuperSubmitter/Tabs/MediaTab.swift")
    // The comments still name the modifier, because they say why it went. Only
    // the code is the claim here.
    let code = tab.split(separator: "\n", omittingEmptySubsequences: false)
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        .joined(separator: "\n")

    #expect(!code.contains(".allowsHitTesting(false)"))
    #expect(code.contains("private struct LiveMediaTile"))
    // The press goes through the one preview route the whole app shares.
    #expect(code.contains("Button { QuickLook.show(url) }"))
    // And it stays read-only: no drag, no drop, no reorder, no remove.
    #expect(code.contains(".accessibilityHint(\"Opens a full size preview\")"))

    // Read-only, judged on the tile itself and not on the file around it: the
    // editable tiles above legitimately drag, drop and remove.
    let tile = try #require(code.range(of: "private struct LiveMediaTile"))
    let next = code.range(of: "\nprivate struct ", range: tile.upperBound..<code.endIndex)
    let body = String(code[tile.lowerBound..<(next?.lowerBound ?? code.endIndex)])
    for editing in ["onDrag", "dropDestination", "onMove", "remove", "onInsert"] {
        #expect(!body.contains(editing), "the live tile must stay read-only: \(editing)")
    }
}

/// A failed download says so. It used to be a press that did nothing, and a
/// quieter version of that is not a fix.
@Test func aFailedPreviewReachesTheAppsErrorChannel() throws {
    let shell = try livePreviewSource("Sources/SuperSubmitter/SuperSubmitterApp.swift")
    let panel = try livePreviewSource("Sources/SuperSubmitter/Shell/QuickLook.swift")

    #expect(shell.contains("QuickLook.report = { state.errorMessage = $0 }"))
    #expect(panel.contains("report?("))
}

/// The Store Page hands the same panel the same kind of address, so it was
/// broken in the same way and is fixed by the same change rather than a second
/// copy of it.
@Test func theStorePageUsesTheSharedPreviewRoute() throws {
    let page = try livePreviewSource("Sources/SuperSubmitter/Tabs/StorePage.swift")

    #expect(page.contains("QuickLook.show(url)"))
}
