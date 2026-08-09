import Foundation

private extension Optional where Wrapped == String {
    /// This value when it says something, and the other one otherwise. An
    /// empty string is a store answering "nothing here", the same as nil.
    func orFilled(_ other: String?) -> String? {
        (self?.isEmpty == false) ? self : other
    }
}

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

    /// - Parameter platform: `IOS`, `MAC_OS`, `TV_OS`, or `VISION_OS`. An app
    ///   that ships on more than one holds a version train per platform under
    ///   one app id, and `/v1/apps/{id}/appStoreVersions` returns all of them
    ///   mixed together.
    ///
    ///   Nothing filtered them, so this walked every platform's versions as one
    ///   list and took whichever record won on state and version string. The
    ///   version number, the text, and the media could each come from a
    ///   different platform, and for a Mac app whose iOS train carried no
    ///   screenshots that meant a full listing with an empty Media tab and no
    ///   failure to explain it. Nil keeps every version, which is right for an
    ///   app that ships on one platform.
    public func apple(appID: String, platform: String? = nil) async throws
        -> ImportedStoreListing {
        var result = ImportedStoreListing()
        var failures: [String] = []

        let app = JSON(data: try await api.apple("GET", "/v1/apps/\(appID)").data)
        result.defaultLocale = app["data"]["attributes"]["primaryLocale"].string
        result.bundleID = app["data"]["attributes"]["bundleId"].string

        // The same choice the plan makes. `limit=1` would take whichever record
        // App Store Connect happened to return first, and that is usually not
        // the version the developer is about to edit.
        // The categories are relationships, and App Store Connect fills the
        // `data` of a to-one relationship only for the ones the request
        // includes. The import read nil for both on every app.
        let infos = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appID)/appInfos?limit=200"
                + "&include=primaryCategory,secondaryCategory").data)
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

        let allVersions = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appID)/appStoreVersions?limit=200").data)
        let versions = Self.applePlatformVersions(allVersions, platform: platform)
        let editableStates = Set(["PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED",
                                  "REJECTED", "METADATA_REJECTED"])
        // The same set `StateReader` calls released. A version pulled from
        // sale still shipped, and its text is still the text the app had.
        let releasedStates = Set(["READY_FOR_SALE", "READY_FOR_DISTRIBUTION",
                                  "PENDING_DEVELOPER_RELEASE", "REMOVED_FROM_SALE",
                                  "DEVELOPER_REMOVED_FROM_SALE"])
        func state(_ version: JSON) -> String {
            version["attributes"]["appVersionState"].string
                ?? version["attributes"]["appStoreState"].string ?? ""
        }
        // The highest, not the first, which is the rule `StateReader` already
        // follows. App Store Connect fixes no order here, and the first
        // released record it happens to return can be an old one.
        //
        // Taking that one cost the whole media import and said nothing. The
        // read picked version 1.2 while 1.4 was live, so `liveVersion` and
        // `version` were the same record and the fill from the live version
        // never ran. Apple keeps the screenshots on the current version and
        // answers a superseded record with empty sets, so the text of 1.2 came
        // through and none of its media did. The developer saw a full Details
        // tab, an empty Media tab, no failure to explain either, and a version
        // number below the one on sale.
        func highest(_ states: Set<String>) -> JSON? {
            versions
                .filter { states.contains(state($0)) }
                .max { Validator.isVersion($1["attributes"]["versionString"].string ?? "",
                                            above: $0["attributes"]["versionString"].string ?? "") }
        }
        let editableVersion = highest(editableStates)
        let liveVersion = highest(releasedStates)
        // The editable version decides the number the developer is about to
        // submit, so it still leads.
        let version = editableVersion ?? liveVersion ?? versions.first
        if let version, let versionID = version["id"].string {
            result.versionName = version["attributes"]["versionString"].string
            result.appleReleaseType = version["attributes"]["releaseType"].string

            var content = await versionContent(versionID: versionID, failures: &failures)

            // What the customer reads today, for every field the editable
            // version leaves empty.
            //
            // An editable version can be an empty shell: App Store Connect
            // creates one with no text and no screenshots, and so does this
            // app's own apply. Reading that shell literally reported an app
            // with no description and no media while its store page was full,
            // and the developer then saw an update flow offering to replace a
            // listing it had failed to read.
            if let liveVersion, let liveID = liveVersion["id"].string, liveID != versionID {
                let live = await versionContent(versionID: liveID, failures: &failures)
                content.fill(from: live)
            }

            for (code, locale) in content.locales {
                var target = result.locales[code] ?? .init()
                target.description = locale.description
                target.whatsNew = locale.whatsNew
                target.keywords = locale.keywords
                target.promotionalText = locale.promotionalText
                target.supportURL = locale.supportURL
                target.marketingURL = locale.marketingURL
                result.locales[code] = target
            }
            result.assets = content.assets

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

        // The newest build, by date. `limit=1` alone took whichever build App
        // Store Connect listed first, which is not the one that shipped.
        if let builds = await attempt("App Store encryption declaration", &failures, {
            JSON(data: try await api.apple(
                "GET",
                "/v1/builds?filter%5Bapp%5D=\(appID)&limit=1&sort=-uploadedDate").data)
        }) {
            let attributes = builds["data"][0]["attributes"]
            result.review.usesNonExemptEncryption = attributes["usesNonExemptEncryption"].bool
            // The app icon rides along in the same payload. It costs no
            // request, and it is what the sidebar draws beside the app name.
            if let url = Self.imageURL(attributes["iconAssetToken"], side: 512) {
                result.assets.append(ImportedStoreAsset(
                    locale: result.defaultLocale ?? "en-US", kind: "icon",
                    url: url, fileName: "icon.png"))
            }
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
            let productIDs = result.subscriptions.flatMap { $0.plans.map(\.id) }
            let groupNames = result.subscriptions.map { $0.groupName ?? $0.groupId }
            if let catalog = await attempt("App Store subscription details", &failures, {
                try await AppleCatalogClient(api: api).subscriptions(
                    appID: appID, productIds: productIDs, groupNames: groupNames)
            }) {
                for groupIndex in result.subscriptions.indices {
                    for planIndex in result.subscriptions[groupIndex].plans.indices {
                        let id = result.subscriptions[groupIndex].plans[planIndex].id
                        guard let product = catalog.products[id],
                              product.subscriptionPlanAvailabilityRead,
                              product.subscriptionPlanTerritories.count == 1,
                              let availability = product.subscriptionPlanTerritories.first
                        else { continue }
                        result.subscriptions[groupIndex].plans[planIndex].applePlanType =
                            availability.key
                        result.subscriptions[groupIndex].plans[planIndex].availableTerritories =
                            availability.value.isEmpty ? nil : availability.value.sorted()
                    }
                }
            }
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

    // MARK: - One version's text and media

    /// The localizations of one App Store version, and the files they show.
    struct VersionContent {
        var locales: [String: ImportedStoreListing.Locale] = [:]
        var assets: [ImportedStoreAsset] = []

        /// Takes from `other` whatever this version does not have.
        ///
        /// Field by field, so a half-written draft keeps every word the
        /// developer typed and still gains the paragraphs they did not.
        /// Media goes by bucket, not by locale. Apple keeps one screenshot set
        /// per display type, so a draft that carries a desktop set is not a
        /// draft that carries a phone set. Skipping the whole locale threw
        /// away every live bucket the draft had not filled, and the tab then
        /// showed one device class of a listing that has five.
        mutating func fill(from other: VersionContent) {
            for (code, source) in other.locales {
                var target = locales[code] ?? .init()
                target.description = target.description.orFilled(source.description)
                target.whatsNew = target.whatsNew.orFilled(source.whatsNew)
                target.keywords = target.keywords.orFilled(source.keywords)
                target.promotionalText = target.promotionalText.orFilled(source.promotionalText)
                target.supportURL = target.supportURL.orFilled(source.supportURL)
                target.marketingURL = target.marketingURL.orFilled(source.marketingURL)
                locales[code] = target
            }
            let covered = Set(assets.map { "\($0.locale)/\($0.kind)" })
            assets += other.assets.filter { !covered.contains("\($0.locale)/\($0.kind)") }
        }
    }

    private func versionContent(versionID: String,
                                failures: inout [String]) async -> VersionContent {
        var content = VersionContent()
        guard let localizations = await attempt("App Store text for version \(versionID)",
                                                &failures, {
            JSON(data: try await api.apple(
                "GET",
                "/v1/appStoreVersions/\(versionID)/appStoreVersionLocalizations?limit=200").data)
        }) else { return content }

        for item in localizations["data"].array {
            let attributes = item["attributes"]
            guard let code = attributes["locale"].string,
                  let localizationID = item["id"].string else { continue }
            var locale = ImportedStoreListing.Locale()
            locale.description = attributes["description"].string
            locale.whatsNew = attributes["whatsNew"].string
            locale.keywords = attributes["keywords"].string
            locale.promotionalText = attributes["promotionalText"].string
            locale.supportURL = attributes["supportUrl"].string
            locale.marketingURL = attributes["marketingUrl"].string
            content.locales[code] = locale

            content.assets += await attempt("App Store screenshots for \(code)", &failures) {
                try await appleScreenshots(localizationID: localizationID, locale: code)
            } ?? []
            content.assets += await attempt("App Store previews for \(code)", &failures) {
                try await applePreviews(localizationID: localizationID, locale: code)
            } ?? []
        }
        return content
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
        return Self.appleAssets(payload, locale: locale, itemType: "appScreenshots",
                                kindKey: "screenshotDisplayType")
    }

    private func applePreviews(localizationID: String,
                               locale: String) async throws -> [ImportedStoreAsset] {
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/appStoreVersionLocalizations/\(localizationID)"
                + "/appPreviewSets?include=appPreviews&limit=50").data)
        return Self.appleAssets(payload, locale: locale, itemType: "appPreviews",
                                kindKey: "previewType")
    }

    /// The versions of one platform, out of a payload that holds every
    /// platform the app ships on.
    ///
    /// A version with no platform attribute is kept. Apple has always sent one
    /// here, and dropping a record because a field is missing would lose the
    /// whole listing rather than narrow it.
    public static func applePlatformVersions(_ payload: JSON,
                                             platform: String?) -> [JSON] {
        let all = payload["data"].array
        guard let platform else { return all }
        let matching = all.filter {
            let value = $0["attributes"]["platform"].string
            return value == nil || value == platform
        }
        // An app id with no version on this platform yet is a real state, and
        // narrowing to nothing is the honest answer: the alternative is to
        // import another platform's listing under this one's name.
        return matching
    }

    /// Where each platform of one app id stands, from the answer the reader
    /// already has.
    ///
    /// `/v1/apps/{id}/appStoreVersions` returns every platform's train mixed
    /// together, and every other reader here narrows that to the one platform
    /// it is planning for. This keeps the rest: an app id whose Mac version is
    /// on sale and whose iOS version has never shipped is an ordinary state,
    /// and the developer has to be able to see it before choosing what to
    /// submit.
    ///
    /// `live` is the highest released number, by the version comparison the
    /// validator uses and not by the order Apple returns, which is unspecified.
    /// `pending` is the newest version that has not been released.
    public static func applePlatformStandings(_ payload: JSON)
        -> [ActualState.Apple.PlatformStanding] {
        let released = Set(["READY_FOR_SALE", "READY_FOR_DISTRIBUTION",
                            "REMOVED_FROM_SALE", "DEVELOPER_REMOVED_FROM_SALE",
                            "REPLACED_WITH_NEW_VERSION"])
        func state(_ version: JSON) -> String {
            version["attributes"]["appVersionState"].string
                ?? version["attributes"]["appStoreState"].string ?? ""
        }
        func number(_ version: JSON) -> String {
            version["attributes"]["versionString"].string ?? ""
        }
        var byPlatform: [String: [JSON]] = [:]
        for version in payload["data"].array {
            let platform = version["attributes"]["platform"].string ?? "IOS"
            byPlatform[platform, default: []].append(version)
        }
        return byPlatform.keys.sorted().map { platform in
            let versions = byPlatform[platform] ?? []
            let live = versions
                .filter { released.contains(state($0)) }
                .max { Validator.isVersion(number($1), above: number($0)) }
            let pending = versions
                .filter { !released.contains(state($0)) }
                .max { Validator.isVersion(number($1), above: number($0)) }
            return ActualState.Apple.PlatformStanding(
                platform: platform,
                live: live.map(number), liveState: live.map(state),
                pending: pending.map(number), pendingState: pending.map(state))
        }
    }

    /// Item id -> the bucket its set names, for a payload read with `include`.
    ///
    /// The **set** names its members. App Store Connect fills `data` on the
    /// to-many relationship the `include` asked for, and sends each included
    /// screenshot with `type`, `id`, `attributes`, and `links` and no
    /// `relationships` key at all.
    ///
    /// This used to walk the included items and ask each one which set it
    /// belonged to. That key does not exist, so every screenshot and every
    /// preview was dropped from a 200 that carried all of them. Nothing threw
    /// and nothing was logged, because a payload that parses to no assets and
    /// a version that holds no media are the same value. The Media tab opened
    /// empty on an app whose store page is full.
    ///
    /// `itemType` is both the type of the included rows and the name of the
    /// relationship that lists them: `appScreenshots`, `appPreviews`.
    static func appleBuckets(_ payload: JSON, itemType: String,
                             kindKey: String) -> [String: String] {
        var kinds: [String: String] = [:]
        for set in payload["data"].array {
            guard let kind = set["attributes"][kindKey].string else { continue }
            for member in set["relationships"][itemType]["data"].array {
                guard let id = member["id"].string else { continue }
                kinds[id] = kind
            }
        }
        return kinds
    }

    /// Apple serves a screenshot as a template with `{w}`, `{h}`, and `{f}`
    /// placeholders, and a preview as a plain video URL.
    ///
    /// The set's own member list drives the walk, so the assets come back in
    /// the order the store shows them, which is the order the tiles keep.
    ///
    /// The position leads the file name because Apple does not make a name
    /// unique inside a set. A real listing here holds two `09-profile.png`
    /// with different checksums, and the import writes one file per name: the
    /// second one found an existing file, skipped its download, and five live
    /// screenshots came back as three tiles, two of them the wrong picture.
    static func appleAssets(_ payload: JSON, locale: String,
                            itemType: String, kindKey: String) -> [ImportedStoreAsset] {
        var rows: [String: JSON] = [:]
        for item in payload["included"].array where item["type"].string == itemType {
            guard let id = item["id"].string else { continue }
            rows[id] = item
        }
        var result: [ImportedStoreAsset] = []
        for set in payload["data"].array {
            guard let kind = set["attributes"][kindKey].string else { continue }
            for (index, member) in set["relationships"][itemType]["data"].array.enumerated() {
                guard let id = member["id"].string, let item = rows[id] else { continue }
                let attributes = item["attributes"]
                let url = attributes["videoUrl"].string.flatMap(URL.init(string:))
                    ?? Self.imageURL(attributes["imageAsset"])
                guard let url else { continue }
                let extension_ = url.pathExtension.isEmpty ? "png" : url.pathExtension
                let name = attributes["fileName"].string ?? "\(kind).\(extension_)"
                result.append(ImportedStoreAsset(locale: locale, kind: kind, url: url,
                                                 fileName: "\(index + 1)-\(name)"))
            }
        }
        return result
    }

    /// The `sourceFileChecksum` of every screenshot in one set payload, by
    /// display type, in the order the store shows them.
    ///
    /// The set's own member list drives the walk, the same as `appleAssets`,
    /// so the order is the store's and not the order the include block
    /// happened to arrive in. The plan compares this list to the manifest
    /// order, and a re-ordered set is a real change.
    static func appleChecksums(_ payload: JSON) -> [String: [String]] {
        var rows: [String: String] = [:]
        for item in payload["included"].array where item["type"].string == "appScreenshots" {
            guard let id = item["id"].string,
                  let checksum = item["attributes"]["sourceFileChecksum"].string else { continue }
            rows[id] = checksum
        }
        var result: [String: [String]] = [:]
        for set in payload["data"].array {
            guard let kind = set["attributes"]["screenshotDisplayType"].string else { continue }
            for member in set["relationships"]["appScreenshots"]["data"].array {
                guard let id = member["id"].string, let checksum = rows[id] else { continue }
                result[kind, default: []].append(checksum)
            }
        }
        return result
    }

    /// Apple serves an image as a template with `{w}`, `{h}`, `{f}`, and `{c}`
    /// placeholders. Every image attribute in the API uses this one shape.
    static func imageURL(_ asset: JSON, side: Int? = nil) -> URL? {
        guard let template = asset["templateUrl"].string else { return nil }
        let width = side ?? asset["width"].int ?? 1_290
        let height = side ?? asset["height"].int ?? 2_796
        return URL(string: template
            .replacingOccurrences(of: "{w}", with: String(width))
            .replacingOccurrences(of: "{h}", with: String(height))
            .replacingOccurrences(of: "{f}", with: "png")
            .replacingOccurrences(of: "{c}", with: ""))
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
