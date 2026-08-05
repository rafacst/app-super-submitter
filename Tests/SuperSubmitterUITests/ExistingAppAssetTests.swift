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
            [asset("APP_IPHONE_69", "shot-1.png")], store: .apple, root: folder,
            manifest: &manifest)

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
    @Test func aDownloadedScreenshotReachesTheBucketOfItsDisplayType() async throws {
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
            store: .apple, root: folder, manifest: &manifest)

        #expect(failures.isEmpty)
        let shots = manifest.mediaPaths(locale: "en-US", deviceClass: .phone)
        #expect(shots.count == 2)
        #expect(shots.allSatisfy(AppState.isImported))
        #expect(FileManager.default.fileExists(
            atPath: folder.appendingPathComponent(shots[0]).path))
        // Apple names a preview bucket after the same display type as a
        // screenshot, so only the file tells the two apart. A video in the
        // screenshot list fails validation on a tab that never mentions it.
        #expect(manifest.mediaPaths(locale: "en-US", deviceClass: .phone, previews: true)
            == ["Store Import/apple/en-US/APP_IPHONE_69/trailer.mov"])
    }
}
