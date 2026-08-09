import Foundation
import Security

public struct AppleCredential: Codable, Sendable, Equatable {
    public var keyID: String
    public var issuerID: String
    public var privateKeyPEM: String
    public var fileName: String

    public init(keyID: String, issuerID: String, privateKeyPEM: String, fileName: String) {
        self.keyID = keyID
        self.issuerID = issuerID
        self.privateKeyPEM = privateKeyPEM
        self.fileName = fileName
    }

    /// The length Apple issues. The fields stop at these, so a key id with a
    /// stray character pasted onto it fails while the developer is still
    /// looking at the field, instead of at the connection.
    public static let keyIDLength = 10
    /// The issuer id is a UUID, which is thirty six characters with hyphens.
    public static let issuerIDLength = 36

    /// The key id that Apple writes into the file name.
    ///
    /// App Store Connect downloads the key as `AuthKey_<key id>.p8`, so a
    /// developer who has the file rarely needs to type the id. Apple issues
    /// ten characters, uppercase letters and digits, and anything else here
    /// returns nil rather than a guess: a wrong id fails the connection with
    /// an error that names nothing useful.
    public static func keyID(fromFileName name: String) -> String? {
        let base = (name as NSString).deletingPathExtension
        let candidate = base.lowercased().hasPrefix("authkey_")
            ? String(base.dropFirst("authkey_".count))
            : base
        guard candidate.count == 10, candidate.allSatisfy({
            $0.isASCII && ($0.isNumber || ($0.isLetter && $0.isUppercase))
        }) else { return nil }
        return candidate
    }
}

public struct GoogleServiceAccount: Codable, Sendable, Equatable {
    public var projectID: String?
    public var privateKeyID: String?
    public var privateKey: String
    public var clientEmail: String
    public var tokenURI: String
    public var fileName: String?

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case privateKeyID = "private_key_id"
        case privateKey = "private_key"
        case clientEmail = "client_email"
        case tokenURI = "token_uri"
        case fileName
    }

    public init(data: Data, fileName: String? = nil) throws {
        self = try JSONDecoder().decode(Self.self, from: data)
        self.fileName = fileName
    }
}

public struct RevenueCatCredential: Codable, Sendable, Equatable {
    public var apiKey: String

    public init(apiKey: String) { self.apiKey = apiKey }
}

public struct ReviewerCredential: Codable, Sendable, Equatable {
    public var username: String
    public var password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

public enum CredentialKind: String, Sendable {
    case apple
    case google
    case revenueCat
    case reviewAccount
    /// The Supabase access and refresh tokens for the Super Submitter account.
    case account
    /// The signed entitlement document. It is not a credential for a store,
    /// but it is a signed secret-adjacent blob, and the Keychain is where the
    /// spec puts it rather than `UserDefaults`.
    case license
}

/// Every secret the app holds, in one Keychain item.
///
/// The file Keychain authorizes per item, so six items asked the developer for
/// their login password six times on one launch. One item asks once. The shape
/// callers see is unchanged: a kind and an account still name one credential.
///
/// The item is read once per launch and kept in memory after that, so no
/// screen can turn into a second prompt.
///
/// `// ponytail: one process owns the vault. A second copy of the app running
/// // at the same time would write over the first one's edits. The app is
/// // single window and single instance, so nothing here reconciles.`
public enum KeychainCredentials {
    /// The Keychain service the vault lives under.
    ///
    /// A run that must not touch the real vault sets this once, before any
    /// read. That used to be what the `account` argument did, and the vault
    /// ended that: every account is now a key **inside** one item, so the
    /// account no longer decides which Keychain item is opened. A demo or
    /// screenshot run that kept the real service therefore opened the real
    /// item, and an unsigned build reading an item a signed build wrote raises
    /// the "allow access" dialog and blocks on it.
    nonisolated(unsafe) public static var service = "com.rafacst.SuperSubmitter.credentials"

    /// Points the vault at a service of its own, and drops anything already
    /// read. Call it before the first credential read of the process.
    public static func useIsolatedService(_ name: String) {
        lock.withLock {
            service = name
            cache = nil
        }
    }

    /// Whether the vault is a dictionary in this process rather than an item
    /// in the Keychain.
    ///
    /// A service of its own was not enough. macOS grants Keychain access to a
    /// *binary*, and an unsigned build is a new binary every time it is
    /// compiled, so the second run of a demo build reads an item the first run
    /// wrote and raises "allow access" — on every single build, forever, and
    /// on the main thread. Isolating the service moved the prompt off the real
    /// credentials; it could not remove it.
    ///
    /// Tests and package builds have nothing worth keeping between launches,
    /// so they start in memory automatically and never open the Keychain. The
    /// signed Xcode app starts with nil and keeps using the real vault.
    nonisolated(unsafe) private static var memory: [String: Data]? = {
        #if SWIFT_PACKAGE
        return [:]
        #else
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
            ? nil : [:]
        #endif
    }()

