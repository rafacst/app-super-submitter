import CryptoKit
import Foundation
import Testing
@testable import SubmitKit

/// The App Store serves more than one product page for an app, and this app
/// read only the version's own. A developer running four custom pages and a
/// test saw none of them, and had to open App Store Connect to answer what any
/// of them shows.

private final class PagesStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var seen: [String] = []
    private static let lock = NSLock()

    /// The paths the walk asked for, so a test can prove it went the whole way
    /// down rather than stopping at the first level.
    static var paths: [String] { lock.withLock { seen } }

    /// Set `brokenPage` to answer one custom page's versions with a 403, the
    /// way a key without the right role would.
    nonisolated(unsafe) static var brokenPage = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private static func body(_ path: String) -> (Int, String) {
        switch path {
        case "/v1/apps/app-1/appCustomProductPages":
            (200, #"""
            {"data":[
              {"id":"page-1","type":"appCustomProductPages",
               "attributes":{"name":"Bakers","visible":true}},
              {"id":"page-2","type":"appCustomProductPages",
               "attributes":{"name":"Chefs","visible":false}}
            ]}
            """#)
        case "/v1/appCustomProductPages/page-1/appCustomProductPageVersions":
            (200, #"{"data":[{"id":"page-version-1","type":"appCustomProductPageVersions"}]}"#)
        case "/v1/appCustomProductPages/page-2/appCustomProductPageVersions":
            brokenPage
                ? (403, #"{"errors":[{"status":"403","title":"FORBIDDEN_ERROR"}]}"#)
                : (200, #"{"data":[{"id":"page-version-2","type":"appCustomProductPageVersions"}]}"#)
        case "/v1/appCustomProductPageVersions/page-version-1/appCustomProductPageLocalizations":
            (200, #"{"data":[{"id":"page-locale-1","attributes":{"locale":"pt-BR"}}]}"#)
        case "/v1/appCustomProductPageVersions/page-version-2/appCustomProductPageLocalizations":
            (200, #"{"data":[{"id":"page-locale-2","attributes":{"locale":"pt-BR"}}]}"#)
        case "/v1/appCustomProductPageLocalizations/page-locale-1/appScreenshotSets":
            (200, screenshots(setID: "set-1", shotID: "shot-1", name: "bakers.png"))
        case "/v1/appCustomProductPageLocalizations/page-locale-2/appScreenshotSets":
            (200, screenshots(setID: "set-2", shotID: "shot-2", name: "chefs.png"))

        case "/v1/apps/app-1/appStoreVersionExperimentsV2":
            (200, #"""
            {"data":[{"id":"exp-1","type":"appStoreVersionExperiments",
                      "attributes":{"name":"PPO 2026-06","state":"COMPLETED"}}]}
            """#)
        case "/v2/appStoreVersionExperiments/exp-1/appStoreVersionExperimentTreatments":
            (200, #"""
            {"data":[{"id":"treatment-1","attributes":{"name":"Treatment B"}}]}
            """#)
        case "/v1/appStoreVersionExperimentTreatments/treatment-1"
            + "/appStoreVersionExperimentTreatmentLocalizations":
            (200, #"{"data":[{"id":"treat-locale-1","attributes":{"locale":"pt-BR"}}]}"#)
        case "/v1/appStoreVersionExperimentTreatmentLocalizations/treat-locale-1"
            + "/appScreenshotSets":
            (200, screenshots(setID: "set-3", shotID: "shot-3", name: "treatment.png"))
        default:
            (200, #"{"data":[]}"#)
        }
    }

    private static func screenshots(setID: String, shotID: String, name: String) -> String {
        """
        {"data":[{"id":"\(setID)","type":"appScreenshotSets",
                  "attributes":{"screenshotDisplayType":"APP_IPHONE_65"},
                  "relationships":{"appScreenshots":{"data":[{"id":"\(shotID)"}]}}}],
         "included":[{"id":"\(shotID)","type":"appScreenshots",
                      "attributes":{"fileName":"\(name)",
                                    "imageAsset":{"templateUrl":"https://example.com/{w}x{h}{f}",
                                                  "width":1242,"height":2688}}}]}
        """
    }

    override func startLoading() {
        let url = request.url!
        Self.lock.withLock { Self.seen.append(url.path) }
        let (status, body) = Self.body(url.path)
        let response = HTTPURLResponse(url: url, statusCode: status,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func start(broken: Bool = false) {
        lock.withLock { seen = [] }
        brokenPage = broken
    }
}

private func pagesReader() -> AppleProductPages {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PagesStubProtocol.self]
    let credential = AppleCredential(
        keyID: "ABCD123456", issuerID: "issuer",
        privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation,
        fileName: "AuthKey_ABCD123456.p8")
    return AppleProductPages(api: StoreAPI(
        credentials: StoreCredentials(apple: credential), record: { _ in },
        session: URLSession(configuration: configuration)))
}

@Suite(.serialized)
struct AppleProductPageTests {
    @Test func everyCustomPageAndTreatmentComesBackWithItsOwnPictures() async {
        PagesStubProtocol.start()
        let pages = await pagesReader().read(appID: "app-1")

        #expect(pages.map(\.name) == ["Bakers", "Chefs", "Treatment B"])
        #expect(pages.map(\.status) == ["Visible", "Hidden", "Completed"])
        #expect(pages.allSatisfy { $0.assets.count == 1 })
        #expect(pages[0].assets[0].locale == "pt-BR")
        #expect(pages[0].assets[0].kind == "APP_IPHONE_65")
        #expect(pages[0].detail == "Custom product page")
        #expect(pages[2].detail == "Test · PPO 2026-06")
    }

    /// The walk is four levels deep on each side, and a level it skips is a
    /// page that silently shows nothing.
    @Test func theWalkReachesTheScreenshotsOfBothKindsOfPage() async {
        PagesStubProtocol.start()
        _ = await pagesReader().read(appID: "app-1")

        let paths = PagesStubProtocol.paths
        #expect(paths.contains("/v1/apps/app-1/appCustomProductPages"))
        #expect(paths.contains(
            "/v1/appCustomProductPageLocalizations/page-locale-1/appScreenshotSets"))
        #expect(paths.contains("/v1/apps/app-1/appStoreVersionExperimentsV2"))
        #expect(paths.contains(
            "/v2/appStoreVersionExperiments/exp-1/appStoreVersionExperimentTreatments"))
        #expect(paths.contains(
            "/v1/appStoreVersionExperimentTreatmentLocalizations/treat-locale-1"
                + "/appScreenshotSets"))
    }

    /// This rides along with the store read, and the read plans a submission.
    /// One page the key cannot open costs that one page and nothing else.
    @Test func aPageTheKeyCannotOpenCostsOnlyThatPage() async {
        PagesStubProtocol.start(broken: true)
        let pages = await pagesReader().read(appID: "app-1")

        #expect(pages.map(\.name) == ["Bakers", "Treatment B"])
    }
}
