import Foundation
import SubmitKit

/// Where the licensing service is and which key signs its documents.
///
/// The Info.plist is the source for a shipped app, because a double-clicked
/// bundle inherits no shell environment. The environment overrides it, so a
/// contributor can point a Debug build at a local service without editing the
/// project.
///
/// No `sk_`, `rk_`, or `whsec_` value belongs here or anywhere else in the
/// bundle. Every privileged Stripe call happens on the service.
struct LicensingConfig {
    let baseURL: URL
    let verifier: EntitlementVerifier
    let auth: SupabaseAuthConfiguration

    static let current: LicensingConfig? = load()

    private static func load() -> LicensingConfig? {
        guard let text = value("SSLicensingBaseURL", "LICENSING_BASE_URL"),
              let url = URL(string: text), url.scheme == "https" else {
            missing("SSLicensingBaseURL / LICENSING_BASE_URL")
            return nil
        }
        guard let keyText = value("SSEntitlementPublicKeys", "ENTITLEMENT_PUBLIC_KEYS") else {
            missing("SSEntitlementPublicKeys / ENTITLEMENT_PUBLIC_KEYS")
            return nil
        }
        guard let verifier = try? EntitlementVerifier(base64Keys: parseKeys(keyText)),
              verifier.isConfigured else {
            missing("SSEntitlementPublicKeys is not a list of base64 Ed25519 keys")
            return nil
        }
        guard let authURLText = value("SSSupabaseURL", "SUPABASE_URL"),
              let authURL = URL(string: authURLText), authURL.scheme == "https",
              let publishableKey = value("SSSupabasePublishableKey", "SUPABASE_PUBLISHABLE_KEY") else {
            missing("SSSupabaseURL / SSSupabasePublishableKey")
            return nil
        }
        return LicensingConfig(baseURL: url, verifier: verifier,
                               auth: .init(baseURL: authURL, publishableKey: publishableKey))
    }

    /// `entitlement-2026-01=BASE64,entitlement-2026-07=BASE64`. A rotation
    /// ships as a second entry, so a document signed by the retired key still
    /// verifies until it expires.
    private static func parseKeys(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in text.split(separator: ",") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            result[parts[0].trimmingCharacters(in: .whitespaces)] =
                parts[1].trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    private static func value(_ plistKey: String, _ variable: String) -> String? {
        if let text = ProcessInfo.processInfo.environment[variable], !text.isEmpty {
            return text
        }
        guard let text = Bundle.main.object(forInfoDictionaryKey: plistKey) as? String,
              !text.isEmpty, !text.hasPrefix("$(") else { return nil }
        return text
    }

    private static func missing(_ name: String) {
#if DEBUG
        FileHandle.standardError.write(Data(
            "[Licensing] \(name) is missing, so this Debug build allows every store write.\n".utf8))
#endif
    }
}

/// The gate of a build that has no licensing configuration.
///
/// A Release build must never use it: the release workflow injects the two
/// values, and refusing every write is the only safe answer if it did not. A
/// Debug build allows, because `swift run` and the test suite reach no
/// service, and locking a contributor out of their own Mac protects nobody.
struct UnconfiguredAccess: AccessGate {
    func authorize(_ capability: AccessCapability) async throws {
#if DEBUG
        FileHandle.standardError.write(Data(
            "[Licensing] no configuration, so \(capability.rawValue) is allowed in this Debug build.\n".utf8))
#else
        throw AccessError.licensingNotConfigured
#endif
    }
}
