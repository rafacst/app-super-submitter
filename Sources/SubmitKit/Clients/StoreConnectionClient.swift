import CryptoKit
import Foundation
import Security

public struct RemoteStoreApp: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let identifier: String

    public init(id: String, name: String, identifier: String) {
        self.id = id
        self.name = name
        self.identifier = identifier
    }
}

public struct ImportedStoreListing: Sendable, Equatable {
    public struct Locale: Sendable, Equatable {
        public var name: String?
        public var subtitle: String?
        public var description: String?
        public var whatsNew: String?
        public var keywords: String?
        public var promotionalText: String?
        public var supportURL: String?
        public var marketingURL: String?
        public var privacyPolicyURL: String?
        public var privacyPolicyText: String?
        public var privacyChoicesURL: String?
        public var video: String?

        public init() {}
    }

    public var versionName: String?
    /// The store's own default language. It becomes the manifest default, so
    /// the Details tab opens on the locale the store already publishes.
    public var defaultLocale: String?
    public var bundleID: String?
    public var locales: [String: Locale] = [:]
    public var assets: [ImportedStoreAsset] = []
    public var review = ImportedReview()
    public var purchases: [Manifest.Purchase] = []
    public var subscriptions: [Manifest.SubscriptionGroup] = []
    public var googleTracks: [String] = []
    public var googleReleaseNotes: [String: String] = [:]
    public var googleContactWebsite: String?
    public var appleReleaseType: String?
    public var applePhasedRelease: Bool?
    /// The optional reads that the store refused. The import keeps everything
    /// else and names these, rather than failing the whole app.
    public var failures: [String] = []

    public init() {}
}

/// The review answers that a store already holds. The demo account user name
/// and password are never here; they live in the Keychain. Spec section 9.5.
public struct ImportedReview: Sendable, Equatable {
    public var contactFirstName: String?
    public var contactLastName: String?
    public var contactEmail: String?
    public var contactPhone: String?
    public var demoAccountRequired: Bool?
    public var notes: String?
    public var applePrimaryCategory: String?
    public var appleSecondaryCategory: String?
    public var usesNonExemptEncryption: Bool?

    public init() {}
}

public struct ImportedStoreAsset: Sendable, Equatable {
    public let locale: String
    public let kind: String
    public let url: URL
    public let fileName: String

    public init(locale: String, kind: String, url: URL, fileName: String) {
        self.locale = locale
        self.kind = kind
        self.url = url
        self.fileName = fileName
    }

    public var deviceClass: Manifest.DeviceClass? {
        Manifest.DeviceClass(storeBucket: kind)
    }
}

public extension Manifest.DeviceClass {
    /// The device class behind a store's own bucket name.
    ///
    /// Apple names a screenshot bucket by display type and Google names it by
    /// image type. Both land here, so the import and the editing tabs group
    /// live media the same way.
    init?(storeBucket: String) {
        switch storeBucket {
        case "phoneScreenshots", "APP_IPHONE_67", "APP_IPHONE_65",
             "APP_IPHONE_61", "APP_IPHONE_58", "APP_IPHONE_55", "APP_IPHONE_47": self = .phone
        case "sevenInchScreenshots": self = .tablet7
        case "tenInchScreenshots", "APP_IPAD_PRO_3GEN_129", "APP_IPAD_PRO_129",
             "APP_IPAD_PRO_3GEN_11": self = .tablet10
        case "tvScreenshots", "APP_APPLE_TV": self = .tv
        case "wearScreenshots", "APP_APPLE_WATCH_SERIES_10": self = .watch
        case "APP_DESKTOP": self = .desktop
        case "APP_VISION_PRO": self = .vision
        default: return nil
        }
    }
}

