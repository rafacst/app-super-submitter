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
}

public enum KeychainCredentials {
    private static let service = "com.rafacst.SuperSubmitter.credentials"

    public static func save<T: Encodable>(_ value: T, kind: CredentialKind,
                                           account: String) throws {
        let data = try JSONEncoder().encode(value)
        let key = accountKey(kind: kind, account: account)
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(match as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainError(status) }

        var add = match
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(addStatus) }
    }

    public static func load<T: Decodable>(_ type: T.Type, kind: CredentialKind,
                                           account: String) throws -> T? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey(kind: kind, account: account),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError(status)
        }
        return try JSONDecoder().decode(type, from: data)
    }

    public static func delete(kind: CredentialKind, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey(kind: kind, account: account),
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status)
        }
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
