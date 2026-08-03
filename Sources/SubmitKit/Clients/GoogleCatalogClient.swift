import Foundation

/// Reads one Google catalog product at a time, and switches one offer.
///
/// The plan needs a per-field diff. A list read answers "which products exist"
/// and nothing else, so the plan could only ever say "write every product".
/// These reads carry the titles, the prices, and the offer states, and the
/// planner compares them field by field.
///
/// The offer switches sit here too, because they name one offer and the batch
/// form in `GoogleCatalog.swift` names a whole product.
///
/// `// ponytail: one client for the reads and the single switches. The batch
/// // writes stay on the runner, because only a plan step sends those.`
public struct GoogleCatalogClient: Sendable {
    /// Google limits a batch read. The client sends several batches rather
    /// than one oversized request.
    static let batchLimit = 100

    private let api: StoreAPI

    public init(api: StoreAPI) {
        self.api = api
    }

    // MARK: - The one-time products

    /// One product. Returns nil when Google holds no product with that id.
    public func oneTimeProduct(packageName: String,
                               productId: String) async throws
        -> ActualState.Google.CatalogProduct? {
        let path = "\(Self.base(packageName))/oneTimeProducts/\(StateReader.escape(productId))"
        do {
            return Self.parseOneTimeProduct(JSON(data: try await api.google("GET", path).data))
        } catch ConnectionError.http(let status, _) where status == 404 {
            return nil
        }
    }

    /// Every named product, in as few requests as the batch limit allows.
    public func oneTimeProducts(packageName: String, productIds: [String]) async throws
        -> [String: ActualState.Google.CatalogProduct] {
        var result: [String: ActualState.Google.CatalogProduct] = [:]
        for chunk in Self.chunks(productIds) {
            let payload = JSON(data: try await api.google(
                "GET", "\(Self.base(packageName))/oneTimeProducts:batchGet",
                query: chunk.map { URLQueryItem(name: "productIds", value: $0) }).data)
            for item in payload["oneTimeProducts"].array {
                guard let product = Self.parseOneTimeProduct(item) else { continue }
                result[product.productId] = product
            }
        }
        return result
    }

    // MARK: - The subscriptions

    public func subscription(packageName: String,
                             productId: String) async throws
        -> ActualState.Google.CatalogProduct? {
        let path = "\(Self.base(packageName))/subscriptions/\(StateReader.escape(productId))"
        do {
            return Self.parseSubscription(JSON(data: try await api.google("GET", path).data))
        } catch ConnectionError.http(let status, _) where status == 404 {
            return nil
        }
    }

    public func subscriptions(packageName: String, productIds: [String]) async throws
        -> [String: ActualState.Google.CatalogProduct] {
        var result: [String: ActualState.Google.CatalogProduct] = [:]
        for chunk in Self.chunks(productIds) {
            let payload = JSON(data: try await api.google(
                "GET", "\(Self.base(packageName))/subscriptions:batchGet",
                query: chunk.map { URLQueryItem(name: "productIds", value: $0) }).data)
            for item in payload["subscriptions"].array {
                guard let product = Self.parseSubscription(item) else { continue }
                result[product.productId] = product
            }
        }
        return result
    }

    // MARK: - The subscription offers

    public struct Offer: Sendable, Equatable, Identifiable {
        public var id: String
        public var basePlanId: String
        public var state: String?

        public init(id: String, basePlanId: String, state: String? = nil) {
            self.id = id
            self.basePlanId = basePlanId
            self.state = state
        }
    }

    public func subscriptionOffer(packageName: String, productId: String, basePlanId: String,
                                  offerId: String) async throws -> Offer? {
        let path = "\(Self.offerBase(packageName, productId, basePlanId))"
            + "/\(StateReader.escape(offerId))"
        do {
            return Self.parseOffer(JSON(data: try await api.google("GET", path).data))
        } catch ConnectionError.http(let status, _) where status == 404 {
            return nil
        }
    }

