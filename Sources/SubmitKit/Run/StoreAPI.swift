import CryptoKit
import Foundation

/// The three systems that this app calls. Each one owns its token bucket.
/// Spec section 14: "One token bucket per system. The three buckets are
/// independent."
public enum PlanSystem: String, Sendable, CaseIterable, Codable {
    case apple, google, provider

    public var displayName: String {
        switch self {
        case .apple: "App Store"
        case .google: "Google Play"
        case .provider: "Provider"
        }
    }
}

public struct StoreCredentials: Sendable {
    public var apple: AppleCredential?
    public var google: GoogleServiceAccount?
    public var googleOAuth: GoogleOAuthCredential?
    public var revenueCatKey: String?
    /// The demo account. It reaches Apple in the review details and it never
    /// reaches `store.yaml`. Spec section 9.5.
    public var reviewer: ReviewerCredential?

    public init(apple: AppleCredential? = nil, google: GoogleServiceAccount? = nil,
                googleOAuth: GoogleOAuthCredential? = nil,
                revenueCatKey: String? = nil, reviewer: ReviewerCredential? = nil) {
        self.apple = apple
        self.google = google
        self.googleOAuth = googleOAuth
        self.revenueCatKey = revenueCatKey
        self.reviewer = reviewer
    }
}

public typealias CallRecorder = @Sendable (APICall) async -> Void

