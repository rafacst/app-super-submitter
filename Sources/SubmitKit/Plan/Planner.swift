import Foundation

/// The manifest, against what the stores hold. Spec section 7.2.
///
/// The output is the list of operations that the runner performs. Tab 7 draws
/// it as a diff and tab 8 draws it as a step list, so the two screens can
/// never disagree about what a run does.
///
/// `// ponytail: one model for the diff and the run. Two models drift, and the
/// // second one always drifts toward a lie.`
public enum Planner {

    public struct Input: Sendable {
        public var manifest: Manifest
        public var actual: ActualState
        public var stores: Set<Store>
        public var root: URL?
        /// What tab 2 read out of the builds. The build rules in section 10.3
        /// compare these to the manifest and to the stores.
        public var packages: [AppPackage.Kind: AppPackage]

        public init(manifest: Manifest, actual: ActualState, stores: Set<Store>,
                    root: URL? = nil, packages: [AppPackage.Kind: AppPackage] = [:]) {
            self.manifest = manifest
            self.actual = actual
            self.stores = stores
            self.root = root
            self.packages = packages
        }
    }

    public static func plan(_ input: Input) -> PlanResult {
        var result = PlanResult()
        result.readAt = input.actual.readAt
        result.readFailures = input.actual.failures
        if input.stores.contains(.apple) { result.steps += appleSteps(input) }
        if input.stores.contains(.google) { result.steps += googleSteps(input) }
        result.steps += providerSteps(input)
        result.findings = Validator.findings(input)
        markUnverifiedComparisons(&result)
        return result
    }

    // MARK: - Apple, in the order of section 7.3