    /// Every offer of one base plan. Pass `-` as the base plan to read the
    /// offers of every base plan of the product, which is what Google
    /// documents for the wildcard.
    public func subscriptionOffers(packageName: String, productId: String,
                                   basePlanId: String = "-") async throws -> [Offer] {
        var result: [Offer] = []
        var token: String?
        // The page loop is bounded. A malformed token never spins forever.
        for _ in 0..<100 {
            var query = [URLQueryItem(name: "pageSize", value: "100")]
            if let token { query.append(URLQueryItem(name: "pageToken", value: token)) }
            let payload = JSON(data: try await api.google(
                "GET", Self.offerBase(packageName, productId, basePlanId), query: query).data)
            result += payload["subscriptionOffers"].array.compactMap(Self.parseOffer)
            token = payload["nextPageToken"].string
            if token?.isEmpty != false { break }
        }
        return result
    }

    /// The named offers of one base plan. Google takes this one as a POST,
    /// unlike the two product batch reads.
    public func subscriptionOffers(packageName: String, productId: String, basePlanId: String,
                                   offerIds: [String]) async throws -> [Offer] {
        var result: [Offer] = []
        for chunk in Self.chunks(offerIds) {
            let payload = JSON(data: try await api.google(
                "POST", "\(Self.offerBase(packageName, productId, basePlanId)):batchGet",
                body: ["requests": chunk.map {
                    ["packageName": packageName, "productId": productId,
                     "basePlanId": basePlanId, "offerId": $0]
                }]).data)
            result += payload["subscriptionOffers"].array.compactMap(Self.parseOffer)
        }
        return result
    }

    // MARK: - The one-time product offers

    /// Every offer of one purchase option. The app writes one option per
    /// product, so the option id is the product id.
    public func oneTimeOffers(packageName: String, productId: String,
                              purchaseOptionId: String) async throws -> [Offer] {
        var result: [Offer] = []
        var token: String?
        for _ in 0..<100 {
            var query = [URLQueryItem(name: "pageSize", value: "100")]
            if let token { query.append(URLQueryItem(name: "pageToken", value: token)) }
            let payload = JSON(data: try await api.google(
                "GET", Self.oneTimeOfferBase(packageName, productId, purchaseOptionId),
                query: query).data)
            result += payload["oneTimeProductOffers"].array.compactMap(Self.parseOffer)
            token = payload["nextPageToken"].string
            if token?.isEmpty != false { break }
        }
        return result
    }

    // MARK: - One offer switch

    /// Activates or stops one subscription offer. Google keeps the offer and
    /// changes its state, the same rule as the base plan switch.
    public func setSubscriptionOfferState(packageName: String, productId: String,
                                          basePlanId: String, offerId: String,
                                          active: Bool) async throws {
        try await api.google(
            "POST",
            "\(Self.offerBase(packageName, productId, basePlanId))"
                + "/\(StateReader.escape(offerId)):\(active ? "activate" : "deactivate")",
            body: ["packageName": packageName, "productId": productId,
                   "basePlanId": basePlanId, "offerId": offerId])
    }

    /// The same switch for a one-time product offer.
    public func setOneTimeOfferState(packageName: String, productId: String,
                                     purchaseOptionId: String, offerId: String,
                                     active: Bool) async throws {
        try await api.google(
            "POST",
            "\(Self.oneTimeOfferBase(packageName, productId, purchaseOptionId))"
                + "/\(StateReader.escape(offerId)):\(active ? "activate" : "deactivate")",
            body: ["packageName": packageName, "productId": productId,
                   "purchaseOptionId": purchaseOptionId, "offerId": offerId])
    }

    // MARK: - The parsers

    static func parseOneTimeProduct(_ item: JSON) -> ActualState.Google.CatalogProduct? {
        guard let productId = item["productId"].string else { return nil }
        var result = ActualState.Google.CatalogProduct()
        result.productId = productId
        result.listings = Self.listings(item["listings"])
        // A one-time product prices each purchase option. The app writes one
        // option per product, so the first one carries the price.
        let option = item["purchaseOptions"].array.first
        for config in option?["regionalPricingAndAvailabilityConfigs"].array ?? [] {
            guard let region = config["regionCode"].string,
                  let price = Self.money(config["price"]) else { continue }
            result.prices[region] = price
        }
        result.basePlanState = option?["state"].string
        return result
    }

