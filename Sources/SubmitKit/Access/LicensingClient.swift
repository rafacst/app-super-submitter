import Foundation

/// What the licensing service offers. The server is authoritative for every
/// amount, so nothing here is hard coded from a price list.
public struct BillingPlan: Codable, Sendable, Equatable, Identifiable {
    /// `monthly`, `annual`, or `lifetime`. The client sends this back and the
    /// server maps it to an allow-listed Stripe Price.
    public var id: String
    /// The smallest currency unit, the way Stripe expresses it.
    public var amount: Int
    /// `month`, `year`, or nil for the one-time purchase.
    public var interval: String?
    public var available: Bool

    public init(id: String, amount: Int, interval: String?, available: Bool) {
        self.id = id
        self.amount = amount
        self.interval = interval
        self.available = available
    }
}

public struct BillingPlans: Codable, Sendable, Equatable {
    public var currency: String
    public var plans: [BillingPlan]

    public init(currency: String, plans: [BillingPlan]) {
        self.currency = currency
        self.plans = plans
    }
}

/// What the server says about a promotion code, and nothing more. No coupon
/// object, no redemption count, no customer restriction detail.
public struct PromotionPreview: Codable, Sendable, Equatable {
    public var valid: Bool
    public var plan: String
    public var subtotal: Int
    public var discount: Int
    public var total: Int
    public var currency: String
    public var message: String?

    public init(valid: Bool, plan: String, subtotal: Int, discount: Int, total: Int,
                currency: String, message: String? = nil) {
        self.valid = valid
        self.plan = plan
        self.subtotal = subtotal
        self.discount = discount
        self.total = total
        self.currency = currency
        self.message = message
    }
}

public struct CheckoutSession: Codable, Sendable, Equatable {
    public var sessionId: String
    /// The Stripe-hosted page. The app opens it in the default browser and
    /// collects no card detail itself.
    public var url: URL
    public var expiresAt: Date?

    public init(sessionId: String, url: URL, expiresAt: Date? = nil) {
        self.sessionId = sessionId
        self.url = url
        self.expiresAt = expiresAt
    }
}

public struct PortalSession: Codable, Sendable, Equatable {
    public var url: URL

    public init(url: URL) { self.url = url }
}

/// The licensing service, as the app sees it.
///
/// Every privileged Stripe call happens behind this. The app holds no Stripe
/// secret key, no webhook secret, and no Stripe object model.
public protocol LicensingClient: Sendable {
    func plans() async throws -> BillingPlans
    func entitlement(idToken: String) async throws -> SignedEntitlement
    func restore(idToken: String) async throws -> SignedEntitlement
    func validate(promotionCode: String, plan: String,
                  idToken: String) async throws -> PromotionPreview
    func checkout(plan: String, promotionCode: String?, idempotencyKey: String,
                  idToken: String) async throws -> CheckoutSession
    func portal(idToken: String) async throws -> PortalSession
}

/// The HTTPS implementation. `licensing-api.md` is the contract it expects.
public struct HTTPLicensingClient: LicensingClient {
    private let base: URL
    private let session: URLSession

    public init(base: URL, session: URLSession = .shared) {
        self.base = base
        self.session = session
    }

    public func plans() async throws -> BillingPlans {
        try await send("v1/billing/plans", method: "GET")
    }

    public func entitlement(idToken: String) async throws -> SignedEntitlement {
        try await send("v1/entitlements/me", method: "GET", idToken: idToken)
    }

    public func restore(idToken: String) async throws -> SignedEntitlement {
        try await send("v1/billing/restore", method: "POST", idToken: idToken, body: [:])
    }

    public func validate(promotionCode: String, plan: String,
                         idToken: String) async throws -> PromotionPreview {
        try await send("v1/billing/promotion-code/validate", method: "POST",
                       idToken: idToken,
                       body: ["plan": plan,
                              "code": promotionCode.trimmingCharacters(in: .whitespacesAndNewlines)])
    }

    public func checkout(plan: String, promotionCode: String?, idempotencyKey: String,
                         idToken: String) async throws -> CheckoutSession {
        var body: [String: String] = ["plan": plan, "idempotencyKey": idempotencyKey]
        if let promotionCode, !promotionCode.isEmpty {
            body["promotionCode"] = promotionCode.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return try await send("v1/billing/checkout", method: "POST", idToken: idToken, body: body)
    }

    public func portal(idToken: String) async throws -> PortalSession {
        try await send("v1/billing/portal", method: "POST", idToken: idToken, body: [:])
    }

    private func send<T: Decodable>(_ path: String, method: String, idToken: String? = nil,
                                    body: [String: String]? = nil) async throws -> T {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let idToken { request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AccessError.serviceUnavailable(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AccessError.serviceUnavailable("The response was not understood.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ServiceError.decode(data, status: http.statusCode)
        }
        do {
            return try LicensingJSON.decoder.decode(T.self, from: data)
        } catch {
            throw AccessError.malformedEntitlement
        }
    }
}

/// The error body the service returns: a stable code and a message that is
/// already safe to show. The client never invents its own wording for a
/// server-side failure it does not recognise.
private struct ServiceError: Decodable {
    let code: String
    /// Optional, because the service is allowed to send `"message": null` and
    /// does on at least one route. It was required, so a null collapsed the
    /// whole decode and threw away the `code` with it: an invalid promotion
    /// code came back as "The service answered with status 400" rather than as
    /// the reason the service actually gave.
    let message: String?

    static func decode(_ data: Data, status: Int) -> AccessError {
        guard let body = try? JSONDecoder().decode(ServiceError.self, from: data) else {
            return .serviceUnavailable("The service answered with status \(status).")
        }
        switch body.code {
        case "authentication_required": return .signedOut
        case "entitlement_expired": return .entitlementExpired
        case "entitlement_refresh_required": return .refreshRequired
        default:
            return .server(code: body.code,
                           message: body.message ?? Self.wording(for: body.code))
        }
    }

    /// A sentence for a code the service sent with no message of its own.
    ///
    /// The list is the one `licensing-service-prompt.md` says the client should
    /// expect. It never invents a reason: it says what the code the service
    /// chose already means.
    private static func wording(for code: String) -> String {
        switch code {
        case "promotion_code_invalid":
            "This code is not valid for the selected plan."
        case "plan_unavailable":
            "This plan is not on sale."
        case "already_subscribed":
            "This account already has a subscription. Open Manage billing to change it."
        case "checkout_pending":
            "A checkout is already open for this plan. Finish it in the browser, or wait a moment and try again."
        case "environment_mismatch":
            "This code belongs to the other Stripe environment. A test-mode code does not exist in live mode."
        case "billing_service_unavailable":
            "Stripe could not be reached. Nothing was charged. Try again in a moment."
        case "rate_limited":
            "Too many attempts. Wait a moment and try again."
        default:
            "The service refused the request: \(code)."
        }
    }
}
