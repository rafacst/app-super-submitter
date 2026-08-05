import Foundation
import Security
import Testing
@testable import SubmitKit

/// One Keychain item, not one per credential.
///
/// The file Keychain authorizes per item, and the developer met that as four
/// login-password prompts on one launch. The take-over below is what makes
/// that the last time they are asked more than once, so it has to keep every
/// key an older build wrote.
@Suite struct CredentialVaultTests {
    private func entry(_ account: String, _ value: String) -> [String: Any] {
        [kSecAttrAccount as String: account, kSecValueData as String: Data(value.utf8)]
    }

    @Test func theTakeOverKeepsEverySeparateItem() {
        let vault = KeychainCredentials.vault(fromSeparateItems: [
            entry("apple:default", "the apple key"),
            entry("google:default", "the service account"),
            entry("account:supabase", "the session"),
            entry("license:dev@example.com", "the entitlement"),
        ])

        #expect(vault.count == 4)
        #expect(vault["apple:default"] == Data("the apple key".utf8))
        #expect(vault["license:dev@example.com"] == Data("the entitlement".utf8))
    }

    /// The vault sits in the same service as the items it replaces. Folding it
    /// into itself would bury every credential under one key nothing reads.
    @Test func theTakeOverSkipsTheVaultsOwnItem() {
        let vault = KeychainCredentials.vault(fromSeparateItems: [
            entry("apple:default", "the apple key"),
            entry("all-credentials", "{\"apple:default\":\"...\"}"),
        ])

        #expect(vault.count == 1)
        #expect(vault["all-credentials"] == nil)
    }

    /// An item with no account, or none of the data, is not a credential. The
    /// Keychain returns attribute-only rows for anything it will not hand over.
    @Test func anIncompleteItemIsDroppedRatherThanGuessed() {
        let vault = KeychainCredentials.vault(fromSeparateItems: [
            [kSecValueData as String: Data("orphan".utf8)],
            [kSecAttrAccount as String: "google:default"],
            entry("apple:default", "the apple key"),
        ])

        #expect(vault == ["apple:default": Data("the apple key".utf8)])
    }

    /// The vault is a dictionary of raw credential blobs, and it travels
    /// through JSON to reach the Keychain. Nothing may change on the way.
    @Test func theVaultSurvivesItsOwnEncoding() throws {
        let vault = ["apple:default": Data("-----BEGIN PRIVATE KEY-----\nabc\n".utf8),
                     "account:supabase": Data("{\"refresh\":\"x\"}".utf8)]
        let restored = try JSONDecoder().decode(
            [String: Data].self, from: JSONEncoder().encode(vault))
        #expect(restored == vault)
    }
}
