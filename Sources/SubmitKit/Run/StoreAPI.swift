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
    public var revenueCatKey: String?
    /// The demo account. It reaches Apple in the review details and it never
    /// reaches `store.yaml`. Spec section 9.5.
    public var reviewer: ReviewerCredential?

    public init(apple: AppleCredential? = nil, google: GoogleServiceAccount? = nil,
                revenueCatKey: String? = nil, reviewer: ReviewerCredential? = nil) {
        self.apple = apple
        self.google = google
        self.revenueCatKey = revenueCatKey
        self.reviewer = reviewer
    }
}

public typealias CallRecorder = @Sendable (APICall) -> Void

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

    @discardableResult
    public func apple(_ method: String, _ path: String,
                      body: Any? = nil) async throws -> Result {
        var request = URLRequest(url: try Self.url("https://api.appstoreconnect.apple.com" + path))
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
        var components = URLComponents(string: "https://androidpublisher.googleapis.com" + path)
        var items = query
        items.append(URLQueryItem(name: "uploadType", value: "media"))
        components?.queryItems = items
        guard let url = components?.url else { throw ConnectionError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(try await googleBearer())", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return try await perform(request, system: .google, path: path)
    }

    /// The dry run never reaches this type, but it still has to appear in the
    /// log. Spec section 7.2: a dry run builds every request and sends none.
    public func recordDryRun(system: PlanSystem, method: String, path: String) {
        record(APICall(system: system.rawValue, method: method, path: path, dryRun: true))
    }

    // MARK: - The one request path

    private func perform(_ request: URLRequest, system: PlanSystem,
                         path: String) async throws -> Result {
        let method = request.httpMethod ?? "GET"
        var attempt = 0
        while true {
            attempt += 1
            try await waitForBucket(system)
            let started = Date()
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw ConnectionError.invalidResponse
                }
                let headers = Self.lowercasedHeaders(http)
                let duration = Int(Date().timeIntervalSince(started) * 1000)
                let requestID = headers["x-request-id"] ?? headers["x-guploader-uploadid"]
                readRateLimits(system: system, headers: headers)

                if Self.retryable.contains(http.statusCode), attempt < Self.maxAttempts {
                    record(APICall(system: system.rawValue, method: method, path: path,
                                   status: http.statusCode, durationMs: duration,
                                   requestId: requestID, error: "retrying"))
                    try await backOff(attempt: attempt, retryAfter: headers["retry-after"])
                    continue
                }
                guard (200..<300).contains(http.statusCode) else {
                    let detail = APIError.message(from: data)
                        ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
                    record(APICall(system: system.rawValue, method: method, path: path,
                                   status: http.statusCode, durationMs: duration,
                                   requestId: requestID, error: detail))
                    throw ConnectionError.http(http.statusCode, detail)
                }
                record(APICall(system: system.rawValue, method: method, path: path,
                               status: http.statusCode, durationMs: duration,
                               requestId: requestID))
                return Result(data: data, status: http.statusCode, headers: headers)
            } catch let error as ConnectionError {
                throw error
            } catch {
                // A transport failure. The same retry budget applies.
                let duration = Int(Date().timeIntervalSince(started) * 1000)
                record(APICall(system: system.rawValue, method: method, path: path,
                               durationMs: duration, error: error.localizedDescription))
                guard attempt < Self.maxAttempts, !(error is CancellationError) else { throw error }
                try await backOff(attempt: attempt, retryAfter: nil)
            }
        }
    }

    /// Exponential backoff with full jitter, base 1 second, cap 60 seconds.
    private func backOff(attempt: Int, retryAfter: String?) async throws {
        if let retryAfter, let seconds = Double(retryAfter) {
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
        if let value = headers["x-rate-limit"] {
            let fields = Self.semicolonFields(value)
            if let limit = fields["user-hour-lim"], let remaining = fields["user-hour-rem"],
               limit > 0 {
                usedFraction = 1 - Double(remaining) / Double(limit)
            }
        }
        if let usage = headers["revenuecat-rate-limit-current-usage"].flatMap(Int.init),
           let limit = headers["revenuecat-rate-limit-current-limit"].flatMap(Int.init),
           limit > 0 {
            usedFraction = Double(usage) / Double(limit)
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
        let token = try AppleJWT.make(credential: credential)
        appleToken = (token, Date().addingTimeInterval(15 * 60))
        return token
    }

    private func googleBearer() async throws -> String {
        guard let credential = credentials.google else {
            throw ConnectionError.missingCredential(.google)
        }
        if let googleToken, googleToken.expires > Date().addingTimeInterval(60) {
            return googleToken.value
        }
        let assertion = try GoogleJWT.make(credential: credential)
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
        let result = try await perform(request, system: .google, path: "/token")
        let payload = try JSONDecoder().decode(GoogleToken.self, from: result.data)
        googleToken = (payload.accessToken,
                       Date().addingTimeInterval(TimeInterval(payload.expiresIn ?? 3_600)))
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

/// The MD5 that Apple wants in `sourceFileChecksum`. Spec section 7.5.
public enum Checksums {
    public static func md5(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
