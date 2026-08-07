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

/// `showAccount` has two presenters now: the shell, for the Account tab, and
/// the paywall, which is itself a sheet and cannot open a sibling over itself.
/// Both firing on one flag is two sheets for one request, and on macOS that
/// shows neither. The shell's copy stands down while a paywall is up.
@Test func onlyOnePresenterCanOpenTheSignInSheet() throws {
    let shell = try source("Sources/SuperSubmitter/Shell/RootView.swift")

    #expect(shell.contains("state.showAccount && state.paywall == nil"),
            "The shell must not present the sign-in sheet while the paywall is up.")
}
