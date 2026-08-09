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

/// The link in the confirmation email.
///
/// Supabase answers a confirmation in the fragment and a refusal in the query,
/// so a reader that looks at one half misses the case it is not in. The app
/// registered the scheme, opened on the link, and did nothing at all until
/// this existed.
@Test func theConfirmationLinkCarriesTheSessionInTheFragment() {
    let confirmed = URL(string: "supersubmitter://auth-callback#access_token=a&expires_in=3600&refresh_token=next&token_type=bearer&type=signup")!
    let parts = SupabaseAuth.parameters(in: confirmed)
    #expect(parts["refresh_token"] == "next")
    #expect(parts["type"] == "signup")

    let refused = URL(string: "supersubmitter://auth-callback?error=access_denied&error_description=Email%20link%20is%20invalid%20or%20has%20expired")!
    #expect(SupabaseAuth.parameters(in: refused)["error_description"]
        == "Email link is invalid or has expired")

    // Nothing at all is the return from Stripe Checkout, which grants nothing.
    #expect(SupabaseAuth.parameters(in: URL(string: "supersubmitter://billing")!).isEmpty)
}

/// A used or expired link fails here, with the reason Supabase gave, instead
/// of at the first store call.
@Test func aRefusedConfirmationLinkSaysWhy() async throws {
    let auth = SupabaseAuth(
        configuration: .init(baseURL: URL(string: "https://project.supabase.co")!,
                             publishableKey: "public-key"),
        store: AuthSessionStore(nil))
    let refused = URL(string: "supersubmitter://auth-callback#error=access_denied&error_description=Email%20link%20is%20invalid")!

    await #expect(throws: SupabaseAuthError.service("Email link is invalid")) {
        try await auth.adopt(callback: refused)
    }
    // A callback with neither a session nor a reason is not a sign-in.
    await #expect(throws: SupabaseAuthError.invalidResponse) {
        try await auth.adopt(callback: URL(string: "supersubmitter://auth-callback")!)
    }
}

@Test func resolvingAConfirmationDoesNotReplaceTheStoredSession() async throws {
    let old = SupabaseSession(accessToken: "old", refreshToken: "old-refresh",
                              expiresAt: .distantFuture, email: "owner@example.com")
    let store = AuthSessionStore(old)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AuthStubProtocol.self]
    let network = URLSession(configuration: configuration)
    defer { network.invalidateAndCancel() }
    let auth = SupabaseAuth(
        configuration: .init(baseURL: URL(string: "https://project.supabase.co")!,
                             publishableKey: "public-key"),
        urlSession: network, store: store)
    let callback = URL(string: "supersubmitter://auth-callback#refresh_token=attacker")!

    let pending = try await auth.resolve(callback: callback)

    #expect(pending.email == "dev@example.com")
    #expect(try store.load()?.email == "owner@example.com")
    #expect(await auth.email == "owner@example.com")

    #expect(try await auth.adopt(session: pending) == "dev@example.com")
    #expect(try store.load()?.email == "dev@example.com")
}
