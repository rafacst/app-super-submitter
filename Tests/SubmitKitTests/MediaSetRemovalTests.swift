import CryptoKit
import Foundation
import Testing
@testable import SubmitKit

/// The Media tab makes one promise twice: "An empty size keeps what is live",
/// and "Leave this size empty to keep them". The apply did the opposite. It
/// kept the buckets the manifest named and deleted every other set, so a class
/// the developer never filled lost what the App Store was showing, and a locale
/// that named no picture at all lost the lot.

private final class MediaSetStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var deleted: [String] = []
    private static let lock = NSLock()

    static func start() { lock.withLock { deleted = [] } }
    static var deletes: [String] { lock.withLock { deleted } }

    /// One phone set and one iPad set, the shape of an app that ships both.
    private static let sets = """
    {"data":[
      {"id":"set-phone","type":"appScreenshotSets",
       "attributes":{"screenshotDisplayType":"APP_IPHONE_69"}},
      {"id":"set-ipad","type":"appScreenshotSets",
       "attributes":{"screenshotDisplayType":"APP_IPAD_PRO_3GEN_129"}}
    ]}
    """

    private static let previews = """
    {"data":[{"id":"preview-phone","type":"appPreviewSets",
              "attributes":{"previewType":"APP_IPHONE_65"}}]}
    """

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let method = request.httpMethod ?? ""
        if method == "DELETE" {
            Self.lock.withLock { Self.deleted.append(url.path) }
        }
        let body: String
        if url.path.hasSuffix("/appScreenshotSets") {
            body = Self.sets
        } else if url.path.hasSuffix("/appPreviewSets") {
            body = Self.previews
        } else {
            body = #"{"data":[]}"#
        }
        let response = HTTPURLResponse(url: url, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func removalRunner(_ manifest: Manifest) -> Runner {
    MediaSetStub.start()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MediaSetStub.self]
    let credential = AppleCredential(
        keyID: "ABCD123456", issuerID: "issuer",
        privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation,
        fileName: "AuthKey_ABCD123456.p8")
    var manifest = manifest
    manifest.apps.apple?.appId = "app-1"
    // The runner seeds the localization ids from the read, so this is how a
    // test hands it the one the stub answers for.
    var actual = ActualState()
    var apple = ActualState.Apple()
    var locale = ActualState.Apple.VersionLocale()
    locale.id = "vl-1"
    apple.versionLocales["en-US"] = locale
    actual.apple = apple
    return Runner(plan: PlanResult(), manifest: manifest, actual: actual,
                  root: nil, credentials: StoreCredentials(apple: credential),
                  dryRun: false, access: GrantAll(),
                  session: URLSession(configuration: configuration), emit: { _ in })
}

@Suite(.serialized)
struct MediaSetRemovalTests {
    /// The one that took down published screenshots. Every apply writes the
    /// version locale, and the version locale ran this.
    @Test func aLocaleThatNamesNoPictureLosesNothing() async throws {
        let runner = removalRunner(appleManifest())

        try await runner.appleDropEmptyMediaSets("en-US")

        #expect(MediaSetStub.deletes.isEmpty)
    }

    /// A class the manifest does not fill keeps what the store shows, whatever
    /// the run is doing for the classes beside it.
    @Test func aDeviceClassTheManifestDoesNotFillKeepsItsSet() async throws {
        let runner = removalRunner(appleManifest())

        // The phone is being replaced and names no bucket this store holds.
        // The iPad is not being replaced at all.
        try await runner.appleDropMediaSets(
            localizationID: "vl-1", collection: "appScreenshotSets",
            typeKey: "screenshotDisplayType", path: "/v1/appScreenshotSets",
            keeping: [], replacing: [.phone])

        #expect(MediaSetStub.deletes == ["/v1/appScreenshotSets/set-phone"])
    }

    /// And a class the manifest does fill still loses the sets it replaces, or
    /// a developer who swapped every phone screenshot for a new size would
    /// publish both sizes at once.
    @Test func aFilledDeviceClassStillLosesTheSetItReplaces() async throws {
        let runner = removalRunner(appleManifest())

        try await runner.appleDropMediaSets(
            localizationID: "vl-1", collection: "appScreenshotSets",
            typeKey: "screenshotDisplayType", path: "/v1/appScreenshotSets",
            keeping: ["APP_IPHONE_65"], replacing: [.phone, .tablet10])

        // 69 is not the bucket the manifest resolved to, and the phone is being
        // replaced, so it goes. The iPad set goes for the same reason.
        #expect(Set(MediaSetStub.deletes) == ["/v1/appScreenshotSets/set-phone",
                                              "/v1/appScreenshotSets/set-ipad"])
    }

    /// A bucket the manifest named is the set being written, so it stays.
    @Test func theBucketTheManifestNamedIsKept() async throws {
        let runner = removalRunner(appleManifest())

        try await runner.appleDropMediaSets(
            localizationID: "vl-1", collection: "appScreenshotSets",
            typeKey: "screenshotDisplayType", path: "/v1/appScreenshotSets",
            keeping: ["APP_IPHONE_69"], replacing: [.phone])

        #expect(MediaSetStub.deletes.isEmpty)
    }

    /// Nothing filled means nothing to replace, and the request is not even
    /// made. A read that fails must never read as "the store holds none".
    @Test func nothingFilledAsksTheStoreNothing() async throws {
        let runner = removalRunner(appleManifest())

        try await runner.appleDropMediaSets(
            localizationID: "vl-1", collection: "appScreenshotSets",
            typeKey: "screenshotDisplayType", path: "/v1/appScreenshotSets",
            keeping: [], replacing: [])

        #expect(MediaSetStub.deletes.isEmpty)
    }
}
