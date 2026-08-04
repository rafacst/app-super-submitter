import Foundation

/// Reads what the stores hold. Spec section 7.2, step 1.
///
/// Every call here is a `GET`, with one exception that Google forces: a
/// listing read needs an edit, so this opens one and **always deletes it**.
/// The plan opens no edit that outlives the read.
public struct StateReader: Sendable {
    private let api: StoreAPI

    public init(api: StoreAPI) {
        self.api = api
    }

    public func read(manifest: Manifest, stores: Set<Store>,
                     provider: Manifest.Provider) async -> ActualState {
        var state = ActualState()
        state.readAt = Date()

        if stores.contains(.apple), let apple = manifest.apps.apple, !apple.appId.isEmpty {
            do {
                state.apple = try await readApple(
                    appID: apple.appId,
                    basePrice: manifest.pricing?.base,
                    versionName: manifest.release?.versionName,
                    purchaseIds: (manifest.purchases ?? []).map(\.id),
                    subscriptionIds: (manifest.subscriptions ?? [])
                        .flatMap { $0.plans.map(\.id) },
                    groupNames: (manifest.subscriptions ?? [])
                        .map { $0.groupName ?? $0.groupId })
            } catch { state.failures.append("App Store: \(error.localizedDescription)") }
        }
        if stores.contains(.google), let google = manifest.apps.google,
           !google.packageName.isEmpty {
            do {
                state.google = try await readGoogle(
                    packageName: google.packageName,
                    track: manifest.googlePrimaryTrack,
                    oneTimeProductIds: (manifest.purchases ?? []).map(\.id),
                    subscriptionProductIds: (manifest.subscriptions ?? [])
                        .flatMap { $0.plans.map(\.id) })
            } catch {
                state.failures.append("Google Play: \(error.localizedDescription)")
            }
        }
        if provider != .none {
            do { state.provider = try await readProvider(manifest: manifest, provider: provider) }
            catch { state.failures.append("Provider: \(error.localizedDescription)") }
        }
        return state
    }

    // MARK: - The App Store

    /// - Parameters:
    ///   - purchaseIds: the purchases that the manifest names. The reader asks
    ///     Apple for each one, because the list endpoint carries no
    ///     localization, no price, and no territory, and the plan compares all
    ///     three.
    ///   - subscriptionIds: the same, for the subscription plans.
    public func readApple(appID: String,
                          basePrice: Price? = nil,
                          versionName: String? = nil,
                          purchaseIds: [String] = [],
                          subscriptionIds: [String] = [],
                          groupNames: [String] = []) async throws -> ActualState.Apple {
        var result = ActualState.Apple()

        let infos = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appID)/appInfos?limit=200").data)
        let info = infos["data"].array.first {
            $0["attributes"]["appStoreState"].string == "PREPARE_FOR_SUBMISSION"
        } ?? infos["data"].array.first
        if let info, let infoID = info["id"].string {
            result.appInfoId = infoID
            let relationships = info["relationships"]
            result.primaryCategory = relationships["primaryCategory"]["data"]["id"].string
            result.secondaryCategory = relationships["secondaryCategory"]["data"]["id"].string

            let localizations = JSON(data: try await api.apple(
                "GET", "/v1/appInfos/\(infoID)/appInfoLocalizations?limit=200").data)
            for item in localizations["data"].array {
                let attributes = item["attributes"]
                guard let locale = attributes["locale"].string else { continue }
                var value = ActualState.Apple.InfoLocale()
                value.id = item["id"].string
                value.name = attributes["name"].string
                value.subtitle = attributes["subtitle"].string
                value.privacyPolicyUrl = attributes["privacyPolicyUrl"].string
                value.privacyPolicyText = attributes["privacyPolicyText"].string
                value.privacyChoicesUrl = attributes["privacyChoicesUrl"].string
                result.infoLocales[locale] = value
            }

            let ageRating = JSON(data: try await api.apple(
                "GET", "/v1/appInfos/\(infoID)/ageRatingDeclaration").data)
            result.ageRatingDeclarationId = ageRating["data"]["id"].string
        }

