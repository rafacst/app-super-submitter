import Foundation

/// Reads an app that already lives in a store, so a new workspace opens with
/// what the store holds instead of an empty form.
///
/// It calls through `StoreAPI`, the same signed client the plan uses. The
/// import and the plan therefore pick the same app info and the same version,
/// and the developer never edits one version while the plan reads another.
///
/// Every read after the listing is optional. A store that answers 404 for one
/// resource costs that one block, never the whole import, and the name of the
/// resource reaches `failures` so the developer knows what to fill by hand.
public struct StoreImportReader: Sendable {
    private let api: StoreAPI

    public init(credentials: StoreCredentials, session: URLSession = .shared) {
        api = StoreAPI(credentials: credentials, record: { _ in }, session: session)
    }

    // MARK: - The App Store

    public func apple(appID: String) async throws -> ImportedStoreListing {
        var result = ImportedStoreListing()
        var failures: [String] = []

        let app = JSON(data: try await api.apple("GET", "/v1/apps/\(appID)").data)
        result.defaultLocale = app["data"]["attributes"]["primaryLocale"].string
        result.bundleID = app["data"]["attributes"]["bundleId"].string

        // The same choice the plan makes. `limit=1` would take whichever record
        // App Store Connect happened to return first, and that is usually not
        // the version the developer is about to edit.
        let infos = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appID)/appInfos?limit=200").data)
        let info = infos["data"].array.first {
            $0["attributes"]["appStoreState"].string == "PREPARE_FOR_SUBMISSION"
        } ?? infos["data"].array.first
        if let info, let infoID = info["id"].string {
            result.review.applePrimaryCategory =
                info["relationships"]["primaryCategory"]["data"]["id"].string
            result.review.appleSecondaryCategory =
                info["relationships"]["secondaryCategory"]["data"]["id"].string

            let localizations = JSON(data: try await api.apple(
                "GET", "/v1/appInfos/\(infoID)/appInfoLocalizations?limit=200").data)
            for item in localizations["data"].array {
                let attributes = item["attributes"]
                guard let code = attributes["locale"].string else { continue }
                var locale = result.locales[code] ?? .init()
                locale.name = attributes["name"].string
                locale.subtitle = attributes["subtitle"].string
                locale.privacyPolicyURL = attributes["privacyPolicyUrl"].string
                locale.privacyPolicyText = attributes["privacyPolicyText"].string
                locale.privacyChoicesURL = attributes["privacyChoicesUrl"].string
                result.locales[code] = locale
            }
        }

