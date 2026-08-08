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
/// installs an update by quitting. "Check for updates" is reachable from the
/// About panel, which is a sheet, so "Install and Relaunch" asked the app to
/// quit and the system log answered "App termination blocked by modal sheet".
/// The app stayed open, and the update waited for the user to close a panel
/// that nothing on the screen tied to the update.
@MainActor
@Test func closingEverySheetLeavesNothingForAppKitToBlockOn() {
    let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                         storeAccount: "test-\(UUID().uuidString)")
    state.showSettings = true
    state.showAbout = true
    state.showOnboarding = true
    state.showExistingAppImport = true
    state.showAddLocale = true
    state.showFieldSearch = true
    state.releaseSheet = .apple

    state.closeEverySheet()

    #expect(!state.showSettings)
    #expect(!state.showAbout)
    #expect(!state.showOnboarding)
    #expect(!state.showExistingAppImport)
    #expect(!state.showAddLocale)
    #expect(!state.showFieldSearch)
    #expect(state.releaseSheet == nil)
}

/// An eighth sheet added to the shell and forgotten in `closeEverySheet` would
/// bring the bug straight back, and it would look exactly like the first time:
/// the app simply does not quit, and nothing on screen says why.
@Test func everySheetOfTheShellIsNamedInCloseEverySheet() throws {
    let shell = try source("Sources/SuperSubmitter/Shell/RootView.swift")
    let appState = try source("Sources/SuperSubmitter/AppState.swift")

    let pattern = #"\.sheet\((?:isPresented|item): \$state\.(\w+)"#
    let regex = try NSRegularExpression(pattern: pattern)
    let matches = regex.matches(in: shell, range: NSRange(shell.startIndex..., in: shell))
    let presented = matches.compactMap { match in
        Range(match.range(at: 1), in: shell).map { String(shell[$0]) }
    }
    #expect(presented.count >= 7, "The shell's sheets could not be read.")

    let body = try #require(appState.range(of: "func closeEverySheet() {").map {
        String(appState[$0.upperBound...].prefix(while: { $0 != "}" }))
    })
    for name in presented {
        #expect(body.contains(name), "closeEverySheet leaves \(name) open.")
    }
}

/// The feed URL and the public key are what make the updater an updater. An
/// empty either one ships an app that silently never updates, and the failure
/// is invisible: no error, no window, nothing in the interface at all.
///
/// The key is also the one thing here that cannot be regenerated. Its private
/// half lives in the login keychain, so a build carrying a different public key
/// refuses every update the release workflow has ever signed.
@Test func theBundleCarriesTheFeedAndTheKeyThatVerifiesIt() throws {
    let project = try source("project.yml")

    let feed = try #require(project.range(of: "SUFeedURL: ").map {
        String(project[$0.upperBound...].prefix(while: { !$0.isNewline }))
    })
    #expect(feed.hasPrefix("https://"), "The feed must be fetched over TLS.")
    #expect(feed.hasSuffix("appcast.xml"), "The feed URL does not name an appcast.")

    let key = try #require(project.range(of: "SUPublicEDKey: ").map {
        String(project[$0.upperBound...].prefix(while: { !$0.isNewline }))
    })
    // A base64 Ed25519 public key is 32 bytes, so 44 characters with padding.
    #expect(Data(base64Encoded: key)?.count == 32,
            "SUPublicEDKey is not a base64 Ed25519 public key.")
}
