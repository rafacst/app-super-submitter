import Foundation
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
