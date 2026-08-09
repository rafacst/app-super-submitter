import CryptoKit
import Foundation
import Testing
@testable import SubmitKit

/// Two pages of price points, the way App Store Connect answers a ladder that
/// does not fit in one.
private final class LadderProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var seen: [String] = []
    private static let lock = NSLock()

    static func start() { lock.withLock { seen = [] } }
    static var paths: [String] { lock.withLock { seen } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let path = url.path + (url.query.map { "?\($0)" } ?? "")
        Self.lock.withLock { Self.seen.append(path) }
        let body = path.contains("cursor=two")
            ? #"{"data":[{"id":"c","attributes":{"customerPrice":"9.99"}}]}"#
            : """
              {"data":[{"id":"a","attributes":{"customerPrice":"0.99"}},
                       {"id":"b","attributes":{"customerPrice":"4.99"}}],
               "links":{"next":"https://api.appstoreconnect.apple.com/v1/apps/1/appPricePoints?cursor=two"}}
              """
        let response = HTTPURLResponse(url: url, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Apple offers around 900 price points per territory and answers 200 at a
/// time. Reading one page made the ladder an arbitrary slice: the Monetization
/// picker offered a fraction of the prices, and the apply resolved the
/// developer's amount to the nearest point in that fraction, so a request could
/// ship as the top of page one.
@Suite(.serialized)
struct PricePointPagingTests {
    private func api() -> StoreAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LadderProtocol.self]
        let credential = AppleCredential(
            keyID: "ABCD123456", issuerID: "issuer",
            privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation,
            fileName: "AuthKey_ABCD123456.p8")
        return StoreAPI(credentials: StoreCredentials(apple: credential), record: { _ in },
                        session: URLSession(configuration: configuration))
    }

    @Test func theWholeLadderIsRead() async throws {
        LadderProtocol.start()
        let points = try await ApplePricePoints.all(
            api(), path: "/v1/apps/1/appPricePoints?filter%5Bterritory%5D=USA")

        #expect(points.map(\.id) == ["a", "b", "c"])
        // The filter survives, and the page size is the helper's business.
        #expect(LadderProtocol.paths.first?.contains("filter%5Bterritory%5D=USA") == true)
        #expect(LadderProtocol.paths.first?.contains("limit=200") == true)
        #expect(LadderProtocol.paths.count == 2)

        // The point that page one alone would have got wrong.
        #expect(ApplePricePoints.nearest(points, to: 9)?.id == "c")
    }
}