    static var isUsingMemoryVault: Bool {
        lock.withLock { memory != nil }
    }

    /// Puts a demo or screenshot run in memory for the rest of the process.
    /// Call it before the first credential read.
    public static func useMemoryVault() {
        lock.withLock {
            memory = [:]
            cache = nil
        }
    }
    /// The one item. The old per-credential items used `kind:account` as their
    /// account, and none of them can collide with this.
    private static let vaultAccount = "all-credentials"

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: Data]?

    public static func save<T: Encodable>(_ value: T, kind: CredentialKind,
                                           account: String) throws {
        let data = try JSONEncoder().encode(value)
        try lock.withLock {
            var vault = try readVault()
            vault[accountKey(kind: kind, account: account)] = data
            try writeVault(vault)
        }
    }

    public static func load<T: Decodable>(_ type: T.Type, kind: CredentialKind,
                                           account: String) throws -> T? {
        let data = try lock.withLock {
            try readVault()[accountKey(kind: kind, account: account)]
        }
        guard let data else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }

    /// Removes the whole vault item, and with it every credential the app
    /// holds. Nothing else in the Keychain is touched: the item is found by
    /// this service and this account, and both belong to Super Submitter.
    public static func deleteEverything() throws {
        try lock.withLock {
            if memory != nil { memory = [:]; cache = nil; return }
            let status = SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: vaultAccount,
            ] as CFDictionary)
            // Nothing stored is the state this asks for, not a failure.
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError(status)
            }
            cache = nil
        }
    }

    public static func delete(kind: CredentialKind, account: String) throws {
        try lock.withLock {
            var vault = try readVault()
            guard vault.removeValue(forKey: accountKey(kind: kind, account: account)) != nil
            else { return }
            try writeVault(vault)
        }
    }

    // MARK: - The one item

    private static func readVault() throws -> [String: Data] {
        if let memory { return memory }
        if let cache { return cache }
        var item: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: vaultAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ] as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            let data = item as? Data ?? Data()
            let vault = (try? JSONDecoder().decode([String: Data].self, from: data)) ?? [:]
            cache = vault
            return vault
        case errSecItemNotFound:
            // Nothing here yet. Either this is a fresh Mac, or this is the
            // first launch after the split items became one, and the old ones
            // are still there to be taken over.
            let vault = adoptSeparateItems()
            cache = vault
            if !vault.isEmpty { try? writeVault(vault) }
            return vault
        default:
            throw KeychainError(status)
        }
    }

    private static func writeVault(_ vault: [String: Data]) throws {
        if memory != nil { memory = vault; return }
        let data = try JSONEncoder().encode(vault)
        cache = vault
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: vaultAccount,
        ]
        let status = SecItemUpdate(match as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainError(status) }
        var add = match
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(addStatus) }
    }

    /// Takes over the items an older build wrote, one per credential.
    ///
    /// This runs once, on the launch that finds no vault, and it is the last
    /// time the developer is asked more than once. The old items are left
    /// alone rather than deleted: a developer who goes back to an older build
    /// still has their keys, and the vault is authoritative from here on.
    private static func adoptSeparateItems() -> [String: Data] {
        var item: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ] as CFDictionary, &item)
        guard status == errSecSuccess, let entries = item as? [[String: Any]] else { return [:] }
        return vault(fromSeparateItems: entries)
    }

    /// What an older build's separate items add up to.
    ///
    /// The vault's own item is in the same service and has to be skipped, or a
    /// re-run would fold the vault into itself under a key nothing reads.
    static func vault(fromSeparateItems entries: [[String: Any]]) -> [String: Data] {
        var vault: [String: Data] = [:]
        for entry in entries {
            guard let key = entry[kSecAttrAccount as String] as? String,
                  key != vaultAccount,
                  let data = entry[kSecValueData as String] as? Data else { continue }
            vault[key] = data
        }
        return vault
    }

    private static func accountKey(kind: CredentialKind, account: String) -> String {
        "\(kind.rawValue):\(account)"
    }
}

public struct KeychainError: Error, LocalizedError {
    public let status: OSStatus

    init(_ status: OSStatus) { self.status = status }

    public var errorDescription: String? {
        (SecCopyErrorMessageString(status, nil) as String?)
            .map { "The Keychain operation failed: \($0)" }
            ?? "The Keychain operation failed with status \(status)."
    }
}