    private static func appleSteps(_ input: Input) -> [PlanStep] {
        let manifest = input.manifest
        let actual = input.actual.apple
        let versionName = manifest.release?.versionName ?? ""
        var steps: [PlanStep] = []

        guard let appID = manifest.apps.apple?.appId, !appID.isEmpty else { return [] }

        // 1 and 2. The version.
        if !versionName.isEmpty {
            let current = actual?.versionString
            if current == nil {
                steps.append(PlanStep(
                    id: "apple.version", system: .apple, kind: .add,
                    summary: "version \(versionName) (PREPARE_FOR_SUBMISSION)",
                    title: "Create the version \(versionName)",
                    requests: [RequestSketch("POST", "/v1/appStoreVersions")],
                    operation: .appleEnsureVersion(versionName)))
            } else if current != versionName {
                steps.append(PlanStep(
                    id: "apple.version", system: .apple, kind: .change,
                    summary: "version \(current ?? "") → \(versionName)",
                    title: "Set the version to \(versionName)",
                    requests: [RequestSketch("PATCH", "/v1/appStoreVersions/{id}")],
                    operation: .appleEnsureVersion(versionName)))
            }
        }

        if manifest.release?.apple?.releaseType != nil {
            steps.append(PlanStep(
                id: "apple.versionAttributes", system: .apple, kind: .change,
                summary: "releaseType \(manifest.release?.apple?.releaseType?.rawValue ?? "")",
                title: "Write the release type",
                requests: [RequestSketch("PATCH", "/v1/appStoreVersions/{id}")],
                operation: .appleVersionAttributes))
        }

        // 3. The categories.
        let primary = manifest.review?.applePrimaryCategory ?? ""
        let secondary = manifest.review?.appleSecondaryCategory ?? ""
        if !primary.isEmpty,
           primary != actual?.primaryCategory || secondary != (actual?.secondaryCategory ?? "") {
            steps.append(PlanStep(
                id: "apple.categories", system: .apple, kind: .change,
                summary: "categories \(([primary, secondary].filter { !$0.isEmpty }).joined(separator: ", "))",
                title: "Write the app information",
                requests: [RequestSketch("PATCH", "/v1/appInfos/{id}")],
                operation: .appleCategories))
        }

        // 4 and 5. The two localization resources.
        for code in (manifest.listing?.locales.keys ?? [:].keys).sorted() {
            let info = actual?.infoLocales[code]
            var infoChanges: [String] = []
            appendChange(&infoChanges, "name", manifest.listingText(locale: code, field: .name),
                         info?.name)
            appendChange(&infoChanges, "subtitle",
                         managedText(manifest, code, .subtitle), info?.subtitle)
            appendChange(&infoChanges, "privacyPolicyUrl",
                         managedText(manifest, code, .privacyPolicyURL), info?.privacyPolicyUrl)
            appendChange(&infoChanges, "privacyPolicyText",
                         managedText(manifest, code, .privacyPolicyText), info?.privacyPolicyText)
            appendChange(&infoChanges, "privacyChoicesUrl",
                         managedText(manifest, code, .privacyChoicesURL), info?.privacyChoicesUrl)
            if !infoChanges.isEmpty {
                steps.append(PlanStep(
                    id: "apple.info.\(code)", system: .apple, kind: info == nil ? .add : .change,
                    summary: "\(code)  \(infoChanges.joined(separator: ", "))",
                    title: "Write the \(code) app information",
                    requests: [RequestSketch(info == nil ? "POST" : "PATCH",
                                             "/v1/appInfoLocalizations")],
                    operation: .appleInfoLocale(code)))
            }

            let version = actual?.versionLocales[code]
            var versionChanges: [String] = []
            appendChange(&versionChanges, "description",
                         managedText(manifest, code, .description), version?.description)
            appendChange(&versionChanges, "whatsNew",
                         managedText(manifest, code, .whatsNew), version?.whatsNew)
            appendChange(&versionChanges, "keywords",
                         managedText(manifest, code, .keywords), version?.keywords)
            appendChange(&versionChanges, "promotionalText",
                         managedText(manifest, code, .promotionalText), version?.promotionalText)
            appendChange(&versionChanges, "supportUrl",
                         managedText(manifest, code, .supportURL), version?.supportUrl)
            appendChange(&versionChanges, "marketingUrl",
                         managedText(manifest, code, .marketingURL), version?.marketingUrl)
            if !versionChanges.isEmpty {
                steps.append(PlanStep(
                    id: "apple.locale.\(code)", system: .apple,
                    kind: version == nil ? .add : .change,
                    summary: "\(code)  \(versionChanges.joined(separator: ", "))",
                    title: "Write the \(code) listing",
                    requests: [RequestSketch(version == nil ? "POST" : "PATCH",
                                             "/v1/appStoreVersionLocalizations")],
                    operation: .appleVersionLocale(code)))
            }
        }

        // 6. The screenshots and the previews.
        steps += mediaSteps(input, store: .apple)

        // 7 and 8. The build.
        if let path = applePath(manifest), let file = resolve(path, root: input.root) {
            let bytes = fileSize(file)
            steps.append(PlanStep(
                id: "apple.build", system: .apple, kind: .add,
                summary: "build \(file.lastPathComponent)  ·  \(bytesText(bytes))",
                title: "Upload the build \(file.lastPathComponent)",
                requests: [RequestSketch("POST", "/v1/buildUploads"),
                           RequestSketch("POST", "/v1/buildUploadFiles")],
                operation: .appleBuildUpload(path: path, bytes: bytes),
                uploadCount: 1, uploadBytes: bytes))
            steps.append(PlanStep(
                id: "apple.attachBuild", system: .apple, kind: .change,
                summary: "attach the build to \(versionName)",
                title: "Attach the build to the version",
                requests: [RequestSketch("PATCH",
                                         "/v1/appStoreVersions/{id}/relationships/build")],
                operation: .appleAttachBuild))
        }
        if let encryption = manifest.review?.usesNonExemptEncryption,
           encryption != actual?.buildUsesNonExemptEncryption {
            steps.append(PlanStep(
                id: "apple.buildCompliance", system: .apple, kind: .change,
                summary: "export compliance declaration",
                title: "Write the build export compliance declaration",
                requests: [RequestSketch("PATCH", "/v1/builds/{id}")],
                operation: .appleBuildCompliance))
        }

        // 9. The review details.
        if let review = manifest.review,
           review.contactEmail?.isEmpty == false || review.notes?.isEmpty == false
            || review.attachments?.isEmpty == false {
            steps.append(PlanStep(
                id: "apple.reviewDetails", system: .apple,
                kind: actual?.reviewDetailId == nil ? .add : .change,
                summary: "review details  \(review.contactEmail ?? "")",
                title: "Write the review details",
                requests: [RequestSketch(actual?.reviewDetailId == nil ? "POST" : "PATCH",
                                         "/v1/appStoreReviewDetails")],
                operation: .appleReviewDetails))
        }

        // 10. The age rating.
        if manifest.review?.ageRatingAnswers?.isEmpty == false
            || manifest.review?.kidsAgeBand?.isEmpty == false {
            let answerCount = manifest.review?.ageRatingAnswers?.count ?? 0
            steps.append(PlanStep(
                id: "apple.ageRating", system: .apple, kind: .change,
                summary: "age rating  \(answerCount) answers",
                title: "Write the age rating answers",
                requests: [RequestSketch("PATCH", "/v1/ageRatingDeclarations/{id}")],
                operation: .appleAgeRating))
        }

        // 11. The purchases. The step counts the purchases alone, because the
        // subscriptions take their own step and their own resources.
        let purchaseCount = manifest.purchases?.count ?? 0
        if purchaseCount > 0 {
            steps.append(PlanStep(
                id: "apple.purchases", system: .apple, kind: .change,
                summary: "\(purchaseCount) purchases in the catalog",
                title: "Write \(purchaseCount) purchases",
                requests: [RequestSketch("GET", "/v1/apps/{id}/inAppPurchasesV2"),
                           RequestSketch("POST", "/v2/inAppPurchases"),
                           RequestSketch("POST", "/v1/inAppPurchasePriceSchedules"),
                           RequestSketch("POST", "/v2/inAppPurchaseLocalizations"),
                           RequestSketch("POST", "/v1/inAppPurchaseAvailabilities"),
                           RequestSketch("POST", "/v1/promotedPurchases")],
                operation: .applePurchases))
        }

        // 11b. The subscription catalog, then the offers on top of it.
        let planCount = manifest.subscriptions?.reduce(0) { $0 + $1.plans.count } ?? 0
        if planCount > 0 {
            steps.append(PlanStep(
                id: "apple.subscriptions", system: .apple, kind: .change,
                summary: "\(planCount) subscription plans in \(manifest.subscriptions?.count ?? 0) groups",
                title: "Write \(planCount) subscriptions",
                requests: [RequestSketch("POST", "/v1/subscriptionGroups"),
                           RequestSketch("POST", "/v1/subscriptions"),
                           RequestSketch("POST", "/v1/subscriptionLocalizations"),
                           RequestSketch("POST", "/v1/subscriptionPrices")],
                operation: .appleSubscriptions))
        }
        let offerCount = manifest.subscriptions?
            .reduce(0) { $0 + $1.plans.reduce(0) { $0 + ($1.offers?.count ?? 0) } } ?? 0
        if offerCount > 0 {
            steps.append(PlanStep(
                id: "apple.subscriptionOffers", system: .apple, kind: .change,
                summary: "\(offerCount) subscription offers",
                title: "Write \(offerCount) subscription offers",
                requests: [RequestSketch("POST", "/v1/subscriptionIntroductoryOffers"),
                           RequestSketch("POST", "/v1/subscriptionOfferCodes"),
                           RequestSketch("POST", "/v1/subscriptionPromotionalOffers"),
                           RequestSketch("POST", "/v1/winBackOffers")],
                operation: .appleSubscriptionOffers))
        }
        if let days = (manifest.subscriptions ?? []).compactMap(\.gracePeriodDays).first {
            steps.append(PlanStep(
                id: "apple.gracePeriod", system: .apple, kind: .change,
                summary: "billing grace period \(AppleDurations.gracePeriod(days: days))",
                title: "Write the billing grace period",
                requests: [RequestSketch("PATCH", "/v1/subscriptionGracePeriods/{id}")],
                operation: .appleGracePeriod))
        }

        steps += appleMarketingSteps(input)

        // 12 and 13.
        if manifest.release?.apple?.phasedRelease == true,
           (manifest.release?.apple?.phasedReleaseState?.rawValue ?? "ACTIVE")
            != actual?.phasedReleaseState {
            steps.append(PlanStep(
                id: "apple.phased", system: .apple, kind: .add,
                summary: "phased release over 7 days",
                title: "Turn on the phased release",
                requests: [RequestSketch("POST", "/v1/appStoreVersionPhasedReleases")],
                operation: .applePhasedRelease))
        }
        if let pricing = manifest.pricing,
           pricing.base.amount != actual?.currentPriceAmount {
            steps.append(PlanStep(
                id: "apple.appPrice", system: .apple, kind: .change,
                summary: "app price schedule",
                title: "Write the app price schedule",
                requests: [RequestSketch("POST", "/v1/appPriceSchedules")],
                operation: .appleAppPrice))
        }
        let wantedAvailability = Dictionary(uniqueKeysWithValues:
            (manifest.pricing?.territories ?? []).map { ($0.territory, $0.available) })
        let autoAvailabilityDiffers = manifest.pricing?.autoConvertOtherTerritories.map {
            $0 != actual?.availableInNewTerritories
        } ?? false
        let territoryAvailabilityDiffers = wantedAvailability.contains {
            actual?.territoryAvailability[$0.key] != $0.value
        }
        if autoAvailabilityDiffers || territoryAvailabilityDiffers {
            steps.append(PlanStep(
                id: "apple.availability", system: .apple, kind: .change,
                summary: "territory availability",
                title: "Write the territory availability",
                requests: [RequestSketch("POST", "/v2/appAvailabilities")],
                operation: .appleAvailability))
        }
        return steps
    }

