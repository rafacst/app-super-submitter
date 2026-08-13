import CryptoKit
import Foundation
import Testing
@testable import SubmitKit

/// Records every path the reader asks for and answers each one with an empty
/// document, so the test is about the requests and nothing else.
private final class RecordingProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var seen: [String] = []
    private static let lock = NSLock()

    static func start() { lock.withLock { seen = [] } }
    static var paths: [String] { lock.withLock { seen } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.lock.withLock { Self.seen.append(url.path + (url.query.map { "?\($0)" } ?? "")) }
        let response = HTTPURLResponse(url: url, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"data":[]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// App Store Connect fills the `data` of a to-one relationship only for the
/// relationships a request includes, and it rejects an include it does not
/// know. Both halves of that rule cost this app a bug on the same day: the
/// categories read nil on every app because nothing asked for them, and the
/// whole App Store read died on an HTTP 400 because something asked for
/// `manualPrices.appPricePoint`, which is not a relationship name.
@Suite(.serialized)
struct AppleIncludeTests {
    private func api() -> StoreAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingProtocol.self]
        let credential = AppleCredential(
            keyID: "ABCD123456", issuerID: "issuer",
            privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation,
            fileName: "AuthKey_ABCD123456.p8")
        return StoreAPI(credentials: StoreCredentials(apple: credential), record: { _ in },
                        session: URLSession(configuration: configuration))
    }

    @Test func theStateReadAsksForTheCategoriesItThenReads() async throws {
        RecordingProtocol.start()
        _ = try await StateReader(api: api()).readApple(appID: "1")

        let appInfos = RecordingProtocol.paths.filter { $0.contains("/appInfos?") }
        #expect(!appInfos.isEmpty, "The read never asked for the app infos.")
        #expect(appInfos.allSatisfy {
            $0.contains("include=primaryCategory,secondaryCategory")
        }, "The categories are relationships, so the request has to include them.")

        // The include Apple refuses. It aborted the whole App Store read, and
        // every field of a listing the store already held was then drawn as
        // an add.
        #expect(!RecordingProtocol.paths.contains { $0.contains("manualPrices.appPricePoint") })
    }

    /// The platform as well as the language. One app id carries a train per
    /// platform and each has its own approved Keywords field, so Apple keeps a
    /// pool per platform and refuses a read that names none: "Filter 'platform'
    /// is required for this operation", which read as a fault in this app.
    @Test func searchKeywordsCarryTheSelectedPlatformAndLocale() async throws {
        RecordingProtocol.start()

        _ = try await AppleKeywordsClient(api: api())
            .pool(appID: "1", locale: "pt-BR", platform: "MAC_OS")

        #expect(RecordingProtocol.paths == [
            "/v1/apps/1/searchKeywords?filter%5Bplatform%5D=MAC_OS"
                + "&filter%5Blocale%5D=pt-BR&limit=200",
        ])
    }
}
