import Foundation

/// The Apple Accounts that buy nothing.
///
/// The Monetization tab writes the products; this answers the question that
/// comes next, which is who can test them and what happens when they do. A
/// sandbox tester is a real Apple Account in a fake store: the purchases cost
/// nothing, and a subscription that renews yearly in the App Store renews every
/// few minutes here.
///
/// Clearing the purchase history is the button that App Store Connect gets
/// opened for. A tester who bought the subscription once cannot buy it again,
/// so every second run of the paywall tests the restore path instead of the
/// purchase path until somebody clears it.
///
/// Nothing here touches a paying customer. A sandbox account has no money in
/// it, which is the whole point of one, so the clear is safe in a way that no
/// other write in this app is.
public struct AppleSandboxClient: Sendable {
    private let api: StoreAPI

    public init(api: StoreAPI) {
        self.api = api
    }

    /// How fast a subscription renews in the sandbox. Apple compresses the
    /// month, and this is the whole published list.
    public static let renewalRates: [StoreValues.Choice] = [
        .init("MONTHLY_RENEWAL_EVERY_THREE_MINUTES", "A month every 3 minutes"),
        .init("MONTHLY_RENEWAL_EVERY_FIVE_MINUTES", "A month every 5 minutes"),
        .init("MONTHLY_RENEWAL_EVERY_FIFTEEN_MINUTES", "A month every 15 minutes"),
        .init("MONTHLY_RENEWAL_EVERY_THIRTY_MINUTES", "A month every 30 minutes"),
        .init("MONTHLY_RENEWAL_EVERY_ONE_HOUR", "A month every hour"),
    ]

    public struct Tester: Sendable, Equatable, Identifiable {
        public var id: String
        /// The Apple Account the tester signs in with.
        public var appleAccount: String
        public var firstName: String?
        public var lastName: String?
        /// The three-letter store the tester buys in, for example `USA`.
        public var territory: String?
        public var renewalRate: String?
        /// Apple interrupts the purchase to test the failure paths: an
        /// expired card, a parental approval, a Terms and Conditions sheet.
        public var interruptPurchases: Bool
        public var applePayCompatible: Bool

        public init(id: String, appleAccount: String, firstName: String? = nil,
                    lastName: String? = nil, territory: String? = nil,
                    renewalRate: String? = nil, interruptPurchases: Bool = false,
                    applePayCompatible: Bool = false) {
            self.id = id
            self.appleAccount = appleAccount
            self.firstName = firstName
            self.lastName = lastName
            self.territory = territory
            self.renewalRate = renewalRate
            self.interruptPurchases = interruptPurchases
            self.applePayCompatible = applePayCompatible
        }

        public var name: String {
            [firstName, lastName].compactMap { $0 }
                .filter { !$0.isEmpty }.joined(separator: " ")
        }
    }

    /// Every sandbox account the team holds.
    ///
    /// Apple creates these in App Store Connect and publishes no create call,
    /// so this reads what is there and the developer adds one in the console.
    public func testers(limit: Int = 200) async throws -> [Tester] {
        let payload = JSON(data: try await api.apple(
            "GET", "/v2/sandboxTesters",
            query: [URLQueryItem(name: "limit",
                                 value: String(min(max(limit, 1), 200)))]).data)
        return payload["data"].array.compactMap(Self.parse)
            .sorted { $0.appleAccount.lowercased() < $1.appleAccount.lowercased() }
    }

    /// Changes how the sandbox behaves for one account. Every value here is a
    /// testing knob, so nothing it does reaches the App Store.
    public func update(testerID: String, renewalRate: String? = nil,
                       interruptPurchases: Bool? = nil,
                       territory: String? = nil) async throws {
        var attributes: [String: Any] = [:]
        if let renewalRate, !renewalRate.isEmpty { attributes["subscriptionRenewalRate"] = renewalRate }
        if let interruptPurchases { attributes["interruptPurchases"] = interruptPurchases }
        if let territory, !territory.isEmpty { attributes["territory"] = territory }
        guard !attributes.isEmpty else { return }
        try await api.apple("PATCH", "/v2/sandboxTesters/\(testerID)", body: [
            "data": ["type": "sandboxTesters", "id": testerID, "attributes": attributes],
        ])
    }

    /// **This forgets everything the accounts ever bought in the sandbox.**
    /// Nothing gives the history back, and that is the point: the next run of
    /// the paywall meets a customer who has bought nothing.
    ///
    /// Apple takes the whole list in one call.
    public func clearPurchaseHistory(testerIDs: [String]) async throws {
        guard !testerIDs.isEmpty else { return }
        try await api.apple("POST", "/v2/sandboxTestersClearPurchaseHistoryRequest", body: [
            "data": [
                "type": "sandboxTestersClearPurchaseHistoryRequest",
                "relationships": ["sandboxTesters": [
                    "data": testerIDs.map { ["type": "sandboxTesters", "id": $0] }]],
            ],
        ])
    }

    static func parse(_ item: JSON) -> Tester? {
        guard let id = item["id"].string else { return nil }
        let attributes = item["attributes"]
        return Tester(
            id: id,
            appleAccount: attributes["acAccountName"].string ?? id,
            firstName: attributes["firstName"].string,
            lastName: attributes["lastName"].string,
            territory: attributes["territory"].string,
            renewalRate: attributes["subscriptionRenewalRate"].string,
            interruptPurchases: attributes["interruptPurchases"].bool ?? false,
            applePayCompatible: attributes["applePayCompatible"].bool ?? false)
    }
}