    // MARK: - The App Store marketing resources

    /// Each block writes only when the manifest holds it. None of these has a
    /// Google twin, so none of them appears on the Google side.
    private static func appleMarketingSteps(_ input: Input) -> [PlanStep] {
        guard let marketing = input.manifest.marketing else { return [] }
        var steps: [PlanStep] = []

        if let pages = marketing.customProductPages, !pages.isEmpty {
            steps.append(PlanStep(
                id: "apple.customProductPages", system: .apple, kind: .change,
                summary: "\(pages.count) custom product pages",
                title: "Write \(pages.count) custom product pages",
                requests: [RequestSketch("POST", "/v1/appCustomProductPages"),
                           RequestSketch("POST", "/v1/appCustomProductPageLocalizations")],
                operation: .appleCustomProductPages))
        }
        if let experiments = marketing.experiments, !experiments.isEmpty {
            let treatments = experiments.reduce(0) { $0 + $1.treatments.count }
            steps.append(PlanStep(
                id: "apple.experiments", system: .apple, kind: .change,
                summary: "\(experiments.count) experiments  ·  \(treatments) treatments (not started)",
                title: "Write \(experiments.count) product page experiments",
                requests: [RequestSketch("POST", "/v2/appStoreVersionExperiments"),
                           RequestSketch("POST", "/v1/appStoreVersionExperimentTreatments")],
                operation: .appleExperiments))
        }
        if let events = marketing.events, !events.isEmpty {
            steps.append(PlanStep(
                id: "apple.events", system: .apple, kind: .change,
                summary: "\(events.count) in-app events",
                title: "Write \(events.count) in-app events",
                requests: [RequestSketch("POST", "/v1/appEvents"),
                           RequestSketch("POST", "/v1/appEventLocalizations")],
                operation: .appleAppEvents))
        }
        if let eula = marketing.eula, !eula.text.isEmpty {
            steps.append(PlanStep(
                id: "apple.eula", system: .apple, kind: .change,
                summary: "licence agreement  \(eula.text.count) characters",
                title: "Write the licence agreement",
                requests: [RequestSketch("POST", "/v1/endUserLicenseAgreements")],
                operation: .appleEULA))
        }
        if let path = marketing.routingCoverage, let file = resolve(path, root: input.root) {
            let bytes = fileSize(file)
            steps.append(PlanStep(
                id: "apple.routingCoverage", system: .apple, kind: .add,
                summary: "routing coverage  \(file.lastPathComponent)  ·  \(bytesText(bytes))",
                title: "Upload the routing app coverage",
                requests: [RequestSketch("POST", "/v1/routingAppCoverages")],
                operation: .appleRoutingCoverage(path: path, bytes: bytes),
                uploadCount: 1, uploadBytes: bytes))
        }
        if let nomination = marketing.nomination {
            steps.append(PlanStep(
                id: "apple.nomination", system: .apple, kind: .change,
                summary: "nomination  \(nomination.name)",
                title: "Write the featuring nomination",
                requests: [RequestSketch("POST", "/v1/nominations")],
                operation: .appleNomination))
        }
        if let accessibility = marketing.accessibility, !accessibility.supports.isEmpty {
            steps.append(PlanStep(
                id: "apple.accessibility", system: .apple, kind: .change,
                summary: "accessibility  \(accessibility.supports.count) features",
                title: "Write the accessibility declaration",
                requests: [RequestSketch("POST", "/v1/accessibilityDeclarations")],
                operation: .appleAccessibility))
        }
        if marketing.appClip != nil {
            steps.append(PlanStep(
                id: "apple.appClip", system: .apple, kind: .change,
                summary: "app clip default experience",
                title: "Write the App Clip default experience",
                requests: [RequestSketch("POST", "/v1/appClipDefaultExperiences"),
                           RequestSketch("POST", "/v1/appClipDefaultExperienceLocalizations")],
                operation: .appleAppClip))
        }
        return steps
    }

    // MARK: - Google, in the order of section 7.4

