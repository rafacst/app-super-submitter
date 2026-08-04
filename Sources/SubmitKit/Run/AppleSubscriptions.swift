import Foundation

/// The App Store subscription catalog.
///
/// The plan counted the subscription plans before this file existed and the
/// runner wrote none of them, so a plan that said "write 5 purchases" wrote
/// two. Every write here is a draft, the same as every other apply step.
extension Runner {

    // MARK: - The groups and the subscriptions

    /// One pass over `manifest.subscriptions`. It reads the store first and
    /// matches by the natural key, because section 14 forbids a blind create.
    func appleSubscriptions() async throws {
        guard !(manifest.subscriptions ?? []).isEmpty else { return }
        var groupIDs = try await appleSubscriptionGroupIDs()

        for group in manifest.subscriptions ?? [] {
            try Task.checkCancellation()
            let groupID: String
            if let existing = groupIDs[group.groupId] {
                groupID = existing
            } else {
                let created = JSON(data: try await api.apple(
                    "POST", "/v1/subscriptionGroups", body: [
                        "data": [
                            "type": "subscriptionGroups",
                            "attributes": ["referenceName": group.groupName ?? group.groupId],
                            "relationships": ["app": [
                                "data": ["type": "apps", "id": appleAppID]]],
                        ],
                    ]).data)
                guard let id = created["data"]["id"].string else {
                    throw RunError.uploadFailed("The subscription group \(group.groupId) failed.")
                }
                groupID = id
                groupIDs[group.groupId] = id
            }

            try await appleSubscriptionGroupLocalizations(group, groupID: groupID)

            var subscriptionIDs = try await appleSubscriptionIDs(groupID: groupID)
            for plan in group.plans {
                try Task.checkCancellation()
                let subscriptionID = try await appleEnsureSubscription(
                    plan, group: group, groupID: groupID, known: subscriptionIDs)
                subscriptionIDs[plan.id] = subscriptionID
                appleSubscriptionIDsByProduct[plan.id] = subscriptionID
                try await appleSubscriptionLocalizations(plan, subscriptionID: subscriptionID)
                try await appleSubscriptionPrice(plan, subscriptionID: subscriptionID)
                try await appleSubscriptionAvailability(plan, subscriptionID: subscriptionID)
                try await appleSubscriptionReviewScreenshot(plan,
                                                            subscriptionID: subscriptionID)
            }
        }
    }

