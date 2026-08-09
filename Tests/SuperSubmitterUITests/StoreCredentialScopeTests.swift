import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// A store credential belongs to the account, not to the app.
///
/// An App Store Connect key covers the team and a Play service account covers
/// the developer account. Opening a second app loads the same key, so the app
/// must never behave as though it wants a new one.
@MainActor
struct StoreCredentialScopeTests {
    private static let key = AppleCredential(keyID: "Z2YFP2FP9D", issuerID: "issuer",
                                             privateKeyPEM: "pem",
                                             fileName: "AuthKey_Z2YFP2FP9D.p8")

    /// Two workspaces in one state, with a Keychain account of its own, so a
    /// test run never reads or writes the real key.
    private func stateWithTwoApps(account: String) throws -> (AppState, [URL]) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("scope-\(UUID().uuidString)")
        var urls: [URL] = []
        for name in ["Alpha", "Beta"] {
            let folder = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var manifest = Manifest()
            manifest.setAppleApp(appID: "1", bundleID: "com.example.\(name.lowercased())")
            let url = folder.appendingPathComponent(ManifestFile.defaultName)
            try ManifestFile.save(manifest, to: url)
            urls.append(url)
        }
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: account)
        for url in urls { state.link(manifestAt: url) }
        return (state, urls)
    }

    /// The bug this guards was a sentence on screen, and it cost trust rather
    /// than money. Every app switch set the connection back to "Not
    /// connected", so a developer who added a second app read it as "enter
    /// your key again" and entered it again.
    @Test func switchingAppsKeepsTheTestedConnection() throws {
        let account = "test-\(UUID().uuidString)"
        defer { try? KeychainCredentials.delete(kind: .apple, account: account) }
        let (state, urls) = try stateWithTwoApps(account: account)
        try KeychainCredentials.save(Self.key, kind: .apple, account: account)

        state.link(manifestAt: urls[0])
        state.appleConnection = .connected("Connected · 3 apps visible")

        state.link(manifestAt: urls[1])

        #expect(state.appleConnection.isConnected)
        #expect(state.appleKeyID == "Z2YFP2FP9D")
    }

    /// A different key is the one thing that can invalidate the test, so the
    /// status still falls for that.
    @Test func aDifferentKeyDropsTheConnection() throws {
        let account = "test-\(UUID().uuidString)"
        defer { try? KeychainCredentials.delete(kind: .apple, account: account) }
        let (state, urls) = try stateWithTwoApps(account: account)
        try KeychainCredentials.save(Self.key, kind: .apple, account: account)
        state.link(manifestAt: urls[0])
        state.appleConnection = .connected("Connected · 3 apps visible")

        try KeychainCredentials.save(
            AppleCredential(keyID: "OTHERKEY99", issuerID: "issuer",
                            privateKeyPEM: "other", fileName: "AuthKey_OTHERKEY99.p8"),
            kind: .apple, account: account)
        state.link(manifestAt: urls[1])

        #expect(!state.appleConnection.isConnected)
        #expect(state.appleKeyID == "OTHERKEY99")
    }

    // MARK: - Removing the credential

    @Test func forgettingTheKeyClearsEveryFieldAndTheStatus() throws {
        let account = "test-\(UUID().uuidString)"
        defer { try? KeychainCredentials.delete(kind: .apple, account: account) }
        let (state, urls) = try stateWithTwoApps(account: account)
        try KeychainCredentials.save(Self.key, kind: .apple, account: account)
        state.link(manifestAt: urls[0])
        state.appleConnection = .connected("Connected")
        #expect(state.hasCredential(for: .apple))

        state.forgetCredential(for: .apple)

        #expect(!state.hasCredential(for: .apple))
        #expect(state.appleKeyID.isEmpty)
        #expect(state.appleIssuerID.isEmpty)
        #expect(state.appleCredentialFileName.isEmpty)
        #expect(!state.appleConnection.isConnected)
        // It has to leave the Keychain too, or the next app switch loads it
        // straight back in.
        #expect(try KeychainCredentials.load(AppleCredential.self, kind: .apple,
                                             account: account) == nil)
    }

    /// The panel asks before it removes, and it only asks when there is
    /// something to remove.
    @Test func aStoreWithNoKeyHasNothingToConfirm() throws {
        let account = "test-\(UUID().uuidString)"
        defer { try? KeychainCredentials.delete(kind: .apple, account: account) }
        let (state, _) = try stateWithTwoApps(account: account)

        #expect(!state.hasCredential(for: .apple))
        #expect(!state.hasCredential(for: .google))
    }

    /// Removing one store's key leaves the other alone.
    @Test func forgettingTheAppleKeyKeepsTheGoogleOne() throws {
        let account = "test-\(UUID().uuidString)"
        defer {
            try? KeychainCredentials.delete(kind: .apple, account: account)
            try? KeychainCredentials.delete(kind: .google, account: account)
        }
        let (state, urls) = try stateWithTwoApps(account: account)
        try KeychainCredentials.save(Self.key, kind: .apple, account: account)
        let json = Data("""
        {"project_id":"p","private_key":"pem",
         "client_email":"bot@example.iam.gserviceaccount.com",
         "token_uri":"https://oauth2.googleapis.com/token"}
        """.utf8)
        try KeychainCredentials.save(
            GoogleServiceAccount(data: json, fileName: "key.json"),
            kind: .google, account: account)
        state.link(manifestAt: urls[0])

        state.forgetCredential(for: .apple)

        #expect(state.hasCredential(for: .google))
        #expect(try KeychainCredentials.load(GoogleServiceAccount.self, kind: .google,
                                             account: account) != nil)
    }

    @Test func theStoresScreenOffersGoogleOAuthAndJSON() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/SuperSubmitter/Tabs/StoresTab.swift"),
            encoding: .utf8)

        #expect(source.contains("Connect with Google"))
        #expect(source.contains("Service account JSON"))
    }
}