    static func parseSubscription(_ item: JSON) -> ActualState.Google.CatalogProduct? {
        guard let productId = item["productId"].string else { return nil }
        var result = ActualState.Google.CatalogProduct()
        result.productId = productId
        result.listings = Self.listings(item["listings"])
        guard let basePlan = item["basePlans"].array.first else { return result }
        result.basePlanId = basePlan["basePlanId"].string
        result.basePlanDuration = basePlan["autoRenewingBasePlanType"]["billingPeriodDuration"]
            .string ?? basePlan["prepaidBasePlanType"]["billingPeriodDuration"].string
        result.basePlanState = basePlan["state"].string
        for config in basePlan["regionalConfigs"].array {
            guard let region = config["regionCode"].string,
                  let price = Self.money(config["price"]) else { continue }
            result.prices[region] = price
        }
        return result
    }

    static func parseOffer(_ item: JSON) -> Offer? {
        guard let id = item["offerId"].string else { return nil }
        // A one-time product offer names the purchase option where a
        // subscription offer names the base plan. Both land in the same field.
        return Offer(id: id,
                     basePlanId: item["basePlanId"].string
                        ?? item["purchaseOptionId"].string ?? "",
                     state: item["state"].string)
    }

    static func listings(_ node: JSON) -> [String: ActualState.Google.CatalogProduct.ProductListing] {
        var result: [String: ActualState.Google.CatalogProduct.ProductListing] = [:]
        for entry in node.array {
            guard let language = entry["languageCode"].string else { continue }
            var listing = ActualState.Google.CatalogProduct.ProductListing()
            listing.title = entry["title"].string
            listing.description = entry["description"].string
            result[language] = listing
        }
        return result
    }

    /// `{"currencyCode":"USD","units":"4","nanos":990000000}` becomes
    /// `"USD 4.99"`. The plan compares the text, so the money never becomes a
    /// float on the way.
    static func money(_ node: JSON) -> String? {
        guard let currency = node["currencyCode"].string else { return nil }
        return priceText(currency: currency, units: Int64(node["units"].int ?? 0),
                         nanos: node["nanos"].int ?? 0)
    }

    /// Google takes units and nanos, never a float.
    ///
    /// `// ponytail: one definition. The apply and the plan both need it, and
    /// // a second copy would drift by a rounding step and show a false diff.`
    static func nanoUnits(_ amount: Decimal) -> (units: Int64, nanos: Int) {
        let total = NSDecimalNumber(decimal: amount * 1_000_000_000).int64Value
        return (total / 1_000_000_000, Int(total % 1_000_000_000))
    }

    static func priceText(currency: String, units: Int64, nanos: Int) -> String {
        let amount = Decimal(units) + Decimal(nanos) / 1_000_000_000
        return "\(currency) \(NSDecimalNumber(decimal: amount).stringValue)"
    }

    static func base(_ packageName: String) -> String {
        "/androidpublisher/v3/applications/\(StateReader.escape(packageName))"
    }

    static func offerBase(_ packageName: String, _ productId: String,
                          _ basePlanId: String) -> String {
        "\(base(packageName))/subscriptions/\(StateReader.escape(productId))"
            + "/basePlans/\(StateReader.escape(basePlanId))/offers"
    }

    static func oneTimeOfferBase(_ packageName: String, _ productId: String,
                                 _ purchaseOptionId: String) -> String {
        "\(base(packageName))/oneTimeProducts/\(StateReader.escape(productId))"
            + "/purchaseOptions/\(StateReader.escape(purchaseOptionId))/offers"
    }

    static func chunks(_ ids: [String]) -> [[String]] {
        guard !ids.isEmpty else { return [] }
        return stride(from: 0, to: ids.count, by: batchLimit).map {
            Array(ids[$0..<min($0 + batchLimit, ids.count)])
        }
    }
}