/// One HTTP client for every store call.
///
/// It signs, it retries, it slows down under a rate limit, and it reports every
/// call to the recorder. No call site repeats any of that.
///
/// `// ponytail: one client, three buckets. A second HTTP stack per store would
/// // duplicate the retry policy three times and drift on the fourth bug.`
public actor StoreAPI {
    public struct Result: Sendable {
        public let data: Data
        public let status: Int
        public let headers: [String: String]

        public func header(_ name: String) -> String? {
            headers[name.lowercased()]
        }
    }

    private let session: URLSession
    private let credentials: StoreCredentials
    private let record: CallRecorder

    private var appleToken: (value: String, expires: Date)?
    private var googleToken: (value: String, expires: Date)?
    private var nextAllowed: [PlanSystem: Date] = [:]

    /// Spec section 14. Retry on these, and on nothing else.
    private static let retryable: Set<Int> = [429, 500, 502, 503, 504]
    private static let maxAttempts = 5

    public init(credentials: StoreCredentials, record: @escaping CallRecorder,
                session: URLSession = .shared) {
        self.credentials = credentials
        self.record = record
        self.session = session
    }

    // MARK: - The three systems

    /// `query` carries the items that need encoding. Apple names its filters
    /// `filter[reportType]`, and a bracket pasted into a path string is not a
    /// legal URL, so the report reads pass their filters here.
    @discardableResult
    public func apple(_ method: String, _ path: String,
                      body: Any? = nil,
                      query: [URLQueryItem] = []) async throws -> Result {
        var components = URLComponents(string: "https://api.appstoreconnect.apple.com" + path)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw ConnectionError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(try appleBearer())", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return try await perform(request, system: .apple, path: path)
    }

    @discardableResult
    public func google(_ method: String, _ path: String, body: Any? = nil,
                       query: [URLQueryItem] = []) async throws -> Result {
        var components = URLComponents(string: "https://androidpublisher.googleapis.com" + path)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw ConnectionError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(try await googleBearer())", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return try await perform(request, system: .google, path: path)
    }

    @discardableResult
    public func revenueCat(_ method: String, _ path: String,
                           body: Any? = nil) async throws -> Result {
        guard let key = credentials.revenueCatKey, !key.isEmpty else {
            throw ProviderConnectionError.missingAPIKey
        }
        var request = URLRequest(url: try Self.url("https://api.revenuecat.com" + path))
        request.httpMethod = method
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return try await perform(request, system: .provider, path: path)
    }

    // MARK: - Uploads

    /// One Apple `uploadOperation`, exactly as the reservation response
    /// described it. Spec sections 7.5 and 7.6.
    @discardableResult
    public func appleUploadOperation(method: String, urlString: String,
                                     headers: [String: String],
                                     body: Data) async throws -> Result {
        var request = URLRequest(url: try Self.url(urlString))
        request.httpMethod = method
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = body
        return try await perform(request, system: .apple, path: "uploadOperation")
    }

    /// A Google multipart upload. Google takes the bytes in one call.
    @discardableResult
    public func googleUpload(_ path: String, contentType: String, body: Data,
                             query: [URLQueryItem] = []) async throws -> Result {
        var request = try await googleUploadRequest(path, contentType: contentType, query: query)
        request.httpBody = body
        return try await perform(request, system: .google, path: path)
    }

    /// Streams a large artifact from disk instead of retaining a second copy
    /// of it in memory for the duration of the upload.
    @discardableResult
    public func googleUpload(_ path: String, contentType: String, file: URL,
                             query: [URLQueryItem] = []) async throws -> Result {
        let request = try await googleUploadRequest(path, contentType: contentType, query: query)
        return try await perform(request, system: .google, path: path, bodyFile: file)
    }

    private func googleUploadRequest(_ path: String, contentType: String,
                                     query: [URLQueryItem]) async throws -> URLRequest {
        var components = URLComponents(string: "https://androidpublisher.googleapis.com" + path)
        var items = query
        items.append(URLQueryItem(name: "uploadType", value: "media"))
        components?.queryItems = items
        guard let url = components?.url else { throw ConnectionError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(try await googleBearer())", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        return request
    }

    /// The dry run never reaches this type, but it still has to appear in the
    /// log. Spec section 7.2: a dry run builds every request and sends none.
    public func recordDryRun(system: PlanSystem, method: String, path: String) async {
        await record(APICall(system: system.rawValue, method: method, path: path, dryRun: true))
    }

    // MARK: - The one request path

    private func perform(_ request: URLRequest, system: PlanSystem,
                         path: String, retryOverride: Bool? = nil,
                         bodyFile: URL? = nil) async throws -> Result {
        let method = request.httpMethod ?? "GET"
        let mayRetry = retryOverride
            ?? ["GET", "HEAD", "PUT", "DELETE", "OPTIONS"].contains(method.uppercased())
        var attempt = 0
        while true {
            attempt += 1
            try await waitForBucket(system)
            let started = Date()
            do {
                let data: Data
                let response: URLResponse
                if let bodyFile {
                    (data, response) = try await session.upload(for: request, fromFile: bodyFile)
                } else {
                    (data, response) = try await session.data(for: request)
                }
                guard let http = response as? HTTPURLResponse else {
                    throw ConnectionError.invalidResponse
                }
                let headers = Self.lowercasedHeaders(http)
                let duration = Int(Date().timeIntervalSince(started) * 1000)
                let requestID = headers["x-request-id"] ?? headers["x-guploader-uploadid"]
                readRateLimits(system: system, headers: headers)

                if mayRetry, Self.retryable.contains(http.statusCode), attempt < Self.maxAttempts {
                    await record(APICall(system: system.rawValue, method: method, path: path,
                                         status: http.statusCode, durationMs: duration,
                                         requestId: requestID, error: "retrying"))
                    try await backOff(attempt: attempt, retryAfter: headers["retry-after"])
                    continue
                }
                guard (200..<300).contains(http.statusCode) else {
                    let detail = APIError.message(from: data)
                        ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
                    await record(APICall(system: system.rawValue, method: method, path: path,
                                         status: http.statusCode, durationMs: duration,
                                         requestId: requestID, error: detail))
                    throw ConnectionError.http(http.statusCode, detail)
                }
                await record(APICall(system: system.rawValue, method: method, path: path,
                                     status: http.statusCode, durationMs: duration,
                                     requestId: requestID))
                return Result(data: data, status: http.statusCode, headers: headers)
            } catch let error as ConnectionError {
                throw error
            } catch {
                // A transport failure. The same retry budget applies.
                let duration = Int(Date().timeIntervalSince(started) * 1000)
                await record(APICall(system: system.rawValue, method: method, path: path,
                                     durationMs: duration, error: error.localizedDescription))
                guard mayRetry, attempt < Self.maxAttempts,
                      !(error is CancellationError) else { throw error }
                try await backOff(attempt: attempt, retryAfter: nil)
            }
        }
    }

    /// Exponential backoff with full jitter, base 1 second, cap 60 seconds.
    private func backOff(attempt: Int, retryAfter: String?) async throws {
        if let retryAfter, let seconds = Double(retryAfter), seconds.isFinite, seconds >= 0 {
            try await Task.sleep(for: .seconds(min(seconds, 60)))
            return
        }
        let ceiling = min(60.0, pow(2.0, Double(attempt - 1)))
        try await Task.sleep(for: .seconds(Double.random(in: 0...ceiling)))
    }

    /// Spec section 14. Apple reports the remaining hourly budget on every
    /// response, and the app slows down under 10 percent of it.
    private func readRateLimits(system: PlanSystem, headers: [String: String]) {
        var usedFraction: Double?
        // Each system reports its budget in its own header, so each one reads
        // only its own. Read both and the second silently wins the first.
        switch system {
        case .apple:
            if let value = headers["x-rate-limit"] {
                let fields = Self.semicolonFields(value)
                if let limit = fields["user-hour-lim"], let remaining = fields["user-hour-rem"],
                   limit > 0 {
                    usedFraction = 1 - Double(remaining) / Double(limit)
                }
            }
        case .provider:
            if let usage = headers["revenuecat-rate-limit-current-usage"].flatMap(Int.init),
               let limit = headers["revenuecat-rate-limit-current-limit"].flatMap(Int.init),
               limit > 0 {
                usedFraction = Double(usage) / Double(limit)
            }
        case .google:
            break
        }
        guard let usedFraction, usedFraction > 0.9 else { return }
        nextAllowed[system] = Date().addingTimeInterval(1)
    }

    private func waitForBucket(_ system: PlanSystem) async throws {
        guard let next = nextAllowed[system] else { return }
        let delay = next.timeIntervalSinceNow
        guard delay > 0 else { return }
        try await Task.sleep(for: .seconds(delay))
    }

    // MARK: - The tokens

    private func appleBearer() throws -> String {
        guard let credential = credentials.apple else { throw ConnectionError.missingCredential(.apple) }
        if let appleToken, appleToken.expires > Date().addingTimeInterval(60) {
            return appleToken.value
        }
        // One instant for both, so the cached expiry cannot outlast the `exp`
        // the token carries.
        let now = Date()
        let token = try AppleJWT.make(credential: credential, now: now)
        appleToken = (token, now + AppleJWT.lifetime)
        return token
    }

    /// The Play Developer Reporting API. A different host and a different
    /// scope from the Publishing API, so it takes its own token.
    ///
    /// Everything here is a read. The vitals answer "how is the shipped app
    /// doing", and no call in this file changes anything in the store.
    @discardableResult
    public func googleReporting(_ method: String, _ path: String,
                                body: Any? = nil) async throws -> Result {
        var request = URLRequest(url: try Self.url(
            "https://playdeveloperreporting.googleapis.com" + path))
        request.httpMethod = method
        request.setValue("Bearer \(try await googleBearer(scope: Self.reportingScope))",
                         forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return try await perform(request, system: .google, path: path)
    }

    static let reportingScope = "https://www.googleapis.com/auth/playdeveloperreporting"

    private func googleBearer(
        scope: String = "https://www.googleapis.com/auth/androidpublisher"
    ) async throws -> String {
        if let credential = credentials.googleOAuth {
            if let googleToken, googleToken.expires > Date().addingTimeInterval(60) {
                return googleToken.value
            }
            if credential.expiresAt > Date().addingTimeInterval(60) {
                googleToken = (credential.accessToken, credential.expiresAt)
                return credential.accessToken
            }
            var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded",
                             forHTTPHeaderField: "Content-Type")
            request.httpBody = FormBody.encoded([
                ("client_id", credential.clientID),
                ("grant_type", "refresh_token"),
                ("refresh_token", credential.refreshToken),
            ])
            let result = try await perform(request, system: .google, path: "/token",
                                           retryOverride: true)
            let payload = try JSONDecoder().decode(GoogleToken.self, from: result.data)
            googleToken = (payload.accessToken,
                           Date().addingTimeInterval(TimeInterval(payload.expiresIn ?? 3_600)))
            return payload.accessToken
        }
        guard let credential = credentials.google else {
            throw ConnectionError.missingCredential(.google)
        }
        // The two scopes cannot share a token, so the cache holds the
        // publishing one and the reporting one asks every time. A vitals read
        // happens on a button, not in a loop.
        if scope != Self.reportingScope, let googleToken,
           googleToken.expires > Date().addingTimeInterval(60) {
            return googleToken.value
        }
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
        let result = try await perform(request, system: .google, path: "/token",
                                       retryOverride: true)
        let payload = try JSONDecoder().decode(GoogleToken.self, from: result.data)
        if scope != Self.reportingScope {
            googleToken = (payload.accessToken,
                           Date().addingTimeInterval(TimeInterval(payload.expiresIn ?? 3_600)))
        }
        return payload.accessToken
    }

    // MARK: - Small helpers

    private static func url(_ string: String) throws -> URL {
        guard let url = URL(string: string) else { throw ConnectionError.invalidResponse }
        return url
    }

    private static func lowercasedHeaders(_ response: HTTPURLResponse) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            guard let name = key as? String, let text = value as? String else { continue }
            result[name.lowercased()] = text
        }
        return result
    }

    /// `user-hour-lim:3600;user-hour-rem:3599;` becomes a dictionary.
    private static func semicolonFields(_ value: String) -> [String: Int] {
        var result: [String: Int] = [:]
        for piece in value.split(separator: ";") {
            let parts = piece.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, let number = Int(parts[1].trimmingCharacters(in: .whitespaces))
            else { continue }
            result[parts[0].trimmingCharacters(in: .whitespaces)] = number
        }
        return result
    }
}

