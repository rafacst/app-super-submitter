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
    public var locales: [String: Locale] = [:]
    public var assets: [ImportedStoreAsset] = []

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
        switch kind {
        case "phoneScreenshots", "APP_IPHONE_67", "APP_IPHONE_65",
             "APP_IPHONE_61", "APP_IPHONE_58", "APP_IPHONE_55", "APP_IPHONE_47": .phone
        case "sevenInchScreenshots": .tablet7
        case "tenInchScreenshots", "APP_IPAD_PRO_3GEN_129", "APP_IPAD_PRO_129",
             "APP_IPAD_PRO_3GEN_11": .tablet10
        case "tvScreenshots", "APP_APPLE_TV": .tv
        case "wearScreenshots", "APP_APPLE_WATCH_SERIES_10": .watch
        case "APP_DESKTOP": .desktop
        case "APP_VISION_PRO": .vision
        default: nil
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

    public func importApple(appID: String,
                            credential: AppleCredential) async throws -> ImportedStoreListing {
        let token = try AppleJWT.make(credential: credential)
        var result = ImportedStoreListing()

        let infosURL = try Self.appleURL("/v1/apps/\(appID)/appInfos?limit=1")
        let infos = try JSONDecoder().decode(AppleResourceList<EmptyAttributes>.self,
                                             from: await appleGET(infosURL, token: token))
        if let infoID = infos.data.first?.id {
            let url = try Self.appleURL("/v1/appInfos/\(infoID)/appInfoLocalizations?limit=200")
            let localizations = try JSONDecoder().decode(
                AppleResourceList<AppleInfoLocaleAttributes>.self,
                from: await appleGET(url, token: token))
            for item in localizations.data {
                var locale = result.locales[item.attributes.locale] ?? .init()
                locale.name = item.attributes.name
                locale.subtitle = item.attributes.subtitle
                locale.privacyPolicyURL = item.attributes.privacyPolicyURL
                locale.privacyPolicyText = item.attributes.privacyPolicyText
                locale.privacyChoicesURL = item.attributes.privacyChoicesURL
                result.locales[item.attributes.locale] = locale
            }
        }

        let versionsURL = try Self.appleURL(
            "/v1/apps/\(appID)/appStoreVersions?filter%5Bplatform%5D=IOS&limit=1")
        let versions = try JSONDecoder().decode(
            AppleResourceList<AppleVersionAttributes>.self,
            from: await appleGET(versionsURL, token: token))
        if let version = versions.data.first {
            result.versionName = version.attributes.versionString
            let url = try Self.appleURL(
                "/v1/appStoreVersions/\(version.id)/appStoreVersionLocalizations?limit=200")
            let localizations = try JSONDecoder().decode(
                AppleResourceList<AppleVersionLocaleAttributes>.self,
                from: await appleGET(url, token: token))
            for item in localizations.data {
                var locale = result.locales[item.attributes.locale] ?? .init()
                locale.description = item.attributes.description
                locale.whatsNew = item.attributes.whatsNew
                locale.keywords = item.attributes.keywords
                locale.promotionalText = item.attributes.promotionalText
                locale.supportURL = item.attributes.supportURL
                locale.marketingURL = item.attributes.marketingURL
                result.locales[item.attributes.locale] = locale
                result.assets += try await appleScreenshotAssets(
                    localizationID: item.id, locale: item.attributes.locale, token: token)
            }
        }
        return result
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
        let token = try await googleAccessToken(credential: credential)
        let escaped = packageName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? packageName
        let editURL = try Self.googleURL("/androidpublisher/v3/applications/\(escaped)/edits")
        var create = URLRequest(url: editURL)
        create.httpMethod = "POST"
        create.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        create.setValue("application/json", forHTTPHeaderField: "Content-Type")
        create.httpBody = Data("{}".utf8)
        let (editData, editResponse) = try await session.data(for: create)
        try Self.requireSuccess(editResponse, data: editData)
        let editID = try JSONDecoder().decode(GoogleEdit.self, from: editData).id
        let base = "/androidpublisher/v3/applications/\(escaped)/edits/\(editID)"

        do {
            let listingsURL = try Self.googleURL("\(base)/listings")
            var request = URLRequest(url: listingsURL)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: request)
            try Self.requireSuccess(response, data: data)
            let payload = try JSONDecoder().decode(GoogleListingsResponse.self, from: data)
            var result = ImportedStoreListing()
            for item in payload.listings ?? [] {
                var locale = ImportedStoreListing.Locale()
                locale.name = item.title
                locale.description = item.fullDescription
                locale.subtitle = item.shortDescription
                locale.video = item.video
                result.locales[item.language] = locale
                for imageType in ["phoneScreenshots", "sevenInchScreenshots",
                                  "tenInchScreenshots", "tvScreenshots", "wearScreenshots",
                                  "icon", "featureGraphic"] {
                    let imageURL = try Self.googleURL(
                        "\(base)/listings/\(item.language)/\(imageType)")
                    var imageRequest = URLRequest(url: imageURL)
                    imageRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    let (imageData, imageResponse) = try await session.data(for: imageRequest)
                    try Self.requireSuccess(imageResponse, data: imageData)
                    let images = try JSONDecoder().decode(GoogleImagesResponse.self,
                                                           from: imageData)
                    for (index, image) in (images.images ?? []).enumerated() {
                        guard let url = URL(string: image.url) else { continue }
                        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
                        result.assets.append(ImportedStoreAsset(
                            locale: item.language, kind: imageType, url: url,
                            fileName: "\(imageType)-\(index + 1).\(ext)"))
                    }
                }
            }
            try await deleteGoogleEdit(base: base, token: token)
            return result
        } catch {
            try? await deleteGoogleEdit(base: base, token: token)
            throw error
        }
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

    private func appleScreenshotAssets(localizationID: String, locale: String,
                                       token: String) async throws -> [ImportedStoreAsset] {
        let url = try Self.appleURL(
            "/v1/appStoreVersionLocalizations/\(localizationID)"
                + "/appScreenshotSets?include=appScreenshots&limit=50")
        let data = try await appleGET(url, token: token)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        let sets = object["data"] as? [[String: Any]] ?? []
        var types: [String: String] = [:]
        for set in sets {
            guard let id = set["id"] as? String,
                  let attributes = set["attributes"] as? [String: Any],
                  let type = attributes["screenshotDisplayType"] as? String else { continue }
            types[id] = type
        }
        return (object["included"] as? [[String: Any]] ?? []).compactMap { item in
            guard item["type"] as? String == "appScreenshots",
                  let attributes = item["attributes"] as? [String: Any],
                  let image = attributes["imageAsset"] as? [String: Any],
                  let template = image["templateUrl"] as? String,
                  let relationships = item["relationships"] as? [String: Any],
                  let set = relationships["appScreenshotSet"] as? [String: Any],
                  let relationData = set["data"] as? [String: Any],
                  let setID = relationData["id"] as? String,
                  let kind = types[setID] else { return nil }
            let width = image["width"] as? Int ?? 1_290
            let height = image["height"] as? Int ?? 2_796
            let rendered = template.replacingOccurrences(of: "{w}", with: String(width))
                .replacingOccurrences(of: "{h}", with: String(height))
                .replacingOccurrences(of: "{f}", with: "png")
                .replacingOccurrences(of: "{c}", with: "")
            guard let url = URL(string: rendered) else { return nil }
            let fileName = attributes["fileName"] as? String
                ?? "\(kind)-\(item["id"] as? String ?? UUID().uuidString).png"
            return ImportedStoreAsset(locale: locale, kind: kind, url: url, fileName: fileName)
        }
    }

    private func deleteGoogleEdit(base: String, token: String) async throws {
        var request = URLRequest(url: try Self.googleURL(base))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try Self.requireSuccess(response, data: data)
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

private struct AppleResourceList<Attributes: Decodable>: Decodable {
    struct Item: Decodable {
        let id: String
        let attributes: Attributes
    }
    let data: [Item]
}

private struct EmptyAttributes: Decodable {}

private struct AppleInfoLocaleAttributes: Decodable {
    let locale: String
    let name: String?
    let subtitle: String?
    let privacyPolicyURL: String?
    let privacyPolicyText: String?
    let privacyChoicesURL: String?

    enum CodingKeys: String, CodingKey {
        case locale, name, subtitle, privacyPolicyText
        case privacyPolicyURL = "privacyPolicyUrl"
        case privacyChoicesURL = "privacyChoicesUrl"
    }
}

private struct AppleVersionAttributes: Decodable {
    let versionString: String?
}

private struct AppleVersionLocaleAttributes: Decodable {
    let locale: String
    let description: String?
    let whatsNew: String?
    let keywords: String?
    let promotionalText: String?
    let supportURL: String?
    let marketingURL: String?

    enum CodingKeys: String, CodingKey {
        case locale, description, whatsNew, keywords, promotionalText
        case supportURL = "supportUrl"
        case marketingURL = "marketingUrl"
    }
}

private struct GoogleTokenResponse: Decodable {
    let accessToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

private struct GoogleEdit: Decodable { let id: String }

private struct GoogleListingsResponse: Decodable {
    struct Listing: Decodable {
        let language: String
        let title: String?
        let fullDescription: String?
        let shortDescription: String?
        let video: String?
    }
    let listings: [Listing]?
}

private struct GoogleAppsResponse: Decodable {
    struct App: Decodable {
        let packageName: String
        let displayName: String?
    }
    let apps: [App]?
    let nextPageToken: String?
}

private struct GoogleImagesResponse: Decodable {
    struct Image: Decodable { let url: String }
    let images: [Image]?
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
