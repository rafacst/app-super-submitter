import CryptoKit
import Foundation
import Testing
@testable import SubmitKit

private final class ImportStubState: @unchecked Sendable {
    private let lock = NSLock()
    private var routes: [String: String] = [:]
    private var seen: [String] = []

    func configure(_ routes: [String: String]) {
        lock.withLock {
            self.routes = routes
            seen = []
        }
    }

    /// The longest matching suffix wins, so a route may name only the tail of
    /// a path and still beat a shorter one.
    func body(for path: String) -> String? {
        lock.withLock {
            seen.append(path)
            return routes.filter { path.hasSuffix($0.key) }
                .max { $0.key.count < $1.key.count }?.value
        }
    }

    var requested: [String] { lock.withLock { seen } }
}

private final class ImportStubProtocol: URLProtocol, @unchecked Sendable {
    static let state = ImportStubState()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let path = url.path + (url.query.map { "?\($0)" } ?? "")
        let body = Self.state.body(for: path)
        let response = HTTPURLResponse(url: url, statusCode: body == nil ? 404 : 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((body ?? #"{"errors":[]}"#).utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func importStubSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ImportStubProtocol.self]
    return URLSession(configuration: configuration)
}

private func testCredential() -> AppleCredential {
    AppleCredential(keyID: "ABC123DEFG", issuerID: "issuer",
                    privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation,
                    fileName: "AuthKey_ABC123DEFG.p8")
}

@Suite(.serialized)
struct StoreImportReaderTests {
    /// The bug this guards: `limit=1` took whichever version App Store Connect
    /// listed first. The live version carries no editable text, so the Details
    /// tab opened with an empty description on an app that has one.
    @Test func theImportReadsTheEditableVersionAndNotTheFirstOneListed() async throws {
        ImportStubProtocol.state.configure([
            "/v1/apps/123": #"{"data":{"attributes":{"primaryLocale":"pt-BR","bundleId":"com.example.app"}}}"#,
            "/v1/apps/123/appInfos?limit=200": """
            {"data":[{"id":"info-live","attributes":{"appStoreState":"READY_FOR_SALE"}},
                     {"id":"info-edit","attributes":{"appStoreState":"PREPARE_FOR_SUBMISSION"},
                      "relationships":{"primaryCategory":{"data":{"id":"SOCIAL_NETWORKING"}}}}]}
            """,
            "/v1/appInfos/info-edit/appInfoLocalizations?limit=200": """
            {"data":[{"id":"il-1","attributes":{"locale":"pt-BR","name":"DeckDeckDeck",
                      "subtitle":"Cliente Bluesky","privacyPolicyUrl":"https://example.com/p"}}]}
            """,
            "/v1/apps/123/appStoreVersions?limit=200": """
            {"data":[{"id":"v-live","attributes":{"versionString":"1.0",
                      "appVersionState":"READY_FOR_SALE"}},
                     {"id":"v-edit","attributes":{"versionString":"2.4","releaseType":"MANUAL",
                      "appVersionState":"PREPARE_FOR_SUBMISSION"}}]}
            """,
            "/v1/appStoreVersions/v-edit/appStoreVersionLocalizations?limit=200": """
            {"data":[{"id":"vl-1","attributes":{"locale":"pt-BR","description":"A descricao completa",
                      "whatsNew":"Correcoes","keywords":"bluesky,social",
                      "supportUrl":"https://example.com/s"}}]}
            """,
            "/v1/appStoreVersions/v-edit/appStoreReviewDetail": """
            {"data":{"attributes":{"contactFirstName":"Rafael","contactEmail":"a@example.com",
                     "demoAccountRequired":false,"notes":"Sign in with the demo account."}}}
            """,
            "/v1/apps/123/inAppPurchasesV2?limit=200": """
            {"data":[{"attributes":{"productId":"com.example.pro","name":"Pro",
                      "inAppPurchaseType":"NON_CONSUMABLE"}}]}
            """,
        ])

        let listing = try await StoreImportReader(
            credentials: StoreCredentials(apple: testCredential()),
            session: importStubSession()).apple(appID: "123")

        #expect(listing.versionName == "2.4")
        #expect(listing.defaultLocale == "pt-BR")
        #expect(listing.bundleID == "com.example.app")
        #expect(listing.locales["pt-BR"]?.description == "A descricao completa")
        #expect(listing.locales["pt-BR"]?.name == "DeckDeckDeck")
        #expect(listing.locales["pt-BR"]?.whatsNew == "Correcoes")
        #expect(listing.locales["pt-BR"]?.keywords == "bluesky,social")
        #expect(listing.locales["pt-BR"]?.privacyPolicyURL == "https://example.com/p")
        #expect(listing.review.applePrimaryCategory == "SOCIAL_NETWORKING")
        #expect(listing.review.contactEmail == "a@example.com")
        #expect(listing.review.notes == "Sign in with the demo account.")
        #expect(listing.purchases.map(\.id) == ["com.example.pro"])
        // The reads that answered 404 cost their own block and nothing else.
        #expect(!listing.failures.isEmpty)
        #expect(!ImportStubProtocol.state.requested.contains {
            $0.contains("/v1/appStoreVersions/v-live/")
        })
    }

    @Test func anImportedListingFillsTheManifestTheDetailsTabReads() async throws {
        ImportStubProtocol.state.configure([
            "/v1/apps/9": #"{"data":{"attributes":{"primaryLocale":"en-US","bundleId":"com.example.app"}}}"#,
            "/v1/apps/9/appInfos?limit=200": #"{"data":[{"id":"i"}]}"#,
            "/v1/appInfos/i/appInfoLocalizations?limit=200": """
            {"data":[{"id":"il","attributes":{"locale":"en-US","name":"Example",
                      "subtitle":"A subtitle"}}]}
            """,
            "/v1/apps/9/appStoreVersions?limit=200": #"{"data":[{"id":"v","attributes":{"versionString":"3.1"}}]}"#,
            "/v1/appStoreVersions/v/appStoreVersionLocalizations?limit=200": """
            {"data":[{"id":"vl","attributes":{"locale":"en-US","description":"The description",
                      "supportUrl":"https://example.com/s"}}]}
            """,
        ])

        let listing = try await StoreImportReader(
            credentials: StoreCredentials(apple: testCredential()),
            session: importStubSession()).apple(appID: "9")
        var manifest = Manifest()
        manifest.setAppleApp(appID: "9", bundleID: listing.bundleID ?? "")
        manifest.mergeAppleImport(listing)

        #expect(manifest.listing?.defaultLocale == "en-US")
        #expect(manifest.listingText(locale: "en-US", field: .description) == "The description")
        #expect(manifest.listingText(locale: "en-US", field: .subtitle) == "A subtitle")
        #expect(manifest.listingText(locale: "en-US", field: .supportURL) == "https://example.com/s")
        #expect(manifest.release?.versionName == "3.1")
    }
}
