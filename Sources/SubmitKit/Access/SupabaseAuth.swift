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
        case .invalidResponse: "The account service returned an invalid response."
        case .service(let message): message.replacingOccurrences(of: "—", with: "-")
        }
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
        let response = try await request("auth/v1/token", query: "grant_type=refresh_token",
                                         body: ["refresh_token": refreshToken])
        let session = try storedSession(from: response, fallbackEmail: self.session?.email ?? "")
        try remember(session)
        return session
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
            let error = try? JSONDecoder().decode(AuthErrorResponse.self, from: data)
            throw SupabaseAuthError.service(error?.displayMessage
                                            ?? "The account service answered with status \(http.statusCode).")
        }
        guard let result = try? JSONDecoder().decode(AuthResponse.self, from: data) else {
            throw SupabaseAuthError.invalidResponse
        }
        return result
    }
}

private struct AuthResponse: Decodable {
    struct User: Decodable { let email: String? }
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let user: User?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
}

private struct AuthErrorResponse: Decodable {
    let message: String?
    let msg: String?
    let errorDescription: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case message, msg, error
        case errorDescription = "error_description"
    }

    var displayMessage: String? { message ?? msg ?? errorDescription ?? error }
}