    private static func googleSteps(_ input: Input) -> [PlanStep] {
        let manifest = input.manifest
        let actual = input.actual.google
        guard let packageName = manifest.apps.google?.packageName, !packageName.isEmpty else {
            return []
        }
        var body: [PlanStep] = []

        for code in (manifest.listing?.locales.keys ?? [:].keys).sorted() {
            let listing = actual?.listings[code]
            var changes: [String] = []
            appendChange(&changes, "title", manifest.listingText(locale: code, field: .name),
                         listing?.title)
            appendChange(&changes, "shortDescription", googleShortDescription(manifest, code),
                         listing?.shortDescription)
            appendChange(&changes, "fullDescription", managedText(manifest, code, .description),
                         listing?.fullDescription)
            appendChange(&changes, "video", managedText(manifest, code, .googleVideo),
                         listing?.video)
            if !changes.isEmpty {
                body.append(PlanStep(
                    id: "google.listing.\(code)", system: .google,
                    kind: listing == nil ? .add : .change,
                    summary: "\(code)  \(changes.joined(separator: ", "))",
                    title: "Write the \(code) listing",
                    requests: [RequestSketch("PUT", "/edits/{editId}/listings/\(code)")],
                    operation: .googleListing(code)))
            }
        }

        let website = manifest.listing.map {
            manifest.listingText(locale: $0.defaultLocale, field: .supportURL)
        } ?? ""
        let emailDiffers = manifest.review?.contactEmail.map {
            $0 != actual?.contactEmail
        } ?? false
        let phoneDiffers = manifest.review?.contactPhone.map {
            $0 != actual?.contactPhone
        } ?? false
        let contactDiffers = emailDiffers || phoneDiffers
            || (!website.isEmpty && website != actual?.contactWebsite)
        if contactDiffers {
            body.append(PlanStep(
                id: "google.details", system: .google, kind: .change,
                summary: "contact  \(manifest.review?.contactEmail ?? "")",
                title: "Write the contact details",
                requests: [RequestSketch("PATCH", "/edits/{editId}/details")],
                operation: .googleDetails))
        }

        if manifest.review?.dataSafetyCSV?.isEmpty == false
            || manifest.review?.dataSafetyAnswers?.isEmpty == false {
            body.append(PlanStep(
                id: "google.dataSafety", system: .google, kind: .change,
                summary: "data safety declaration",
                title: "Write the Google data safety declaration",
                requests: [RequestSketch("POST", "/applications/{package}/dataSafety")],
                operation: .googleDataSafety))
        }

        let wantedLocales = Set(manifest.listing?.locales.keys ?? [:].keys)
        for locale in Set(actual?.listings.keys ?? [:].keys).subtracting(wantedLocales).sorted() {
            body.append(PlanStep(
                id: "google.deleteListing.\(locale)", system: .google, kind: .remove,
                summary: "listing \(locale) delete",
                title: "Delete the \(locale) listing",
                requests: [RequestSketch("DELETE", "/edits/{editId}/listings/\(locale)")],
                operation: .googleDeleteListing(locale)))
        }

        body += mediaSteps(input, store: .google)

        if let path = manifest.release?.build?.android, let file = resolve(path, root: input.root) {
            let bytes = fileSize(file)
            body.append(PlanStep(
                id: "google.bundle", system: .google, kind: .add,
                summary: "bundle \(file.lastPathComponent)  ·  \(bytesText(bytes))",
                title: "Upload the bundle \(file.lastPathComponent)",
                requests: [RequestSketch("POST", "/edits/{editId}/bundles")],
                operation: .googleBundleUpload(path: path, bytes: bytes),
                uploadCount: 1, uploadBytes: bytes))
        }

        if let path = manifest.release?.build?.androidApk,
           let file = resolve(path, root: input.root) {
            let bytes = fileSize(file)
            body.append(PlanStep(
                id: "google.apk", system: .google, kind: .add,
                summary: "apk \(file.lastPathComponent)  ·  \(bytesText(bytes))",
                title: "Upload the APK \(file.lastPathComponent)",
                requests: [RequestSketch("POST", "/edits/{editId}/apks")],
                operation: .googleApkUpload(path: path, bytes: bytes),
                uploadCount: 1, uploadBytes: bytes))
        }

        if let external = manifest.release?.google?.externalApk {
            body.append(PlanStep(
                id: "google.externalApk", system: .google, kind: .add,
                summary: "externally hosted apk  \(external.versionName) (\(external.versionCode))",
                title: "Register the externally hosted APK",
                requests: [RequestSketch("POST", "/edits/{editId}/apks/externallyHosted")],
                operation: .googleExternalApk))
        }

        // The mapping file and the symbols attach to an uploaded artifact, so
        // they follow every upload step.
        for (kind, path, label) in [
            ("proguard", manifest.release?.google?.mappingFile, "the mapping file"),
            ("nativeCode", manifest.release?.google?.nativeDebugSymbols, "the native symbols"),
        ] {
            guard let path, let file = resolve(path, root: input.root) else { continue }
            let bytes = fileSize(file)
            body.append(PlanStep(
                id: "google.deobfuscation.\(kind)", system: .google, kind: .add,
                summary: "\(label)  \(file.lastPathComponent)  ·  \(bytesText(bytes))",
                title: "Upload \(label)",
                requests: [RequestSketch("POST",
                                         "/edits/{editId}/apks/{code}/deobfuscationFiles/\(kind)")],
                operation: .googleDeobfuscation(kind: kind, path: path, bytes: bytes),
                uploadCount: 1, uploadBytes: bytes))
        }

        for (kind, path) in [("main", manifest.release?.google?.expansionFileMain),
                             ("patch", manifest.release?.google?.expansionFilePatch)] {
            guard let path, let file = resolve(path, root: input.root) else { continue }
            let bytes = fileSize(file)
            body.append(PlanStep(
                id: "google.expansion.\(kind)", system: .google, kind: .add,
                summary: "\(kind) expansion file  \(file.lastPathComponent)  ·  \(bytesText(bytes))",
                title: "Upload the \(kind) expansion file",
                requests: [RequestSketch("POST",
                                         "/edits/{editId}/apks/{code}/expansionFiles/\(kind)")],
                operation: .googleExpansionFile(kind: kind, path: path, bytes: bytes),
                uploadCount: 1, uploadBytes: bytes))
        }

        // Google owns the four standard tracks. Any other name is a custom
        // closed test, and the edit creates it before it writes a release.
        for track in manifest.googleTracks {
            guard !Self.standardGoogleTracks.contains(track),
                  actual?.tracks[track] == nil else { continue }
            body.append(PlanStep(
                id: "google.createTrack.\(track)", system: .google, kind: .add,
                summary: "track \(track)  create",
                title: "Create the \(track) track",
                requests: [RequestSketch("POST", "/edits/{editId}/tracks")],
                operation: .googleCreateTrack(track)))
        }

        let countries = (manifest.release?.google?.countries ?? []).filter { !$0.isEmpty }
        for track in manifest.googleTracks {
            var summary = "track \(track)  release draft"
            if !countries.isEmpty {
                summary += "  ·  \(countries.count) countries"
                // The country availability read says what Google sells today,
                // so the diff line shows both sides instead of the wanted
                // side alone.
                if let live = actual?.tracks[track]?.countries, Set(live) != Set(countries) {
                    summary += " (now \(live.count))"
                }
            }
            body.append(PlanStep(
                id: "google.track.\(track)", system: .google, kind: .change,
                summary: summary,
                title: "Write the \(track) track, draft",
                requests: [RequestSketch("PATCH", "/edits/{editId}/tracks/\(track)")],
                operation: .googleTrack(track)))
        }

        // The tester groups of a closed track. Google replaces the whole list,
        // so a track that already holds the wanted groups needs no write.
        for (track, wanted) in (manifest.release?.google?.testers ?? [:]).sorted(by: {
            $0.key < $1.key
        }) {
            let groups = wanted.map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let live = actual?.tracks[track]?.testers ?? []
            guard actual == nil || Set(live) != Set(groups) else { continue }
            body.append(PlanStep(
                id: "google.testers.\(track)", system: .google,
                kind: groups.isEmpty ? .remove : (live.isEmpty ? .add : .change),
                summary: "track \(track)  \(groups.count) tester groups",
                title: "Write the \(track) tester groups",
                requests: [RequestSketch("PUT", "/edits/{editId}/testers/\(track)")],
                operation: .googleTesters(track: track),
                comparison: actual == nil ? .unverified : .verified))
        }

        // The per-product read carries the titles, the prices, and the base
        // plans, so the plan names the products that differ instead of always
        // saying "write every product".
        // The batch update carries every product, because it is idempotent and
        // one call costs less than a call per product. The summary names the
        // ones that differ, and the title says that the write is the whole
        // catalog.
        let catalog = googleCatalogDiff(manifest, actual)
        if !catalog.changes.isEmpty {
            body.append(PlanStep(
                id: "google.products", system: .google, kind: .change,
                summary: catalog.summary,
                title: "Write the catalog, \(catalog.changes.count) products differ",
                requests: [RequestSketch("POST", "/monetization/oneTimeProducts:batchUpdate"),
                           RequestSketch("POST", "/monetization/subscriptions:batchUpdate")],
                operation: .googleProducts,
                comparison: catalog.verified ? .verified : .unverified))
        }
        body += googleCatalogSteps(input)

        if let path = manifest.release?.google?.deviceTierConfig,
           resolve(path, root: input.root) != nil {
            body.append(PlanStep(
                id: "google.deviceTierConfig", system: .google, kind: .add,
                summary: "device tier configuration",
                title: "Create the device tier configuration",
                requests: [RequestSketch("POST", "/deviceTierConfigs")],
                operation: .googleDeviceTierConfig(path: path)))
        }

        guard !body.isEmpty else { return [] }

        // An edit wraps the whole Google side. It opens first and it commits
        // last, and the run deletes it on any failure before the commit.
        let open = PlanStep(
            id: "google.openEdit", system: .google, kind: .add,
            summary: "open one edit",
            title: "Open the edit",
            requests: [RequestSketch("POST", "/edits")],
            operation: .googleOpenEdit)
        let validate = PlanStep(
            id: "google.validate", system: .google, kind: .change,
            summary: "validate the edit",
            title: "Validate the edit",
            requests: [RequestSketch("POST", "/edits/{editId}:validate")],
            operation: .googleValidate)
        let commit = PlanStep(
            id: "google.commit", system: .google, kind: .change,
            summary: "commit, changes not sent for review",
            title: "Commit, changes not sent for review",
            requests: [RequestSketch("POST",
                                     "/edits/{editId}:commit?changesNotSentForReview=true")],
            operation: .googleCommit)
        return [open] + body + [validate, commit]
    }

