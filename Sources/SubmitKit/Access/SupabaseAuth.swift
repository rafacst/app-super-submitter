import Foundation

public struct SupabaseAuthConfiguration: Sendable {
    public let baseURL: URL
    public let publishableKey: String

    public init(baseURL: URL, publishableKey: String) {
        self.baseURL = baseURL
        self.publishableKey = publishableKey
    }
}

public enum SupabaseSignUpResult: Sendable, Equatable {
    case signedIn(String)
    case confirmationRequired
}

public enum SupabaseAuthError: Error, LocalizedError, Sendable, Equatable {
    case invalidResponse
    case service(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The account service answered with something this app could not read. Try again in a moment."
        case .service(let message): Self.humanize(message)
        }
    }

    /// The account service speaks its own dialect. These are the answers a
    /// developer actually meets, said the way a person would say them.
    public static func humanize(_ message: String) -> String {
        let plain = message.replacingOccurrences(of: "—", with: "-")
        let lower = plain.lowercased()
        if lower.contains("invalid login credentials") {
            return "That email address and password do not match an account. Check both, or create an account."
        }
        if lower.contains("already registered") || lower.contains("already exists") {
            return "An account already uses that email address. Sign in instead, or reset the password."
        }
        if lower.contains("email not confirmed") {
            return "This account is not confirmed yet. Open the link in the email we sent you."
        }
        if lower.contains("password") && lower.contains("6 characters") {
            return "The password is too short. Use at least six characters."
        }
        if lower.contains("rate limit") || lower.contains("too many") {
            return "Too many attempts for now. Wait a minute and try again."
        }
        if lower.contains("expired") || lower.contains("invalid") && lower.contains("link") {
            return "That link has already been used or has expired. Ask for a new one."
        }
        // A status line with a number in it says nothing to a developer.
        if lower.contains("answered with status") {
            return "The account service refused the request. Try again in a moment."
        }
        return plain
    }
}

public protocol SupabaseSessionStoring: Sendable {
    func load() throws -> SupabaseSession?
    func save(_ session: SupabaseSession) throws
    func clear() throws
}

public struct SupabaseSession: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public let email: String

    public init(accessToken: String, refreshToken: String, expiresAt: Date, email: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.email = email
    }
}

public struct KeychainSupabaseSessionStore: SupabaseSessionStoring {
    public init() {}

    public func load() throws -> SupabaseSession? {
        try KeychainCredentials.load(SupabaseSession.self, kind: .account, account: "supabase")
    }

    public func save(_ session: SupabaseSession) throws {
        try KeychainCredentials.save(session, kind: .account, account: "supabase")
    }

    public func clear() throws {
        try KeychainCredentials.delete(kind: .account, account: "supabase")
    }
}

