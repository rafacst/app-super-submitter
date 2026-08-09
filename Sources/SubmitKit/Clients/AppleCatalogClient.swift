import Foundation

/// The one version rule shared by apply, catalog, and release.
///
/// Prefer the newest editable draft. When none exists, the newest version is
/// still the truthful catalog read, but only an editable one can be changed or
/// added to a review submission.
enum AppleVersionSelection {
    static func preferred(_ items: [JSON]) -> JSON? {
        newest(items.filter(isEditable)) ?? newest(items)
    }

    static func editable(_ items: [JSON]) -> JSON? {
        newest(items.filter(isEditable))
    }

    static func isEditable(_ item: JSON) -> Bool {
        let state = item["attributes"]["state"].string
        return state == nil || state == "PREPARE_FOR_SUBMISSION"
    }

    static func blocksEdits(_ item: JSON) -> Bool {
        ["READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW"]
            .contains(item["attributes"]["state"].string ?? "")
    }

    private static func newest(_ items: [JSON]) -> JSON? {
        items.max { ($0["attributes"]["version"].int ?? 0)
            < ($1["attributes"]["version"].int ?? 0) }
    }
}

/// Reads one App Store paid product at a time.
///
/// The list endpoints answer "which products exist" and nothing else, so the
/// plan could only ever say "write every product". These reads carry the
/// names, the localizations, the prices, the territories, and the offers, and
/// the planner compares them field by field.
///
/// This is the App Store twin of `GoogleCatalogClient`. The two stores shape a
/// product differently, so the two clients stay apart and only the compared
/// fields line up.
///
/// `// ponytail: one request per product per aspect. App Store Connect takes
/// // no batch read, so a large catalog costs a large read. The plan already
/// // limits it to the products the manifest names.`
public struct AppleCatalogClient: Sendable {
    private let api: StoreAPI

    public init(api: StoreAPI) {
        self.api = api
    }

    // MARK: - The one-time purchases

    /// Every purchase that the app holds, keyed by the product id.
    ///
    /// The detail reads run only for the products the caller names. A product
    /// that Apple holds and the manifest never mentions costs one row in the
    /// id set and no request.
    public func purchases(appID: String, productIds: [String]) async throws
        -> [String: ActualState.Apple.CatalogProduct] {
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appID)/inAppPurchasesV2?limit=200").data)
        var result: [String: ActualState.Apple.CatalogProduct] = [:]
        let wanted = Set(productIds)