    /// The offers of one product whose state differs from the store.
    ///
    /// Returns nil when no offer names `active`, and nil when every offer
    /// already holds the wanted state. Google reports `ACTIVE` for a live
    /// offer, so anything else counts as stopped.
    static func googleOfferStateSummary(_ offers: [Manifest.Offer], productId: String,
                                        actual: ActualState.Google?)
        -> (summary: String, count: Int, comparison: ComparisonConfidence)? {
        let wanted = offers.filter { $0.active != nil }
        guard !wanted.isEmpty else { return nil }
        let states = actual?.catalog[productId]?.offerStates
        // No read means no comparison. The switch still runs, and the plan
        // says that nobody verified it.
        guard let states else {
            return ("\(wanted.count) offer switches on \(productId)", wanted.count, .unverified)
        }
        let differs = wanted.filter { offer in
            (states[offer.id] == "ACTIVE") != (offer.active == true)
        }
        guard !differs.isEmpty else { return nil }
        let activate = differs.filter { $0.active == true }.count
        let stop = differs.count - activate
        var parts: [String] = []
        if activate > 0 { parts.append("activate \(activate)") }
        if stop > 0 { parts.append("stop \(stop)") }
        return ("offers on \(productId)  \(parts.joined(separator: ", "))",
                differs.count, .verified)
    }

    // MARK: - The Google catalog diff

    /// Which products differ from the manifest, and in which fields.
    ///
    /// `verified` is false when a wanted product exists in the store and its
    /// detail could not be read. The plan then says `unverified` rather than
    /// claim a diff that nobody checked.
    static func googleCatalogDiff(_ manifest: Manifest, _ actual: ActualState.Google?)
        -> (changes: [String], summary: String, verified: Bool) {
        var changes: [String] = []
        var verified = actual != nil
        let defaultLocale = manifest.listing?.defaultLocale ?? "en-US"

        func compare(id: String, exists: Bool, wanted: ActualState.Google.CatalogProduct) {
            guard exists else {
                changes.append("\(id)  create")
                return
            }
            guard let live = actual?.catalog[id] else {
                // The store holds the product and the detail read failed.
                verified = false
                changes.append("\(id)  unread")
                return
            }
            var fields: [String] = []
            for (locale, text) in wanted.listings.sorted(by: { $0.key < $1.key }) {
                let current = live.listings[locale]
                if let title = text.title, title != current?.title { fields.append("title") }
                if let detail = text.description, detail != current?.description {
                    fields.append("description")
                }
            }
            for (region, price) in wanted.prices where live.prices[region] != price {
                fields.append("price")
            }
            if let plan = wanted.basePlanId, plan != live.basePlanId {
                fields.append("base plan")
            }
            if let duration = wanted.basePlanDuration, duration != live.basePlanDuration {
                fields.append("duration")
            }
            let unique = NSOrderedSet(array: fields).compactMap { $0 as? String }
            guard !unique.isEmpty else { return }
            changes.append("\(id)  \(unique.joined(separator: ", "))")
        }

        for purchase in manifest.purchases ?? [] {
            var wanted = ActualState.Google.CatalogProduct()
            wanted.productId = purchase.id
            wanted.listings = googleWantedListings(
                locales: purchase.locales, fallbackName: purchase.name ?? purchase.id,
                defaultLocale: defaultLocale)
            if let price = purchase.price {
                wanted.prices[price.territory ?? "US"] = googlePriceText(price)
            }
            compare(id: purchase.id,
                    exists: actual?.oneTimeProductIds.contains(purchase.id) ?? false,
                    wanted: wanted)
        }

        for group in manifest.subscriptions ?? [] {
            for plan in group.plans {
                var wanted = ActualState.Google.CatalogProduct()
                wanted.productId = plan.id
                wanted.listings = googleWantedListings(
                    locales: plan.locales ?? group.locales,
                    fallbackName: group.groupName ?? group.groupId,
                    defaultLocale: defaultLocale)
                if let price = plan.price {
                    wanted.prices[price.territory ?? "US"] = googlePriceText(price)
                }
                wanted.basePlanId = plan.basePlanId ?? "default"
                wanted.basePlanDuration = plan.duration
                compare(id: plan.id,
                        exists: actual?.subscriptionIds.contains(plan.id) ?? false,
                        wanted: wanted)
            }
        }

        let summary = changes.count <= 3
            ? changes.joined(separator: "  ·  ")
            : "\(changes.count) products differ  ·  \(changes.prefix(2).joined(separator: "  ·  "))  ·  …"
        return (changes, summary, verified)
    }

    /// The titles that the apply writes, in the same shape that
    /// `googleProducts` sends.
    static func googleWantedListings(locales: [String: Manifest.ProductLocale]?,
                                     fallbackName: String, defaultLocale: String)
        -> [String: ActualState.Google.CatalogProduct.ProductListing] {
        var result: [String: ActualState.Google.CatalogProduct.ProductListing] = [:]
        guard let locales, !locales.isEmpty else {
            var listing = ActualState.Google.CatalogProduct.ProductListing()
            listing.title = fallbackName
            result[defaultLocale] = listing
            return result
        }
        for (locale, text) in locales {
            var listing = ActualState.Google.CatalogProduct.ProductListing()
            listing.title = text.name ?? fallbackName
            listing.description = text.description ?? ""
            result[locale] = listing
        }
        return result
    }

