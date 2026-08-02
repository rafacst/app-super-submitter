import Foundation

/// Spec section 7.8. This step runs last, after both stores hold the products.
///
/// The provider is a mirror. The stores are the source of truth, and the app
/// never calls an endpoint that would make the provider a second writer to a
/// store.
extension Runner {

    private var provider: Manifest.Provider { manifest.monetization?.provider ?? .none }
    private var revenueCatBase: String {
        "/v2/projects/\(manifest.monetization?.revenuecat?.projectId ?? "")"
    }
    private var adaptyAppID: String { manifest.monetization?.adapty?.appId ?? "" }

    func providerProduct(storeProductId: String, appId: String) async throws {
        switch provider {
        case .none:
            return
        case .revenuecat:
            // Re-read by the natural key first. A blind create duplicates.
            let existing = JSON(data: try await api.revenueCat(
                "GET", "\(revenueCatBase)/products?app_id=\(appId)&limit=100").data)
            if let match = existing["items"].array.first(where: {
                $0["store_identifier"].string == storeProductId
            }) {
                guard let id = match["id"].string else { return }
                try await api.revenueCat("POST", "\(revenueCatBase)/products/\(id)", body: [
                    "display_name": displayName(for: storeProductId),
                ])
                return
            }
            let created = JSON(data: try await api.revenueCat(
                "POST", "\(revenueCatBase)/products", body: [
                    "store_identifier": storeProductId,
                    "app_id": appId,
                    "type": isSubscription(storeProductId) ? "subscription" : "one_time",
                    "display_name": displayName(for: storeProductId),
                ]).data)
            if let id = created["id"].string {
                createdProviderObjects.append((kind: "product", id: id))
            }
        case .adapty:
            let cli = AdaptyCLIClient()
            let title = displayName(for: storeProductId)
            var arguments = ["products", "create", "--app", adaptyAppID, "--title", title]
            if manifest.apps.apple != nil {
                arguments += ["--ios-product-id", storeProductId]
            }
            if manifest.apps.google != nil {
                arguments += ["--android-product-id", storeProductId]
                if let basePlan = basePlanId(for: storeProductId) {
                    arguments += ["--android-base-plan-id", basePlan]
                }
            }
            if let duration = duration(for: storeProductId),
               let period = AdaptyPeriods.period(for: duration) {
                arguments += ["--period", period]
            }
            if let entitlement = entitlement(for: storeProductId) {
                arguments += ["--access-level-id", entitlement]
            }
            let created = try cli.json(arguments)
            if let id = created["id"].string ?? created["data"]["id"].string {
                createdProviderObjects.append((kind: "product", id: id))
            }
        }
    }

    func providerEntitlement(_ key: String) async throws {
        let name = (manifest.entitlements ?? []).first { $0.key == key }?.name ?? key
        switch provider {
        case .none:
            return
        case .revenuecat:
            let existing = JSON(data: try await api.revenueCat(
                "GET", "\(revenueCatBase)/entitlements?limit=100").data)
            guard !existing["items"].array.contains(where: { $0["lookup_key"].string == key })
            else { return }
            let created = JSON(data: try await api.revenueCat(
                "POST", "\(revenueCatBase)/entitlements",
                body: ["lookup_key": key, "display_name": name]).data)
            if let id = created["id"].string {
                createdProviderObjects.append((kind: "entitlement", id: id))
            }
        case .adapty:
            let cli = AdaptyCLIClient()
            let created = try cli.json(["access-levels", "create", "--app", adaptyAppID,
                                        "--sdk-id", key, "--title", name])
            if let id = created["id"].string ?? created["data"]["id"].string {
                createdProviderObjects.append((kind: "access-level", id: id))
            }
        }
    }

    func providerAttach(entitlement: String, products: [String]) async throws {
        switch provider {
        case .none, .adapty:
            // Adapty attaches on the product itself, with `--access-level-id`.
            return
        case .revenuecat:
            let entitlements = JSON(data: try await api.revenueCat(
                "GET", "\(revenueCatBase)/entitlements?limit=100").data)
            guard let id = entitlements["items"].array.first(where: {
                $0["lookup_key"].string == entitlement
            })?["id"].string else { return }
            let known = JSON(data: try await api.revenueCat(
                "GET", "\(revenueCatBase)/products?limit=200").data)
            var ids: [String] = []
            for product in known["items"].array {
                guard let storeID = product["store_identifier"].string,
                      products.contains(storeID), let productID = product["id"].string else {
                    continue
                }
                ids.append(productID)
            }
            guard !ids.isEmpty else { return }
            try await api.revenueCat(
                "POST", "\(revenueCatBase)/entitlements/\(id)/actions/attach_products",
                body: ["product_ids": ids])
        }
    }