        for item in payload["data"].array {
            guard let product = Self.parsePurchase(item) else { continue }
            result[product.productId] = product
        }
        for productId in wanted {
            guard var product = result[productId], let id = product.id else { continue }
            await fillPurchase(&product, id: id)
            result[productId] = product
        }
        return result
    }

    /// The detail of one purchase. A failure on any one aspect leaves that
    /// field nil, and the planner then marks the row unverified rather than
    /// showing a diff that nobody read.
    private func fillPurchase(_ product: inout ActualState.Apple.CatalogProduct,
                              id: String) async {
        if let versions = try? await api.apple(
            "GET", "/v2/inAppPurchases/\(id)/versions?limit=200"),
           let version = AppleVersionSelection.preferred(
            JSON(data: versions.data)["data"].array),
           let versionID = version["id"].string,
           let response = try? await api.apple(
            "GET", "/v1/inAppPurchaseVersions/\(versionID)/localizations?limit=200") {
            product.locales = Self.localizations(JSON(data: response.data))
            product.localesRead = true
        }
        if let response = try? await api.apple(
            "GET", "/v2/inAppPurchases/\(id)/iapPriceSchedule"
                + "?include=manualPrices,manualPrices.inAppPurchasePricePoint") {
            product.prices = Self.prices(JSON(data: response.data),
                                         pointType: "inAppPurchasePricePoints")
        }
        if let response = try? await api.apple(
            "GET", "/v2/inAppPurchases/\(id)/inAppPurchaseAvailability"
                + "?include=availableTerritories&limit=200") {
            product.availableTerritories = Self.territories(JSON(data: response.data))
        }
        // Apple answers 404 when the purchase is not promoted, which is a
        // state and not a failure.
        if let response = try? await api.apple(
            "GET", "/v2/inAppPurchases/\(id)/promotedPurchase") {
            let promoted = JSON(data: response.data)["data"]
            product.promoted = promoted["attributes"]["visibleForAllUsers"].bool
                ?? (promoted["id"].string != nil)
        } else {
            product.promoted = false
        }
    }

    // MARK: - The subscriptions

    /// The groups that Apple holds and their localizations.
    public struct Groups: Sendable {
        public var names: Set<String> = []
        public var locales: [String: [String: ActualState.Apple.CatalogProduct.ProductLocale]] = [:]
    }

    /// Every subscription that the app holds, keyed by the product id, plus
    /// the groups that hold them.
    ///
    /// The subscription write covers the group, its localizations, and its
    /// plans in one operation, so the read carries all three and the diff can
    /// drop the whole step when every part matches.
    public func subscriptions(appID: String, productIds: [String],
                              groupNames: [String] = []) async throws
        -> (products: [String: ActualState.Apple.CatalogProduct], groups: Groups) {
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appID)/subscriptionGroups?include=subscriptions&limit=200").data)
        var result: [String: ActualState.Apple.CatalogProduct] = [:]
        var groups = Groups()
        let versions = AppleSubscriptionVersionsClient(api: api)
        let wanted = Set(productIds)
        let wantedGroups = Set(groupNames)

        for item in payload["included"].array where item["type"].string == "subscriptions" {
            guard let product = Self.parseSubscription(item) else { continue }
            result[product.productId] = product
        }
        for item in payload["data"].array {
            guard let name = item["attributes"]["referenceName"].string else { continue }
            groups.names.insert(name)
            guard wantedGroups.contains(name), let id = item["id"].string,
                  let draft = try? await versions.latestVersion(kind: .group, productID: id),
                  let localizations = try? await versions.localizationMetadata(
                    kind: .group, draftID: draft.id) else { continue }
            groups.locales[name] = Self.catalogLocalizations(localizations)
        }
        for productId in wanted {
            guard var product = result[productId], let id = product.id else { continue }
            await fillSubscription(&product, id: id)
            result[productId] = product
        }
        return (result, groups)
    }

    private func fillSubscription(_ product: inout ActualState.Apple.CatalogProduct,
                                  id: String) async {
        let versions = AppleSubscriptionVersionsClient(api: api)
        if let draft = try? await versions.latestVersion(kind: .subscription, productID: id),
           let localizations = try? await versions.localizationMetadata(
            kind: .subscription, draftID: draft.id) {
            product.locales = Self.catalogLocalizations(localizations)
            product.localesRead = true
        }
        if let response = try? await api.apple(
            "GET", "/v1/subscriptions/\(id)/prices"
                + "?include=subscriptionPricePoint,territory&limit=200") {
            product.prices = Self.subscriptionPrices(JSON(data: response.data))
        }
        if let response = try? await api.apple(
            "GET", "/v1/subscriptions/\(id)/planAvailabilities"
                + "?include=availableTerritories&limit=200") {
            let payload = JSON(data: response.data)
            for item in payload["data"].array {
                guard let raw = item["attributes"]["planType"].string,
                      let type = Manifest.ApplePlanType(rawValue: raw) else { continue }
                product.subscriptionPlanTerritories[type] = Set(
                    item["relationships"]["availableTerritories"]["data"].array
                        .compactMap { $0["id"].string })
            }
            product.subscriptionPlanAvailabilityRead = true
        }
        // The three offer kinds live on three collections. The count only
        // means something when all three answered, so one failure leaves it
        // nil and the plan says that nobody verified the offers.
        var count = 0
        var readEvery = true
        for collection in ["introductoryOffers", "promotionalOffers", "winBackOffers"] {
            guard let response = try? await api.apple(
                "GET", "/v1/subscriptions/\(id)/\(collection)?limit=200") else {
                readEvery = false
                continue
            }
            let items = JSON(data: response.data)["data"].array
            count += items.count
            for item in items {
                // A promotional offer carries the code, and a win back offer
                // carries the reference name. An introductory offer carries
                // neither, so it counts and stays unnamed.
                let key = item["attributes"]["offerCode"].string
                    ?? item["attributes"]["referenceName"].string
                    ?? item["attributes"]["offerName"].string
                if let key { product.offerIds.insert(key) }
            }
        }
        if readEvery { product.offerCount = count }
    }

    // MARK: - The parsers

    static func parsePurchase(_ item: JSON) -> ActualState.Apple.CatalogProduct? {
        let attributes = item["attributes"]
        guard let productId = attributes["productId"].string else { return nil }
        var result = ActualState.Apple.CatalogProduct()
        result.productId = productId
        result.id = item["id"].string
        result.name = attributes["name"].string
        result.reviewNote = attributes["reviewNote"].string
        return result
    }

    static func parseSubscription(_ item: JSON) -> ActualState.Apple.CatalogProduct? {
        let attributes = item["attributes"]
        guard let productId = attributes["productId"].string else { return nil }
        var result = ActualState.Apple.CatalogProduct()
        result.productId = productId
        result.id = item["id"].string
        result.name = attributes["name"].string
        result.reviewNote = attributes["reviewNote"].string
        result.duration = Self.duration(attributes["subscriptionPeriod"].string)
        return result
    }

    /// `ONE_MONTH` becomes `P1M`, the form the manifest holds.
    static func duration(_ period: String?) -> String? {
        switch period {
        case "ONE_WEEK": "P1W"
        case "ONE_MONTH": "P1M"
        case "TWO_MONTHS": "P2M"
        case "THREE_MONTHS": "P3M"
        case "SIX_MONTHS": "P6M"
        case "ONE_YEAR": "P1Y"
        default: nil
        }
    }

    static func localizations(_ payload: JSON)
        -> [String: ActualState.Apple.CatalogProduct.ProductLocale] {
        var result: [String: ActualState.Apple.CatalogProduct.ProductLocale] = [:]
        for item in payload["data"].array {
            let attributes = item["attributes"]
            guard let locale = attributes["locale"].string else { continue }
            var value = ActualState.Apple.CatalogProduct.ProductLocale()
            value.name = attributes["name"].string
            value.description = attributes["description"].string
            result[locale] = value
        }
        return result
    }

    private static func catalogLocalizations(
        _ localizations: [String: AppleSubscriptionVersionsClient.Localization])
        -> [String: ActualState.Apple.CatalogProduct.ProductLocale] {
        localizations.mapValues { text in
            var value = ActualState.Apple.CatalogProduct.ProductLocale()
            value.name = text.name
            value.description = text.description
            return value
        }
    }

    /// The manual prices of a price schedule, as territory to customer price.
    ///
    /// The schedule answers with the prices in `data` and the price points and
    /// the territories in `included`, so the territory of a price comes off
    /// the price point that the price names.
    static func prices(_ payload: JSON, pointType: String) -> [String: String] {
        var territoryOfPoint: [String: String] = [:]
        var priceOfPoint: [String: String] = [:]
        for item in payload["included"].array where item["type"].string == pointType {
            guard let id = item["id"].string else { continue }
            priceOfPoint[id] = item["attributes"]["customerPrice"].string
            territoryOfPoint[id] = item["relationships"]["territory"]["data"]["id"].string
        }
        var result: [String: String] = [:]
        for item in payload["included"].array
        where item["type"].string == "inAppPurchasePrices"
            || item["type"].string == "appPrices" {
            let pointID = item["relationships"][pointType.hasPrefix("inApp")
                ? "inAppPurchasePricePoint" : "appPricePoint"]["data"]["id"].string
            guard let pointID, let price = priceOfPoint[pointID],
                  let territory = territoryOfPoint[pointID] else { continue }
            result[territory] = price
        }
        // A schedule with one manual price answers without the join rows, so
        // the price points alone still carry a comparable price.
        if result.isEmpty {
            for (pointID, price) in priceOfPoint {
                guard let territory = territoryOfPoint[pointID] else { continue }
                result[territory] = price
            }
        }
        return result
    }

    /// The subscription prices, which name the territory on the price itself.
    static func subscriptionPrices(_ payload: JSON) -> [String: String] {
        var priceOfPoint: [String: String] = [:]
        for item in payload["included"].array
        where item["type"].string == "subscriptionPricePoints" {
            guard let id = item["id"].string else { continue }
            priceOfPoint[id] = item["attributes"]["customerPrice"].string
        }
        var result: [String: String] = [:]
        for item in payload["data"].array {
            let relationships = item["relationships"]
            guard let territory = relationships["territory"]["data"]["id"].string else { continue }
            let pointID = relationships["subscriptionPricePoint"]["data"]["id"].string
            guard let pointID, let price = priceOfPoint[pointID] else { continue }
            result[territory] = price
        }
        return result
    }

    static func territories(_ payload: JSON) -> Set<String> {
        Set(payload["included"].array
            .filter { $0["type"].string == "territories" }
            .compactMap { $0["id"].string })
    }
}