    /// The same text that `GoogleCatalogClient` builds from a Google price.
    ///
    /// It runs the amount through the same units and nanos step that the apply
    /// uses, so a decimal that a literal cannot hold exactly compares equal on
    /// both sides.
    static func googlePriceText(_ price: Price) -> String {
        let money = GoogleCatalogClient.nanoUnits(price.amount)
        return GoogleCatalogClient.priceText(currency: price.currency,
                                             units: money.units, nanos: money.nanos)
    }

    // MARK: - The Google catalog states, offers, and archives

    /// These calls sit outside the edit, the same as the two batch updates.
    /// Google keys them by the product, so each product takes its own step
    /// and a failure names the product that failed.
    private static func googleCatalogSteps(_ input: Input) -> [PlanStep] {
        let manifest = input.manifest
        var steps: [PlanStep] = []

        for purchase in manifest.purchases ?? [] {
            if let active = purchase.active {
                steps.append(PlanStep(
                    id: "google.purchaseOptionState.\(purchase.id)", system: .google,
                    kind: .change,
                    summary: "purchase option  \(purchase.id)  \(active ? "activate" : "deactivate")",
                    title: "\(active ? "Activate" : "Deactivate") \(purchase.id)",
                    requests: [RequestSketch(
                        "POST", "/monetization/oneTimeProducts/{id}/purchaseOptions:batchUpdateStates")],
                    operation: .googlePurchaseOptionState(productId: purchase.id,
                                                          purchaseOptionId: purchase.id,
                                                          active: active)))
            }
            if let offers = purchase.offers, !offers.isEmpty {
                steps.append(PlanStep(
                    id: "google.oneTimeOffers.\(purchase.id)", system: .google, kind: .change,
                    summary: "\(offers.count) offers on \(purchase.id)",
                    title: "Write \(offers.count) offers on \(purchase.id)",
                    requests: [RequestSketch(
                        "POST",
                        "/monetization/oneTimeProducts/{id}/purchaseOptions/{option}/offers:batchUpdate")],
                    operation: .googleOneTimeOffers(productId: purchase.id)))
                if let switches = googleOfferStateSummary(offers, productId: purchase.id,
                                                          actual: input.actual.google) {
                    steps.append(PlanStep(
                        id: "google.oneTimeOfferStates.\(purchase.id)", system: .google,
                        kind: .change, summary: switches.summary,
                        title: "Switch \(switches.count) offers on \(purchase.id)",
                        requests: [RequestSketch(
                            "POST",
                            "/monetization/oneTimeProducts/{id}/purchaseOptions/{option}/offers:batchUpdateStates")],
                        operation: .googleOneTimeOfferStates(productId: purchase.id),
                        comparison: switches.comparison))
                }
            }
        }

        for group in manifest.subscriptions ?? [] {
            for plan in group.plans {
                let basePlanId = plan.basePlanId ?? "default"
                if let active = plan.active {
                    steps.append(PlanStep(
                        id: "google.basePlanState.\(plan.id)", system: .google, kind: .change,
                        summary: "base plan  \(basePlanId)  \(active ? "activate" : "deactivate")",
                        title: "\(active ? "Activate" : "Deactivate") the \(basePlanId) base plan",
                        requests: [RequestSketch(
                            "POST",
                            "/monetization/subscriptions/{id}/basePlans/{plan}:\(active ? "activate" : "deactivate")")],
                        operation: .googleBasePlanState(productId: plan.id,
                                                        basePlanId: basePlanId,
                                                        active: active)))
                }
                if let offers = plan.offers, !offers.isEmpty {
                    steps.append(PlanStep(
                        id: "google.subscriptionOffers.\(plan.id)", system: .google, kind: .change,
                        summary: "\(offers.count) offers on \(plan.id)",
                        title: "Write \(offers.count) offers on \(plan.id)",
                        requests: [RequestSketch(
                            "POST",
                            "/monetization/subscriptions/{id}/basePlans/{plan}/offers:batchUpdate")],
                        operation: .googleSubscriptionOffers(productId: plan.id,
                                                             basePlanId: basePlanId)))
                    if let switches = googleOfferStateSummary(offers, productId: plan.id,
                                                              actual: input.actual.google) {
                        steps.append(PlanStep(
                            id: "google.subscriptionOfferStates.\(plan.id)", system: .google,
                            kind: .change, summary: switches.summary,
                            title: "Switch \(switches.count) offers on \(plan.id)",
                            requests: [RequestSketch(
                                "POST",
                                "/monetization/subscriptions/{id}/basePlans/{plan}/offers:batchUpdateStates")],
                            operation: .googleSubscriptionOfferStates(productId: plan.id,
                                                                       basePlanId: basePlanId),
                            comparison: switches.comparison))
                    }
                }
                if plan.migrateExistingSubscribers == true {
                    steps.append(PlanStep(
                        id: "google.migratePrices.\(plan.id)", system: .google, kind: .change,
                        summary: "migrate the existing subscribers of \(plan.id)",
                        title: "Migrate the prices of \(plan.id)",
                        requests: [RequestSketch(
                            "POST",
                            "/monetization/subscriptions/{id}/basePlans:batchMigratePrices")],
                        operation: .googleMigratePrices(productId: plan.id,
                                                        basePlanId: basePlanId)))
                }
            }
        }

        // Spec section 8, rule 6. A subscription that left the manifest is
        // archived, never deleted, because an installed app still asks for it.
        let wanted = Set((manifest.subscriptions ?? []).flatMap { $0.plans.map(\.id) })
        for orphan in (input.actual.google?.subscriptionIds ?? []).subtracting(wanted).sorted() {
            steps.append(PlanStep(
                id: "google.archive.\(orphan)", system: .google, kind: .remove,
                summary: "subscription  \(orphan)  archive",
                title: "Archive the subscription \(orphan)",
                requests: [RequestSketch("POST", "/monetization/subscriptions/{id}:archive")],
                operation: .googleArchiveSubscription(productId: orphan)))
        }
        return steps
    }

    // MARK: - The provider, section 7.8