public struct StoreConnectionClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func appleApps(credential: AppleCredential) async throws -> [RemoteStoreApp] {
        let token = try AppleJWT.make(credential: credential)
        var next = URL(string: "https://api.appstoreconnect.apple.com/v1/apps?limit=200")
        var result: [RemoteStoreApp] = []
        while let url = next {
            let data = try await appleGET(url, token: token)
            let payload = try JSONDecoder().decode(AppleAppsResponse.self, from: data)
            result.append(contentsOf: payload.data.map {
                RemoteStoreApp(id: $0.id, name: $0.attributes.name,
                               identifier: $0.attributes.bundleID)
            })
            next = payload.links?.next.flatMap(URL.init(string:))
        }
        return result
    }

    /// The Publishing API is package-scoped, but the Play Developer Reporting
    /// API can enumerate every app visible to the same service account.
    public func googleApps(credential: GoogleServiceAccount) async throws -> [RemoteStoreApp] {
        let scope = "https://www.googleapis.com/auth/playdeveloperreporting"
        let token = try await googleAccessToken(credential: credential, scope: scope)
        var components = URLComponents(
            string: "https://playdeveloperreporting.googleapis.com/v1beta1/apps:search")!
        components.queryItems = [URLQueryItem(name: "pageSize", value: "1000")]
        var result: [RemoteStoreApp] = []
        while let url = components.url {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: request)
            try Self.requireSuccess(response, data: data)
            let page = try JSONDecoder().decode(GoogleAppsResponse.self, from: data)
            result += (page.apps ?? []).map {
                RemoteStoreApp(id: $0.packageName,
                               name: $0.displayName ?? $0.packageName,
                               identifier: $0.packageName)
            }
            guard let next = page.nextPageToken, !next.isEmpty else { break }
            components.queryItems = [URLQueryItem(name: "pageSize", value: "1000"),
                                     URLQueryItem(name: "pageToken", value: next)]
        }
        return result
    }

    /// The icon of every named app, keyed by its App Store id.
    ///
    /// App Store Connect serves no marketing icon, but every build carries the
    /// icon it shipped with, and one filtered request covers the whole list.
    /// An app with no build has no icon here, and the picker shows the store
    /// mark instead.
    public func appleIcons(appIDs: [String], credential: AppleCredential,
                           side: Int = 180) async throws -> AppleIcons {
        guard !appIDs.isEmpty else { return AppleIcons() }
        let api = StoreAPI(credentials: StoreCredentials(apple: credential),
                           record: { _ in }, session: session)
        var result = AppleIcons()

        // One request per app, and the newest build of that app.
        //
        // The old shape asked for 200 builds across every app at once, sorted
        // by date. An account whose newest 200 builds belong to two apps left
        // every other app without an icon, and nothing said so. A request per
        // app cannot crowd one app out with another app's history.
        for appID in appIDs {
            do {
                let payload = JSON(data: try await api.apple(
                    "GET", "/v1/builds?filter%5Bapp%5D=\(appID)"
                        + "&limit=1&sort=-uploadedDate"
                        + "&fields%5Bbuilds%5D=iconAssetToken").data)
                guard let build = payload["data"].array.first else {
                    // The app record exists and no build sits under it. That
                    // is a state, and the picker shows the store mark.
                    result.withoutBuild.insert(appID)
                    continue
                }
                guard let url = StoreImportReader.imageURL(
                    build["attributes"]["iconAssetToken"], side: side) else {
                    result.withoutIcon.insert(appID)
                    continue
                }
                result.urls[appID] = url
            } catch {
                // One app that fails never costs the other nine their icons.
                result.failures.append("\(appID): \(error.localizedDescription)")
            }
        }
        return result
    }

    /// What the icon read found, and what it could not find.
    ///
    /// A missing icon used to be silent, so "no icons" and "the request
    /// failed" looked the same on screen. Each reason is named now.
    public struct AppleIcons: Sendable {
        public var urls: [String: URL] = [:]
        /// The apps whose record carries no build at all.
        public var withoutBuild: Set<String> = []
        /// The apps whose newest build carries no icon, which is what a
        /// processing build looks like.
        public var withoutIcon: Set<String> = []
        public var failures: [String] = []

        public init() {}

        /// The one line the picker shows when nothing came back.
        public var explanation: String? {
            if let first = failures.first {
                return failures.count == 1
                    ? "The icons could not be read. \(first)"
                    : "\(failures.count) icons could not be read. \(first)"
            }
            if !withoutBuild.isEmpty {
                return "\(withoutBuild.count) apps carry no build yet, and an App Store icon comes from a build."
            }
            if !withoutIcon.isEmpty {
                return "\(withoutIcon.count) builds carry no icon yet. Apple attaches one when it finishes processing the build."
            }
            return nil
        }
    }

    public func importApple(appID: String,
                            credential: AppleCredential) async throws -> ImportedStoreListing {
        try await StoreImportReader(credentials: StoreCredentials(apple: credential),
                                    session: session).apple(appID: appID)
    }

    /// Android Publisher has no endpoint that lists every app available to a
    /// service account. Testing a known package by reading one review verifies
    /// both OAuth and the mandatory Play Console invitation without writing.
    public func testGoogle(credential: GoogleServiceAccount,
                           packageName: String) async throws -> String {
        let token = try await googleAccessToken(credential: credential)
        guard !packageName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "OAuth accepted for \(credential.clientEmail). Add a package name to verify Play Console access."
        }

        let escaped = packageName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? packageName
        guard let url = URL(string: "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/\(escaped)/reviews?maxResults=1") else {
            throw ConnectionError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try Self.requireSuccess(response, data: data)
        return "Connected · \(credential.clientEmail)"
    }

    public func importGoogle(credential: GoogleServiceAccount,
                             packageName: String) async throws -> ImportedStoreListing {
        try await StoreImportReader(credentials: StoreCredentials(google: credential),
                                    session: session).google(packageName: packageName)
    }

    private func googleAccessToken(
        credential: GoogleServiceAccount,
        scope: String = "https://www.googleapis.com/auth/androidpublisher"
    ) async throws -> String {
        let assertion = try GoogleJWT.make(credential: credential, scope: scope)
        guard let url = URL(string: credential.tokenURI) else {
            throw ConnectionError.invalidTokenURL
        }
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "urn:ietf:params:oauth:grant-type:jwt-bearer"),
            URLQueryItem(name: "assertion", value: assertion),
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)
        let (data, response) = try await session.data(for: request)
        try Self.requireSuccess(response, data: data)
        return try JSONDecoder().decode(GoogleTokenResponse.self, from: data).accessToken
    }

    private func appleGET(_ url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try Self.requireSuccess(response, data: data)
        return data
    }

    private static func appleURL(_ path: String) throws -> URL {
        guard let url = URL(string: "https://api.appstoreconnect.apple.com\(path)") else {
            throw ConnectionError.invalidResponse
        }
        return url
    }

    private static func googleURL(_ path: String) throws -> URL {
        guard let url = URL(string: "https://androidpublisher.googleapis.com\(path)") else {
            throw ConnectionError.invalidResponse
        }
        return url
    }

    private static func requireSuccess(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ConnectionError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = APIError.message(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw ConnectionError.http(http.statusCode, detail)
        }
    }
}

