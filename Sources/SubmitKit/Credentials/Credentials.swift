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
