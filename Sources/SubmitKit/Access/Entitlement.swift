import Foundation

/// What a paid account may do. Free grants none of these.
///
/// The app asks for a capability, never for a plan name. A plan comparison
/// spread across twelve call sites is what makes a pricing change a refactor.
public enum AccessCapability: String, Codable, Sendable, CaseIterable {
    /// Any non-dry apply against App Store Connect or Google Play.
    case storeWrite = "store_write"
    /// Sending an `.ipa`, `.pkg`, `.aab`, or `.apk` to a store.
    case storeUpload = "store_upload"
    /// The irreversible calls: review submission, cancellation, approved
    /// release, Google track commit, and rollout halt.
    case storeRelease = "store_release"
}

public enum AccessPlan: String, Codable, Sendable {
    case free, monthly, annual, lifetime, complimentary
}

public enum EntitlementStatus: String, Codable, Sendable {
    case free, active, grace, expired, revoked
}

/// The server's answer to "what may this account do".
///
/// The client never derives this from a Stripe object, a success URL, or a
/// cached boolean. Only a signed document from the licensing service counts.
public struct Entitlement: Codable, Sendable, Equatable {
    public var version: Int
    /// The opaque Supabase account id used by the licensing service.
    public var subject: String
    /// Display only. The Plan and billing section shows it and nothing else
    /// reads it.
    public var email: String?
    public var status: EntitlementStatus
    public var plan: AccessPlan
    public var capabilities: [AccessCapability]
    public var issuedAt: Date
    /// After this, refresh in the background while the app runs.
    public var refreshAfter: Date
    /// After this, the document authorizes nothing. The server sizes the
    /// window per plan, so no plan arithmetic lives in the client.
    public var expiresAt: Date
    public var currentPeriodEnd: Date?
    public var cancelAtPeriodEnd: Bool?

    public init(version: Int = 1, subject: String, email: String? = nil,
                status: EntitlementStatus, plan: AccessPlan,
                capabilities: [AccessCapability], issuedAt: Date,
                refreshAfter: Date, expiresAt: Date,
                currentPeriodEnd: Date? = nil, cancelAtPeriodEnd: Bool? = nil) {
        self.version = version
        self.subject = subject
        self.email = email
        self.status = status
        self.plan = plan
        self.capabilities = capabilities
        self.issuedAt = issuedAt
        self.refreshAfter = refreshAfter
        self.expiresAt = expiresAt
        self.currentPeriodEnd = currentPeriodEnd
        self.cancelAtPeriodEnd = cancelAtPeriodEnd
    }

    public func grants(_ capability: AccessCapability) -> Bool {
        capabilities.contains(capability)
    }

    public var isPaid: Bool { status == .active || status == .grace }

    /// What nobody has proved anything about. Every gate refuses it.
    public static func free(subject: String = "anonymous", at date: Date) -> Entitlement {
        Entitlement(subject: subject, status: .free, plan: .free, capabilities: [],
                    issuedAt: date, refreshAfter: date, expiresAt: date)
    }
}

/// The document as it travels: a payload and a detached Ed25519 signature.
///
/// The signature covers the ASCII of `payload`, the base64url text itself, and
/// never a re-encoding of the decoded JSON. Two JSON encoders disagree about
/// key order and about how many digits a date carries, and a signature that
/// depends on either one fails on the day a server library is upgraded.
public struct SignedEntitlement: Codable, Sendable, Equatable {
    public var payload: String
    public var signature: String
    public var keyId: String

    public init(payload: String, signature: String, keyId: String) {
        self.payload = payload
        self.signature = signature
        self.keyId = keyId
    }
}

/// base64url without padding, the encoding the document uses on both fields.
enum Base64URL {
    static func decode(_ text: String) -> Data? {
        var value = text.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = value.count % 4
        if remainder > 0 { value += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: value)
    }

    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// One decoder for every licensing response.
///
/// The service may or may not send fractional seconds. Rejecting a document
/// over a decimal point would lock out a paying user, so both forms decode.
enum LicensingJSON {
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { source in
            let text = try source.singleValueContainer().decode(String.self)
            guard let date = iso8601.date(from: text) ?? iso8601Plain.date(from: text) else {
                throw DecodingError.dataCorrupted(DecodingError.Context(
                    codingPath: source.codingPath,
                    debugDescription: "The date \(text) is not an ISO 8601 timestamp."))
            }
            return date
        }
        return decoder
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, target in
            var container = target.singleValueContainer()
            try container.encode(iso8601Plain.string(from: date))
        }
        return encoder
    }

    /// A fresh formatter per call. `ISO8601DateFormatter` is not `Sendable`,
    /// and a document is decoded a handful of times per session, so a shared
    /// one would buy nothing and cost a lock.
    private static var iso8601: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static var iso8601Plain: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}