        let versions = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appID)/appStoreVersions?limit=200").data)
        let editable = Set(["PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED",
                            "REJECTED", "METADATA_REJECTED"])
        let version = versions["data"].array.first {
            let state = $0["attributes"]["appVersionState"].string
                ?? $0["attributes"]["appStoreState"].string ?? ""
            return editable.contains(state)
        } ?? versions["data"].array.first
        if let version, let versionID = version["id"].string {
            result.versionName = version["attributes"]["versionString"].string
            result.appleReleaseType = version["attributes"]["releaseType"].string

            let localizations = JSON(data: try await api.apple(
                "GET",
                "/v1/appStoreVersions/\(versionID)/appStoreVersionLocalizations?limit=200").data)
            var assets: [ImportedStoreAsset] = []
            for item in localizations["data"].array {
                let attributes = item["attributes"]
                guard let code = attributes["locale"].string,
                      let localizationID = item["id"].string else { continue }
                var locale = result.locales[code] ?? .init()
                locale.description = attributes["description"].string
                locale.whatsNew = attributes["whatsNew"].string
                locale.keywords = attributes["keywords"].string
                locale.promotionalText = attributes["promotionalText"].string
                locale.supportURL = attributes["supportUrl"].string
                locale.marketingURL = attributes["marketingUrl"].string
                result.locales[code] = locale

                assets += await attempt("App Store screenshots for \(code)", &failures) {
                    try await appleScreenshots(localizationID: localizationID, locale: code)
                } ?? []
                assets += await attempt("App Store previews for \(code)", &failures) {
                    try await applePreviews(localizationID: localizationID, locale: code)
                } ?? []
            }
            result.assets = assets

            if let detail = await attempt("App Store review details", &failures, {
                JSON(data: try await api.apple(
                    "GET", "/v1/appStoreVersions/\(versionID)/appStoreReviewDetail").data)
            }) {
                let attributes = detail["data"]["attributes"]
                result.review.contactFirstName = attributes["contactFirstName"].string
                result.review.contactLastName = attributes["contactLastName"].string
                result.review.contactEmail = attributes["contactEmail"].string
                result.review.contactPhone = attributes["contactPhone"].string
                result.review.demoAccountRequired = attributes["demoAccountRequired"].bool
                result.review.notes = attributes["notes"].string
            }

            if let phased = await attempt("App Store phased release", &failures, {
                JSON(data: try await api.apple(
                    "GET",
                    "/v1/appStoreVersions/\(versionID)/appStoreVersionPhasedRelease").data)
            }) {
                result.applePhasedRelease = phased["data"]["id"].exists
            }
        }

        if let builds = await attempt("App Store encryption declaration", &failures, {
            JSON(data: try await api.apple(
                "GET", "/v1/builds?filter%5Bapp%5D=\(appID)&limit=1").data)
        }) {
            result.review.usesNonExemptEncryption =
                builds["data"][0]["attributes"]["usesNonExemptEncryption"].bool
        }

        if let purchases = await attempt("App Store in-app purchases", &failures, {
            JSON(data: try await api.apple(
                "GET", "/v1/apps/\(appID)/inAppPurchasesV2?limit=200").data)
        }) {
            result.purchases = purchases["data"].array.compactMap(Self.applePurchase)
        }

        if let groups = await attempt("App Store subscriptions", &failures, {
            JSON(data: try await api.apple(
                "GET",
                "/v1/apps/\(appID)/subscriptionGroups?include=subscriptions&limit=200").data)
        }) {
            result.subscriptions = Self.appleSubscriptionGroups(groups)
        }

        result.failures = failures
        return result
    }

    // MARK: - Google Play

    public func google(packageName: String) async throws -> ImportedStoreListing {
        var result = ImportedStoreListing()
        var failures: [String] = []
        let base = "/androidpublisher/v3/applications/\(StateReader.escape(packageName))"
        let edit = JSON(data: try await api.google("POST", "\(base)/edits", body: [:]).data)
        guard let editID = edit["id"].string else { throw ConnectionError.invalidResponse }
        let editBase = "\(base)/edits/\(editID)"

        do {
            let details = JSON(data: try await api.google("GET", "\(editBase)/details").data)
            result.defaultLocale = details["defaultLanguage"].string
            result.review.contactEmail = details["contactEmail"].string
            result.review.contactPhone = details["contactPhone"].string
            result.googleContactWebsite = details["contactWebsite"].string

            let listings = JSON(data: try await api.google("GET", "\(editBase)/listings").data)
            var assets: [ImportedStoreAsset] = []
            for item in listings["listings"].array {
                guard let language = item["language"].string else { continue }
                var locale = ImportedStoreListing.Locale()
                locale.name = item["title"].string
                locale.subtitle = item["shortDescription"].string
                locale.description = item["fullDescription"].string
                locale.video = item["video"].string
                result.locales[language] = locale

                for kind in ["phoneScreenshots", "sevenInchScreenshots", "tenInchScreenshots",
                             "tvScreenshots", "wearScreenshots", "icon", "featureGraphic"] {
                    assets += await attempt("Google Play \(kind) for \(language)", &failures) {
                        let images = JSON(data: try await api.google(
                            "GET", "\(editBase)/listings/\(language)/\(kind)").data)
                        return images["images"].array.enumerated().compactMap { index, image in
                            guard let text = image["url"].string,
                                  let url = URL(string: text) else { return nil }
                            let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
                            return ImportedStoreAsset(
                                locale: language, kind: kind, url: url,
                                fileName: "\(kind)-\(index + 1).\(ext)")
                        }
                    } ?? []
                }
            }
            result.assets = assets

            if let tracks = await attempt("Google Play tracks", &failures, {
                JSON(data: try await api.google("GET", "\(editBase)/tracks").data)
            }) {
                for item in tracks["tracks"].array {
                    guard let name = item["track"].string,
                          let release = item["releases"].array.first,
                          !release["versionCodes"].array.isEmpty else { continue }
                    result.googleTracks.append(name)
                    for note in release["releaseNotes"].array {
                        guard let language = note["language"].string,
                              let text = note["text"].string else { continue }
                        result.googleReleaseNotes[language] = text
                    }
                }
                result.googleTracks.sort()
            }
            _ = try? await api.google("DELETE", editBase)
        } catch {
            // A read never leaves an edit behind. Spec section 7.2.
            _ = try? await api.google("DELETE", editBase)
            throw error
        }

        if let catalog = await attempt("Google Play products", &failures, {
            try await googleCatalog(packageName: packageName, base: base)
        }) {
            result.purchases = catalog.purchases
            result.subscriptions = catalog.subscriptions
        }

        result.failures = failures
        return result
    }

    private func googleCatalog(packageName: String, base: String) async throws
        -> (purchases: [Manifest.Purchase], subscriptions: [Manifest.SubscriptionGroup]) {
        let oneTime = JSON(data: try await api.google(
            "GET", "\(base)/oneTimeProducts?pageSize=100").data)
        let ids = oneTime["oneTimeProducts"].array.compactMap { $0["productId"].string }
        let subscriptions = JSON(data: try await api.google(
            "GET", "\(base)/subscriptions?pageSize=100").data)
        let planIds = subscriptions["subscriptions"].array.compactMap { $0["productId"].string }

        let client = GoogleCatalogClient(api: api)
        let products = ids.isEmpty ? [:]
            : try await client.oneTimeProducts(packageName: packageName, productIds: ids)
        let plans = planIds.isEmpty ? [:]
            : try await client.subscriptions(packageName: packageName, productIds: planIds)
        return (ids.compactMap { products[$0] }.map(Self.googlePurchase),
                planIds.compactMap { plans[$0] }.map(Self.googleSubscription))
    }

    // MARK: - The optional reads

    /// Runs one read that the import can live without. A failure costs that one
    /// block and reaches the developer as a line naming what stayed empty.
    private func attempt<T>(_ what: String, _ failures: inout [String],
                            _ read: () async throws -> T) async -> T? {
        do { return try await read() }
        catch {
            failures.append("\(what): \(error.localizedDescription)")
            return nil
        }
    }

    private func appleScreenshots(localizationID: String,
                                  locale: String) async throws -> [ImportedStoreAsset] {
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/appStoreVersionLocalizations/\(localizationID)"
                + "/appScreenshotSets?include=appScreenshots&limit=50").data)
        return Self.appleAssets(payload, locale: locale, setKey: "appScreenshotSet",
                                itemType: "appScreenshots",
                                kindKey: "screenshotDisplayType")
    }

    private func applePreviews(localizationID: String,
                               locale: String) async throws -> [ImportedStoreAsset] {
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/appStoreVersionLocalizations/\(localizationID)"
                + "/appPreviewSets?include=appPreviews&limit=50").data)
        return Self.appleAssets(payload, locale: locale, setKey: "appPreviewSet",
                                itemType: "appPreviews", kindKey: "previewType")
    }

    /// Apple serves a screenshot as a template with `{w}`, `{h}`, and `{f}`
    /// placeholders, and a preview as a plain video URL.
    static func appleAssets(_ payload: JSON, locale: String, setKey: String,
                            itemType: String, kindKey: String) -> [ImportedStoreAsset] {
        var kinds: [String: String] = [:]
        for entry in payload["data"].array {
            guard let id = entry["id"].string,
                  let kind = entry["attributes"][kindKey].string else { continue }
            kinds[id] = kind
        }
        return payload["included"].array.compactMap { item -> ImportedStoreAsset? in
            guard item["type"].string == itemType,
                  let setID = item["relationships"][setKey]["data"]["id"].string,
                  let kind = kinds[setID] else { return nil }
            let attributes = item["attributes"]
            let text: String?
            if let video = attributes["videoUrl"].string {
                text = video
            } else if let template = attributes["imageAsset"]["templateUrl"].string {
                let width = attributes["imageAsset"]["width"].int ?? 1_290
                let height = attributes["imageAsset"]["height"].int ?? 2_796
                text = template.replacingOccurrences(of: "{w}", with: String(width))
                    .replacingOccurrences(of: "{h}", with: String(height))
                    .replacingOccurrences(of: "{f}", with: "png")
                    .replacingOccurrences(of: "{c}", with: "")
            } else {
                text = nil
            }
            guard let text, let url = URL(string: text) else { return nil }
            let fallback = "\(kind)-\(item["id"].string ?? UUID().uuidString)"
            let name = attributes["fileName"].string
                ?? "\(fallback).\(url.pathExtension.isEmpty ? "png" : url.pathExtension)"
            return ImportedStoreAsset(locale: locale, kind: kind, url: url, fileName: name)
        }
    }

    // MARK: - The catalog shapes

    static func applePurchase(_ item: JSON) -> Manifest.Purchase? {
        guard let id = item["attributes"]["productId"].string else { return nil }
        let kind: Manifest.Purchase.Kind = switch item["attributes"]["inAppPurchaseType"].string {
        case "CONSUMABLE": .consumable
        case "NON_RENEWING_SUBSCRIPTION": .nonRenewing
        default: .nonConsumable
        }
        return Manifest.Purchase(id: id, kind: kind, name: item["attributes"]["name"].string,
                                 reviewNote: item["attributes"]["reviewNote"].string)
    }

    static func appleSubscriptionGroups(_ payload: JSON) -> [Manifest.SubscriptionGroup] {
        var plansByGroup: [String: [Manifest.SubscriptionGroup.Plan]] = [:]
        for item in payload["included"].array where item["type"].string == "subscriptions" {
            let attributes = item["attributes"]
            guard let id = attributes["productId"].string else { continue }
            let group = item["relationships"]["group"]["data"]["id"].string ?? ""
            plansByGroup[group, default: []].append(Manifest.SubscriptionGroup.Plan(
                id: id,
                duration: Self.appleDuration(attributes["subscriptionPeriod"].string)))
        }
        return payload["data"].array.compactMap { item in
            guard let id = item["id"].string else { return nil }
            return Manifest.SubscriptionGroup(
                groupId: id,
                groupName: item["attributes"]["referenceName"].string,
                plans: plansByGroup[id] ?? [])
        }
    }

    static func appleDuration(_ period: String?) -> String {
        switch period {
        case "ONE_WEEK": "P1W"
        case "TWO_MONTHS": "P2M"
        case "THREE_MONTHS": "P3M"
        case "SIX_MONTHS": "P6M"
        case "ONE_YEAR": "P1Y"
        default: "P1M"
        }
    }

    static func googlePurchase(_ product: ActualState.Google.CatalogProduct) -> Manifest.Purchase {
        Manifest.Purchase(id: product.productId, kind: .nonConsumable,
                          name: Self.firstTitle(product), price: Self.firstPrice(product))
    }

    static func googleSubscription(
        _ product: ActualState.Google.CatalogProduct) -> Manifest.SubscriptionGroup {
        Manifest.SubscriptionGroup(
            groupId: product.productId, groupName: Self.firstTitle(product),
            plans: [Manifest.SubscriptionGroup.Plan(
                id: product.productId,
                duration: product.basePlanDuration ?? "P1M",
                basePlanId: product.basePlanId,
                price: Self.firstPrice(product))])
    }

    private static func firstTitle(_ product: ActualState.Google.CatalogProduct) -> String? {
        product.listings.sorted { $0.key < $1.key }.first?.value.title
    }

    /// Google answers `"USD 4.99"` per region. The manifest holds one price, so
    /// the import takes the United States when it exists and the first region
    /// otherwise.
    private static func firstPrice(_ product: ActualState.Google.CatalogProduct) -> Price? {
        let text = product.prices["US"] ?? product.prices.sorted { $0.key < $1.key }.first?.value
        let parts = (text ?? "").split(separator: " ")
        guard parts.count == 2, let amount = Decimal(string: String(parts[1])) else { return nil }
        return Price(amount: amount, currency: String(parts[0]))
    }
}
