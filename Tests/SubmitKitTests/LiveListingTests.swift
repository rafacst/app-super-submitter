import CryptoKit
import Foundation
import Testing
@testable import SubmitKit

/// Answers the routes it is given and an empty document for everything else,
/// so a test names only the payloads it cares about.
private final class LiveStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var routes: [String: String] = [:]
    private static let lock = NSLock()

    static func configure(_ routes: [String: String]) {
        lock.withLock { Self.routes = routes }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let path = url.path + (url.query.map { "?\($0)" } ?? "")
        let body = Self.lock.withLock {
            Self.routes.filter { path.hasSuffix($0.key) }
                .max { $0.key.count < $1.key.count }?.value
        }
        let response = HTTPURLResponse(url: url, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((body ?? #"{"data":[]}"#).utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// What the customer reads, beside what the app is about to write.
///
/// The bug this guards: the state read took the editable version and nothing
/// else. App Store Connect creates that version empty, and so does this app's
/// own apply, so the read reported an app with no description while its store
/// page was full. The import already looked at both versions; the read did
/// not, and the two disagreed about the same app.
@Suite(.serialized)
struct LiveListingTests {
    private func reader() -> StateReader {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LiveStubProtocol.self]
        let credential = AppleCredential(
            keyID: "ABCD123456", issuerID: "issuer",
            privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation,
            fileName: "AuthKey_ABCD123456.p8")
        return StateReader(api: StoreAPI(credentials: StoreCredentials(apple: credential),
                                          record: { _ in },
                                          session: URLSession(configuration: configuration)))
    }

    @Test func theReadSeesTheLiveTextWithoutLettingItReachThePlan() async throws {
        LiveStubProtocol.configure([
            "/v1/apps/7/appStoreVersions?limit=200": """
            {"data":[{"id":"v-draft","attributes":{"versionString":"1.5",
                      "appVersionState":"PREPARE_FOR_SUBMISSION"}},
                     {"id":"v-live","attributes":{"versionString":"1.4",
                      "appVersionState":"READY_FOR_DISTRIBUTION"}},
                     {"id":"v-old","attributes":{"versionString":"1.0",
                      "appVersionState":"REPLACED_WITH_NEW_VERSION"}}]}
            """,
            // The shape the real account was in: the draft carries the
            // keywords it inherited and not one word of the description.
            "/v1/appStoreVersions/v-draft/appStoreVersionLocalizations?limit=200": """
            {"data":[{"id":"vl-draft","attributes":{"locale":"en-US","description":"",
                      "keywords":"atproto,deck,columns"}}]}
            """,
            "/v1/appStoreVersions/v-live/appStoreVersionLocalizations?limit=200": """
            {"data":[{"id":"vl-live","attributes":{"locale":"en-US",
                      "description":"DeckDeckDeck turns Bluesky into a deck of live columns.",
                      "whatsNew":"A secret menu.","keywords":"old,keywords"}}]}
            """,
        ])

        let apple = try await reader().readApple(appID: "7")

        // The write target is the draft and only the draft. A live version is
        // the listing the customers are reading, and the runner must never
        // hold its id.
        #expect(apple.versionId == "v-draft")
        #expect(apple.liveVersionString == "1.4")

        // The plan still diffs against the draft, so the description it holds
        // stays the empty one and the run writes the words.
        #expect(apple.versionLocales["en-US"]?.description == "")
        #expect(apple.versionLocales["en-US"]?.keywords == "atproto,deck,columns")

        // And the words the customer reads are now on hand for the tabs.
        #expect(apple.liveVersionLocales["en-US"]?.description
            == "DeckDeckDeck turns Bluesky into a deck of live columns.")
        #expect(apple.liveVersionLocales["en-US"]?.whatsNew == "A secret menu.")
    }

    /// An app with no live version reads exactly as it did before, so a first
    /// submission gains no second picture and no second request.
    @Test func aFirstSubmissionHasNoLiveText() async throws {
        LiveStubProtocol.configure([
            "/v1/apps/8/appStoreVersions?limit=200": """
            {"data":[{"id":"v-draft","attributes":{"versionString":"1.0",
                      "appVersionState":"PREPARE_FOR_SUBMISSION"}}]}
            """,
            "/v1/appStoreVersions/v-draft/appStoreVersionLocalizations?limit=200": """
            {"data":[{"id":"vl","attributes":{"locale":"en-US","description":"The first one."}}]}
            """,
        ])

        let apple = try await reader().readApple(appID: "8")

        #expect(apple.liveVersionString == nil)
        #expect(apple.liveVersionLocales.isEmpty)
        #expect(apple.versionLocales["en-US"]?.description == "The first one.")
    }
}
