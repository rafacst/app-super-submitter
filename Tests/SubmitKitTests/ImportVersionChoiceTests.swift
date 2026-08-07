import CryptoKit
import Foundation
import Testing
@testable import SubmitKit

/// Which version the import reads, and what it keeps from the live one.
///
/// The importer took the **first** released record App Store Connect returned,
/// while `StateReader` took the highest. On an app with several released
/// versions the API can answer with an old one first, and then three things
/// went wrong at once and none of them said so:
///
/// 1. `versionName` came back below the version on sale, so the Summary tab
///    reported "1.2 is not above 1.4" about a number nobody had typed.
/// 2. That old record was also `liveVersion`, so the fill from the live
///    version was skipped: the two ids matched.
/// 3. Apple keeps the media on the current version and answers a superseded
///    record with empty screenshot sets, so every read succeeded, no failure
///    was reported, the text arrived, and the Media tab was empty.

/// Three released versions, answered oldest first, and only the newest holds
/// a screenshot.
private final class VersionOrderStub: URLProtocol, @unchecked Sendable {
    static let versions = """
    {"data":[
      {"id":"v-120","type":"appStoreVersions",
       "attributes":{"versionString":"1.2","appVersionState":"READY_FOR_SALE"}},
      {"id":"v-140","type":"appStoreVersions",
       "attributes":{"versionString":"1.4","appVersionState":"READY_FOR_SALE"}},
      {"id":"v-90","type":"appStoreVersions",
       "attributes":{"versionString":"0.9","appVersionState":"REMOVED_FROM_SALE"}}
     ]}
    """

    /// The localizations of whichever version was asked for. Only 1.4 carries
    /// a screenshot, exactly as App Store Connect answers a live app.
    static func localizations(_ versionID: String) -> String {
        """
        {"data":[{"id":"loc-\(versionID)","type":"appStoreVersionLocalizations",
          "attributes":{"locale":"en-US","description":"From \(versionID)."}}]}
        """
    }

    static let screenshots = """
    {"data":[{"id":"set-1","type":"appScreenshotSets",
      "attributes":{"screenshotDisplayType":"APP_DESKTOP"}}],
     "included":[{"id":"shot-1","type":"appScreenshots",
      "attributes":{"fileName":"one.png",
        "imageAsset":{"templateUrl":"https://example.com/{w}x{h}.{f}",
                      "width":2880,"height":1800}},
      "relationships":{"appScreenshotSet":{"data":{"id":"set-1"}}}}]}
    """

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let body: String
        if path.hasSuffix("/appStoreVersions") {
            body = Self.versions
        } else if path.hasSuffix("/appStoreVersionLocalizations") {
            let id = path.split(separator: "/").dropLast().last.map(String.init) ?? ""
            body = Self.localizations(id)
        } else if path.hasSuffix("/appScreenshotSets"), path.contains("loc-v-140") {
            body = Self.screenshots
        } else {
            body = #"{"data":[]}"#
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct ImportVersionChoiceTests {
    private func imported() async throws -> ImportedStoreListing {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VersionOrderStub.self]
        let credential = AppleCredential(
            keyID: "ABCD123456", issuerID: "issuer",
            privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation,
            fileName: "AuthKey_ABCD123456.p8")
        return try await StoreImportReader(credentials: StoreCredentials(apple: credential),
                                           session: URLSession(configuration: configuration))
            .apple(appID: "1")
    }

    @Test func theImportReadsTheHighestReleasedVersion() async throws {
        let listing = try await imported()
        // Not "1.2", which is the first record the API answered with.
        #expect(listing.versionName == "1.4")
    }

    @Test func theScreenshotsOfTheLiveVersionReachTheImport() async throws {
        let listing = try await imported()
        #expect(listing.assets.count == 1, "The live version's screenshot was dropped.")
        #expect(listing.assets.first?.kind == "APP_DESKTOP")
        #expect(listing.assets.first?.deviceClass == .desktop)
    }

    @Test func nothingFailedSoNothingIsReported() async throws {
        // The symptom that made this so hard to see: every read succeeded.
        #expect(try await imported().failures.isEmpty)
    }
}

/// The draft leads field by field and bucket by bucket.
///
/// It used to skip a whole locale once the draft held one asset for it. Apple
/// keeps a screenshot set per display type, so a draft carrying only the
/// desktop set discarded the live phone, tablet, and watch sets with it, and
/// the tab showed one device class of a listing that has five.
@Test func aDraftBucketDoesNotDiscardTheOtherLiveBuckets() {
    func asset(_ kind: String, _ locale: String = "en-US") -> ImportedStoreAsset {
        ImportedStoreAsset(locale: locale, kind: kind,
                           url: URL(string: "https://example.com/\(kind).png")!,
                           fileName: "\(kind).png")
    }
    var draft = StoreImportReader.VersionContent(assets: [asset("APP_DESKTOP")])
    let live = StoreImportReader.VersionContent(
        assets: [asset("APP_DESKTOP"), asset("APP_IPHONE_67"), asset("APP_IPAD_PRO_3GEN_129")])

    draft.fill(from: live)

    let kinds = Set(draft.assets.map(\.kind))
    #expect(kinds == ["APP_DESKTOP", "APP_IPHONE_67", "APP_IPAD_PRO_3GEN_129"])
    // The draft's own desktop set is the one that survives, not the live copy.
    #expect(draft.assets.filter { $0.kind == "APP_DESKTOP" }.count == 1)
}
