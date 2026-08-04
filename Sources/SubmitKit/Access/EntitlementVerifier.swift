import CryptoKit
import Foundation

/// Checks that a document came from the licensing service and still applies.
///
/// The app bundle holds only the verification half of the pair. A signing key
/// in a direct-download binary is a signing key in every customer's hands.
public struct EntitlementVerifier: Sendable {
    /// One public key per `keyId`, so a key rotation ships as a new entry and
    /// not as a forced update for everyone holding a document signed by the
    /// old one.
    private let keys: [String: Curve25519.Signing.PublicKey]
    /// How far ahead of this machine the service's clock may run. Two hosts
    /// never agree to the second, and a document rejected over a few seconds
    /// of drift locks out a paying user.
    private let skew: TimeInterval

    public init(keys: [String: Curve25519.Signing.PublicKey], skew: TimeInterval = 300) {
        self.keys = keys
        self.skew = skew
    }

    /// - Parameter base64Keys: `keyId` to base64 raw 32-byte public key, the
    ///   form the build configuration carries.
    public init(base64Keys: [String: String], skew: TimeInterval = 300) throws {
        var parsed: [String: Curve25519.Signing.PublicKey] = [:]
        for (id, text) in base64Keys {
            guard let raw = Data(base64Encoded: text)
                    ?? Base64URL.decode(text) else {
                throw AccessError.configurationInvalid
            }
            parsed[id] = try Curve25519.Signing.PublicKey(rawRepresentation: raw)
        }
        self.init(keys: parsed, skew: skew)
    }

    public var isConfigured: Bool { !keys.isEmpty }

    /// Verifies the signature and the validity window, then returns the
    /// entitlement. Every failure is a refusal, never a downgrade to a
    /// weaker check.
    ///
    /// - Parameter subject: the account the app believes it is signed in as.
    ///   A document for another subject is a replayed document.
    public func verify(_ document: SignedEntitlement, at date: Date,
                       subject: String? = nil) throws -> Entitlement {
        guard let key = keys[document.keyId] else { throw AccessError.unknownSigningKey }
        guard let signature = Base64URL.decode(document.signature),
              let payload = Base64URL.decode(document.payload) else {
            throw AccessError.malformedEntitlement
        }
        guard key.isValidSignature(signature, for: Data(document.payload.utf8)) else {
            throw AccessError.invalidSignature
        }

        let entitlement = try LicensingJSON.decoder.decode(Entitlement.self, from: payload)
        guard entitlement.version == 1 else { throw AccessError.unsupportedVersion }
        guard entitlement.issuedAt <= date.addingTimeInterval(skew) else {
            throw AccessError.clockMismatch
        }
        guard entitlement.expiresAt > date else { throw AccessError.entitlementExpired }
        if let subject, !subject.isEmpty, subject != entitlement.subject {
            throw AccessError.subjectMismatch
        }
        return entitlement
    }
}

/// Every way the gate can say no. The message is what the user reads, so it
/// names what still works rather than what does not.
public enum AccessError: Error, LocalizedError, Equatable {
    case notEntitled(AccessCapability)
    case signedOut
    case entitlementExpired
    case refreshRequired
    case serviceUnavailable(String)
    case invalidSignature
    case malformedEntitlement
    case unknownSigningKey
    case unsupportedVersion
    case subjectMismatch
    case clockMismatch
    case configurationInvalid
    case licensingNotConfigured
    /// A stable code the service returned, with the message it supplied.
    case server(code: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .notEntitled(let capability):
            switch capability {
            case .storeWrite:
                "Store writes need paid access. Reading the stores, the plan, and the dry run stay free."
            case .storeUpload:
                "Uploading a build to a store needs paid access. The build itself is kept."
            case .storeRelease:
                "Releasing to review needs paid access. Your draft stays as it is."
            }
        case .signedOut:
            "Sign in to Super Submitter to use your subscription or your lifetime licence."
        case .entitlementExpired:
            "Your paid access has ended. Every local edit, plan, and dry run still works."
        case .refreshRequired:
            "Super Submitter must confirm your access before it writes to a store. Connect to the internet and try again."
        case .serviceUnavailable(let detail):
            "The licensing service could not be reached. \(detail)"
        case .invalidSignature, .malformedEntitlement, .unknownSigningKey,
             .unsupportedVersion, .subjectMismatch, .clockMismatch:
            "Your access could not be confirmed on this Mac. Sign in again, or check the date and time."
        case .configurationInvalid, .licensingNotConfigured:
            "This build of Super Submitter carries no licensing configuration. Report it as a build problem."
        case .server(_, let message):
            message
        }
    }

    /// The stable code, for the analytics event and for a support reference.
    /// It carries no email, no token, and no Stripe id.
    public var code: String {
        switch self {
        case .notEntitled: "entitlement_expired"
        case .signedOut: "authentication_required"
        case .entitlementExpired: "entitlement_expired"
        case .refreshRequired: "entitlement_refresh_required"
        case .serviceUnavailable: "billing_service_unavailable"
        case .invalidSignature: "entitlement_signature_invalid"
        case .malformedEntitlement: "entitlement_malformed"
        case .unknownSigningKey: "entitlement_key_unknown"
        case .unsupportedVersion: "entitlement_version_unsupported"
        case .subjectMismatch: "entitlement_subject_mismatch"
        case .clockMismatch: "entitlement_clock_mismatch"
        case .configurationInvalid, .licensingNotConfigured: "environment_mismatch"
        case .server(let code, _): code
        }
    }
}