    private static func providerSteps(_ input: Input) -> [PlanStep] {
        let manifest = input.manifest
        let provider = manifest.monetization?.provider ?? .none
        guard provider != .none else { return [] }
        let actual = input.actual.provider
        var steps: [PlanStep] = []

        // One RevenueCat product per store app. Adapty holds both ids on one
        // product. Spec section 8.1 explains the difference.
        let storeApps: [(key: String, label: String)] = provider == .revenuecat
            ? [(manifest.monetization?.revenuecat?.appIds.appStore ?? "", "app_store"),
               (manifest.monetization?.revenuecat?.appIds.playStore ?? "", "play_store")]
                .filter { !$0.0.isEmpty }
            : [("", "both stores")]

        for product in manifest.productIds {
            for app in storeApps {
                let key = provider == .revenuecat ? "\(product)@\(app.label)" : product
                guard actual?.productIds[key] == nil else { continue }
                steps.append(PlanStep(
                    id: "provider.product.\(key)", system: .provider, kind: .add,
                    summary: "product  \(product)  (\(app.label))",
                    title: "Create the product \(product)",
                    requests: [providerRequest(provider, "create the product")],
                    operation: .providerProduct(storeProductId: product, appId: app.key)))
            }
        }

        for entitlement in manifest.entitlements ?? [] {
            guard actual?.entitlementKeys.contains(entitlement.key) != true else { continue }
            steps.append(PlanStep(
                id: "provider.entitlement.\(entitlement.key)", system: .provider, kind: .add,
                summary: "entitlement  \(entitlement.key)",
                title: "Create the entitlement \(entitlement.key)",
                requests: [providerRequest(provider, "create the entitlement")],
                operation: .providerEntitlement(key: entitlement.key)))
        }

        for entitlement in manifest.entitlements ?? [] {
            let products = manifest.products(for: entitlement.key)
            guard !products.isEmpty else { continue }
            steps.append(PlanStep(
                id: "provider.attach.\(entitlement.key)", system: .provider, kind: .change,
                summary: "entitlement  \(entitlement.key)  attach \(products.count) products",
                title: "Attach \(products.count) products to \(entitlement.key)",
                requests: [providerRequest(provider, "attach the products")],
                operation: .providerAttach(entitlement: entitlement.key, products: products)))
        }

        for offering in manifest.offerings ?? [] {
            let known = actual?.offeringKeys.contains(offering.key) == true
            steps.append(PlanStep(
                id: "provider.offering.\(offering.key)", system: .provider,
                kind: known ? .change : .add,
                summary: "offering  \(offering.key)  \(offering.products?.count ?? 0) packages",
                title: "Write the \(offering.key) offering",
                requests: [providerRequest(provider, "write the offering")],
                operation: .providerOffering(key: offering.key)))
        }

        // Spec section 8, rule 6. The app archives; it never deletes.
        for orphan in (actual?.offeringKeys ?? []).subtracting(
            Set((manifest.offerings ?? []).map(\.key))).sorted() {
            steps.append(PlanStep(
                id: "provider.archive.\(orphan)", system: .provider, kind: .remove,
                summary: "offering  \(orphan)  archive",
                title: "Archive the \(orphan) offering",
                requests: [providerRequest(provider, "archive the offering")],
                operation: .providerArchive(kind: "offering", key: orphan)))
        }
        return steps
    }

    private static func providerRequest(_ provider: Manifest.Provider,
                                        _ what: String) -> RequestSketch {
        provider == .adapty
            ? RequestSketch("adapty", what)
            : RequestSketch("POST", "/v2/projects/{project}/…")
    }

    // MARK: - The media

    private static func mediaSteps(_ input: Input, store: Store) -> [PlanStep] {
        let manifest = input.manifest
        var steps: [PlanStep] = []
        let locales = Array(manifest.media?.screenshots?.keys ?? [:].keys).sorted()

        for code in locales {
            for deviceClass in Manifest.DeviceClass.allCases {
                let paths = manifest.mediaPaths(locale: code, deviceClass: deviceClass)
                guard !paths.isEmpty else { continue }
                let uploads = mediaUploads(paths, deviceClass: deviceClass, store: store,
                                           root: input.root)
                guard !uploads.isEmpty else { continue }

                let held: Set<String>
                switch store {
                case .apple:
                    held = input.actual.apple?
                        .screenshotChecksums["\(code)/\(uploads[0].bucket)"] ?? []
                case .google:
                    held = input.actual.google?
                        .imageHashes["\(code)/\(uploads[0].bucket)"] ?? []
                }
                let desired = uploads.map { store == .apple ? $0.md5 : $0.sha256 }
                let orderedMatches = store == .apple
                    ? input.actual.apple?.screenshotChecksumOrder[
                        "\(code)/\(uploads[0].bucket)"] == desired
                    : held == Set(desired)
                guard !orderedMatches else { continue }
                let bytes = uploads.reduce(Int64(0)) { $0 + $1.bytes }
                let label = store == .apple ? "screenshots" : "\(uploads[0].bucket)"
                steps.append(PlanStep(
                    id: "\(store.rawValue).media.\(code).\(deviceClass.rawValue)",
                    system: store == .apple ? .apple : .google, kind: .add,
                    summary: "replace with \(uploads.count) \(label)  ·  \(bytesText(bytes))  (\(code))",
                    title: "Reconcile \(uploads.count) \(label) for \(code)",
                    requests: store == .apple
                        ? [RequestSketch("DELETE", "/v1/appScreenshots/{id}"),
                           RequestSketch("POST", "/v1/appScreenshotSets"),
                           RequestSketch("POST", "/v1/appScreenshots")]
                        : [RequestSketch("DELETE", "/edits/{editId}/listings/\(code)/images"),
                           RequestSketch("POST", "/edits/{editId}/listings/\(code)/images")],
                    operation: store == .apple
                        ? .appleScreenshots(locale: code, deviceClass: deviceClass.rawValue,
                                            files: uploads)
                        : .googleImages(locale: code, imageType: uploads[0].bucket,
                                        files: uploads),
                    uploadCount: uploads.count, uploadBytes: bytes))
            }

            // Apple takes a video file. Google takes a YouTube URL and no file.
            guard store == .apple else { continue }
            for deviceClass in Manifest.DeviceClass.allCases {
                let paths = manifest.mediaPaths(locale: code, deviceClass: deviceClass,
                                                previews: true)
                guard !paths.isEmpty else { continue }
                let files: [MediaUpload] = paths.compactMap { path in
                    guard let url = resolve(path, root: input.root) else { return nil }
                    guard let previewType = AssetInspector.applePreviewType(for: deviceClass)
                    else { return nil }
                    return MediaUpload(path: path, url: url, bytes: fileSize(url), md5: "",
                                       sha256: "", bucket: previewType)
                }
                guard !files.isEmpty else { continue }
                let bytes = files.reduce(Int64(0)) { $0 + $1.bytes }
                steps.append(PlanStep(
                    id: "apple.preview.\(code).\(deviceClass.rawValue)", system: .apple,
                    kind: .add,
                    summary: "\(files.count) app previews  ·  \(bytesText(bytes))  (\(code))",
                    title: "Upload \(files.count) app previews for \(code)",
                    requests: [RequestSketch("POST", "/v1/appPreviewSets"),
                               RequestSketch("POST", "/v1/appPreviews")],
                    operation: .applePreviews(locale: code, deviceClass: deviceClass.rawValue,
                                              files: files),
                    uploadCount: files.count, uploadBytes: bytes))
            }
        }
        if store == .google {
            let locale = manifest.listing?.defaultLocale ?? "en-US"
            for (path, type) in [(manifest.media?.icon, "icon"),
                                 (manifest.media?.featureGraphic, "featureGraphic")] {
                guard let path, let url = resolve(path, root: input.root),
                      let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { continue }
                let upload = MediaUpload(path: path, url: url, bytes: Int64(data.count), md5: "",
                                         sha256: Checksums.sha256(data), bucket: type)
                let held = input.actual.google?.imageHashes["\(locale)/\(type)"] ?? []
                guard held != [upload.sha256] else { continue }
                steps.append(PlanStep(
                    id: "google.media.\(type)", system: .google, kind: .change,
                    summary: "replace \(type)  ·  \(bytesText(upload.bytes))",
                    title: "Upload the Google \(type)",
                    requests: [RequestSketch("DELETE", "/edits/{editId}/listings/\(locale)/\(type)"),
                               RequestSketch("POST", "/edits/{editId}/listings/\(locale)/\(type)")],
                    operation: .googleImages(locale: locale, imageType: type, files: [upload]),
                    uploadCount: 1, uploadBytes: upload.bytes))
            }

            var desiredKeys: Set<String> = []
            for (locale, groups) in manifest.media?.screenshots ?? [:] {
                for device in Manifest.DeviceClass.allCases
                where groups[device.rawValue]?.isEmpty == false {
                    if let type = AssetInspector.googleImageType(for: device) {
                        desiredKeys.insert("\(locale)/\(type)")
                    }
                }
            }
            if manifest.media?.icon != nil { desiredKeys.insert("\(locale)/icon") }
            if manifest.media?.featureGraphic != nil {
                desiredKeys.insert("\(locale)/featureGraphic")
            }
            for key in Set(input.actual.google?.imageHashes.keys ?? [:].keys)
                .subtracting(desiredKeys).sorted() {
                let pieces = key.split(separator: "/", maxSplits: 1).map(String.init)
                guard pieces.count == 2 else { continue }
                guard manifest.listing?.locales[pieces[0]] != nil else { continue }
                steps.append(PlanStep(
                    id: "google.media.delete.\(pieces[0]).\(pieces[1])", system: .google,
                    kind: .remove, summary: "delete \(pieces[1]) (\(pieces[0]))",
                    title: "Delete the dropped \(pieces[1])",
                    requests: [RequestSketch("DELETE", "/edits/{editId}/listings/\(key)")],
                    operation: .googleImages(locale: pieces[0], imageType: pieces[1], files: [])))
            }
        }
        return steps
    }

