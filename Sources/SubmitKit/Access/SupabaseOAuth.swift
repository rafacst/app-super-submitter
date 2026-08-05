import CryptoKit
import Foundation

/// The identity providers Supabase can hand this app a session from.
///
/// The raw value is the wire name Supabase expects on `/authorize`, so it is
/// a mapping and not a label. The display name lives with the button.
public enum SupabaseOAuthProvider: String, CaseIterable, Sendable, Identifiable {
    // Google is absent on purpose: its console needs a consent screen, a
    // verification review, and a publish step before anyone outside a test
    // list can sign in. Email covers those people.
    case apple, github, gitlab

    public var id: String { rawValue }
}

/// One authorization attempt: where to send the browser, and the secret that
/// proves the code that comes back belongs to this attempt.
///
/// The verifier never leaves the app until the exchange. That is the whole
/// point of PKCE: a stolen code is worthless without it.
public struct SupabaseOAuthRequest: Sendable {
    public let url: URL
    public let verifier: String
}

public extension SupabaseAuth {

    /// Builds the `/authorize` URL and the PKCE pair behind it.
    ///
    /// This does no network work. The caller opens the URL in a browser
    /// session and brings the callback back to `completeOAuth`.
    nonisolated func authorization(with provider: SupabaseOAuthProvider,
                                   redirectTo: URL) -> SupabaseOAuthRequest {
        let verifier = Self.randomVerifier()
        var components = URLComponents(
            url: configuration.baseURL.appendingPathComponent("auth/v1/authorize"),
            resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "provider", value: provider.rawValue),
            .init(name: "redirect_to", value: redirectTo.absoluteString),
            .init(name: "code_challenge", value: Self.challenge(for: verifier)),
            .init(name: "code_challenge_method", value: "s256"),
        ]
        return SupabaseOAuthRequest(url: components.url!, verifier: verifier)
    }

    /// Trades the code on the callback for a session, and remembers it.
    ///
    /// A provider that refuses answers on the same callback with `error`, so
    /// that case is read here rather than left to look like a missing code.
    @discardableResult
    func completeOAuth(callback: URL, verifier: String) async throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }
        if let error = value("error_description") ?? value("error") {
            throw SupabaseAuthError.service(error.replacingOccurrences(of: "+", with: " "))
        }
        guard let code = value("code") else { throw SupabaseAuthError.invalidResponse }
        return try await exchange(code: code, verifier: verifier)
    }

    /// 32 random bytes as base64url. Well inside the 43 to 128 characters
    /// RFC 7636 allows, and it needs no character filtering.
    nonisolated internal static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        // ponytail: SecRandomCopyBytes is the platform source. A failure here
        // means the system CSPRNG is broken, and there is no safer fallback
        // to reach for, so it stops rather than invent one.
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            fatalError("The system random number generator failed.")
        }
        return base64URL(Data(bytes))
    }

    nonisolated internal static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    nonisolated internal static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