private struct GoogleToken: Decodable {
    let accessToken: String
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
    }
}

public extension ConnectionError {
    static func missingCredential(_ store: Store) -> ConnectionError {
        .http(401, store == .apple
              ? "Connect the App Store on the Stores tab first."
              : "Connect Google Play on the Stores tab first.")
    }
}

/// Apple writes its constants in upper snake case, and no screen should show
/// one that way.
public enum AppleWords {
    /// `IOS_DISTRIBUTION` becomes `Ios distribution`, which is what a reader
    /// wants.
    public static func title(_ identifier: String) -> String {
        guard !identifier.isEmpty else { return identifier }
        let words = identifier.replacingOccurrences(of: "_", with: " ").lowercased()
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}

/// The MD5 that Apple wants in `sourceFileChecksum`. Spec section 7.5.
public enum Checksums {
    public static func md5(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// A stable checksum of a directory artifact. Relative paths and every
    /// regular file's bytes participate, so changing any archive member
    /// changes the value shown to the developer.
    public static func sha256(directory root: URL) throws -> String {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys,
            options: []) else {
            throw CocoaError(.fileReadUnknown)
        }
        let rootPath = root.standardizedFileURL.path
        let entries = enumerator.compactMap { $0 as? URL }.sorted { $0.path < $1.path }
        var hasher = SHA256()
        for entry in entries {
            let values = try entry.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true || values.isSymbolicLink == true else { continue }
            let path = entry.standardizedFileURL.path
            guard path.hasPrefix(rootPath + "/") else { continue }
            update(&hasher, with: Data(path.dropFirst(rootPath.count + 1).utf8))
            if values.isSymbolicLink == true {
                let destination = try FileManager.default.destinationOfSymbolicLink(atPath: path)
                update(&hasher, with: Data(destination.utf8))
                continue
            }
            do {
                let handle = try FileHandle(forReadingFrom: entry)
                defer { try? handle.close() }
                while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
                    hasher.update(data: chunk)
                }
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func update(_ hasher: inout SHA256, with data: Data) {
        var length = UInt64(data.count).littleEndian
        withUnsafeBytes(of: &length) { hasher.update(bufferPointer: $0) }
        hasher.update(data: data)
    }
}
