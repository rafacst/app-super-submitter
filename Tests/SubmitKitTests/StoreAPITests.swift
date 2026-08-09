import CryptoKit
import Foundation
import Testing
@testable import SubmitKit

private final class URLProtocolState: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var responder: @Sendable (URLRequest, Int) throws -> (HTTPURLResponse, Data) = {
        request, _ in
        (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil,
                         headerFields: nil)!, Data())
    }

    func configure(_ responder: @escaping @Sendable (URLRequest, Int) throws
                   -> (HTTPURLResponse, Data)) {
        lock.withLock {
            count = 0
            self.responder = responder
        }
    }

    func respond(to request: URLRequest) throws -> (HTTPURLResponse, Data) {
        let value = lock.withLock { () -> (Int, @Sendable (URLRequest, Int) throws
                                            -> (HTTPURLResponse, Data)) in
            count += 1
            return (count, responder)
        }
        return try value.1(request, value.0)
    }

    var requestCount: Int { lock.withLock { count } }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    static let state = URLProtocolState()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try Self.state.respond(to: request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func stubSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: configuration)
}

@Suite(.serialized)
struct StoreAPIRetryTests {
    @Test func aNonIdempotentPostIsNotRetriedAfterAServerFailure() async {
        StubURLProtocol.state.configure { request, _ in
            (HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil,
                             headerFields: ["Retry-After": "0"])!, Data("failed".utf8))
        }
        let api = StoreAPI(credentials: StoreCredentials(revenueCatKey: "fake-test-key"),
                           record: { _ in }, session: stubSession())

        do {
            _ = try await api.revenueCat("POST", "/v2/projects/project/products", body: [:])
            Issue.record("The request should fail.")
        } catch {}

        #expect(StubURLProtocol.state.requestCount == 1)
    }

    @Test func anIdempotentGetMayRetryATransientFailure() async throws {
        StubURLProtocol.state.configure { request, count in
            let status = count == 1 ? 503 : 200
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                    headerFields: ["Retry-After": "0"])!, Data("{}".utf8))
        }
        let api = StoreAPI(credentials: StoreCredentials(revenueCatKey: "fake-test-key"),
                           record: { _ in }, session: stubSession())

        _ = try await api.revenueCat("GET", "/v2/projects/project/products")

        #expect(StubURLProtocol.state.requestCount == 2)
    }

    /// One response carries both header families. Apple reports one percent of
    /// the hourly budget left, and RevenueCat reports one percent of its own
    /// budget used. An Apple call must read Apple's number, so the next Apple
    /// call waits out the bucket.
    @Test func anAppleCallReadsAppleRateLimitsAndNotTheProviderHeaders() async throws {
        StubURLProtocol.state.configure { request, _ in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                             headerFields: [
                                "x-rate-limit": "user-hour-lim:100;user-hour-rem:1",
                                "revenuecat-rate-limit-current-usage": "1",
                                "revenuecat-rate-limit-current-limit": "100",
                             ])!, Data("{}".utf8))
        }
        let credential = AppleCredential(
            keyID: "ABCD123456", issuerID: "issuer",
            privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation,
            fileName: "AuthKey_ABCD123456.p8")
        let api = StoreAPI(credentials: StoreCredentials(apple: credential),
                           record: { _ in }, session: stubSession())

        _ = try await api.apple("GET", "/v1/apps")
        let started = Date()
        _ = try await api.apple("GET", "/v1/apps")

        // The bucket holds the second call for a second. Read the RevenueCat
        // headers here and the throttle disappears.
        #expect(Date().timeIntervalSince(started) > 0.5)
    }
}

private func base64URLDecoded(_ value: String) -> Data? {
    var text = value.replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    while text.count % 4 != 0 { text += "=" }
    return Data(base64Encoded: text)
}

/// The cache in `appleBearer` holds a token until `AppleJWT.lifetime`. This
/// proves the signed `exp` says the same, so neither number can drift alone.
@Test func theSignedTokenExpiresWhenTheCachedLifetimeSaysItDoes() throws {
    let credential = AppleCredential(
        keyID: "ABCD123456", issuerID: "issuer",
        privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation,
        fileName: "AuthKey_ABCD123456.p8")
    let now = Date()

    let token = try AppleJWT.make(credential: credential, now: now)

    let segments = token.split(separator: ".")
    let data = try #require(base64URLDecoded(String(segments[1])))
    let claims = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(claims["exp"] as? Int
            == Int(now.timeIntervalSince1970) + Int(AppleJWT.lifetime))
    // Apple refuses a token that lives longer than this.
    #expect(AppleJWT.lifetime <= 20 * 60)
}

@Test func aFormBodyEscapesWhatAQueryStringWouldLeaveForAFormReaderToMisread() {
    let body = String(decoding: FormBody.encoded([
        ("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer"),
        ("assertion", "a+b/c=d&e"),
    ]), as: UTF8.self)

    // A `+` that survives reads back as a space, and a bare `&` or `=` splits
    // the body into fields that nobody sent. A query allows all three.
    #expect(body.contains("assertion=a%2Bb%2Fc%3Dd%26e"))
    #expect(body.contains("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer"))
    #expect(body.filter { $0 == "&" }.count == 1)
}

@Test func apiCallLogsDropQueriesAndRedactBoundedErrors() {
    let token = "SUPERSECRETVALUE12345"
    let call = APICall(system: "apple", method: "GET",
                       path: "/v1/apps?cursor=\(token)",
                       error: "Authorization: Bearer \(token) " + String(repeating: "x", count: 8_000))

    #expect(call.path == "/v1/apps")
    #expect(call.error?.contains(token) != true)
    #expect((call.error?.utf8.count ?? 0) <= 2_048)
}

/// A shared 401 explanation cannot name Apple's issuer id while reporting a
/// Google service-account failure. Keep the shared copy true for both stores.
@Test func credentialRefusalsUseStoreNeutralInstructions() {
    let message = ConnectionError.http(401, "Unauthorized").localizedDescription

    #expect(message.contains("credential file"))
    #expect(message.contains("Stores tab"))
    #expect(!message.localizedCaseInsensitiveContains("issuer"))
    #expect(!message.localizedCaseInsensitiveContains("key id"))
}
