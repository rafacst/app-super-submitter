import Foundation
import Testing
@testable import SubmitKit

private let configuration = SupabaseAuthConfiguration(
    baseURL: URL(string: "https://project.supabase.co")!,
    publishableKey: "sb_publishable_test")

private let callback = URL(string: "supersubmitter://auth-callback")!

private func query(_ url: URL) -> [String: String] {
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    return Dictionary(items.compactMap { item in
        item.value.map { (item.name, $0) }
    }, uniquingKeysWith: { first, _ in first })
}

/// RFC 7636 appendix B. A wrong challenge fails only at the provider, hours
/// later and with no useful message, so the vector is checked here.
@Test func theCodeChallengeMatchesTheRFCVector() {
    let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"

    #expect(SupabaseAuth.challenge(for: verifier)
            == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
}

@Test func aVerifierIsBase64URLAndLongEnoughForTheSpec() {
    let verifier = SupabaseAuth.randomVerifier()

    // RFC 7636 allows 43 to 128 characters, and none of "+/=".
    #expect(verifier.count >= 43 && verifier.count <= 128)
    #expect(!verifier.contains(where: { "+/=".contains($0) }))
    #expect(verifier != SupabaseAuth.randomVerifier())
}

@Test func theAuthorizeURLCarriesTheProviderTheRedirectAndTheChallenge() {
    let auth = SupabaseAuth(configuration: configuration, store: NoStore())

    let request = auth.authorization(with: .github, redirectTo: callback)
    let items = query(request.url)

    #expect(request.url.path == "/auth/v1/authorize")
    #expect(items["provider"] == "github")
    #expect(items["redirect_to"] == "supersubmitter://auth-callback")
    #expect(items["code_challenge_method"] == "s256")
    #expect(items["code_challenge"] == SupabaseAuth.challenge(for: request.verifier))
    // The secret half stays here until the exchange.
    #expect(!request.url.absoluteString.contains(request.verifier))
}

@Test func everyProviderKeepsTheNameSupabaseExpectsOnTheWire() {
    #expect(SupabaseOAuthProvider.allCases.map(\.rawValue)
            == ["apple", "google", "github", "gitlab"])
}

@Test func aRefusedSignInReadsAsTheProvidersReasonAndNotAMissingCode() async throws {
    let auth = SupabaseAuth(configuration: configuration, store: NoStore())
    let denied = URL(string: "supersubmitter://auth-callback?error=access_denied&error_description=The+user+said+no")!

    await #expect(throws: SupabaseAuthError.service("The user said no")) {
        try await auth.completeOAuth(callback: denied, verifier: "v")
    }
}

@Test func aCallbackWithNeitherACodeNorAnErrorIsInvalid() async throws {
    let auth = SupabaseAuth(configuration: configuration, store: NoStore())

    await #expect(throws: SupabaseAuthError.invalidResponse) {
        try await auth.completeOAuth(callback: callback, verifier: "v")
    }
}

private struct NoStore: SupabaseSessionStoring {
    func load() throws -> SupabaseSession? { nil }
    func save(_ session: SupabaseSession) throws {}
    func clear() throws {}
}