public enum ConnectionError: Error, LocalizedError {
    case invalidResponse
    case invalidTokenURL
    case invalidPrivateKey
    case malformedPrivateKey
    case signingFailed(String)
    case http(Int, String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "The store returned an invalid response."
        case .invalidTokenURL: "The service account has an invalid token URL."
        case .invalidPrivateKey: "The private key could not be read. Choose the original credential file."
        case .malformedPrivateKey: "The service account private key is not valid PKCS#8 data."
        case .signingFailed(let detail): "The Google assertion could not be signed. \(detail)"
        case .http(let status, let detail): "The store returned HTTP \(status): \(detail)"
        }
    }
}

/// Shared with `StoreAPI`. Both the read clients and the runner sign the same
/// way, so the signing code exists once.
enum AppleJWT {
    static func make(credential: AppleCredential, now: Date = Date()) throws -> String {
        let header: [String: Any] = ["alg": "ES256", "kid": credential.keyID, "typ": "JWT"]
        let issued = Int(now.timeIntervalSince1970)
        let payload: [String: Any] = [
            "iss": credential.issuerID,
            "iat": issued,
            "exp": issued + 15 * 60,
            "aud": "appstoreconnect-v1",
        ]
        let signingInput = try JWT.signingInput(header: header, payload: payload)
        let key: P256.Signing.PrivateKey
        do {
            key = try P256.Signing.PrivateKey(pemRepresentation: credential.privateKeyPEM)
        } catch {
            throw ConnectionError.invalidPrivateKey
        }
        let signature = try key.signature(for: Data(signingInput.utf8))
        return "\(signingInput).\(signature.rawRepresentation.base64URL)"
    }
}

