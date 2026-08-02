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

@Test func apiCallLogsDropQueriesAndRedactBoundedErrors() {
    let token = "SUPERSECRETVALUE12345"
    let call = APICall(system: "apple", method: "GET",
                       path: "/v1/apps?cursor=\(token)",
                       error: "Authorization: Bearer \(token) " + String(repeating: "x", count: 8_000))

    #expect(call.path == "/v1/apps")
    #expect(call.error?.contains(token) != true)
    #expect((call.error?.utf8.count ?? 0) <= 2_048)
}
