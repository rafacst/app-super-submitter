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
            "/v1/apps/123/appInfos?limit=200&include=primaryCategory,secondaryCategory": """
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
        // The categories are relationships, and App Store Connect fills the
        // `data` of a to-one relationship only for the ones the request
        // includes. Without the include the category read nil on every real
        // app while a stub that always answers it stayed green.
        #expect(ImportStubProtocol.state.requested.contains {
            $0.contains("appInfos") && $0.contains("include=primaryCategory,secondaryCategory")
        })
        #expect(listing.review.contactEmail == "a@example.com")
        #expect(listing.review.notes == "Sign in with the demo account.")
        #expect(listing.purchases.map(\.id) == ["com.example.pro"])
        // The reads that answered 404 cost their own block and nothing else.
        #expect(!listing.failures.isEmpty)
    }

    /// The bug this guards, and it is the same bug one turn further on. The
    /// import preferred the editable version, which was right, and then took
    /// it literally, which was not. An editable version can be an empty
    /// shell: App Store Connect creates one with no text and no screenshots,
    /// and so does this app's own apply. A store page with 3699 characters of
    /// description and five screenshots imported as a blank Details tab and
    /// an empty Media tab, and nothing said why.
    @Test func anEmptyDraftFallsBackToWhatTheStoreShowsToday() async throws {
        ImportStubProtocol.state.configure([
            "/v1/apps/7": #"{"data":{"attributes":{"primaryLocale":"en-US","bundleId":"com.example.app"}}}"#,
            "/v1/apps/7/appInfos?limit=200&include=primaryCategory,secondaryCategory": """
            {"data":[{"id":"info","attributes":{"appStoreState":"PREPARE_FOR_SUBMISSION"}}]}
            """,
            "/v1/appInfos/info/appInfoLocalizations?limit=200": """
            {"data":[{"id":"il","attributes":{"locale":"en-US","name":"DeckDeckDeck",
                      "subtitle":"Social client for Bluesky"}}]}
            """,
            "/v1/apps/7/appStoreVersions?limit=200": """
            {"data":[{"id":"v-draft","attributes":{"versionString":"1.2",
                      "appVersionState":"PREPARE_FOR_SUBMISSION"}},
                     {"id":"v-live","attributes":{"versionString":"1.4",
                      "appVersionState":"READY_FOR_SALE"}}]}
            """,
            // The draft carries the keywords and the URLs and nothing else,
            // which is exactly the shape the real account was in.
            "/v1/appStoreVersions/v-draft/appStoreVersionLocalizations?limit=200": """
            {"data":[{"id":"vl-draft","attributes":{"locale":"en-US","description":"",
                      "keywords":"atproto,deck,columns",
                      "supportUrl":"https://example.com/support"}}]}
            """,
            "/v1/appStoreVersions/v-live/appStoreVersionLocalizations?limit=200": """
            {"data":[{"id":"vl-live","attributes":{"locale":"en-US",
                      "description":"DeckDeckDeck turns Bluesky into a deck of live columns.",
                      "whatsNew":"A secret menu.","keywords":"old,keywords",
                      "marketingUrl":"https://example.com/"}}]}
            """,
            "/v1/appStoreVersionLocalizations/vl-live/appScreenshotSets?include=appScreenshots&limit=50": """
            {"data":[{"id":"set","attributes":{"screenshotDisplayType":"APP_DESKTOP"},
                      "relationships":{"appScreenshots":{"data":[
                        {"type":"appScreenshots","id":"s1"}]}}}],
             "included":[{"type":"appScreenshots","id":"s1","links":{"self":"x"},
                          "attributes":{"fileName":"one.png",
                            "imageAsset":{"templateUrl":"https://example.com/{w}x{h}.{f}",
                                          "width":2880,"height":1800}}}]}
            """,
        ])

        let listing = try await StoreImportReader(
            credentials: StoreCredentials(apple: testCredential()),
            session: importStubSession()).apple(appID: "7")

        // The number stays the one the developer is about to submit.
        #expect(listing.versionName == "1.2")
        // The words come from the version that has them.
        #expect(listing.locales["en-US"]?.description
            == "DeckDeckDeck turns Bluesky into a deck of live columns.")
        #expect(listing.locales["en-US"]?.whatsNew == "A secret menu.")
        // The draft still wins wherever it says something of its own.
        #expect(listing.locales["en-US"]?.keywords == "atproto,deck,columns")
        #expect(listing.locales["en-US"]?.supportURL == "https://example.com/support")
        #expect(listing.locales["en-US"]?.marketingURL == "https://example.com/")
        // The screenshots the customer sees today, on a draft that has none.
        #expect(listing.assets.count == 1)
        #expect(listing.assets.first?.deviceClass == .desktop)
    }

    @Test func anImportedListingFillsTheManifestTheDetailsTabReads() async throws {
        ImportStubProtocol.state.configure([
            "/v1/apps/9": #"{"data":{"attributes":{"primaryLocale":"en-US","bundleId":"com.example.app"}}}"#,
            "/v1/apps/9/appInfos?limit=200&include=primaryCategory,secondaryCategory": #"{"data":[{"id":"i"}]}"#,
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

/// The payload shape App Store Connect really answers with.
///
/// Captured from `/v1/appStoreVersionLocalizations/{id}/appScreenshotSets`
/// `?include=appScreenshots` against a live app. The set lists its members
/// under `relationships.appScreenshots.data`, and every included screenshot
/// carries `type`, `id`, `attributes`, and `links` and **no** `relationships`
/// key. The reader used to ask each included row which set it belonged to,
/// so it matched nothing and dropped all five shots of a full store page
/// without a word.
struct AppleAssetShapeTests {
    private let realPayload = """
    {"data":[{"type":"appScreenshotSets","id":"set-desktop",
              "attributes":{"screenshotDisplayType":"APP_DESKTOP"},
              "relationships":{"appScreenshots":{"meta":{"paging":{"total":2,"limit":50}},
                "data":[{"type":"appScreenshots","id":"a"},
                        {"type":"appScreenshots","id":"b"}]}}}],
     "included":[
       {"type":"appScreenshots","id":"a","links":{"self":"x"},
        "attributes":{"fileName":"01-home.png","sourceFileChecksum":"aaa",
          "imageAsset":{"templateUrl":"https://example.com/a/{w}x{h}.{f}",
                        "width":2880,"height":1800}}},
       {"type":"appScreenshots","id":"b","links":{"self":"x"},
        "attributes":{"fileName":"02-explore.png","sourceFileChecksum":"bbb",
          "imageAsset":{"templateUrl":"https://example.com/b/{w}x{h}.{f}",
                        "width":2880,"height":1800}}}]}
    """

    @Test func everyScreenshotOfASetSurvivesTheRealPayload() {
        let assets = StoreImportReader.appleAssets(
            JSON(data: Data(realPayload.utf8)), locale: "en-US",
            itemType: "appScreenshots", kindKey: "screenshotDisplayType")

        #expect(assets.count == 2)
        #expect(assets.allSatisfy { $0.kind == "APP_DESKTOP" })
        #expect(assets.allSatisfy { $0.locale == "en-US" })
        // A Mac screenshot has to reach the tab's Desktop group.
        #expect(assets.allSatisfy { $0.deviceClass == .desktop })
        // The position leads the name, so two shots that share a name inside
        // one set still become two files.
        #expect(assets.map(\.fileName) == ["1-01-home.png", "2-02-explore.png"])
        // The `{w}` `{h}` `{f}` template is expanded, so the tile can load it.
        #expect(assets.contains { $0.url.absoluteString == "https://example.com/a/2880x1800.png" })
    }

    /// The app picker learns the platforms from the app's own relationship.
    /// The included version rows carry no `relationships` key, and reading
    /// only those left every app with no platform, so the import fell back on
    /// its iPhone guess and wrote a Mac app into `store.yaml` as an iOS app.
    @Test func thePickerReadsBothPlatformsOfAUniversalApp() throws {
        let payload = """
        {"data":[{"id":"app-1","attributes":{"name":"DeckDeckDeck",
                  "bundleId":"com.example.deck"},
                  "relationships":{"appStoreVersions":{"data":[
                    {"type":"appStoreVersions","id":"v-ios"},
                    {"type":"appStoreVersions","id":"v-mac"}]}}}],
         "included":[
           {"type":"appStoreVersions","id":"v-ios","attributes":{"platform":"IOS"}},
           {"type":"appStoreVersions","id":"v-mac","attributes":{"platform":"MAC_OS"}}]}
        """
        let decoded = try JSONDecoder().decode(AppleAppsResponse.self,
                                               from: Data(payload.utf8))

        let platforms = StoreConnectionClient.platforms(decoded.included ?? [],
                                                        apps: decoded.data)

        #expect(platforms["app-1"] == [.ios, .macOS])
    }
}

/// Apple lets two screenshots of one set carry the same name.
///
/// The import writes one file per name under
/// `Store Import/apple/<locale>/<display type>/`, so two `09-profile.png`
/// became one file and the tab lost three of five live screenshots.
struct DuplicateScreenshotNameTests {
    @Test func twoShotsThatShareANameStayTwoFiles() {
        let payload = """
        {"data":[{"type":"appScreenshotSets","id":"set",
                  "attributes":{"screenshotDisplayType":"APP_DESKTOP"},
                  "relationships":{"appScreenshots":{"data":[
                    {"type":"appScreenshots","id":"a"},
                    {"type":"appScreenshots","id":"b"}]}}}],
         "included":[
           {"type":"appScreenshots","id":"a",
            "attributes":{"fileName":"09-profile.png","sourceFileChecksum":"one",
              "imageAsset":{"templateUrl":"https://example.com/a/{w}x{h}.{f}",
                            "width":2880,"height":1800}}},
           {"type":"appScreenshots","id":"b",
            "attributes":{"fileName":"09-profile.png","sourceFileChecksum":"two",
              "imageAsset":{"templateUrl":"https://example.com/b/{w}x{h}.{f}",
                            "width":2880,"height":1800}}}]}
        """
        let assets = StoreImportReader.appleAssets(
            JSON(data: Data(payload.utf8)), locale: "en-US",
            itemType: "appScreenshots", kindKey: "screenshotDisplayType")

        #expect(assets.count == 2)
        #expect(Set(assets.map(\.fileName)).count == 2)
        #expect(Set(assets.map(\.url)).count == 2)
    }
}
