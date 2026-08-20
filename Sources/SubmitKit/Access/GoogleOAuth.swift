import CryptoKit
import Foundation
import Security

/// Google's installed-app OAuth flow, apart from the local browser callback.
public enum GoogleOAuth {
    public static let scopes = [
        "https://www.googleapis.com/auth/androidpublisher",
        "https://www.googleapis.com/auth/playdeveloperreporting",
    ]

    public enum Error: Swift.Error, LocalizedError, Equatable {
        case invalidState
        case missingCode
        case denied(String)
        case missingRefreshToken
        case invalidResponse
        case randomness

        public var errorDescription: String? {
            switch self {
            case .invalidState: "Google returned an authorization that this app did not start."
            case .missingCode: "Google returned without an authorization code."
            case .denied(let reason): "Google authorization was not completed. \(reason)"
            case .missingRefreshToken:
                "Google returned no refresh token. Remove Super Submitter from your Google account access and connect again."
            case .invalidResponse: "Google returned an unreadable OAuth response."
            case .randomness: "Super Submitter could not create a secure Google authorization request."
            }
        }
    }

    public static func randomToken(byteCount: Int = 32) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw Error.randomness
        }
        return Base64URL.encode(Data(bytes))
    }

    public static func authorizationURL(clientID: String, redirectURI: String,
                                        state: String, verifier: String) throws -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        guard let url = components.url else { throw Error.invalidResponse }
        return url
    }

    public static func authorizationCode(from callback: URL,
                                         expectedState: String) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value: (String) -> String? = { name in
            items.first { $0.name == name }?.value
        }
        guard value("state") == expectedState else { throw Error.invalidState }
        if let error = value("error") { throw Error.denied(value("error_description") ?? error) }
        guard let code = value("code"), !code.isEmpty else { throw Error.missingCode }
        return code
    }

    public static func exchange(code: String, clientID: String, redirectURI: String,
                                verifier: String, session: URLSession = .shared) async throws
        -> GoogleOAuthCredential {
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = FormBody.encoded([
            ("client_id", clientID),
            ("code", code),
            ("code_verifier", verifier),
            ("grant_type", "authorization_code"),
            ("redirect_uri", redirectURI),
        ])
        let (data, response) = try await session.data(for: request)
        try requireSuccess(response, data: data)
        let token = try GoogleToken.decode(data)
        guard let refresh = token.refreshToken, !refresh.isEmpty else {
            throw Error.missingRefreshToken
        }
        return GoogleOAuthCredential(
            clientID: clientID, accessToken: token.accessToken, refreshToken: refresh,
            expiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn ?? 3_600)))
    }

    private static func challenge(for verifier: String) -> String {
        Base64URL.encode(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func requireSuccess(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw Error.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = APIError.message(from: data)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw Error.denied(message)
        }
    }

}

/// What Google's token endpoint answers, wherever the app asks it.
///
/// One shape, three askers: the OAuth sign-in, the per-call refresh in
/// `StoreAPI`, and the connection test. Each used to declare its own struct
/// naming whichever fields it happened to read. A refresh token only comes
/// back on the first exchange, and an expiry is not always sent, so both stay
/// optional and the caller decides whether it needs them.
struct GoogleToken: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?

    /// Google spells these `access_token` and the rest in snake case, so the
    /// decoder converts rather than each field naming itself twice.
    static func decode(_ data: Data) throws -> GoogleToken {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GoogleToken.self, from: data)
    }
}
