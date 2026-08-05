import AppKit
import AuthenticationServices
import SubmitKit

/// The browser half of an OAuth sign-in.
///
/// `ASWebAuthenticationSession` is the only door Apple sanctions here: the
/// password is typed into the provider's own page, in a browser this app
/// cannot read, and only the callback comes back. A `WKWebView` would put the
/// provider's login form inside our process, which Apple refuses outright.
///
/// ponytail: no delegate object kept around, no state machine. One call, one
/// URL back, and the session dies with the continuation.
@MainActor
final class OAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    /// The scheme `ASWebAuthenticationSession` watches for. It matches the one
    /// stripe-spec.md registers for the billing return.
    static let scheme = "supersubmitter"
    static let callback = URL(string: "\(scheme)://auth-callback")!

    private var session: ASWebAuthenticationSession?

    /// Opens the provider's page and answers with the callback URL.
    ///
    /// A user who closes the window is not an error worth shouting about, so
    /// that case answers nil and the caller says nothing.
    func run(_ url: URL) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            // `@Sendable`, and nothing but the continuation inside it.
            //
            // The class is `@MainActor`, so a plain closure written here
            // inherits that isolation and checks the executor as it starts.
            // AuthenticationServices calls this one on its XPC reply queue,
            // never on the main thread, so the check trapped and took the app
            // down the moment Apple sign-in answered. A continuation is
            // `Sendable` and resumes safely from any thread, so the closure
            // needs no main actor and must not ask for one.
            let session = ASWebAuthenticationSession(
                url: url, callbackURLScheme: Self.scheme
            ) { @Sendable callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(throwing: error ?? OAuthError.noCallback)
                }
            }
            session.presentationContextProvider = self
            // The provider decides who is signed in, not Safari's cookie jar.
            // Without this a second account can never be reached.
            session.prefersEphemeralWebBrowserSession = true
            self.session = session
            guard session.start() else {
                continuation.resume(throwing: OAuthError.couldNotStart)
                return
            }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession)
        -> ASPresentationAnchor {
        MainActor.assumeIsolated { NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor() }
    }
}

enum OAuthError: LocalizedError {
    case noCallback, couldNotStart

    var errorDescription: String? {
        switch self {
        case .noCallback: "The sign-in window closed before it answered."
        case .couldNotStart: "The sign-in window could not open."
        }
    }
}

extension SupabaseOAuthProvider {
    var title: String {
        switch self {
        case .apple: "Apple"
        case .github: "GitHub"
        case .gitlab: "GitLab"
        }
    }

    /// SF Symbols carries the Apple and GitHub marks and neither of the other
    /// two, so the four use one neutral shape rather than two logos and two
    /// stand-ins.
    var symbol: String {
        switch self {
        case .apple: "apple.logo"
        default: "person.crop.circle"
        }
    }
}
