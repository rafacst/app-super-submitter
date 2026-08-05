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

/// AppKit refuses to quit an app that holds a modal sheet, and Sparkle
/// installs an update by quitting. "Check for updates" sits inside the
/// Settings sheet, so "Install and Relaunch" asked the app to quit and the
/// system log answered "App termination blocked by modal sheet". The app
/// stayed open, and the update waited for the user to close a panel that
/// nothing on the screen tied to the update.
@MainActor
@Test func closingEverySheetLeavesNothingForAppKitToBlockOn() {
    let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                         storeAccount: "test-\(UUID().uuidString)")
    state.showSettings = true
    state.showOnboarding = true
    state.showExistingAppImport = true
    state.showAddLocale = true
    state.releaseSheet = .apple
    state.paywall = .apply
    state.pendingPaywall = .marketing

    state.closeEverySheet()

    #expect(!state.showSettings)
    #expect(!state.showOnboarding)
    #expect(!state.showExistingAppImport)
    #expect(!state.showAddLocale)
    #expect(state.releaseSheet == nil)
    #expect(state.paywall == nil)
    // A queued paywall re-opens a sheet the moment the shell is free, which
    // would block the quit a second time.
    #expect(state.pendingPaywall == nil)
}

/// A seventh sheet added to the shell and forgotten here would bring the bug
/// straight back, and it would look exactly like the first time: the app
/// simply does not quit, and nothing on screen says why.
@Test func everySheetOfTheShellIsNamedInCloseEverySheet() throws {
    let shell = try source("Sources/SuperSubmitter/Shell/RootView.swift")
    let appState = try source("Sources/SuperSubmitter/AppState.swift")

    let pattern = #"\.sheet\((?:isPresented|item): \$state\.(\w+)"#
    let regex = try NSRegularExpression(pattern: pattern)
    let matches = regex.matches(in: shell, range: NSRange(shell.startIndex..., in: shell))
    let presented = matches.compactMap { match in
        Range(match.range(at: 1), in: shell).map { String(shell[$0]) }
    }
    #expect(presented.count >= 6, "The shell's sheets could not be read.")

    let body = try #require(appState.range(of: "func closeEverySheet() {").map {
        String(appState[$0.upperBound...].prefix(while: { $0 != "}" }))
    })
    for name in presented {
        #expect(body.contains(name), "closeEverySheet leaves \(name) open.")
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