    /// Reads each file once: the dimensions pick the bucket and the bytes
    /// produce both checksums. A file that no store accepts is dropped here
    /// and reported by the validator, not uploaded and rejected later.
    static func mediaUploads(_ paths: [String], deviceClass: Manifest.DeviceClass,
                             store: Store, root: URL?) -> [MediaUpload] {
        paths.compactMap { path in
            guard let url = resolve(path, root: root),
                  let info = try? AssetInspector.image(at: url) else { return nil }
            let bucket: String?
            switch store {
            case .apple:
                bucket = (try? AssetInspector.appleDisplayType(for: info,
                                                               deviceClass: deviceClass)) ?? nil
            case .google:
                bucket = AssetInspector.googleImageType(for: deviceClass)
            }
            guard let bucket, let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
                return nil
            }
            return MediaUpload(path: path, url: url, bytes: Int64(data.count),
                               md5: Checksums.md5(data), sha256: Checksums.sha256(data),
                               bucket: bucket)
        }
    }

    // MARK: - Small helpers

    private static func appendChange(_ list: inout [String], _ name: String,
                                     _ wanted: String, _ current: String?) {
        guard !wanted.isEmpty else { return }
        guard wanted != (current ?? "") else { return }
        list.append("\(name) (\(wanted.count) chars)")
    }

    static func managedText(_ manifest: Manifest, _ code: String,
                            _ field: ListingTextField) -> String {
        manifest.listingText(locale: code, field: field)
    }

    static func googleShortDescription(_ manifest: Manifest, _ code: String) -> String {
        let override = manifest.listingText(locale: code, field: .googleShortDescription)
        return override.isEmpty ? manifest.listingText(locale: code, field: .subtitle) : override
    }

    private static func markUnverifiedComparisons(_ result: inout PlanResult) {
        let prefixes = [
            "apple.reviewDetails", "apple.purchases", "apple.subscriptions",
            "apple.subscriptionOffers",
            "apple.gracePeriod", "apple.customProductPages", "apple.experiments",
            "apple.events", "apple.eula", "apple.nomination", "apple.accessibility",
            "apple.appClip", "google.dataSafety",
            "google.purchaseOptionState", "google.oneTimeOffers",
            "google.basePlanState", "google.subscriptionOffers",
            "google.migratePrices", "provider.attach", "provider.offering",
        ]
        // `google.products` left this list. The per-product read carries the
        // titles, the prices, and the base plans, so that step compares real
        // fields and marks itself when a read fails.
        var ids: [String] = []
        for index in result.steps.indices
        where prefixes.contains(where: { result.steps[index].id.hasPrefix($0) })
            || result.steps[index].comparison == .unverified {
            result.steps[index].comparison = .unverified
            if !result.steps[index].summary.hasPrefix("unverified · ") {
                result.steps[index].summary = "unverified · " + result.steps[index].summary
            }
            ids.append(result.steps[index].id)
        }
        if !ids.isEmpty {
            result.findings.append(Finding(
                id: "plan.unverified", severity: .warning,
                message: "\(ids.count) plan rows cannot be compared with readable store state; they are explicitly marked unverified and may repeat on the next apply.",
                location: "Summary", fix: .plan))
        }
    }

    static func applePath(_ manifest: Manifest) -> String? {
        manifest.release?.build?.ios ?? manifest.release?.build?.macos
    }

    /// The tracks that every Play app already has. Google creates no other.
    static let standardGoogleTracks: Set<String> = ["internal", "alpha", "beta", "production"]

    /// A manifest path against the manifest's own directory, or nil when the
    /// file does not exist. The app target resolves the same way, so this is
    /// public rather than copied into a second definition that drifts.
    public static func resolve(_ path: String, root: URL?) -> URL? {
        let url = path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : root?.appendingPathComponent(path) ?? URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func fileSize(_ url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
    }

    static func bytesText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

public extension Manifest {
    /// Every store product id that the manifest declares, purchases first.
    var productIds: [String] {
        (purchases ?? []).map(\.id)
            + (subscriptions ?? []).flatMap { $0.plans.map(\.id) }
    }

    /// The product ids that name one entitlement key.
    func products(for entitlementKey: String) -> [String] {
        (purchases ?? []).filter { $0.entitlements?.contains(entitlementKey) == true }.map(\.id)
            + (subscriptions ?? []).flatMap {
                $0.plans.filter { $0.entitlements?.contains(entitlementKey) == true }.map(\.id)
            }
    }
}
