import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// Answers every download with one canned result. `URLSession.shared` is what
/// the asset import uses, so the stub registers globally and unregisters at
/// the end of the test.
private final class AssetStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data("image-bytes".utf8)

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "assets.example.com"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func asset(_ kind: String, _ file: String) -> ImportedStoreAsset {
    ImportedStoreAsset(locale: "en-US", kind: kind,
                       url: URL(string: "https://assets.example.com/\(file)")!,
                       fileName: file)
}

private func scratchFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("import-assets-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite(.serialized)
struct ExistingAppAssetTests {

    /// The bug this guards: one image that would not download threw out of the
    /// whole import. The throw happened before the save, so every description
    /// the import had already read was discarded with it and the folder was
    /// left with no `store.yaml` at all.
    @MainActor
    @Test func oneRefusedFileCostsThatFileAndNothingElse() async throws {
        URLProtocol.registerClass(AssetStubProtocol.self)
        defer { URLProtocol.unregisterClass(AssetStubProtocol.self) }
        AssetStubProtocol.status = 404
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let state = AppState()
        var manifest = Manifest()
        manifest.setListingText("The description", locale: "en-US", field: .description)

        let failures = await state.materializeImportedAssets(
            [asset("APP_IPHONE_69", "shot-1.png")], store: .apple, root: folder).failures

        #expect(failures.count == 1)
        #expect(failures[0].contains("shot-1.png"))
        // The text the import already read survives the refused image.
        #expect(manifest.listingText(locale: "en-US", field: .description) == "The description")
        #expect(manifest.mediaPaths(locale: "en-US", deviceClass: .phone).isEmpty)
    }

    /// The 6.9 inch set is what a current app ships. The reader's own list of
    /// display types never named it, so the phone bucket arrived empty on an
    /// app whose store is full.
    @MainActor
    @Test func downloadedStoreMediaIsObservedAndNeverQueuedForUpload() async throws {
        URLProtocol.registerClass(AssetStubProtocol.self)
        defer { URLProtocol.unregisterClass(AssetStubProtocol.self) }
        AssetStubProtocol.status = 200
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let state = AppState()
        var manifest = Manifest()

        let failures = await state.materializeImportedAssets(
            [asset("APP_IPHONE_69", "shot-1.png"), asset("APP_IPHONE_69", "trailer.mov"),
             asset("phoneScreenshots", "play-1.png")],
            store: .apple, root: folder).failures

        #expect(failures.isEmpty)
        let shots = manifest.mediaPaths(locale: "en-US", deviceClass: .phone)
        #expect(shots.isEmpty)
        #expect(FileManager.default.fileExists(
            atPath: folder.appendingPathComponent(
                "Store Import/apple/en-US/APP_IPHONE_69/shot-1.png").path))
        #expect(manifest.mediaPaths(locale: "en-US", deviceClass: .phone,
                                    previews: true).isEmpty)
    }

    @MainActor
    @Test func storeAssetPathsStayInsideTheImportFolder() async throws {
        URLProtocol.registerClass(AssetStubProtocol.self)
        defer { URLProtocol.unregisterClass(AssetStubProtocol.self) }
        AssetStubProtocol.status = 200
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let escapeName = "escape-\(UUID().uuidString)"
        let outside = folder.deletingLastPathComponent().appendingPathComponent(escapeName)
        let malicious = ImportedStoreAsset(
            locale: "../../../\(escapeName)", kind: ".",
            url: URL(string: "https://assets.example.com/agent.plist")!,
            fileName: "agent.plist")
        let state = AppState()
        var manifest = Manifest()

        let failures = await state.materializeImportedAssets(
            [malicious], store: .apple, root: folder).failures

        #expect(failures.isEmpty)
        #expect(!FileManager.default.fileExists(
            atPath: outside.appendingPathComponent("agent.plist").path))
        let importFolder = folder.appendingPathComponent(AppState.importFolder)
        let files = FileManager.default.enumerator(at: importFolder,
                                                    includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { !$0.hasDirectoryPath } ?? []
        #expect(files.count == 1)
        #expect(files[0].standardizedFileURL.path.hasPrefix(
            importFolder.standardizedFileURL.path + "/"))
    }

    @MainActor
    @Test func aFileURLIsNotAnImportedAsset() async throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let state = AppState()
        let local = ImportedStoreAsset(locale: "en-US", kind: "icon",
                                       url: URL(fileURLWithPath: "/etc/hosts"),
                                       fileName: "hosts")

        let failures = await state.materializeImportedAssets(
            [local], store: .apple, root: folder).failures

        #expect(failures.count == 1)
        #expect(!FileManager.default.fileExists(
            atPath: folder.appendingPathComponent("Store Import/apple/en-US/icon/hosts").path))
    }

    @MainActor
    @Test func aPreexistingSymlinkCannotRedirectAnImportedAsset() async throws {
        URLProtocol.registerClass(AssetStubProtocol.self)
        defer { URLProtocol.unregisterClass(AssetStubProtocol.self) }
        AssetStubProtocol.status = 200
        let folder = try scratchFolder()
        let outside = try scratchFolder()
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: outside)
        }
        let parent = folder.appendingPathComponent("Store Import/apple/en-US")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: parent.appendingPathComponent("icon"), withDestinationURL: outside)
        let state = AppState()
        let failures = await state.materializeImportedAssets(
            [asset("icon", "agent.plist")], store: .apple, root: folder).failures

        #expect(failures.count == 1)
        #expect(!FileManager.default.fileExists(
            atPath: outside.appendingPathComponent("agent.plist").path))
    }

    @MainActor
    @Test func legacyImportedMediaIsRemovedButChosenMediaStays() {
        var manifest = Manifest()
        manifest.addMediaPaths(
            ["Store Import/apple/en-US/APP_IPHONE_69/live.png", "shots/new.png"],
            locale: "en-US", deviceClass: .phone)
        manifest.media?.icon = "Store Import/google/en-US/icon/icon.png"

        manifest.removeImportedMedia()

        #expect(manifest.mediaPaths(locale: "en-US", deviceClass: .phone) == ["shots/new.png"])
        #expect(manifest.media?.icon == nil)
    }
}