enum GoogleJWT {
    static func make(credential: GoogleServiceAccount,
                     scope: String = "https://www.googleapis.com/auth/androidpublisher",
                     now: Date = Date()) throws -> String {
        let header: [String: Any] = ["alg": "RS256", "typ": "JWT"]
        let issued = Int(now.timeIntervalSince1970)
        let payload: [String: Any] = [
            "iss": credential.clientEmail,
            "scope": scope,
            "aud": credential.tokenURI,
            "iat": issued,
            "exp": issued + 60 * 60,
        ]
        let signingInput = try JWT.signingInput(header: header, payload: payload)
        let keyData = try PKCS8.privateKeyData(from: credential.privateKey)
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]
        var keyError: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary,
                                             &keyError) else {
            throw ConnectionError.signingFailed(keyError?.takeRetainedValue().localizedDescription ?? "Invalid RSA key.")
        }
        var signError: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            key, .rsaSignatureMessagePKCS1v15SHA256, Data(signingInput.utf8) as CFData,
            &signError) as Data? else {
            throw ConnectionError.signingFailed(signError?.takeRetainedValue().localizedDescription ?? "Unknown signing error.")
        }
        return "\(signingInput).\(signature.base64URL)"
    }
}

private enum JWT {
    static func signingInput(header: [String: Any], payload: [String: Any]) throws -> String {
        let options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
        let headerData = try JSONSerialization.data(withJSONObject: header, options: options)
        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: options)
        return "\(headerData.base64URL).\(payloadData.base64URL)"
    }
}

private enum PKCS8 {
    static func privateKeyData(from pem: String) throws -> Data {
        let body = pem.components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") }
            .joined()
        guard let der = Data(base64Encoded: body) else { throw ConnectionError.invalidPrivateKey }

        var outer = DERReader(der)
        let sequence = try outer.read(tag: 0x30)
        var content = DERReader(sequence)
        _ = try content.read(tag: 0x02) // version
        _ = try content.read(tag: 0x30) // algorithm identifier
        return try content.read(tag: 0x04) // PKCS#1 RSAPrivateKey
    }

    private struct DERReader {
        let data: Data
        var offset = 0

        init(_ data: Data) { self.data = data }

        mutating func read(tag expectedTag: UInt8) throws -> Data {
            guard offset < data.count, data[offset] == expectedTag else {
                throw ConnectionError.malformedPrivateKey
            }
            offset += 1
            let length = try readLength()
            guard length >= 0, offset + length <= data.count else {
                throw ConnectionError.malformedPrivateKey
            }
            defer { offset += length }
            return data.subdata(in: offset..<(offset + length))
        }

        mutating func readLength() throws -> Int {
            guard offset < data.count else { throw ConnectionError.malformedPrivateKey }
            let first = Int(data[offset])
            offset += 1
            if first & 0x80 == 0 { return first }
            let byteCount = first & 0x7f
            guard byteCount > 0, byteCount <= 4, offset + byteCount <= data.count else {
                throw ConnectionError.malformedPrivateKey
            }
            var value = 0
            for _ in 0..<byteCount {
                value = (value << 8) | Int(data[offset])
                offset += 1
            }
            return value
        }
    }
}

private struct AppleAppsResponse: Decodable {
    struct Item: Decodable {
        struct Attributes: Decodable {
            let name: String
            let bundleID: String

            enum CodingKeys: String, CodingKey {
                case name
                case bundleID = "bundleId"
            }
        }
        let id: String
        let attributes: Attributes
    }
    let data: [Item]
    let links: AppleLinks?
}

private struct AppleLinks: Decodable { let next: String? }

private struct GoogleTokenResponse: Decodable {
    let accessToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

private struct GoogleAppsResponse: Decodable {
    struct App: Decodable {
        let packageName: String
        let displayName: String?
    }
    let apps: [App]?
    let nextPageToken: String?
}

enum APIError {
    static func message(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }
        if let errors = object["errors"] as? [[String: Any]],
           let first = errors.first,
           let detail = first["detail"] as? String ?? first["title"] as? String {
            return detail
        }
        if let error = object["error"] as? [String: Any] {
            return error["message"] as? String ?? error["error_description"] as? String
        }
        if let error = object["error"] as? String { return error }
        return String(data: data, encoding: .utf8)
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
