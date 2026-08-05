import Foundation

/// The signing identities of the team: the bundle IDs, the capabilities, the
/// certificates, the devices, the profiles, the merchant IDs, and the pass
/// type IDs.
///
/// Every call here is a read. Nothing in this file creates, revokes, or
/// deletes an identity. A revoked certificate breaks every machine that signs
/// with it, and a deleted profile breaks a build, so those stay in the
/// Developer portal where one person owns the consequence.
///
/// The value this adds is the expiry. A certificate and a profile both lapse
/// on a date that nothing else in the app shows, and the first sign of a lapse
/// is usually a failed build.
public struct AppleProvisioningClient: Sendable {
    private let api: StoreAPI

    public init(api: StoreAPI) {
        self.api = api
    }

    /// One identity, whatever its resource. Seven resources with four useful
    /// fields between them do not earn seven models.
    public struct Item: Sendable, Equatable, Identifiable {
        public var id: String
        public var kind: Kind
        public var name: String
        /// The identifier, the serial number, or the UDID, whichever the
        /// resource carries.
        public var detail: String?
        public var platform: String?
        public var expiresAt: Date?
        /// `ENABLED`, `ACTIVE`, `INVALID`, `EXPIRED`, and the rest.
        public var state: String?

        public init(id: String, kind: Kind, name: String, detail: String? = nil,
                    platform: String? = nil, expiresAt: Date? = nil,
                    state: String? = nil) {
            self.id = id
            self.kind = kind
            self.name = name
            self.detail = detail
            self.platform = platform
            self.expiresAt = expiresAt
            self.state = state
        }

        public enum Kind: String, Sendable, Equatable, CaseIterable {
            case bundleId, capability, certificate, device, profile
            case merchantId, passTypeId

            public var title: String {
                switch self {
                case .bundleId: "Bundle IDs"
                case .capability: "Capabilities"
                case .certificate: "Certificates"
                case .device: "Devices"
                case .profile: "Profiles"
                case .merchantId: "Merchant IDs"
                case .passTypeId: "Pass type IDs"
                }
            }

            public var symbol: String {
                switch self {
                case .bundleId: "at"
                case .capability: "switch.2"
                case .certificate: "seal"
                case .device: "iphone"
                case .profile: "doc.badge.gearshape"
                case .merchantId: "creditcard"
                case .passTypeId: "wallet.pass"
                }
            }
        }

        /// Apple already refuses it.
        public var isExpired: Bool {
            guard let expiresAt else { return false }
            return expiresAt < Date()
        }

        /// Close enough that a developer wants to know now. Apple gives no
        /// warning of its own, and a certificate that lapses mid-release is
        /// the expensive way to find out.
        public func expiresSoon(within days: Int = 30, now: Date = Date()) -> Bool {
            guard let expiresAt, expiresAt >= now else { return false }
            return expiresAt.timeIntervalSince(now) <= Double(days) * 86_400
        }
    }

    /// Everything the team holds, in one list.
    ///
    /// A resource that answers an error contributes nothing and never fails
    /// the whole read. An API key scoped to one app answers 403 on the
    /// provisioning resources, which is a permission state and not a fault.
    public func inventory() async throws -> (items: [Item], failures: [String]) {
        var items: [Item] = []
        var failures: [String] = []

        // The bundle IDs carry their capabilities in one call, so the
        // capability rows cost no second round trip per bundle ID.
        do {
            let payload = JSON(data: try await api.apple(
                "GET", "/v1/bundleIds",
                query: [URLQueryItem(name: "limit", value: "200"),
                        URLQueryItem(name: "include", value: "bundleIdCapabilities")]).data)
            items += payload["data"].array.compactMap(Self.parseBundleId)
            items += payload["included"].array.compactMap(Self.parseCapability)
        } catch {
            failures.append("Bundle IDs: \(error.localizedDescription)")
        }

        for (path, parse) in Self.simpleReads {
            do {
                let payload = JSON(data: try await api.apple(
                    "GET", path,
                    query: [URLQueryItem(name: "limit", value: "200")]).data)
                items += payload["data"].array.compactMap(parse)
            } catch {
                failures.append("\(path.dropFirst(4)): \(error.localizedDescription)")
            }
        }
        return (items, failures)
    }

    private static let simpleReads: [(String, @Sendable (JSON) -> Item?)] = [
        ("/v1/certificates", parseCertificate),
        ("/v1/devices", parseDevice),
        ("/v1/profiles", parseProfile),
        ("/v1/merchantIds", parseMerchantId),
        ("/v1/passTypeIds", parsePassTypeId),
    ]

    // MARK: - The parsers

    static func parseBundleId(_ item: JSON) -> Item? {
        guard let id = item["id"].string else { return nil }
        let attributes = item["attributes"]
        return Item(id: id, kind: .bundleId,
                    name: attributes["name"].string ?? id,
                    detail: attributes["identifier"].string,
                    platform: attributes["platform"].string)
    }

    static func parseCapability(_ item: JSON) -> Item? {
        guard item["type"].string == "bundleIdCapabilities",
              let id = item["id"].string,
              let type = item["attributes"]["capabilityType"].string else { return nil }
        return Item(id: id, kind: .capability, name: Self.title(type))
    }

    static func parseCertificate(_ item: JSON) -> Item? {
        guard let id = item["id"].string else { return nil }
        let attributes = item["attributes"]
        return Item(id: id, kind: .certificate,
                    name: attributes["displayName"].string
                        ?? attributes["name"].string ?? id,
                    detail: attributes["serialNumber"].string,
                    platform: attributes["platform"].string,
                    expiresAt: Self.date(attributes["expirationDate"].string),
                    state: Self.title(attributes["certificateType"].string ?? ""))
    }

    static func parseDevice(_ item: JSON) -> Item? {
        guard let id = item["id"].string else { return nil }
        let attributes = item["attributes"]
        return Item(id: id, kind: .device,
                    name: attributes["name"].string ?? id,
                    detail: attributes["udid"].string,
                    platform: attributes["platform"].string,
                    state: attributes["status"].string)
    }

    static func parseProfile(_ item: JSON) -> Item? {
        guard let id = item["id"].string else { return nil }
        let attributes = item["attributes"]
        return Item(id: id, kind: .profile,
                    name: attributes["name"].string ?? id,
                    detail: Self.title(attributes["profileType"].string ?? ""),
                    platform: attributes["platform"].string,
                    expiresAt: Self.date(attributes["expirationDate"].string),
                    state: attributes["profileState"].string)
    }

    static func parseMerchantId(_ item: JSON) -> Item? {
        guard let id = item["id"].string else { return nil }
        return Item(id: id, kind: .merchantId,
                    name: item["attributes"]["name"].string ?? id,
                    detail: item["attributes"]["identifier"].string)
    }

    static func parsePassTypeId(_ item: JSON) -> Item? {
        guard let id = item["id"].string else { return nil }
        return Item(id: id, kind: .passTypeId,
                    name: item["attributes"]["name"].string ?? id,
                    detail: item["attributes"]["identifier"].string)
    }

    static func title(_ identifier: String) -> String { AppleWords.title(identifier) }

    static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
            ?? ISO8601DateFormatter().date(from: text)
    }
}
