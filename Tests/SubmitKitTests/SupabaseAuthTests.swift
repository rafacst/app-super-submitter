import Foundation
import Testing
@testable import SubmitKit

private final class AuthSessionStore: SupabaseSessionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: SupabaseSession?

    init(_ value: SupabaseSession?) { self.value = value }

    func load() throws -> SupabaseSession? {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func save(_ session: SupabaseSession) throws {
        lock.lock(); defer { lock.unlock() }
        value = session
    }

    func clear() throws {
        lock.lock(); defer { lock.unlock() }
        value = nil
    }
}

private final class AuthRequestState: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var request: URLRequest?

    func record(_ request: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        self.request = request
    }
}

private final class AuthStubProtocol: URLProtocol, @unchecked Sendable {
    static let state = AuthRequestState()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.state.record(request)
        let body = Data(#"{"access_token":"fresh","refresh_token":"next","expires_in":3600,"user":{"email":"dev@example.com"}}"#.utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Test func expiredSupabaseSessionRefreshesThroughTheNativeAuthEndpoint() async throws {
    let old = SupabaseSession(accessToken: "old", refreshToken: "refresh",
                              expiresAt: .distantPast, email: "dev@example.com")
    let store = AuthSessionStore(old)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AuthStubProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let auth = SupabaseAuth(
        configuration: .init(baseURL: URL(string: "https://project.supabase.co")!,
                             publishableKey: "public-key"),
        urlSession: session, store: store)

    #expect(try await auth.accessToken() == "fresh")
    let request = AuthStubProtocol.state.request
    #expect(request?.url?.query == "grant_type=refresh_token")
    #expect(request?.value(forHTTPHeaderField: "apikey") == "public-key")
    #expect(try store.load()?.refreshToken == "next")
}
