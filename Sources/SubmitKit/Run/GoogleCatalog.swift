import Foundation

/// The Google monetization calls that sit outside the two batch updates.
///
/// Every call here keeps the product and changes its state. Nothing deletes,
/// because a deleted product breaks an installed app that still asks for it.
/// Spec section 8, rule 6.
extension Runner {

    private var monetizationBase: String {
        "/androidpublisher/v3/applications/"
            + StateReader.escape(manifest.apps.google?.packageName ?? "")
    }

    // MARK: - The device tier configuration

    /// Google assigns the id, so a create is the only write and every apply
    /// makes a new configuration. The validator says so, because the
    /// developer cannot see it in a diff.
    ///
    /// `// ponytail: no content comparison. Google returns the groups in its
    /// // own order and its own shape, so a diff would need a normalizer that
    /// // is longer than this file. Remove the manifest key between applies.`
    func googleDeviceTierConfig(path: String) async throws {
        guard let url = resolve(path) else { throw RunError.missingBuild }
        let data = try Data(contentsOf: url)
        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RunError.uploadFailed("\(url.lastPathComponent) is not a JSON object.")
        }
        try await api.google("POST", "\(monetizationBase)/deviceTierConfigs", body: body)
    }

    // MARK: - The base plan and the purchase option states

    func googleBasePlanState(productId: String, basePlanId: String,
                             active: Bool) async throws {
        let action = active ? "activate" : "deactivate"
        try await api.google(
            "POST",
            "\(monetizationBase)/subscriptions/\(StateReader.escape(productId))"
                + "/basePlans/\(StateReader.escape(basePlanId)):\(action)",
            body: ["packageName": manifest.apps.google?.packageName ?? "",
                   "productId": productId, "basePlanId": basePlanId])
    }

    /// Google takes the purchase option states in one batch, and the batch
    /// carries one product. The plan makes one step per product.
    func googlePurchaseOptionState(productId: String, purchaseOptionId: String,
                                   active: Bool) async throws {
        let state: [String: Any] = active
            ? ["activatePurchaseOptionRequest": [
                "packageName": manifest.apps.google?.packageName ?? "",
                "productId": productId, "purchaseOptionId": purchaseOptionId]]
            : ["deactivatePurchaseOptionRequest": [
                "packageName": manifest.apps.google?.packageName ?? "",
                "productId": productId, "purchaseOptionId": purchaseOptionId]]
        try await api.google(
            "POST",
            "\(monetizationBase)/oneTimeProducts/\(StateReader.escape(productId))"
                + "/purchaseOptions:batchUpdateStates",
            body: ["requests": [state]])
    }

    // MARK: - The offers

    /// The free trial and the introductory price of one base plan.
    ///
    /// `allowMissing` makes one call cover the create and the update, so the
    /// app never reads the offer list to decide which verb to send.
    func googleSubscriptionOffers(productId: String, basePlanId: String) async throws {
        let offers = manifest.googleOffers(productId: productId)
        guard !offers.isEmpty else { return }
        let packageName = manifest.apps.google?.packageName ?? ""

        let requests = offers.map { offer -> [String: Any] in
            var phase: [String: Any] = [
                "recurrenceCount": offer.periods ?? 1,
            ]
            if let duration = offer.duration { phase["duration"] = duration }
            switch offer.kind {
            case .freeTrial:
                phase["freePriceOverride"] = [:]
            case .introPrice, .offerCode, .promotional, .winBack:
                if let price = offer.price {
                    phase["absoluteDiscount"] = Self.money(price)
                }
            }

            var payload: [String: Any] = [
                "packageName": packageName,
                "productId": productId,
                "basePlanId": basePlanId,
                "offerId": offer.id,
                "phases": [phase],
            ]
            let regions = (offer.regions ?? []).filter { !$0.isEmpty }
            payload["regionalConfigs"] = (regions.isEmpty ? ["US"] : regions).map {
                ["regionCode": $0, "newSubscriberAvailability": true]
            }
            if let eligibility = offer.eligibility {
                payload["targeting"] = Self.googleTargeting(eligibility)
            }
            return ["updateSubscriptionOfferRequest": [
                "subscriptionOffer": payload, "allowMissing": true]]
        }

        try await api.google(
            "POST",
            "\(monetizationBase)/subscriptions/\(StateReader.escape(productId))"
                + "/basePlans/\(StateReader.escape(basePlanId))/offers:batchUpdate",
            body: ["requests": requests])
    }

    /// The discounts on a one-time product. Google keys them by the purchase
    /// option, and the app uses the product id as the option id, the same as
    /// the batch update in `googleProducts`.
    func googleOneTimeOffers(productId: String) async throws {
        let offers = manifest.googleOffers(productId: productId)
        guard !offers.isEmpty else { return }
        let packageName = manifest.apps.google?.packageName ?? ""

        let requests = offers.map { offer -> [String: Any] in
            var payload: [String: Any] = [
                "packageName": packageName,
                "productId": productId,
                "purchaseOptionId": productId,
                "offerId": offer.id,
            ]
            if let price = offer.price {
                payload["discountedPrice"] = ["regionalConfigs": (
                    (offer.regions ?? []).filter { !$0.isEmpty }.isEmpty
                        ? ["US"] : (offer.regions ?? []).filter { !$0.isEmpty }
                ).map { ["regionCode": $0, "price": Self.money(price)] }]
            }
            return ["updateOneTimeProductOfferRequest": [
                "oneTimeProductOffer": payload, "allowMissing": true]]
        }

        try await api.google(
            "POST",
            "\(monetizationBase)/oneTimeProducts/\(StateReader.escape(productId))"
                + "/purchaseOptions/\(StateReader.escape(productId))/offers:batchUpdate",
            body: ["requests": requests])
    }

    // MARK: - The offer states

    /// Activates or stops every offer of one base plan that names `active`.
    ///
    /// Google creates an offer in the draft state, so an offer that nobody
    /// activates sells nothing. The batch carries one base plan, and the plan
    /// makes one step per base plan.
    func googleSubscriptionOfferStates(productId: String, basePlanId: String) async throws {
        let requests = manifest.googleOffers(productId: productId)
            .compactMap { offer -> [String: Any]? in
                guard let active = offer.active else { return nil }
                let payload: [String: Any] = [
                    "packageName": manifest.apps.google?.packageName ?? "",
                    "productId": productId, "basePlanId": basePlanId, "offerId": offer.id,
                ]
                return active
                    ? ["activateSubscriptionOfferRequest": payload]
                    : ["deactivateSubscriptionOfferRequest": payload]
            }
        guard !requests.isEmpty else { return }
        try await api.google(
            "POST",
            "\(monetizationBase)/subscriptions/\(StateReader.escape(productId))"
                + "/basePlans/\(StateReader.escape(basePlanId))/offers:batchUpdateStates",
            body: ["requests": requests])
    }

    /// The same switch for the offers of a one-time product. The app uses the
    /// product id as the purchase option id, the same as `googleProducts`.
    func googleOneTimeOfferStates(productId: String) async throws {
        let requests = manifest.googleOffers(productId: productId)
            .compactMap { offer -> [String: Any]? in
                guard let active = offer.active else { return nil }
                let payload: [String: Any] = [
                    "packageName": manifest.apps.google?.packageName ?? "",
                    "productId": productId, "purchaseOptionId": productId,
                    "offerId": offer.id,
                ]
                return active
                    ? ["activateOneTimeProductOfferRequest": payload]
                    : ["deactivateOneTimeProductOfferRequest": payload]
            }
        guard !requests.isEmpty else { return }
        try await api.google(
            "POST",
            "\(monetizationBase)/oneTimeProducts/\(StateReader.escape(productId))"
                + "/purchaseOptions/\(StateReader.escape(productId))/offers:batchUpdateStates",
            body: ["requests": requests])
    }

    // MARK: - The price migration

    /// This changes what an existing subscriber pays at the next renewal.
    /// It is the only Google call in the app that reaches a paying customer,
    /// so the manifest opts in per plan and the validator warns every time.
    func googleMigratePrices(productId: String, basePlanId: String) async throws {
        let regions = manifest.googleMigrationRegions(productId: productId)
        guard !regions.isEmpty else { return }
        try await api.google(
            "POST",
            "\(monetizationBase)/subscriptions/\(StateReader.escape(productId))"
                + "/basePlans:batchMigratePrices",
            body: ["requests": [[
                "packageName": manifest.apps.google?.packageName ?? "",
                "productId": productId,
                "basePlanId": basePlanId,
                "regionalPriceMigrations": regions.map {
                    ["regionCode": $0,
                     "priceIncreaseType": "PRICE_INCREASE_TYPE_OPT_OUT"]
                },
                "regionsVersion": ["version": "2022/02"],
            ]]])
    }

    // MARK: - The archive

    /// A subscription that the manifest dropped. Google keeps it and stops
    /// the sale, the same rule that the provider archive follows.
    func googleArchiveSubscription(productId: String) async throws {
        try await api.google(
            "POST",
            "\(monetizationBase)/subscriptions/\(StateReader.escape(productId)):archive",
            body: ["packageName": manifest.apps.google?.packageName ?? "",
                   "productId": productId])
    }

    static func googleTargeting(_ eligibility: Manifest.Offer.Eligibility) -> [String: Any] {
        switch eligibility {
        case .new:
            ["acquisitionRule": ["scope": ["specificSubscriptionInApp": ""]]]
        case .existing:
            ["upgradeRule": ["oncePerUser": false]]
        case .winBack:
            ["winBackRule": ["oncePerUser": true]]
        }
    }
}

public extension Manifest {
    /// Every offer that names one product id, from the purchases and from
    /// the subscription plans alike.
    func googleOffers(productId: String) -> [Offer] {
        if let purchase = (purchases ?? []).first(where: { $0.id == productId }) {
            return purchase.offers ?? []
        }
        for group in subscriptions ?? [] {
            if let plan = group.plans.first(where: { $0.id == productId }) {
                return plan.offers ?? []
            }
        }
        return []
    }

    /// The regions that a price migration touches. The plan price names them,
    /// and an empty result means the manifest opted out.
    func googleMigrationRegions(productId: String) -> [String] {
        for group in subscriptions ?? [] {
            guard let plan = group.plans.first(where: { $0.id == productId }),
                  plan.migrateExistingSubscribers == true else { continue }
            return [plan.price?.territory ?? "US"]
        }
        return []
    }

    /// The base plan id that a plan writes. Google needs a non-empty value.
    func googleBasePlanId(productId: String) -> String? {
        for group in subscriptions ?? [] {
            if let plan = group.plans.first(where: { $0.id == productId }) {
                return plan.basePlanId ?? "default"
            }
        }
        return nil
    }
}