// MARK: - Sending back what the store already showed

/// The import downloads every live screenshot, and the manifest kept them out
/// on purpose, so there was no way to say "send these again". A developer whose
/// set left the store, and who had no other copy, had them in the project
/// folder with no route back.
@Test func theDownloadedLiveScreenshotsCanGoBackToTheStore() async throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("resend-\(UUID().uuidString)", isDirectory: true)
    let size = folder.appendingPathComponent("Store Import/apple/en-US/APP_IPHONE_67",
                                             isDirectory: true)
    try FileManager.default.createDirectory(at: size, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    // Out of order on disk, so the numeric prefix is what settles the order.
    for name in ["10-shot.png", "2-shot.png", "1-shot.png"] {
        try Data([0x89]).write(to: size.appendingPathComponent(name))
    }
    // A preview sits beside them. Apple serves previews as an HLS stream, so
    // what the import saved is the playlist and never the film.
    try Data([0x89]).write(to: size.appendingPathComponent("1-trailer.mov"))
    // Another page's pictures are in a folder of their own and belong to it.
    let page = folder.appendingPathComponent(
        "Store Import/apple/pages/Bakers/en-US/APP_IPHONE_67", isDirectory: true)
    try FileManager.default.createDirectory(at: page, withIntermediateDirectories: true)
    try Data([0x89]).write(to: page.appendingPathComponent("1-bakers.png"))

    let state = await AppState()
    await MainActor.run {
        state.manifestURL = folder.appendingPathComponent("store.yaml")
        state.locale = "en-US"
    }

    let found = await state.resendableLiveMedia(deviceClass: .phone)

    #expect(found.map(\.lastPathComponent) == ["1-shot.png", "2-shot.png", "10-shot.png"])
    #expect(!found.contains { $0.pathExtension == "mov" })
    #expect(!found.contains { $0.lastPathComponent.contains("bakers") })
}

/// A size this app never downloaded says so, rather than filling the bucket
/// with nothing and reading as done.
@Test func aSizeWithNoDownloadedCopySaysSo() async throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("resend-empty-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let state = await AppState()
    await MainActor.run {
        state.manifestURL = folder.appendingPathComponent("store.yaml")
        state.locale = "en-US"
        state.resendLiveMedia(deviceClass: .phone)
    }

    let message = await state.mediaError
    #expect(message?.contains("no downloaded copy") == true)
    #expect(await state.mediaPaths(deviceClass: .phone).isEmpty)
}
