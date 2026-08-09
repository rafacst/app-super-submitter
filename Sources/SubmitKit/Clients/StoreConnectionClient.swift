import CryptoKit
import Foundation
import Security

public struct RemoteStoreApp: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let identifier: String
    /// What the app ships on, in Apple's own order of a platform picker.
    ///
    /// One App Store record covers every platform, so "an iOS app" and "a Mac
    /// app" are the same record with different versions under it. Empty means
    /// the record carries no version yet, and the app then says so rather
    /// than guessing at iOS.
    public let platforms: [Manifest.Platform]

    public init(id: String, name: String, identifier: String,
                platforms: [Manifest.Platform] = []) {
        self.id = id
        self.name = name
        self.identifier = identifier
        self.platforms = platforms
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
    ///
    /// The Apple half comes out of `screenshot-sizes.json`, the one table the
    /// upload already reads. A hand-written copy sat here and drifted: it
    /// missed `APP_IPHONE_69`, and it spelled the watch and the vision types
    /// the way Apple does not. Every screenshot in those buckets was dropped
    /// on the way in without a word.
    init?(storeBucket: String) {
        switch storeBucket {
        case "phoneScreenshots": self = .phone
        case "sevenInchScreenshots": self = .tablet7
        case "tenInchScreenshots": self = .tablet10
        case "tvScreenshots": self = .tv
        case "wearScreenshots": self = .watch
        default:
            guard let derived = AssetInspector.deviceClass(forAppleDisplayType: storeBucket)
            else { return nil }
            self = derived
        }
    }
}

public struct StoreConnectionClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Every app the key can see, and what each one ships on.
    ///
    /// The versions ride along on the same request. One App Store record
    /// carries every platform it ships on, so "is this a Mac app" is only
    /// answerable from its versions, and a second request per app to learn it
    /// would cost one round trip for every row of the picker.
    ///
    /// Which app a version belongs to is answered by the **app**, not by the
    /// version: an included row carries `type`, `id`, `attributes`, and
    /// `links` and no relationships at all. Asking `fields[appStoreVersions]`
    /// for the `app` relationship did not change that, and the read learned
    /// no platform for any app for as long as it tried.
    public func appleApps(credential: AppleCredential) async throws -> [RemoteStoreApp] {
        let token = try AppleJWT.make(credential: credential)
        var next = URL(string: "https://api.appstoreconnect.apple.com/v1/apps?limit=200"
            + "&include=appStoreVersions"
            + "&fields%5BappStoreVersions%5D=platform"
            + "&limit%5BappStoreVersions%5D=50")
        var result: [RemoteStoreApp] = []
        while let url = next {
            let data = try await appleGET(url, token: token)
            let payload = try JSONDecoder().decode(AppleAppsResponse.self, from: data)
            let platforms = Self.platforms(payload.included ?? [], apps: payload.data)
            result.append(contentsOf: payload.data.map {
                RemoteStoreApp(id: $0.id, name: $0.attributes.name,
                               identifier: $0.attributes.bundleID,
                               platforms: platforms[$0.id] ?? [])
            })
            next = payload.links?.next.flatMap(Self.trustedAppleURL)
        }
        return result
    }

    /// App id -> the platforms its versions name, in `Platform.allCases`
    /// order so two apps on the same platforms always read the same way.
    ///
    /// The owner comes off the **app's** own `appStoreVersions` relationship.
    /// App Store Connect fills `data` there, on the side the `include` was
    /// asked for, and leaves the included version's own `app` back reference
    /// carrying `links` alone. Reading only that back reference learned no
    /// platform for any app, the picker then showed no platform under any
    /// row, and the import fell back on its iPhone guess and wrote every Mac
    /// app into `store.yaml` as an iOS app.
    static func platforms(_ included: [AppleIncluded],
                          apps: [AppleAppsResponse.Item]) -> [String: [Manifest.Platform]] {
        var owner: [String: String] = [:]
        for app in apps {
            for version in app.relationships?.appStoreVersions?.data ?? [] {
                owner[version.id] = app.id
            }
        }
        var found: [String: Set<Manifest.Platform>] = [:]
        for item in included where item.type == "appStoreVersions" {
            guard let appID = owner[item.id],
                  let raw = item.attributes?.platform,
                  let platform = Manifest.Platform(rawValue: raw) else { continue }
            found[appID, default: []].insert(platform)
        }
        return found.mapValues { set in
            Manifest.Platform.allCases.filter(set.contains)
        }
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

    public func importApple(appID: String, credential: AppleCredential,
                            platform: String? = nil) async throws -> ImportedStoreListing {
        try await StoreImportReader(credentials: StoreCredentials(apple: credential),
                                    session: session).apple(appID: appID, platform: platform)
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

    public func testGoogle(credential: GoogleOAuthCredential,
                           packageName: String) async throws -> String {
        guard !packageName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Connected with Google. Add a package name to verify Play Console access."
        }
        let escaped = packageName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? packageName
        let api = StoreAPI(credentials: StoreCredentials(googleOAuth: credential),
                           record: { _ in }, session: session)
        _ = try await api.google(
            "GET", "/androidpublisher/v3/applications/\(escaped)/reviews",
            query: [URLQueryItem(name: "maxResults", value: "1")])
        return "Connected with Google"
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
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = FormBody.encoded([
            ("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer"),
            ("assertion", assertion),
        ])
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

    static func trustedAppleURL(_ value: String) -> URL? {
        StoreDiagnostics.appleNextPath(value).flatMap { try? appleURL($0) }
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
        case .invalidResponse:
            "The store answered with something this app could not read. Try again in a moment."
        case .invalidTokenURL:
            "The service account file is missing its token address. Download the key again from the Google Cloud console."
        case .invalidPrivateKey:
            "The private key could not be read. Choose the original file the store gave you, not a copy you edited."
        case .malformedPrivateKey:
            "The service account file does not hold a usable key. Download it again from the Google Cloud console."
        case .signingFailed:
            "The Google credentials could not be signed. Download the service account file again."
        case .http(let status, let detail): Self.explain(status: status, detail: detail)
        }
    }

    /// What a refusal means, in the developer's terms.
    ///
    /// A status code names the protocol, not the problem. The developer needs
    /// to know which of three things went wrong: who they are, what they
    /// asked for, or the store itself. The store's own sentence follows when
    /// it has one, because Apple and Google usually name the exact field.
    static func explain(status: Int, detail: String) -> String {
        let cause = switch status {
        case 400:
            "The store refused this as it stands."
        case 401:
            "The store did not accept the credentials. Check the credential file and the fields beside it on the Stores tab."
        case 403:
            "This account is not allowed to do that. Check the role its key was given in the store console."
        case 404:
            "The store holds no record of this. Check the app id and the bundle id on the Stores tab."
        case 409:
            "The store already holds something that conflicts with this."
        case 422:
            "The store understood the request and refused the values in it."
        case 429:
            "The store is holding this account back for a moment. Wait a minute and run it again."
        case 500...599:
            "The store is having trouble on its own side. Nothing here is wrong, so try again in a few minutes."
        default:
            "The store refused this."
        }
        let sentence = Self.sentence(from: detail)
        return sentence.isEmpty ? cause : "\(cause) \(sentence)"
    }

    /// The store's own words, when they are words.
    ///
    /// A payload that is still JSON, or a wall of it, says nothing to a
    /// developer, so it is dropped rather than printed at them.
    static func sentence(from detail: String) -> String {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("{"), !trimmed.hasPrefix("["),
              !trimmed.hasPrefix("<"), trimmed.count <= 240 else { return "" }
        return trimmed.hasSuffix(".") ? trimmed : trimmed + "."
    }
}