    private func appleSubscriptionGroupIDs() async throws -> [String: String] {
        let response = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appleAppID)/subscriptionGroups?limit=200").data)
        var result: [String: String] = [:]
        for item in response["data"].array {
            guard let name = item["attributes"]["referenceName"].string,
                  let id = item["id"].string else { continue }
            result[name] = id
        }
        return result
    }

    private func appleSubscriptionIDs(groupID: String) async throws -> [String: String] {
        let response = JSON(data: try await api.apple(
            "GET", "/v1/subscriptionGroups/\(groupID)/subscriptions?limit=200").data)
        var result: [String: String] = [:]
        for item in response["data"].array {
            guard let productID = item["attributes"]["productId"].string,
                  let id = item["id"].string else { continue }
            result[productID] = id
        }
        return result
    }

    private func appleEnsureSubscription(_ plan: Manifest.SubscriptionGroup.Plan,
                                         group: Manifest.SubscriptionGroup,
                                         groupID: String,
                                         known: [String: String]) async throws -> String {
        let period = AppleDurations.apiPeriod(for: plan.duration)
        if let id = known[plan.id] {
            var attributes: [String: Any] = [
                "name": plan.locales?.values.first?.name ?? group.groupName ?? plan.id,
            ]
            if let period { attributes["subscriptionPeriod"] = period }
            try await api.apple("PATCH", "/v1/subscriptions/\(id)", body: [
                "data": ["type": "subscriptions", "id": id, "attributes": attributes],
            ])
            return id
        }

        var attributes: [String: Any] = [
            "name": plan.locales?.values.first?.name ?? group.groupName ?? plan.id,
            "productId": plan.id,
            "familySharable": false,
        ]
        if let period { attributes["subscriptionPeriod"] = period }
        let created = JSON(data: try await api.apple("POST", "/v1/subscriptions", body: [
            "data": [
                "type": "subscriptions",
                "attributes": attributes,
                "relationships": ["group": [
                    "data": ["type": "subscriptionGroups", "id": groupID]]],
            ],
        ]).data)
        guard let id = created["data"]["id"].string else {
            throw RunError.uploadFailed("The subscription \(plan.id) failed.")
        }
        return id
    }

    private func appleSubscriptionGroupLocalizations(
        _ group: Manifest.SubscriptionGroup, groupID: String) async throws {
        guard let locales = group.locales, !locales.isEmpty else { return }
        let existing = JSON(data: try await api.apple(
            "GET",
            "/v1/subscriptionGroups/\(groupID)/subscriptionGroupLocalizations?limit=200").data)
        var byLocale: [String: String] = [:]
        for item in existing["data"].array {
            guard let locale = item["attributes"]["locale"].string,
                  let id = item["id"].string else { continue }
            byLocale[locale] = id
        }
        try await appleDropLocalizations(existing, keeping: Set(locales.keys),
                                         path: "/v1/subscriptionGroupLocalizations")

        for (locale, text) in locales.sorted(by: { $0.key < $1.key }) {
            let name = text.name ?? group.groupName ?? group.groupId
            if let id = byLocale[locale] {
                try await api.apple("PATCH", "/v1/subscriptionGroupLocalizations/\(id)", body: [
                    "data": ["type": "subscriptionGroupLocalizations", "id": id,
                             "attributes": ["name": name]],
                ])
                continue
            }
            try await api.apple("POST", "/v1/subscriptionGroupLocalizations", body: [
                "data": [
                    "type": "subscriptionGroupLocalizations",
                    "attributes": ["name": name, "locale": locale],
                    "relationships": ["subscriptionGroup": [
                        "data": ["type": "subscriptionGroups", "id": groupID]]],
                ],
            ])
        }
    }

    private func appleSubscriptionLocalizations(_ plan: Manifest.SubscriptionGroup.Plan,
                                                subscriptionID: String) async throws {
        guard let locales = plan.locales, !locales.isEmpty else { return }
        let existing = JSON(data: try await api.apple(
            "GET",
            "/v1/subscriptions/\(subscriptionID)/subscriptionLocalizations?limit=200").data)
        var byLocale: [String: String] = [:]
        for item in existing["data"].array {
            guard let locale = item["attributes"]["locale"].string,
                  let id = item["id"].string else { continue }
            byLocale[locale] = id
        }
        try await appleDropLocalizations(existing, keeping: Set(locales.keys),
                                         path: "/v1/subscriptionLocalizations")

        for (locale, text) in locales.sorted(by: { $0.key < $1.key }) {
            var attributes: [String: Any] = ["name": text.name ?? plan.id]
            put(&attributes, "description", text.description ?? "")
            if let id = byLocale[locale] {
                try await api.apple("PATCH", "/v1/subscriptionLocalizations/\(id)", body: [
                    "data": ["type": "subscriptionLocalizations", "id": id,
                             "attributes": attributes],
                ])
                continue
            }
            attributes["locale"] = locale
            try await api.apple("POST", "/v1/subscriptionLocalizations", body: [
                "data": [
                    "type": "subscriptionLocalizations",
                    "attributes": attributes,
                    "relationships": ["subscription": [
                        "data": ["type": "subscriptions", "id": subscriptionID]]],
                ],
            ])
        }
    }

    /// Apple sells at a price point, never at the amount you asked for. This
    /// resolves the nearest point and writes that, the same rule that section
    /// 6.7 states for the app price.
    private func appleSubscriptionPrice(_ plan: Manifest.SubscriptionGroup.Plan,
                                        subscriptionID: String) async throws {
        guard let price = plan.price else { return }
        let territory = price.territory ?? "USA"
        let points = JSON(data: try await api.apple(
            "GET",
            "/v1/subscriptions/\(subscriptionID)/pricePoints"
                + "?filter%5Bterritory%5D=\(territory)&limit=200").data)
        guard let point = Self.nearestPricePoint(points, to: price.amount) else { return }

        // A subscription price is a schedule, so a second apply used to stack
        // a second row on top of the first. Apple keeps the manual price it
        // holds until something removes it, so the stale rows go first.
        if let held = try? await api.apple(
            "GET", "/v1/subscriptions/\(subscriptionID)/prices"
                + "?include=subscriptionPricePoint&limit=200") {
            for item in JSON(data: held.data)["data"].array {
                guard let id = item["id"].string else { continue }
                let heldPoint = item["relationships"]["subscriptionPricePoint"]["data"]["id"].string
                guard heldPoint != point else { return }
                try await api.apple("DELETE", "/v1/subscriptionPrices/\(id)")
            }
        }

        try await api.apple("POST", "/v1/subscriptionPrices", body: [
            "data": [
                "type": "subscriptionPrices",
                "attributes": ["preserveCurrentPrice": true],
                "relationships": [
                    "subscription": ["data": ["type": "subscriptions", "id": subscriptionID]],
                    "subscriptionPricePoint": [
                        "data": ["type": "subscriptionPricePoints", "id": point]],
                ],
            ],
        ])
    }

    /// The territories that sell this subscription.
    ///
    /// A one-time purchase already had this through
    /// `inAppPurchaseAvailabilities`. Apple gives a subscription its own
    /// resource with the same shape, so the two halves now match.
    private func appleSubscriptionAvailability(_ plan: Manifest.SubscriptionGroup.Plan,
                                               subscriptionID: String) async throws {
        guard let territories = plan.availableTerritories, !territories.isEmpty else { return }
        try await api.apple("POST", "/v1/subscriptionAvailabilities", body: [
            "data": [
                "type": "subscriptionAvailabilities",
                "attributes": ["availableInNewTerritories": false],
                "relationships": [
                    "subscription": ["data": ["type": "subscriptions", "id": subscriptionID]],
                    "availableTerritories": ["data": territories.map {
                        ["type": "territories", "id": $0]
                    }],
                ],
            ],
        ])
    }

    /// The screenshot the reviewer sees beside the subscription.
    ///
    /// The three calls are the reservation, the bytes, and the commit, exactly
    /// as the one-time purchase screenshot does it in `AppleApply`.
    private func appleSubscriptionReviewScreenshot(
        _ plan: Manifest.SubscriptionGroup.Plan, subscriptionID: String) async throws {
        guard let path = plan.reviewScreenshot, let url = resolve(path) else { return }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let reservation = JSON(data: try await api.apple(
            "POST", "/v1/subscriptionAppStoreReviewScreenshots", body: [
                "data": [
                    "type": "subscriptionAppStoreReviewScreenshots",
                    "attributes": ["fileName": url.lastPathComponent,
                                   "fileSize": data.count],
                    "relationships": ["subscription": [
                        "data": ["type": "subscriptions", "id": subscriptionID]]],
                ],
            ]).data)
        guard let id = reservation["data"]["id"].string else { return }
        try await executeUploadOperations(
            reservation["data"]["attributes"]["uploadOperations"], data: data)
        try await api.apple("PATCH",
            "/v1/subscriptionAppStoreReviewScreenshots/\(id)", body: [
                "data": ["type": "subscriptionAppStoreReviewScreenshots", "id": id,
                         "attributes": ["uploaded": true]],
            ])
    }

    static func nearestPricePoint(_ response: JSON, to amount: Decimal) -> String? {
        response["data"].array
            .compactMap { item -> (String, Decimal)? in
                guard let id = item["id"].string,
                      let text = item["attributes"]["customerPrice"].string,
                      let value = Decimal(string: text) else { return nil }
                return (id, value)
            }
            .min { abs($0.1 - amount) < abs($1.1 - amount) }?.0
    }

    // MARK: - The offers

    /// The introductory offer, the promotional offer, and the offer code.
    /// Each one attaches to a subscription that `appleSubscriptions` created,
    /// so this step always follows it.
    func appleSubscriptionOffers() async throws {
        for group in manifest.subscriptions ?? [] {
            for plan in group.plans {
                guard let subscriptionID = appleSubscriptionIDsByProduct[plan.id] else { continue }
                let offers = plan.offers ?? []
                // The removal runs even for a plan that names no offer, which
                // is exactly the case where a developer dropped the last one.
                let held = try await appleDropOffers(plan, subscriptionID: subscriptionID)
                guard !offers.isEmpty else { continue }
                let territory = plan.price?.territory ?? "USA"
                let point = try await appleFirstPricePoint(subscriptionID: subscriptionID,
                                                           territory: territory)

                for offer in offers where !held.contains(offer.id) {
                    try Task.checkCancellation()
                    switch offer.kind {
                    case .freeTrial, .introPrice:
                        try await appleIntroductoryOffer(offer, subscriptionID: subscriptionID,
                                                         territory: territory, pricePoint: point)
                    case .offerCode:
                        try await appleOfferCode(offer, subscriptionID: subscriptionID)
                    case .promotional:
                        try await applePromotionalOffer(offer, subscriptionID: subscriptionID)
                    case .winBack:
                        try await appleWinBackOffer(offer, subscriptionID: subscriptionID,
                                                    pricePoint: point)
                    }
                }
            }
        }
    }

    /// Removes the offers the manifest dropped, and reports the ones it keeps.
    ///
    /// Two problems, one pass. Without the removal, a dropped offer sells
    /// forever. Without the report, every apply creates the same offer again,
    /// because the three create calls take no natural key and Apple never
    /// refuses a duplicate.
    ///
    /// An introductory offer carries no name, so Apple holds one per territory
    /// and the manifest owns it entirely. It goes when the plan names no free
    /// trial and no introductory price, and it stays otherwise.
    private func appleDropOffers(_ plan: Manifest.SubscriptionGroup.Plan,
                                 subscriptionID: String) async throws -> Set<String> {
        let offers = plan.offers ?? []
        var kept: Set<String> = []

        let named: [(collection: String, path: String, key: String)] = [
            ("promotionalOffers", "/v1/subscriptionPromotionalOffers", "name"),
            ("winBackOffers", "/v1/winBackOffers", "referenceName"),
        ]
        for entry in named {
            let wanted = Set(offers.filter {
                entry.collection == "winBackOffers" ? $0.kind == .winBack : $0.kind == .promotional
            }.map(\.id))
            guard let response = try? await api.apple(
                "GET", "/v1/subscriptions/\(subscriptionID)/\(entry.collection)?limit=200")
            else { continue }
            for item in JSON(data: response.data)["data"].array {
                guard let id = item["id"].string else { continue }
                let name = item["attributes"][entry.key].string ?? ""
                if wanted.contains(name) {
                    kept.insert(name)
                } else {
                    try await api.apple("DELETE", "\(entry.path)/\(id)")
                }
            }
        }

        let wantsIntro = offers.contains { $0.kind == .freeTrial || $0.kind == .introPrice }
        if let response = try? await api.apple(
            "GET", "/v1/subscriptions/\(subscriptionID)/introductoryOffers?limit=200") {
            for item in JSON(data: response.data)["data"].array {
                guard let id = item["id"].string else { continue }
                if wantsIntro {
                    // Apple takes one per territory, so the held one is the
                    // manifest's own. Keep it and skip the create.
                    offers.filter { $0.kind == .freeTrial || $0.kind == .introPrice }
                        .forEach { kept.insert($0.id) }
                } else {
                    try await api.apple("DELETE", "/v1/subscriptionIntroductoryOffers/\(id)")
                }
            }
        }
        return kept
    }

    private func appleFirstPricePoint(subscriptionID: String,
                                      territory: String) async throws -> String? {
        let points = JSON(data: try await api.apple(
            "GET",
            "/v1/subscriptions/\(subscriptionID)/pricePoints"
                + "?filter%5Bterritory%5D=\(territory)&limit=200").data)
        return points["data"].array.first?["id"].string
    }

    private func appleIntroductoryOffer(_ offer: Manifest.Offer, subscriptionID: String,
                                        territory: String,
                                        pricePoint: String?) async throws {
        var attributes: [String: Any] = [
            "startDate": NSNull(),
            "endDate": NSNull(),
            "duration": AppleDurations.offerDuration(for: offer.duration ?? "P1M") ?? "ONE_MONTH",
            "offerMode": offer.kind == .freeTrial ? "FREE_TRIAL" : "PAY_UP_FRONT",
            "numberOfPeriods": offer.periods ?? 1,
        ]
        if offer.kind == .freeTrial { attributes["offerMode"] = "FREE_TRIAL" }

        var relationships: [String: Any] = [
            "subscription": ["data": ["type": "subscriptions", "id": subscriptionID]],
            "territory": ["data": ["type": "territories", "id": territory]],
        ]
        // A free trial takes no price point. Every other mode needs one.
        if offer.kind != .freeTrial, let pricePoint {
            relationships["subscriptionPricePoint"] = [
                "data": ["type": "subscriptionPricePoints", "id": pricePoint]]
        }

        try await api.apple("POST", "/v1/subscriptionIntroductoryOffers", body: [
            "data": [
                "type": "subscriptionIntroductoryOffers",
                "attributes": attributes,
                "relationships": relationships,
            ],
        ])
    }

    private func appleOfferCode(_ offer: Manifest.Offer, subscriptionID: String) async throws {
        let existing = JSON(data: try await api.apple(
            "GET", "/v1/subscriptions/\(subscriptionID)/offerCodes?limit=200").data)
        if existing["data"].array.contains(where: {
            $0["attributes"]["name"].string == offer.id
        }) { return }

        try await api.apple("POST", "/v1/subscriptionOfferCodes", body: [
            "data": [
                "type": "subscriptionOfferCodes",
                "attributes": [
                    "name": offer.id,
                    "customerEligibilities": [Self.appleEligibility(offer.eligibility)],
                    "offerEligibility": "STACK_WITH_INTRO_OFFERS",
                    "duration": AppleDurations.offerDuration(for: offer.duration ?? "P1M")
                        ?? "ONE_MONTH",
                    "offerMode": offer.kind == .freeTrial ? "FREE_TRIAL" : "PAY_UP_FRONT",
                    "numberOfPeriods": offer.periods ?? 1,
                ],
                "relationships": ["subscription": [
                    "data": ["type": "subscriptions", "id": subscriptionID]]],
            ],
        ])
    }

    private func applePromotionalOffer(_ offer: Manifest.Offer,
                                       subscriptionID: String) async throws {
        try await api.apple("POST", "/v1/subscriptionPromotionalOffers", body: [
            "data": [
                "type": "subscriptionPromotionalOffers",
                "attributes": [
                    "name": offer.id,
                    "offerCode": offer.id,
                    "duration": AppleDurations.offerDuration(for: offer.duration ?? "P1M")
                        ?? "ONE_MONTH",
                    "offerMode": offer.price == nil ? "FREE_TRIAL" : "PAY_UP_FRONT",
                    "numberOfPeriods": offer.periods ?? 1,
                ],
                "relationships": ["subscription": [
                    "data": ["type": "subscriptions", "id": subscriptionID]]],
            ],
        ])
    }

    private func appleWinBackOffer(_ offer: Manifest.Offer, subscriptionID: String,
                                   pricePoint: String?) async throws {
        var relationships: [String: Any] = [
            "subscription": ["data": ["type": "subscriptions", "id": subscriptionID]],
        ]
        if let pricePoint {
            relationships["subscriptionPricePoint"] = [
                "data": ["type": "subscriptionPricePoints", "id": pricePoint]]
        }
        try await api.apple("POST", "/v1/winBackOffers", body: [
            "data": [
                "type": "winBackOffers",
                "attributes": [
                    "referenceName": offer.id,
                    "offerId": offer.id,
                    "duration": AppleDurations.offerDuration(for: offer.duration ?? "P1M")
                        ?? "ONE_MONTH",
                    "offerMode": offer.price == nil ? "FREE_TRIAL" : "PAY_UP_FRONT",
                    "numberOfPeriods": offer.periods ?? 1,
                ],
                "relationships": relationships,
            ],
        ])
    }

    static func appleEligibility(_ eligibility: Manifest.Offer.Eligibility?) -> String {
        switch eligibility {
        case .existing: "EXISTING_SUBSCRIBERS"
        case .winBack: "EXPIRED_SUBSCRIBERS"
        case .new, nil: "NEW"
        }
    }

    // MARK: - The grace period

    /// Apple sets one billing grace period for the whole app, not per group.
    /// The manifest carries it on a group, so the first group that names one
    /// wins and the validator reports a disagreement.
    func appleGracePeriod() async throws {
        guard let days = (manifest.subscriptions ?? []).compactMap(\.gracePeriodDays).first
        else { return }
        let current = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appleAppID)/subscriptionGracePeriod").data)
        guard let id = current["data"]["id"].string else { return }
        try await api.apple("PATCH", "/v1/subscriptionGracePeriods/\(id)", body: [
            "data": [
                "type": "subscriptionGracePeriods",
                "id": id,
                "attributes": [
                    "optIn": true,
                    "duration": AppleDurations.gracePeriod(days: days),
                    "renewalType": "ALL_RENEWALS",
                ],
            ],
        ])
    }
}