/// The app's Supabase session. Stripe and entitlement routes receive only its
/// short-lived access token; the refresh token stays in the Keychain.
public actor SupabaseAuth {
    // Not private: the OAuth half lives in SupabaseOAuth.swift and builds the
    // authorize URL from it. A `let` of a Sendable type reads nonisolated.
    let configuration: SupabaseAuthConfiguration
    private let urlSession: URLSession
    private let store: any SupabaseSessionStoring
    private let now: @Sendable () -> Date
    private var session: SupabaseSession?

    public init(configuration: SupabaseAuthConfiguration,
                urlSession: URLSession = .shared,
                store: any SupabaseSessionStoring = KeychainSupabaseSessionStore(),
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.configuration = configuration
        self.urlSession = urlSession
        self.store = store
        self.now = now
        session = try? store.load()
    }

    public var email: String? { session?.email }

    public func accessToken() async throws -> String? {
        guard let session else { return nil }
        if session.expiresAt.timeIntervalSince(now()) > 60 { return session.accessToken }
        return try await refresh(session.refreshToken).accessToken
    }

    @discardableResult
    public func signIn(email: String, password: String) async throws -> String {
        let response = try await request("auth/v1/token", query: "grant_type=password",
                                         body: ["email": email, "password": password])
        let session = try storedSession(from: response, fallbackEmail: email)
        try remember(session)
        return session.email
    }

    public func signUp(email: String, password: String) async throws -> SupabaseSignUpResult {
        let response = try await request("auth/v1/signup", body: ["email": email,
                                                                   "password": password])
        guard response.accessToken != nil else { return .confirmationRequired }
        let session = try storedSession(from: response, fallbackEmail: email)
        try remember(session)
        return .signedIn(session.email)
    }

    /// Adopts the session that a confirmation link hands back.
    ///
    /// Supabase puts the token pair in the fragment of the redirect, because a
    /// link opened from a mail client carries no PKCE verifier. The refresh
    /// token is exchanged for a session rather than trusted as it stands, so a
    /// link that was already used, or that expired, fails here and says so
    /// instead of failing at the first store call.
    @discardableResult
    public func adopt(callback: URL) async throws -> String {
        try adopt(session: await resolve(callback: callback))
    }

    /// Resolves a confirmation token without changing the signed-in account.
    /// The app can show the returned email address before it adopts the session.
    public func resolve(callback: URL) async throws -> SupabaseSession {
        let parts = Self.parameters(in: callback)
        if let message = parts["error_description"] ?? parts["error"] {
            throw SupabaseAuthError.service(message)
        }
        guard let refreshToken = parts["refresh_token"] else {
            throw SupabaseAuthError.invalidResponse
        }
        let session = try await refreshedSession(refreshToken, fallbackEmail: "")
        guard !session.email.isEmpty else { throw SupabaseAuthError.invalidResponse }
        return session
    }

    @discardableResult
    public func adopt(session: SupabaseSession) throws -> String {
        try remember(session)
        return session.email
    }

    /// The query and the fragment of a callback, in one dictionary.
    ///
    /// Supabase answers a confirmation in the fragment and an error in either
    /// half, so reading one half alone misses the case it is not in.
    public static func parameters(in url: URL) -> [String: String] {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var pairs: [String: String] = [:]
        for item in components?.queryItems ?? [] { pairs[item.name] = item.value }
        // The encoded half, not `fragment`. `URLComponents` hands the decoded
        // one back, and assigning a decoded space to `percentEncodedQuery`
        // traps rather than returning nil.
        var fragment = URLComponents()
        fragment.percentEncodedQuery = components?.percentEncodedFragment
        for item in fragment.queryItems ?? [] { pairs[item.name] = item.value }
        return pairs
    }

    public func signOut() async {
        if let token = try? await accessToken() {
            var request = URLRequest(url: configuration.baseURL.appendingPathComponent("auth/v1/logout"))
            request.httpMethod = "POST"
            request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await urlSession.data(for: request)
        }
        session = nil
        try? store.clear()
    }

    /// The PKCE half of the OAuth flow. The provider gave the browser a code;
    /// this proves the code belongs to this app and takes the session.
    @discardableResult
    func exchange(code: String, verifier: String) async throws -> String {
        let response = try await request("auth/v1/token", query: "grant_type=pkce",
                                         body: ["auth_code": code,
                                                "code_verifier": verifier])
        let session = try storedSession(from: response, fallbackEmail: "")
        try remember(session)
        return session.email
    }

    private func refresh(_ refreshToken: String) async throws -> SupabaseSession {
        let session = try await refreshedSession(refreshToken)
        try remember(session)
        return session
    }

    private func refreshedSession(_ refreshToken: String,
                                  fallbackEmail: String? = nil) async throws -> SupabaseSession {
        let response = try await request("auth/v1/token", query: "grant_type=refresh_token",
                                         body: ["refresh_token": refreshToken])
        return try storedSession(from: response,
                                 fallbackEmail: fallbackEmail ?? session?.email ?? "")
    }

    private func remember(_ session: SupabaseSession) throws {
        self.session = session
        try store.save(session)
    }

    private func storedSession(from response: AuthResponse,
                               fallbackEmail: String) throws -> SupabaseSession {
        guard let accessToken = response.accessToken,
              let refreshToken = response.refreshToken,
              let expiresIn = response.expiresIn else { throw SupabaseAuthError.invalidResponse }
        return SupabaseSession(accessToken: accessToken, refreshToken: refreshToken,
                               expiresAt: now().addingTimeInterval(TimeInterval(expiresIn)),
                               email: response.user?.email ?? fallbackEmail)
    }

    private func request(_ path: String, query: String? = nil,
                         body: [String: String]) async throws -> AuthResponse {
        var components = URLComponents(url: configuration.baseURL.appendingPathComponent(path),
                                       resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery = query
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw SupabaseAuthError.service("The account service could not be reached. \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseAuthError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let error = try? Self.decoder.decode(AuthErrorResponse.self, from: data)
            throw SupabaseAuthError.service(error?.displayMessage
                                            ?? "The account service answered with status \(http.statusCode).")
        }
        guard let result = try? Self.decoder.decode(AuthResponse.self, from: data) else {
            throw SupabaseAuthError.invalidResponse
        }
        return result
    }

    /// Supabase spells every field in snake case, so the decoder converts
    /// rather than each field naming itself a second time.
    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

private struct AuthResponse: Decodable {
    struct User: Decodable { let email: String? }
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let user: User?
}

private struct AuthErrorResponse: Decodable {
    let message: String?
    let msg: String?
    let errorDescription: String?
    let error: String?

    var displayMessage: String? { message ?? msg ?? errorDescription ?? error }
}