/// Shared with `StoreAPI`. Both the read clients and the runner sign the same
/// way, so the signing code exists once.
enum AppleJWT {
    /// How long a token this app signs stays good for. Apple refuses anything
    /// over 20 minutes. A cache that holds a token reads this and never its
    /// own copy of the number, because a second copy drifts.
    static let lifetime: TimeInterval = 15 * 60

    static func make(credential: AppleCredential, now: Date = Date()) throws -> String {
        let header: [String: Any] = ["alg": "ES256", "kid": credential.keyID, "typ": "JWT"]
        let issued = Int(now.timeIntervalSince1970)
        let payload: [String: Any] = [
            "iss": credential.issuerID,
            "iat": issued,
            "exp": issued + Int(Self.lifetime),
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

/// An `application/x-www-form-urlencoded` body.
///
/// `URLComponents.percentEncodedQuery` writes a query, not a form body: it
/// leaves `+` alone, and a form reader takes a `+` for a space. Today every
/// value here is a base64url token or a fixed URN, so nothing breaks. This
/// keeps it that way for the next field somebody adds.
enum FormBody {
    /// RFC 3986 unreserved. Everything else takes a percent escape, which a
    /// form reader decodes back to the exact bytes.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func encoded(_ fields: [(String, String)]) -> Data {
        Data(fields.map { "\(escape($0.0))=\(escape($0.1))" }.joined(separator: "&").utf8)
    }

    private static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
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

struct AppleAppsResponse: Decodable {
    struct Item: Decodable {
        struct Attributes: Decodable {
            let name: String
            let bundleID: String

            enum CodingKeys: String, CodingKey {
                case name
                case bundleID = "bundleId"
            }
        }
        /// The version ids this app owns. App Store Connect fills it for the
        /// relationship the request includes, which is the only side that
        /// names the owner at all.
        struct Relationships: Decodable {
            struct Versions: Decodable {
                struct Item: Decodable { let id: String }
                let data: [Item]?
            }
            let appStoreVersions: Versions?
        }
        let id: String
        let attributes: Attributes
        let relationships: Relationships?
    }
    let data: [Item]
    let included: [AppleIncluded]?
    let links: AppleLinks?
}

/// One row of the `included` array. Only the app store versions are read, and
/// only for their platform, so everything here is optional and a shape the
/// reader does not know costs nothing.
struct AppleIncluded: Decodable {
    struct Attributes: Decodable { let platform: String? }

    let id: String
    let type: String
    let attributes: Attributes?
}

struct AppleLinks: Decodable { let next: String? }

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
