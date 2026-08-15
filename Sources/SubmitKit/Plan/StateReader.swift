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
                    versionName: manifest.versionName(for: .apple),
                    platform: apple.platforms.first?.rawValue,
                    buildNumber: manifest.release?.apple?.buildNumber,
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
    ///   - platform: `IOS` or `MAC_OS`. An app that ships both holds two build
    ///     trains under one version string, and only one of them is this run's.
    ///   - buildNumber: the build the manifest chose out of the ones App Store
    ///     Connect holds. Nil takes the highest processed build of the train.
    public func readApple(appID: String,
                          basePrice: Price? = nil,
                          versionName: String? = nil,
                          platform: String? = nil,
                          buildNumber: String? = nil,
                          purchaseIds: [String] = [],
                          subscriptionIds: [String] = [],
                          groupNames: [String] = []) async throws -> ActualState.Apple {
        var result = ActualState.Apple()

        // The categories are relationships, and App Store Connect fills the
        // `data` of a to-one relationship only for the ones the request
        // includes. Without this the category read nil on every app, the
        // Review info tab showed two empty boxes on an app that has both, and
        // the console checklist reported "the API reports no primary
        // category" for the same reason.
        // The ids Apple accepts. A category the manifest names and Apple does
        // not have fails the apply the way an invented age rating field did,
        // so the plan checks it against this and stops before any write.
        //
        // Every page, because a short list here would call a real category
        // invented and block a release over it. A page that fails leaves the
        // set empty, and an empty set judges nothing.
        var categoryPath: String? = "/v1/appCategories?limit=200"
        var seenPages: Set<String> = []
        while let current = categoryPath, seenPages.insert(current).inserted,
              result.appCategoryIDs.count < 1_000 {
            guard let page = try? await api.apple("GET", current) else {
                result.appCategoryIDs = []
                break
            }
            let payload = JSON(data: page.data)
            for item in payload["data"].array {
                guard let id = item["id"].string else { continue }
                result.appCategoryIDs.insert(id)
            }
            categoryPath = payload["links"]["next"].string
                .flatMap(StoreDiagnostics.appleNextPath)
        }

        let infos = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appID)/appInfos?limit=200"
                + "&include=primaryCategory,secondaryCategory").data)
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
            // Apple's own answer names every field it has. The app hardcodes
            // none of them, so a questionnaire change on Apple's side arrives
            // here without a release.
            let attributes = ageRating["data"]["attributes"]
            for key in attributes.keys {
                guard let value = AgeRatingAnswer(attributes[key]) else { continue }
                result.ageRating[key] = value
            }
        }

        // One platform's versions. An app that ships on iOS and macOS holds a
        // train per platform under one app id, and this endpoint returns them
        // mixed. Reading them as one list let the editable version, the live
        // version, and the media each come from a different platform.
        let everyPlatform = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appID)/appStoreVersions?limit=200").data)
        // Before the narrowing, because the answer covers every platform and
        // the Build tab asks about all of them. No second request.
        result.platforms = StoreImportReader.applePlatformStandings(everyPlatform)
        let versions = StoreImportReader.applePlatformVersions(everyPlatform,
                                                               platform: platform)
        let editableStates = AppleVersionState.editable
        func versionState(_ version: JSON) -> String {
            version["attributes"]["appVersionState"].string
                ?? version["attributes"]["appStoreState"].string ?? ""
        }
        let editableVersion = versions.first {
            editableStates.contains(versionState($0))
        }
        let namedVersion = versionName.flatMap { wanted in
            versions.first {
                $0["attributes"]["versionString"].string == wanted
            }
        }
        // The version that reached the store. It decides two things: the
        // number the manifest has to beat, and whether this app is an update
        // at all. Nil means the app has never shipped, and the update rules
        // stay quiet for a first submission.
        //
        // A version removed from sale still counts. The app was on the store,
        // so the next version is an update and Apple still wants the number to
        // climb past it.
        let releasedStates = Set(["READY_FOR_SALE", "READY_FOR_DISTRIBUTION",
                                  "REMOVED_FROM_SALE", "DEVELOPER_REMOVED_FROM_SALE",
                                  "PENDING_DEVELOPER_RELEASE"])
        // The highest, not the first. App Store Connect fixes no order here,
        // and comparing against an older release would let a lower version
        // through.
        let liveVersion = versions
            .filter { releasedStates.contains(versionState($0)) }
            .max { Validator.isVersion($1["attributes"]["versionString"].string ?? "",
                                        above: $0["attributes"]["versionString"].string ?? "") }
        result.liveVersionString = liveVersion?["attributes"]["versionString"].string

        // No fallback to "whatever App Store Connect returned first". A live
        // version is not writable, and handing its id to the runner would
        // point every metadata write at the listing the customers are reading.
        // Nil means "no version yet", and the planner then creates one.
        //
        // A named version that is live still lands here, because the developer
        // named a number that is already used and the validator must say so.
        if let version = namedVersion ?? editableVersion {
            let versionID = version["id"].string
            result.versionId = versionID
            result.versionString = version["attributes"]["versionString"].string
            result.versionState = version["attributes"]["appVersionState"].string
                ?? version["attributes"]["appStoreState"].string
            result.releaseType = version["attributes"]["releaseType"].string

            if let versionID {
                // The linkage, and not the row this list already returned.
                //
                // App Store Connect fills `data` under a relationship only on
                // the side an `include` asked for. A list row carries `links`
                // and nothing else, which the icon read next door learned the
                // same way. So `relationships.build.data.id` read nil for
                // every version of every app, forever: the release checklist
                // said "a build is uploaded and no version holds it" about a
                // version that held one, the plan queued the attach on every
                // run, and What to test, the beta state, the build bundles and
                // the crash panel all sat behind the same nil.
                //
                // A version with no build answers 404, which is a state and
                // not a failure, so this stays a `try?`.
                if let linkage = try? await api.apple(
                    "GET", "/v1/appStoreVersions/\(versionID)/relationships/build") {
                    result.attachedBuildId = JSON(data: linkage.data)["data"]["id"].string
                }
                let phased = JSON(data: try await api.apple(
                    "GET", "/v1/appStoreVersions/\(versionID)/appStoreVersionPhasedRelease").data)
                result.phasedReleaseId = phased["data"]["id"].string
                result.phasedReleaseState = phased["data"]["attributes"]["phasedReleaseState"].string
                let localizations = JSON(data: try await api.apple(
                    "GET",
                    "/v1/appStoreVersions/\(versionID)/appStoreVersionLocalizations?limit=200").data)
                for item in localizations["data"].array {
                    guard let (locale, value) = Self.versionLocale(item) else { continue }
                    result.versionLocales[locale] = value

                    // The checksums make a second apply skip an upload that
                    // already landed. Spec section 7.5.
                    if let localizationID = value.id {
                        let sets = JSON(data: try await api.apple(
                            "GET",
                            "/v1/appStoreVersionLocalizations/\(localizationID)/appScreenshotSets?include=appScreenshots&limit=50").data)
                        // The same two-way link the import reads. The item's
                        // own back reference alone matched no set, so every
                        // checksum was lost too and a re-run re-uploaded a
                        // screenshot that was already on the store.
                        let byItem = StoreImportReader.appleBuckets(
                            sets, itemType: "appScreenshots",
                            kindKey: "screenshotDisplayType")
                        for included in sets["included"].array
                        where included["type"].string == "appScreenshots" {
                            guard let id = included["id"].string,
                                  let type = byItem[id] else { continue }
                            // The image URL rides along in the same payload.
                            if let url = StoreImportReader.imageURL(
                                included["attributes"]["imageAsset"]) {
                                result.screenshotURLs["\(locale)/\(type)", default: []].append(url)
                            }
                        }
                        // The set drives the order, not the include block.
                        // Walking `included` appended in whatever order the
                        // payload arrived, so a set that matched the manifest
                        // could still compare unequal and re-upload itself.
                        for (type, checksums) in StoreImportReader.appleChecksums(sets) {
                            result.screenshotChecksums["\(locale)/\(type)"] = Set(checksums)
                            result.screenshotChecksumOrder["\(locale)/\(type)"] = checksums
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
                // Empty is the same as absent here. Apple returns "" for a
                // password it will not hand back, and a blank that reads as an
                // answer would overwrite the one in the Keychain with nothing.
                result.reviewDemoAccountName = review["demoAccountName"].string
                    .flatMap { $0.isEmpty ? nil : $0 }
                result.reviewDemoAccountPassword = review["demoAccountPassword"].string
                    .flatMap { $0.isEmpty ? nil : $0 }
                result.reviewNotes = review["notes"].string
            }
        }

        // The words the customers read today.
        //
        // The block above reads the editable draft and nothing else, which is
        // right for every write: a draft is the only thing the app may patch.
        // But App Store Connect creates that draft empty, and so does this
        // app's own apply, so reading it alone reported an app with no
        // description while its store page was full. This fills the picture
        // the editing tabs draw. It touches no id, no plan, and no diff.
        //
        // The read is optional. A failure costs the display, never the plan.
        // The reviewer sign-in the released version was approved with.
        //
        // The block above reads the review detail of the draft, and between
        // releases there is no draft, so an update read nothing and the Review
        // info tab opened with two empty fields on an app that has shipped with
        // a demo account several times. Apple carries the detail into the next
        // version, so the released one is what the next version will start
        // with. It never overwrites the draft: this runs only when the draft
        // did not answer.
        if let liveID = liveVersion?["id"].string, liveID != result.versionId,
           result.reviewDemoAccountName == nil,
           let payload = try? await api.apple(
            "GET", "/v1/appStoreVersions/\(liveID)/appStoreReviewDetail") {
            let review = JSON(data: payload.data)["data"]["attributes"]
            result.reviewDemoAccountRequired = result.reviewDemoAccountRequired
                ?? review["demoAccountRequired"].bool
            result.reviewDemoAccountName = review["demoAccountName"].string
                .flatMap { $0.isEmpty ? nil : $0 }
            result.reviewDemoAccountPassword = review["demoAccountPassword"].string
                .flatMap { $0.isEmpty ? nil : $0 }
        }

        if let liveID = liveVersion?["id"].string, liveID != result.versionId,
           let payload = try? await api.apple(
            "GET", "/v1/appStoreVersions/\(liveID)/appStoreVersionLocalizations?limit=200") {
            for item in JSON(data: payload.data)["data"].array {
                guard let (locale, value) = Self.versionLocale(item) else { continue }
                result.liveVersionLocales[locale] = value
                // The pictures the customer sees, for the buckets the draft
                // leaves empty. The checksums stay the draft's, because they
                // decide which upload the apply may skip and an upload must
                // never be skipped against a version nobody is writing to.
                guard let localizationID = value.id else { continue }
                await Self.readLiveMedia(localizationID: localizationID, locale: locale,
                                          api: api, into: &result)
            }
        }

        // `include=preReleaseVersion` carries the marketing version of every
        // build in the same payload, so the train each build belongs to costs
        // no extra request.
        let builds = JSON(data: try await api.apple(
            "GET", "/v1/builds?filter%5Bapp%5D=\(appID)"
                + "&include=preReleaseVersion&limit=200").data)
        let trains = Self.appleTrains(builds, platform: platform)
        // Only the builds of the version this run writes to. A number below
        // another train is no conflict: Apple lets a new train start at one,
        // and a comparison across trains blocked an upload Apple accepts.
        let sameTrain = versionName.map { wanted in
            builds["data"].array.filter { build in
                build["relationships"]["preReleaseVersion"]["data"]["id"].string
                    .flatMap { trains[$0] } == wanted
            }
        } ?? []
        result.highestBuildNumber = sameTrain
            .compactMap { $0["attributes"]["version"].int }
            .max()
        // A build Apple is still processing is not one it lets a version hold,
        // so it stays out and the next read picks it up.
        let processed = sameTrain
            .filter { $0["attributes"]["processingState"].string == "VALID" }
        // The build the manifest chose, when it chose one. A number that names
        // no processed build of this train answers nothing rather than the
        // highest one: attaching a build the developer did not ask for is the
        // one outcome worse than attaching none.
        let chosen = buildNumber.map { wanted in
            processed.first { $0["attributes"]["version"].string == wanted }
        } ?? processed
            .max { ($0["attributes"]["version"].int ?? 0) < ($1["attributes"]["version"].int ?? 0) }
        result.buildIdForVersion = chosen?["id"].string
        // The build the apply writes to, and not only the attached one. Between
        // releases a version holds nothing, so this read answered nil, the plan
        // queued the export compliance write against a build that already
        // carried the answer, and Apple refused it: it takes the value from
        // `ITSAppUsesNonExemptEncryption` while it processes the build and lets
        // nobody change it afterwards. `AppleApply.appleTargetBuildID` picks the
        // build in this order, so the read follows it.
        if let buildID = result.buildIdForVersion ?? result.attachedBuildId,
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
        // Both list reads answered, so an id missing from the catalog is one
        // Apple does not hold rather than one nobody has asked about. Either
        // read above throws instead of returning empty, so reaching this line
        // is the proof.
        result.catalogRead = true

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
        // Price and availability are optional blocks, the same as the
        // marketing resources below. One HTTP 400 in here used to abort the
        // whole App Store read: the plan then held no App Store state at all,
        // so every line of a listing the store already carried was drawn as
        // an add, and one banner said the store could not be read. A block
        // that fails now costs its own rows, which the plan marks unverified.
        // The list is read whether the manifest names a price or not. It used
        // to be fetched only to resolve one, so an app with no price yet got no
        // list, and the field that asks for the first price was the one field
        // that could not offer the prices Apple sells at.
        let territory = basePrice?.territory ?? "USA"
        if let points = try? await ApplePricePoints.app(api, appID: appID,
                                                        territory: territory) {
            let amounts = points.map(\.amount)
            result.pricePoints = Set(amounts).sorted()
            // The ladder is this territory's money. The field that offers it
            // has to know which, because Brazil's prices under a request for
            // the United States are the wrong numbers in the wrong currency.
            result.pricePointTerritory = territory
            if let basePrice {
                result.priceAmount = Self.nearest(to: basePrice.amount, in: amounts)
                result.priceCurrency = basePrice.currency
            }
        }

        // The price the store holds today, in the territory the manifest
        // prices in.
        //
        // Three things were wrong with reading it off the schedule's own
        // include. The schedule holds one row per territory, so `first` read
        // Brazil's money as the United States' as often as not. It holds the
        // price that ended last month beside the one on sale, so `first` read
        // a dead row. And the point was then fetched by id off version one of
        // the price point resource, which does not exist: that read is a v3
        // route. Apple answered 404, `try?` swallowed it, and
        // `currentPriceAmount` came back nil for every app that has ever run
        // this. The plan wrote the price schedule on every single apply.
        //
        // `manualPrices` takes the territory filter and carries the point back
        // in the same response, so the fix is one request and no second hop.
        if let response = try? await api.apple(
            "GET", "/v1/apps/\(appID)/appPriceSchedule"),
           let scheduleID = JSON(data: response.data)["data"]["id"].string,
           let prices = try? await api.apple(
            "GET", "/v1/appPriceSchedules/\(Self.escape(scheduleID))/manualPrices"
                + "?limit=200&include=appPricePoint"
                + "&fields%5BappPricePoints%5D=customerPrice"
                + "&filter%5Bterritory%5D=\(Self.escape(territory))") {
            result.currentPriceAmount = Self.currentPrice(JSON(data: prices.data))
        }

        // The include on the record is one page long, so this read used to
        // hold the first fifty countries of an app that sells in 175, and the
        // plan then compared the manifest against a third of the record. The
        // diagnostics read pages it to the end, and it is the same request.
        if let availability = try? await StoreDiagnostics(api: api)
            .appAvailability(appID: appID) {
            result.availableInNewTerritories = availability.newTerritories
            result.territoryCount = availability.total
            result.territoryAvailability = availability.territories
        }

        await readAppleMarketing(appID: appID, into: &result)
        await readAppleTestFlight(appID: appID, into: &result)
        await readAppleGameCenter(appID: appID, into: &result)
        // The pages that are not this version's own. An app with none of them
        // pays one request for the answer, and every request under it is
        // optional, so nothing here can cost the read.
        result.productPages = await AppleProductPages(api: api).read(appID: appID)

        let submissions = JSON(data: try await api.apple(
            "GET", "/v1/reviewSubmissions?filter%5Bapp%5D=\(appID)&limit=20").data)
        result.openReviewSubmission = submissions["data"].array.compactMap { item in
            item["attributes"]["state"].string
        }.first { ["WAITING_FOR_REVIEW", "IN_REVIEW", "UNRESOLVED_ISSUES"].contains($0) }
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
                // The dates and the traffic share come back in this same
                // response. The reader kept the state alone, so the Marketing
                // tab could say an experiment was running and never how far.
                result.experiments[name] = ActualState.Apple.Experiment(
                    state: item["attributes"]["state"].string ?? "",
                    startDate: item["attributes"]["startDate"].string,
                    endDate: item["attributes"]["endDate"].string,
                    trafficProportion: item["attributes"]["trafficProportion"].int)
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
        // So does the licence. Apple creates one per app and fills it with its
        // own standard text, so a nil here is a read that failed.
        if let agreement = try? await client.licenseAgreement(appID: appID) {
            result.betaLicenseAgreement = agreement
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

    /// Game Center, and one request for every app that is not a game.
    ///
    /// The detail read is the gate. Apple answers 404 for an app with no
    /// configuration, so a `nil` detail is the ordinary state of most apps: the
    /// read stops, `read` is true, and every map stays empty. That costs one
    /// request and it is the common case.
    ///
    /// A detail read that **throws** is different. It leaves `read` false, and
    /// the planner then writes no Game Center step at all, because a create
    /// against a detail that already exists answers 409. One line goes into
    /// `state.failures` so the Summary tab says why.
    ///
    /// Below the detail, each family is optional on its own. A family that
    /// fails leaves its map empty and names itself in `unreadFamilies`, so a
    /// panel can say the count is short rather than drawing a wrong zero.
    private func readAppleGameCenter(appID: String,
                                     into result: inout ActualState.Apple) async {
        let client = AppleGameCenterClient(api: api)
        var state = ActualState.Apple.GameCenter()

        let detail: AppleGameCenterClient.Detail?
        do {
            detail = try await client.detail(appID: appID)
        } catch {
            // A 404 is "not a game", not a fault. Anything else is a read this
            // app must not write against.
            if Self.isNotFound(error) {
                state.read = true
                result.gameCenter = state
                return
            }
            result.gameCenter = state
            return
        }

        state.read = true
        guard let detail else {
            result.gameCenter = state
            return
        }
        state.detail = detail
        state.groups = (try? await client.groups()) ?? [:]
        state.appVersions = (try? await client.appVersions(detailID: detail.id)) ?? [:]

        let catalog = AppleGameCenterCatalogClient(api: api)
        for family in AppleGameCenterCatalogClient.Family.allCases {
            guard let objects = try? await catalog.objects(family: family,
                                                           detailID: detail.id) else {
                state.unreadFamilies.insert(family.rawValue)
                continue
            }
            switch family {
            case .achievement: state.achievements = objects
            case .leaderboard: state.leaderboards = objects
            case .leaderboardSet: state.leaderboardSets = objects
            case .activity: state.activities = objects
            case .challenge: state.challenges = objects
            }
        }

        // A link holds resource ids, and the manifest holds vendor
        // identifiers. Both maps are already read, so the translation costs no
        // request of its own.
        let boardsByResourceID = Dictionary(
            state.leaderboards.values.map { ($0.id, $0.vendorIdentifier) },
            uniquingKeysWith: { first, _ in first })
        let achievementsByResourceID = Dictionary(
            state.achievements.values.map { ($0.id, $0.vendorIdentifier) },
            uniquingKeysWith: { first, _ in first })

        for (vendorID, set) in state.leaderboardSets {
            state.leaderboardSets[vendorID]?.linkedIDs = await catalog.members(
                setID: set.id, leaderboardsByResourceID: boardsByResourceID)
            let names = await catalog.memberLocalizations(setID: set.id)
            if !names.isEmpty { state.memberLocalizations[vendorID] = names }
        }
        // The links of an activity and the board of a challenge. Without these
        // the plan would offer to write the same links on every apply, having
        // nothing to compare them against.
        for (vendorID, activity) in state.activities {
            let links = await catalog.activityLinks(
                activityID: activity.id,
                achievementsByResourceID: achievementsByResourceID,
                leaderboardsByResourceID: boardsByResourceID)
            state.activities[vendorID]?.linkedAchievementIDs = links.achievements
            state.activities[vendorID]?.linkedIDs = links.leaderboards
        }
        for (vendorID, challenge) in state.challenges {
            guard let board = await catalog.challengeLeaderboard(
                challengeID: challenge.id,
                leaderboardsByResourceID: boardsByResourceID) else { continue }
            state.challenges[vendorID]?.linkedIDs = [board]
        }

        // The default leaderboard comes back as a resource id, and the tab
        // names boards by the identifier the game passes to GameKit.
        if let boardID = detail.defaultLeaderboardID {
            state.detail?.defaultLeaderboardVendorID = boardsByResourceID[boardID]
        }

        // Matchmaking belongs to the account rather than to the app, like the
        // groups above. It fails on its own: an empty map that the plan read
        // as truth would create every rule set a second time, so a failure
        // names itself and the planner marks those steps unverified.
        let matchmaking = AppleGameCenterMatchmakingClient(api: api)
        if let sets = try? await matchmaking.ruleSets() {
            state.ruleSets = sets
            state.queues = (try? await matchmaking.queues()) ?? [:]
        } else {
            state.unreadFamilies.insert("matchmaking")
        }

        result.gameCenter = state
    }

    /// Whether an error is Apple answering "there is nothing here".
    ///
    /// The detail read is the one place the difference decides behaviour: a 404
    /// is every app that is not a game, and anything else has to stop the plan
    /// from creating a second configuration against a detail that exists.
    ///
    /// It matches the status code and not the message. The message is
    /// localized and comes partly from Apple's own `detail` string, so a reader
    /// that grepped it for "404" would answer differently on a French Mac and
    /// would take any error whose text merely mentioned the number.
    private static func isNotFound(_ error: any Error) -> Bool {
        guard case ConnectionError.http(let status, _) = error else { return false }
        return status == 404
    }

    /// The images and the videos one live localization shows: the URLs for the
    /// screen, and the screenshot checksums for the plan.
    ///
    /// A bucket the draft already filled is left alone on the URL side, so what
    /// the developer is about to send always wins the screen, and a locale the
    /// draft has not touched shows the store instead of an empty grid.
    ///
    /// The checksums take no such care and land in a map of their own.
    /// `startingScreenshotOrder` picks the draft first and reaches this only
    /// when no draft exists, so there is nothing here to leave alone.
    ///
    /// Both reads are optional. A failure costs the pictures, never the plan.
    /// It costs the skip too: an unreadable live set reads as "no checksums",
    /// which re-uploads a set that already matched. That is the safe way round.
    static func readLiveMedia(localizationID: String, locale: String, api: StoreAPI,
                              into result: inout ActualState.Apple) async {
        if let payload = try? await api.apple(
            "GET", "/v1/appStoreVersionLocalizations/\(localizationID)"
                + "/appScreenshotSets?include=appScreenshots&limit=50") {
            let sets = JSON(data: payload.data)
            let assets = StoreImportReader.appleAssets(
                sets, locale: locale,
                itemType: "appScreenshots", kindKey: "screenshotDisplayType")
            result.liveAssets += assets
            fill(&result.screenshotURLs, locale: locale, with: assets)
            for (type, checksums) in StoreImportReader.appleChecksums(sets) {
                result.liveScreenshotChecksumOrder["\(locale)/\(type)"] = checksums
            }
        }
        if let payload = try? await api.apple(
            "GET", "/v1/appStoreVersionLocalizations/\(localizationID)"
                + "/appPreviewSets?include=appPreviews&limit=50") {
            fill(&result.previewURLs, locale: locale, with: StoreImportReader.appleAssets(
                JSON(data: payload.data), locale: locale,
                itemType: "appPreviews", kindKey: "previewType"))
        }
    }

    /// The bucket the draft already filled is the one to leave alone, and it
    /// has to be read before this loop starts appending. Asking `target` per
    /// asset made the first live screenshot of a bucket block the other four,
    /// so a five shot set showed one shot.
    private static func fill(_ target: inout [String: [URL]], locale: String,
                             with assets: [ImportedStoreAsset]) {
        let drafted = Set(target.keys)
        for asset in assets {
            let key = "\(locale)/\(asset.kind)"
            guard !drafted.contains(key) else { continue }
            target[key, default: []].append(asset.url)
        }
    }

    /// The marketing version of every build train, keyed by the
    /// `preReleaseVersions` id that a build points at.
    ///
    /// A train that reports another platform is dropped, because an app that
    /// ships iOS and macOS carries two trains under one version string and
    /// only one of them belongs to this run.
    static func appleTrains(_ builds: JSON, platform: String?) -> [String: String] {
        builds["included"].array
            .filter { $0["type"].string == "preReleaseVersions" }
            .reduce(into: [:]) { result, item in
                guard let id = item["id"].string,
                      let version = item["attributes"]["version"].string else { return }
                guard platform == nil
                    || item["attributes"]["platform"].string == nil
                    || item["attributes"]["platform"].string == platform else { return }
                result[id] = version
            }
    }

    /// The words of one `appStoreVersionLocalizations` record.
    ///
    /// The draft and the live version are read through this one mapping, so a
    /// field added to one is never missing from the other.
    static func versionLocale(_ item: JSON)
        -> (locale: String, value: ActualState.Apple.VersionLocale)? {
        let attributes = item["attributes"]
        guard let locale = attributes["locale"].string else { return nil }
        var value = ActualState.Apple.VersionLocale()
        value.id = item["id"].string
        value.description = attributes["description"].string
        value.whatsNew = attributes["whatsNew"].string
        value.keywords = attributes["keywords"].string
        value.promotionalText = attributes["promotionalText"].string
        value.supportUrl = attributes["supportUrl"].string
        value.marketingUrl = attributes["marketingUrl"].string
        return (locale, value)
    }

    static func readPreviews(_ payload: JSON, locale: String,
                             into result: inout ActualState.Apple) {
        let byItem = StoreImportReader.appleBuckets(
            payload, itemType: "appPreviews", kindKey: "previewType")
        for included in payload["included"].array
        where included["type"].string == "appPreviews" {
            guard let id = included["id"].string, let type = byItem[id] else { continue }
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

    /// The price in force now, out of a manual price list.
    ///
    /// A schedule carries the price that ended last month and the one that
    /// starts next quarter beside the one a customer pays today. The row with
    /// no end date is the one on sale, which is also the shape the apply
    /// writes: `startDate` and `endDate` both null.
    static func currentPrice(_ payload: JSON) -> Decimal? {
        var amounts: [String: Decimal] = [:]
        for item in payload["included"].array where item["type"].string == "appPricePoints" {
            guard let id = item["id"].string,
                  let amount = item["attributes"]["customerPrice"].string
                    .flatMap({ Price.amount(from: $0) }) else { continue }
            amounts[id] = amount
        }
        let rows = payload["data"].array
        let live = rows.first { $0["attributes"]["endDate"].string == nil } ?? rows.first
        return live?["relationships"]["appPricePoint"]["data"]["id"].string
            .flatMap { amounts[$0] }
    }
}
