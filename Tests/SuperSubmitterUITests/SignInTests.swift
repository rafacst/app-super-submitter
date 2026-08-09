import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

private let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func source(_ relativePath: String) throws -> String {
    try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath),
               encoding: .utf8)
}

private final class CallbackStore: SupabaseSessionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var session: SupabaseSession?

    init(_ session: SupabaseSession? = nil) { self.session = session }

    func load() throws -> SupabaseSession? { lock.withLock { session } }
    func save(_ session: SupabaseSession) throws { lock.withLock { self.session = session } }
    func clear() throws { lock.withLock { session = nil } }
}

private final class CallbackProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount += 1
        let body = Data(#"{"access_token":"new","refresh_token":"next","expires_in":3600,"user":{"email":"attacker@example.com"}}"#.utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
    for _ in 0..<100 where !condition() {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

/// One keyword, and the app lives or dies on it.
///
/// `OAuthSession` is `@MainActor`, so a plain closure written inside it
/// inherits that isolation and checks the executor as it starts.
/// AuthenticationServices calls the completion handler on its own XPC reply
/// queue, so the check trapped and Apple sign-in took the whole app down.
/// The continuation is `Sendable` and resumes from any thread, so the closure
/// must stay nonisolated.
@Test func theSignInCallbackClaimsNoActor() throws {
    let session = try source("Sources/SuperSubmitter/Overlays/OAuthSession.swift")

    #expect(session.contains("{ @Sendable callback, error in"),
            "The ASWebAuthenticationSession handler must not inherit the main actor.")
}

/// Sign in is a panel beside the Account tab, not a sheet. It was a sheet, and
/// the paywall presented one too, so signing in on the way to a purchase put
/// two modal layers between the developer and the plan they were buying.
@MainActor
@Test func signingInOpensBesideTheAccountTabAndNotOverIt() {
    let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                         storeAccount: "test-\(UUID().uuidString)")
    #expect(!state.showSignIn)

    state.openAccount()

    #expect(state.showSignIn)
    let shell = try! source("Sources/SuperSubmitter/Shell/RootView.swift")
    #expect(!shell.contains("showSignIn"),
            "The shell must not present sign in as a sheet.")
}

@MainActor
@Test func onlyTheExactAccountCallbackMayRequestAConfirmation() async throws {
    let old = SupabaseSession(accessToken: "old", refreshToken: "old-refresh",
                              expiresAt: .distantFuture, email: "owner@example.com")
    let store = CallbackStore(old)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CallbackProtocol.self]
    let network = URLSession(configuration: configuration)
    defer { network.invalidateAndCancel() }
    let auth = SupabaseAuth(
        configuration: .init(baseURL: URL(string: "https://project.supabase.co")!,
                             publishableKey: "public-key"),
        urlSession: network, store: store)
    let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                         storeAccount: "test-\(UUID().uuidString)")
    state.authController = auth
    state.accountEmail = old.email
    CallbackProtocol.requestCount = 0

    for url in ["https://evil.example/#refresh_token=x",
                "supersubmitter://evil/#refresh_token=x",
                "otherscheme://auth-callback#refresh_token=x"] {
        state.handle(callback: URL(string: url)!)
    }

    #expect(CallbackProtocol.requestCount == 0)
    #expect(state.pendingAccountEmail == nil)
    #expect(try store.load()?.email == old.email)

    state.handle(callback: URL(
        string: "supersubmitter://auth-callback#refresh_token=attacker")!)
    await waitUntil { state.pendingAccountEmail != nil }

    #expect(state.pendingAccountEmail == "attacker@example.com")
    #expect(state.accountEmail == old.email)
    #expect(try store.load()?.email == old.email)

    state.confirmPendingAccount()
    await waitUntil { state.accountEmail == "attacker@example.com" }
    #expect(try store.load()?.email == "attacker@example.com")
}

@MainActor
@Test func browserHandoffsOnlyOpenStripeHostsOverHTTPS() {
    #expect(AppState.isTrustedStripeURL(URL(string: "https://checkout.stripe.com/c/pay")!))
    #expect(AppState.isTrustedStripeURL(URL(string: "https://billing.stripe.com/p/session")!))
    #expect(!AppState.isTrustedStripeURL(URL(string: "http://checkout.stripe.com/c/pay")!))
    #expect(!AppState.isTrustedStripeURL(URL(string: "https://checkout.stripe.com.evil.example")!))
    #expect(!AppState.isTrustedStripeURL(URL(string: "https://evil.example/pay")!))
}