        let versions = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appID)/appStoreVersions?limit=200").data)
        let editableStates = Set(["PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED",
                                  "REJECTED", "METADATA_REJECTED"])
        let editableVersion = versions["data"].array.first {
            let state = $0["attributes"]["appVersionState"].string
                ?? $0["attributes"]["appStoreState"].string ?? ""
            return editableStates.contains(state)
        }
        let namedVersion = versionName.flatMap { wanted in
            versions["data"].array.first {
                $0["attributes"]["versionString"].string == wanted
            }
        }
        if let version = namedVersion ?? editableVersion ?? versions["data"].array.first {
            let versionID = version["id"].string
            result.versionId = versionID
            result.versionString = version["attributes"]["versionString"].string
            result.versionState = version["attributes"]["appVersionState"].string
                ?? version["attributes"]["appStoreState"].string
            result.attachedBuildId = version["relationships"]["build"]["data"]["id"].string

            if let versionID {
                let phased = JSON(data: try await api.apple(
                    "GET", "/v1/appStoreVersions/\(versionID)/appStoreVersionPhasedRelease").data)
                result.phasedReleaseId = phased["data"]["id"].string
                result.phasedReleaseState = phased["data"]["attributes"]["phasedReleaseState"].string
                let localizations = JSON(data: try await api.apple(
                    "GET",
                    "/v1/appStoreVersions/\(versionID)/appStoreVersionLocalizations?limit=200").data)
                for item in localizations["data"].array {
                    let attributes = item["attributes"]
                    guard let locale = attributes["locale"].string else { continue }
                    var value = ActualState.Apple.VersionLocale()
                    value.id = item["id"].string
                    value.description = attributes["description"].string
                    value.whatsNew = attributes["whatsNew"].string
                    value.keywords = attributes["keywords"].string
                    value.promotionalText = attributes["promotionalText"].string
                    value.supportUrl = attributes["supportUrl"].string
                    value.marketingUrl = attributes["marketingUrl"].string
                    result.versionLocales[locale] = value

                    // The checksums make a second apply skip an upload that
                    // already landed. Spec section 7.5.
                    if let localizationID = value.id {
                        let sets = JSON(data: try await api.apple(
                            "GET",
                            "/v1/appStoreVersionLocalizations/\(localizationID)/appScreenshotSets?include=appScreenshots&limit=50").data)
                        var byBucket: [String: String] = [:]
                        for entry in sets["data"].array {
                            guard let type = entry["attributes"]["screenshotDisplayType"].string
                            else { continue }
                            byBucket[entry["id"].string ?? ""] = type
                        }
                        for included in sets["included"].array
                        where included["type"].string == "appScreenshots" {
                            let checksum = included["attributes"]["sourceFileChecksum"].string
                            let setID = included["relationships"]["appScreenshotSet"]["data"]["id"]
                                .string ?? ""
                            guard let type = byBucket[setID] else { continue }
                            // The image URL rides along in the same payload.
                            if let url = StoreImportReader.imageURL(
                                included["attributes"]["imageAsset"]) {
                                result.screenshotURLs["\(locale)/\(type)", default: []].append(url)
                            }
                            guard let checksum else { continue }
                            result.screenshotChecksums["\(locale)/\(type)", default: []]
                                .insert(checksum)
                            result.screenshotChecksumOrder["\(locale)/\(type)", default: []]
                                .append(checksum)
                        }

                        // A missing preview set is not a read failure, and the
                        // plan carries on without the video diff.
                        if let previews = try? await api.apple(
                            "GET", "/v1/appStoreVersionLocalizations/\(localizationID)"
                                + "/appPreviewSets?include=appPreviews&limit=50") {
                            Self.readPreviews(JSON(data: previews.data), locale: locale,
                                              into: &result)
                        }
                    }
                }

                let reviewDetail = JSON(data: try await api.apple(
                    "GET", "/v1/appStoreVersions/\(versionID)/appStoreReviewDetail").data)
                result.reviewDetailId = reviewDetail["data"]["id"].string
                let review = reviewDetail["data"]["attributes"]
                result.reviewContactEmail = review["contactEmail"].string
                result.reviewContactFirstName = review["contactFirstName"].string
                result.reviewContactLastName = review["contactLastName"].string
                result.reviewContactPhone = review["contactPhone"].string
                result.reviewDemoAccountRequired = review["demoAccountRequired"].bool
                result.reviewNotes = review["notes"].string
            }
        }

        let builds = JSON(data: try await api.apple(
            "GET", "/v1/builds?filter%5Bapp%5D=\(appID)&limit=200").data)
        result.highestBuildNumber = builds["data"].array
            .compactMap { $0["attributes"]["version"].int }
            .max()
        if let buildID = result.attachedBuildId,
           let build = builds["data"].array.first(where: { $0["id"].string == buildID }) {
            result.buildUsesNonExemptEncryption = build["attributes"]["usesNonExemptEncryption"].bool
        }

        // The catalog. The ids come off the two list reads, and the detail
        // comes off one read per named product, the same shape as Google.
        let catalog = AppleCatalogClient(api: api)
        let purchases = try await catalog.purchases(appID: appID, productIds: purchaseIds)
        result.purchaseIds = Set(purchases.keys)
        result.catalog = purchases

        let subscriptions = try await catalog.subscriptions(appID: appID,
                                                            productIds: subscriptionIds,
                                                            groupNames: groupNames)
        result.subscriptionIds = Set(subscriptions.products.keys)
        result.catalog.merge(subscriptions.products) { _, new in new }
        result.subscriptionGroupNames = subscriptions.groups.names
        result.subscriptionGroupLocales = subscriptions.groups.locales

        // The grace period is one resource on the app. Apple answers 404 when
        // the app has none, which is a state and not a failure.
        if let response = try? await api.apple(
            "GET", "/v1/apps/\(appID)/subscriptionGracePeriod") {
            let attributes = JSON(data: response.data)["data"]["attributes"]
            result.gracePeriodOptIn = attributes["optIn"].bool
            result.gracePeriodDays = Self.gracePeriodDays(attributes["duration"].string)
        }

        // Apple sells at a price point, never at the amount you asked for.
        // The plan shows the resolved amount, and the validator warns over a
        // 5 percent gap. Spec sections 6.7 and 10.4.
        if let basePrice {
            let territory = basePrice.territory ?? "USA"
            let points = JSON(data: try await api.apple(
                "GET",
                "/v1/apps/\(appID)/appPricePoints?filter%5Bterritory%5D=\(territory)&limit=200").data)
            let amounts = points["data"].array
                .compactMap { $0["attributes"]["customerPrice"].string }
                .compactMap { Decimal(string: $0) }
            result.priceAmount = Self.nearest(to: basePrice.amount, in: amounts)
            result.priceCurrency = basePrice.currency
        }

        let schedule = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appID)/appPriceSchedule"
                + "?include=baseTerritory,manualPrices,manualPrices.appPricePoint").data)
        for included in schedule["included"].array
        where included["type"].string == "appPricePoints" {
            if let text = included["attributes"]["customerPrice"].string {
                result.currentPriceAmount = Decimal(string: text)
                break
            }
        }

        let availabilities = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appID)/appAvailabilityV2?include=territoryAvailabilities").data)
        result.appAvailabilityId = availabilities["data"]["id"].string
        result.availableInNewTerritories = availabilities["data"]["attributes"]["availableInNewTerritories"].bool
        let territories = availabilities["data"]["relationships"]["territoryAvailabilities"]
        result.territoryCount = territories["meta"]["paging"]["total"].int
        for item in availabilities["included"].array
        where item["type"].string == "territoryAvailabilities" {
            guard let code = item["relationships"]["territory"]["data"]["id"].string else {
                continue
            }
            result.territoryAvailability[code] = item["attributes"]["available"].bool ?? false
        }

        await readAppleMarketing(appID: appID, into: &result)
        await readAppleTestFlight(appID: appID, into: &result)

        let submissions = JSON(data: try await api.apple(
            "GET", "/v1/reviewSubmissions?filter%5Bapp%5D=\(appID)&limit=20").data)
        result.hasOpenReviewSubmission = submissions["data"].array.contains { item in
            let state = item["attributes"]["state"].string ?? ""
            return ["READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW",
                    "UNRESOLVED_ISSUES"].contains(state)
        }
        return result
    }

    /// The seven App Store marketing resources.
    ///
    /// Each one is optional on a real app, and Apple answers 404 for the ones
    /// the app never created. A 404 is a state, not a failure, so none of
    /// these ends the read. A resource that answers fills its field and the
    /// plan then compares it; a resource that fails leaves the field empty and
    /// the plan marks that one row unverified.
    private func readAppleMarketing(appID: String,
                                    into result: inout ActualState.Apple) async {
        if let response = try? await api.apple(
            "GET", "/v1/apps/\(appID)/appCustomProductPages?limit=200") {
            for item in JSON(data: response.data)["data"].array {
                guard let name = item["attributes"]["name"].string else { continue }
                result.customProductPageNames[name] = item["id"].string ?? ""
            }
        }
        if let versionID = result.versionId, let response = try? await api.apple(
            "GET", "/v1/appStoreVersions/\(versionID)/appStoreVersionExperimentsV2?limit=200") {
            for item in JSON(data: response.data)["data"].array {
                guard let name = item["attributes"]["name"].string else { continue }
                result.experimentNames[name] = item["attributes"]["state"].string ?? ""
            }
        }
        if let response = try? await api.apple("GET", "/v1/apps/\(appID)/appEvents?limit=200") {
            for item in JSON(data: response.data)["data"].array {
                guard let name = item["attributes"]["referenceName"].string else { continue }
                result.appEventNames[name] = item["attributes"]["eventState"].string ?? ""
            }
        }
        if let response = try? await api.apple(
            "GET", "/v1/apps/\(appID)/endUserLicenseAgreement?include=territories") {
            let payload = JSON(data: response.data)
            result.eulaText = payload["data"]["attributes"]["agreementText"].string
            result.eulaTerritories = Set(payload["included"].array
                .filter { $0["type"].string == "territories" }
                .compactMap { $0["id"].string })
        }
        if let response = try? await api.apple(
            "GET", "/v1/nominations?filter%5Bstate%5D=DRAFT,SUBMITTED&limit=200") {
            result.nominationNames = Set(JSON(data: response.data)["data"].array
                .compactMap { $0["attributes"]["name"].string })
        }
        if let response = try? await api.apple(
            "GET", "/v1/apps/\(appID)/accessibilityDeclarations?limit=200"),
           let first = JSON(data: response.data)["data"].array.first {
            // Apple names one boolean per supported feature, and the manifest
            // lists the names it turns on.
            let attributes = first["attributes"]
            for key in attributes.keys where attributes[key].bool == true {
                result.accessibilitySupports.insert(key)
            }
        }
        if let response = try? await api.apple("GET", "/v1/apps/\(appID)/appClips?limit=200"),
           let clipID = JSON(data: response.data)["data"].array.first?["id"].string {
            result.hasAppClipExperience = false
            if let experiences = try? await api.apple(
                "GET", "/v1/appClips/\(clipID)/appClipDefaultExperiences?limit=200") {
                let payload = JSON(data: experiences.data)
                result.hasAppClipExperience = !payload["data"].array.isEmpty
                result.appClipExperienceActions = Set(payload["data"].array
                    .compactMap { $0["attributes"]["action"].string })
            }
        }
    }

    /// The TestFlight groups, and the notes on the build that is attached.
    ///
    /// A team with no TestFlight group answers with an empty list, which is a
    /// state and not a failure. The build reads only run when a build is
    /// attached, because "What to Test" belongs to a build.
    private func readAppleTestFlight(appID: String,
                                     into result: inout ActualState.Apple) async {
        let client = AppleTestFlightClient(api: api)
        if let groups = try? await client.groups(appID: appID) {
            result.betaGroups = groups
        }
        // The app-level page needs no build, so it is read before the guard.
        if let localizations = try? await client.appLocalizations(appID: appID) {
            result.betaAppLocalizations = localizations
            result.betaAppLocalizationsRead = true
        }
        guard let buildID = result.attachedBuildId else { return }
        if let notes = try? await client.whatToTest(buildID: buildID) {
            result.whatToTest = notes
        }
        if let state = try? await client.buildBetaState(buildID: buildID) {
            result.betaReviewSubmitted = state.submitted
            result.betaAutoNotify = state.autoNotify
        }
    }

    /// The app previews of one locale, in the shape the screenshots use.
    static func readPreviews(_ payload: JSON, locale: String,
                             into result: inout ActualState.Apple) {
        var byBucket: [String: String] = [:]
        for entry in payload["data"].array {
            guard let type = entry["attributes"]["previewType"].string else { continue }
            byBucket[entry["id"].string ?? ""] = type
        }
        for included in payload["included"].array
        where included["type"].string == "appPreviews" {
            let setID = included["relationships"]["appPreviewSet"]["data"]["id"].string ?? ""
            guard let type = byBucket[setID] else { continue }
            if let checksum = included["attributes"]["sourceFileChecksum"].string {
                result.previewChecksums["\(locale)/\(type)", default: []].insert(checksum)
            }
            let attributes = included["attributes"]
            let url = attributes["videoUrl"].string.flatMap(URL.init(string:))
                ?? StoreImportReader.imageURL(attributes["previewFrameImageAsset"])
            if let url { result.previewURLs["\(locale)/\(type)", default: []].append(url) }
        }
    }

    // MARK: - Google Play

    /// - Parameters:
    ///   - oneTimeProductIds: the products that the manifest names. The reader
    ///     asks Google for each one, because the list endpoint carries no
    ///     title, no price, and no offer state, and the plan compares all
    ///     three.
    ///   - subscriptionProductIds: the same, for the subscription plans.
    public func readGoogle(packageName: String, track: String,
                           oneTimeProductIds: [String] = [],
                           subscriptionProductIds: [String] = [])
        async throws -> ActualState.Google {
        let base = "/androidpublisher/v3/applications/\(Self.escape(packageName))"
        let edit = JSON(data: try await api.google("POST", "\(base)/edits", body: [:]).data)
        guard let editID = edit["id"].string else { throw ConnectionError.invalidResponse }
        let editBase = "\(base)/edits/\(editID)"

        do {
            var result = ActualState.Google()

            let listings = JSON(data: try await api.google("GET", "\(editBase)/listings").data)
            for item in listings["listings"].array {
                guard let language = item["language"].string else { continue }
                var value = ActualState.Google.Listing()
                value.title = item["title"].string
                value.shortDescription = item["shortDescription"].string
                value.fullDescription = item["fullDescription"].string
                value.video = item["video"].string
                result.listings[language] = value

                for imageType in ["phoneScreenshots", "sevenInchScreenshots",
                                  "tenInchScreenshots", "tvScreenshots", "wearScreenshots",
                                  "icon", "featureGraphic"] {
                    let images = JSON(data: try await api.google(
                        "GET", "\(editBase)/listings/\(language)/\(imageType)").data)
                    let hashes = images["images"].array.compactMap { $0["sha256"].string }
                    guard !hashes.isEmpty else { continue }
                    result.imageHashes["\(language)/\(imageType)"] = Set(hashes)
                    result.imageURLs["\(language)/\(imageType)"] = images["images"].array
                        .compactMap { $0["url"].string.flatMap(URL.init(string:)) }
                }
            }

            let details = JSON(data: try await api.google("GET", "\(editBase)/details").data)
            result.contactEmail = details["contactEmail"].string
            result.contactWebsite = details["contactWebsite"].string
            result.contactPhone = details["contactPhone"].string

            let tracks = JSON(data: try await api.google("GET", "\(editBase)/tracks").data)
            for item in tracks["tracks"].array {
                guard let name = item["track"].string else { continue }
                var value = ActualState.Google.Track()
                let release = item["releases"].array.first
                value.versionCodes = release?["versionCodes"].array.compactMap(\.int) ?? []
                value.status = release?["status"].string
                value.userFraction = release?["userFraction"].double
                for note in release?["releaseNotes"].array ?? [] {
                    guard let language = note["language"].string else { continue }
                    value.releaseNotes[language] = note["text"].string
                }

                // Google answers 404 for a track that carries no tester group
                // and for a track that targets every country. Neither is a
                // read failure, so neither ends the whole read.
                let escapedTrack = Self.escape(name)
                if let testers = try? await api.google(
                    "GET", "\(editBase)/testers/\(escapedTrack)") {
                    value.testers = JSON(data: testers.data)["googleGroups"].array
                        .compactMap(\.string).sorted()
                }
                if let availability = try? await api.google(
                    "GET", "\(editBase)/countryAvailability/\(escapedTrack)") {
                    let payload = JSON(data: availability.data)
                    value.countries = payload["countries"].array
                        .compactMap { $0["countryCode"].string }.sorted()
                    value.restOfWorld = payload["restOfWorld"].bool
                }
                result.tracks[name] = value
            }
            result.highestVersionCode = result.tracks[track]?.versionCodes.max()
                ?? result.tracks.values.flatMap(\.versionCodes).max()

            let oneTime = JSON(data: try await api.google(
                "GET", "\(base)/oneTimeProducts?pageSize=100").data)
            result.oneTimeProductIds = Set(oneTime["oneTimeProducts"].array
                .compactMap { $0["productId"].string })
            let subscriptions = JSON(data: try await api.google(
                "GET", "\(base)/subscriptions?pageSize=100").data)
            result.subscriptionIds = Set(subscriptions["subscriptions"].array
                .compactMap { $0["productId"].string })

            result.catalog = await readGoogleCatalog(
                packageName: packageName,
                oneTimeProductIds: oneTimeProductIds.filter(result.oneTimeProductIds.contains),
                subscriptionProductIds: subscriptionProductIds
                    .filter(result.subscriptionIds.contains))

            _ = try? await api.google("DELETE", editBase)
            return result
        } catch {
            // A read never leaves an edit behind. Spec section 7.2.
            _ = try? await api.google("DELETE", editBase)
            throw error
        }
    }

    /// The per-product detail that the plan diffs against the manifest.
    ///
    /// A failure here never fails the whole read. The plan then holds no
    /// detail for that product, and it marks the catalog step `unverified`
    /// instead of showing a diff that nobody verified.
    func readGoogleCatalog(packageName: String, oneTimeProductIds: [String],
                           subscriptionProductIds: [String]) async
        -> [String: ActualState.Google.CatalogProduct] {
        let client = GoogleCatalogClient(api: api)
        var result: [String: ActualState.Google.CatalogProduct] = [:]

        if !oneTimeProductIds.isEmpty,
           let products = try? await client.oneTimeProducts(packageName: packageName,
                                                            productIds: oneTimeProductIds) {
            result.merge(products) { _, new in new }
        }
        if !subscriptionProductIds.isEmpty,
           let products = try? await client.subscriptions(packageName: packageName,
                                                          productIds: subscriptionProductIds) {
            result.merge(products) { _, new in new }
        }

        // The offer state lives beside the offer, never on the product, so it
        // takes one read per subscription that actually has a base plan.
        for productId in subscriptionProductIds {
            guard let basePlanId = result[productId]?.basePlanId, !basePlanId.isEmpty,
                  let offers = try? await client.subscriptionOffers(
                    packageName: packageName, productId: productId,
                    basePlanId: basePlanId) else { continue }
            for offer in offers where offer.state != nil {
                result[productId]?.offerStates[offer.id] = offer.state
            }
        }
        // The same read for the one-time products. The app writes one purchase
        // option per product, so the option id is the product id.
        for productId in oneTimeProductIds {
            guard result[productId] != nil,
                  let offers = try? await client.oneTimeOffers(
                    packageName: packageName, productId: productId,
                    purchaseOptionId: productId) else { continue }
            for offer in offers where offer.state != nil {
                result[productId]?.offerStates[offer.id] = offer.state
            }
        }
        return result
    }

    // MARK: - The provider

    public func readProvider(manifest: Manifest,
                             provider: Manifest.Provider) async throws -> ActualState.Provider {
        switch provider {
        case .none:
            return ActualState.Provider()
        case .revenuecat:
            return try await readRevenueCat(manifest: manifest)
        case .adapty:
            return try readAdapty(manifest: manifest)
        }
    }

    private func readRevenueCat(manifest: Manifest) async throws -> ActualState.Provider {
        var result = ActualState.Provider()
        result.kind = .revenuecat
        guard let projectID = manifest.monetization?.revenuecat?.projectId, !projectID.isEmpty else {
            return result
        }
        let base = "/v2/projects/\(projectID)"

        // A 403 names the scope that the key lacks. Spec 10.5 asks the plan to
        // name it rather than fail on the first write.
        for (collection, scope) in [("apps", "project_configuration:apps:read"),
                                    ("products", "project_configuration:products:read"),
                                    ("entitlements", "project_configuration:entitlements:read"),
                                    ("offerings", "project_configuration:offerings:read")] {
            do {
                _ = try await api.revenueCat("GET", "\(base)/\(collection)?limit=1")
            } catch ConnectionError.http(let status, _) where status == 403 {
                result.missingScopes.append(scope)
            }
        }
        guard result.missingScopes.isEmpty else { return result }

        let apps = JSON(data: try await api.revenueCat("GET", "\(base)/apps").data)
        for app in apps["items"].array {
            guard let id = app["id"].string else { continue }
            result.appIdentifiers[id] = app["bundle_id"].string
                ?? app["package_name"].string
                ?? app["app_store"]["bundle_id"].string
                ?? app["play_store"]["package_name"].string
        }

        for (id, _) in result.appIdentifiers {
            let expectedPrefix = "\(base)/products"
            var path: String? = "\(expectedPrefix)?app_id=\(id)&limit=100"
            var visited: Set<String> = []
            for _ in 0..<100 {
                guard let current = path, visited.insert(current).inserted else { break }
                let page = JSON(data: try await api.revenueCat("GET", current).data)
                for product in page["items"].array {
                    guard let storeID = product["store_identifier"].string,
                          let productID = product["id"].string else { continue }
                    result.productIds["\(storeID)@\(id)"] = productID
                    result.productIds[storeID] = productID
                }
                path = page["next_page"].string.flatMap {
                    Self.revenueCatNextPagePath($0, expectedPrefix: expectedPrefix)
                }
            }
        }

        let entitlements = JSON(data: try await api.revenueCat("GET", "\(base)/entitlements").data)
        result.entitlementKeys = Set(entitlements["items"].array
            .compactMap { $0["lookup_key"].string })

        // What each entitlement already holds, so the attach step compares the
        // products instead of attaching the same list on every run. A read
        // that fails leaves the key out, and the plan then says unverified.
        for item in entitlements["items"].array {
            guard let key = item["lookup_key"].string, let id = item["id"].string,
                  let response = try? await api.revenueCat(
                    "GET", "\(base)/entitlements/\(id)/products?limit=200") else { continue }
            result.entitlementProducts[key] = Set(JSON(data: response.data)["items"].array
                .compactMap { $0["store_identifier"].string })
        }

        let offerings = JSON(data: try await api.revenueCat("GET", "\(base)/offerings").data)
        result.offeringKeys = Set(offerings["items"].array
            .compactMap { $0["lookup_key"].string ?? $0["id"].string })
        for item in offerings["items"].array {
            guard let key = item["lookup_key"].string ?? item["id"].string else { continue }
            if item["is_current"].bool == true { result.currentOfferingKey = key }
            guard let id = item["id"].string, let response = try? await api.revenueCat(
                "GET", "\(base)/offerings/\(id)/packages?limit=200&expand=items.products")
            else { continue }
            // A package carries its products, and the plan compares the store
            // ids in the order the offering serves them.
            result.offeringProducts[key] = JSON(data: response.data)["items"].array
                .flatMap { package in
                    package["products"]["items"].array
                        .compactMap { $0["store_identifier"].string }
                }
        }
        return result
    }

    private func readAdapty(manifest: Manifest) throws -> ActualState.Provider {
        var result = ActualState.Provider()
        result.kind = .adapty
        let cli = AdaptyCLIClient()
        result.loggedInAs = try? cli.status()
        guard result.loggedInAs != nil,
              let appID = manifest.monetization?.adapty?.appId, !appID.isEmpty else {
            return result
        }
        let catalog = try cli.catalog(appID: appID)
        result.productIds = catalog.productIds
        result.entitlementKeys = catalog.accessLevels
        result.offeringKeys = catalog.placements
        result.appIdentifiers = catalog.appIdentifiers.compactMapValues { $0 }
        return result
    }

    /// The three grace periods Apple names, back to the number of days that
    /// the manifest holds. `AppleDurations.gracePeriod` writes the same three.
    static func gracePeriodDays(_ duration: String?) -> Int? {
        switch duration {
        case "THREE_DAYS": 3
        case "SIXTEEN_DAYS": 16
        case "TWENTY_EIGHT_DAYS": 28
        default: nil
        }
    }

    static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    static func revenueCatNextPagePath(_ value: String, expectedPrefix: String) -> String? {
        guard let components = URLComponents(string: value) else { return nil }
        if let host = components.host, host.lowercased() != "api.revenuecat.com" { return nil }
        let path = components.percentEncodedPath
        guard path == expectedPrefix else { return nil }
        guard let query = components.percentEncodedQuery, !query.isEmpty else { return nil }
        return "\(path)?\(query)"
    }

    /// The nearest price point to the requested amount. The app never rounds a
    /// price by itself; it reports what Apple actually resolved.
    static func nearest(to amount: Decimal, in points: [Decimal]) -> Decimal? {
        points.min { abs($0 - amount) < abs($1 - amount) }
    }
}