    func providerOffering(_ key: String) async throws {
        guard let offering = (manifest.offerings ?? []).first(where: { $0.key == key }) else {
            return
        }
        switch provider {
        case .none:
            return
        case .revenuecat:
            let existing = JSON(data: try await api.revenueCat(
                "GET", "\(revenueCatBase)/offerings?limit=100").data)
            var offeringID = existing["items"].array.first {
                $0["lookup_key"].string == key
            }?["id"].string
            if offeringID == nil {
                let created = JSON(data: try await api.revenueCat(
                    "POST", "\(revenueCatBase)/offerings", body: [
                        "lookup_key": key,
                        "display_name": offering.name ?? key,
                        "is_current": offering.isCurrent ?? false,
                    ]).data)
                offeringID = created["id"].string
                if let id = offeringID {
                    createdProviderObjects.append((kind: "offering", id: id))
                }
            }
            guard let offeringID else { return }

            // The package order is the manifest list order. Spec 7.8.1 step 8.
            for (position, productID) in (offering.products ?? []).enumerated() {
                let packageKey = packageKey(for: productID) ?? productID
                let created = JSON(data: try await api.revenueCat(
                    "POST", "\(revenueCatBase)/offerings/\(offeringID)/packages", body: [
                        "lookup_key": packageKey,
                        "display_name": packageKey,
                        "position": position + 1,
                    ]).data)
                guard let packageID = created["id"].string else { continue }
                let products = JSON(data: try await api.revenueCat(
                    "GET", "\(revenueCatBase)/products?limit=200").data)
                let ids = products["items"].array
                    .filter { $0["store_identifier"].string == productID }
                    .compactMap { $0["id"].string }
                guard !ids.isEmpty else { continue }
                try await api.revenueCat(
                    "POST", "\(revenueCatBase)/packages/\(packageID)/actions/attach_products",
                    body: ["products": ids.map { ["product_id": $0] }])
            }
        case .adapty:
            let cli = AdaptyCLIClient()
            let catalog = try cli.catalog(appID: adaptyAppID)
            let productIDs = (offering.products ?? []).compactMap { catalog.productIds[$0] }
            var paywallID = catalog.paywalls[offering.name ?? key]
            if paywallID == nil {
                var arguments = ["paywalls", "create", "--app", adaptyAppID,
                                 "--title", offering.name ?? key]
                for id in productIDs { arguments += ["--product-id", id] }
                let created = try cli.json(arguments)
                paywallID = created["id"].string ?? created["data"]["id"].string
                if let id = paywallID { createdProviderObjects.append((kind: "paywall", id: id)) }
            }
            guard let paywallID else { return }

            // The app always passes `--audiences`. `--paywall-id` drops every
            // segment-specific audience. Spec 7.8.2, rule 1.
            let audiences = [["paywall_id": paywallID, "segment_ids": [],
                              "priority": 0]] as [[String: Any]]
            let payload = String(decoding: (try? JSONSerialization.data(
                withJSONObject: audiences)) ?? Data("[]".utf8), as: UTF8.self)
            if catalog.placements.contains(key) {
                _ = try cli.json(["placements", "update", "--app", adaptyAppID,
                                  "--developer-id", key, "--audiences", payload])
            } else {
                let created = try cli.json(["placements", "create", "--app", adaptyAppID,
                                            "--title", offering.name ?? key,
                                            "--developer-id", key, "--audiences", payload])
                if let id = created["id"].string ?? created["data"]["id"].string {
                    createdProviderObjects.append((kind: "placement", id: id))
                }
            }
        }
    }

    /// The app archives, or it deactivates. The app does not delete. A
    /// `DELETE` on a live catalog breaks the running app. Spec section 8,
    /// rule 6.
    func archiveProviderObject(kind: String, id: String) async throws {
        switch provider {
        case .none:
            return
        case .revenuecat:
            let collection = kind == "offering" ? "offerings"
                : kind == "entitlement" ? "entitlements" : "products"
            try await api.revenueCat(
                "POST", "\(revenueCatBase)/\(collection)/\(id)/actions/archive")
        case .adapty:
            let cli = AdaptyCLIClient()
            _ = try? cli.json([kind == "offering" ? "placements" : "products",
                               "archive", "--app", adaptyAppID, "--id", id])
        }
    }

    // MARK: - The manifest lookups

    private func displayName(for productID: String) -> String {
        if let purchase = (manifest.purchases ?? []).first(where: { $0.id == productID }) {
            return purchase.name ?? productID
        }
        for group in manifest.subscriptions ?? [] {
            if group.plans.contains(where: { $0.id == productID }) {
                return group.groupName ?? productID
            }
        }
        return productID
    }

    private func isSubscription(_ productID: String) -> Bool {
        (manifest.subscriptions ?? []).contains { $0.plans.contains { $0.id == productID } }
    }

    private func duration(for productID: String) -> String? {
        (manifest.subscriptions ?? []).flatMap(\.plans).first { $0.id == productID }?.duration
    }

    private func basePlanId(for productID: String) -> String? {
        (manifest.subscriptions ?? []).flatMap(\.plans).first { $0.id == productID }?.basePlanId
    }

    private func packageKey(for productID: String) -> String? {
        (manifest.subscriptions ?? []).flatMap(\.plans).first { $0.id == productID }?.packageKey
    }

    /// Adapty takes one access level, so the app uses the first and says so.
    private func entitlement(for productID: String) -> String? {
        manifest.entitlementsByProduct[productID]?.first
    }
}
