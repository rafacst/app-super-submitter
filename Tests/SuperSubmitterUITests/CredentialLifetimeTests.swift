import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// A store key outlives every app that used it.
///
/// An App Store Connect key covers the team and a Play service account covers
/// the developer account, so one of each answers for every app on the machine,
/// including the ones not added yet. Only "Forget" on the Stores tab takes one
/// away.
///
/// It did not work that way. `loadCredentials` returned at the door when no app
/// was linked, so removing the last app left the fields empty and the next
/// "Update existing apps" asked for the `.p8` a second time, from an app that
/// had held it in the Keychain the whole time. Nothing had deleted it. Nothing
/// read it back.

@MainActor
private func freshState(account: String) -> AppState {
    AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!, storeAccount: account)
}

@MainActor
@Test func aStoreKeySurvivesRemovingEveryApp() throws {
    let account = "test-\(UUID().uuidString)"
    defer { try? KeychainCredentials.delete(kind: .apple, account: account) }

    let state = freshState(account: account)
    state.appleKeyID = "ABCD123456"
    state.appleIssuerID = "11111111-2222-3333-4444-555555555555"
    state.applePrivateKeyPEM = "-----BEGIN PRIVATE KEY-----\nx\n-----END PRIVATE KEY-----"
    state.appleCredentialFileName = "AuthKey_ABCD123456.p8"
    state.appleCredentialFieldsChanged()

    // No app was ever linked, which is the state the app is in right after the
    // last one is removed.
    #expect(state.credentialAccount == nil)

    let relaunched = freshState(account: account)

    #expect(relaunched.appleKeyID == "ABCD123456")
    #expect(relaunched.appleIssuerID == "11111111-2222-3333-4444-555555555555")
    #expect(!relaunched.applePrivateKeyPEM.isEmpty)
    #expect(relaunched.appleCredentialFileName == "AuthKey_ABCD123456.p8")
}

/// Forget is the one door out, and it has to close behind itself.
@MainActor
@Test func forgettingAStoreKeyIsWhatRemovesIt() throws {
    let account = "test-\(UUID().uuidString)"
    defer { try? KeychainCredentials.delete(kind: .apple, account: account) }

    let state = freshState(account: account)
    state.appleKeyID = "ABCD123456"
    state.appleIssuerID = "issuer"
    state.applePrivateKeyPEM = "key"
    state.appleCredentialFieldsChanged()

    state.forgetCredential(for: .apple)

    #expect(state.appleKeyID.isEmpty)
    #expect(freshState(account: account).appleKeyID.isEmpty,
            "Forget must reach the Keychain, not only the fields.")
}

/// The sidebar has said for a while that these two work with no app. The rows
/// were greyed anyway, so the one screen that can undo a credential was shut
/// exactly when a developer went looking for it.
@Test func theFooterTabsWorkWithNoAppLinked() {
    #expect(Tab.stores.standsAlone)
    #expect(Tab.account.standsAlone)
    // As a set: `footer` is in the order the sidebar draws them, and
    // `allCases` is in the order of the work.
    #expect(Set(Tab.allCases.filter(\.standsAlone)) == Set(Tab.footer))
    // Everything else edits or reads one app.
    #expect(!Tab.build.standsAlone)
    #expect(!Tab.details.standsAlone)
}
