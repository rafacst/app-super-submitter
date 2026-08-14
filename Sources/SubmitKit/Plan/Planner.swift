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
        let versionName = manifest.versionName(for: .apple) ?? ""
        var steps: [PlanStep] = []

        guard let appID = manifest.apps.apple?.appId, !appID.isEmpty else { return [] }

        // 1 and 2. The version.
        if !versionName.isEmpty {
            let current = actual?.versionString
            if current == nil {
                steps.append(PlanStep(
                    id: "apple.version", system: .apple, kind: .add,
                    summary: "Create version \(versionName) as a draft nobody can see yet",
                    title: "Create the version \(versionName)",
                    requests: [RequestSketch("POST", "/v1/appStoreVersions")],
                    operation: .appleEnsureVersion(versionName)))
            } else if current != versionName {
                steps.append(PlanStep(
                    id: "apple.version", system: .apple, kind: .change,
                    summary: "Renumber the draft from \(current ?? "") to \(versionName)",
                    title: "Set the version to \(versionName)",
                    requests: [RequestSketch("PATCH", "/v1/appStoreVersions/{id}")],
                    operation: .appleEnsureVersion(versionName)))
            }
        }

        // A version this run creates carries Apple's default, and the read saw
        // no version at all, so a created version always writes this once.
        if let releaseType = manifest.release?.apple?.releaseType,
           actual?.versionId == nil || releaseType.rawValue != actual?.releaseType {
            steps.append(PlanStep(
                id: "apple.versionAttributes", system: .apple, kind: .change,
                summary: "When it goes on sale: \(Self.appleReleaseLabel(manifest))",
                title: "Write the release type",
                requests: [RequestSketch("PATCH", "/v1/appStoreVersions/{id}")],
                operation: .appleVersionAttributes,
                comparison: actual == nil ? .unverified : .verified))
        }

        // 3. The categories.
        let primary = manifest.review?.applePrimaryCategory ?? ""
        let secondary = manifest.review?.appleSecondaryCategory ?? ""
        if !primary.isEmpty,
           primary != actual?.primaryCategory || secondary != (actual?.secondaryCategory ?? "") {
            steps.append(PlanStep(
                id: "apple.categories", system: .apple, kind: .change,
                summary: "Categories: \(([primary, secondary].filter { !$0.isEmpty }).joined(separator: ", "))",
                title: "Write the app information",
                requests: [RequestSketch("PATCH", "/v1/appInfos/{id}")],
                operation: .appleCategories))
        }

        // 4 and 5. The two localization resources.
        for code in (manifest.listing?.locales.keys ?? [:].keys).sorted() {
            let info = actual?.infoLocales[code]
            var infoChanges: [String] = []
            appendChange(&infoChanges, .name, manifest.listingText(locale: code, field: .name),
                         info?.name)
            appendChange(&infoChanges, .subtitle,
                         managedText(manifest, code, .subtitle), info?.subtitle)
            appendChange(&infoChanges, .privacyPolicyURL,
                         managedText(manifest, code, .privacyPolicyURL), info?.privacyPolicyUrl)
            appendChange(&infoChanges, .privacyPolicyText,
                         managedText(manifest, code, .privacyPolicyText), info?.privacyPolicyText)
            appendChange(&infoChanges, .privacyChoicesURL,
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

            // An update inherits the released version, so the comparison is
            // against what the next version will start out holding and not
            // against an empty draft that does not exist yet. Diffing against
            // nothing made every field of every update look changed, and the
            // apply then wrote the description, the keywords and the URLs back
            // over the identical bytes Apple had already carried across.
            let version = actual?.startingVersionLocale(code)
            var versionChanges: [String] = []
            appendChange(&versionChanges, .description,
                         managedText(manifest, code, .description), version?.description)
            appendChange(&versionChanges, .whatsNew,
                         managedText(manifest, code, .whatsNew), version?.whatsNew)
            appendChange(&versionChanges, .keywords,
                         managedText(manifest, code, .keywords), version?.keywords)
            appendChange(&versionChanges, .promotionalText,
                         managedText(manifest, code, .promotionalText), version?.promotionalText)
            appendChange(&versionChanges, .supportURL,
                         managedText(manifest, code, .supportURL), version?.supportUrl)
            appendChange(&versionChanges, .marketingURL,
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
        //
        // The two steps are decided apart. A build reaches Apple by this app's
        // own upload, or by Build from Project, which uploads inside
        // `xcodebuild -exportArchive`. The second route names no file, and
        // gating the attach on one left the version empty and the release
        // refused.
        let namedBuild = applePath(manifest).flatMap { path in
            resolve(path, root: input.root).map { (path: path, file: $0) }
        }
        if let named = namedBuild {
            let bytes = fileSize(named.file)
            steps.append(PlanStep(
                id: "apple.build", system: .apple, kind: .add,
                summary: artifactSummary(named.file, bytes: bytes, prefix: "build "),
                title: "Upload the build \(named.file.lastPathComponent)",
                requests: [RequestSketch("POST", "/v1/buildUploads"),
                           RequestSketch("POST", "/v1/buildUploadFiles")],
                operation: .appleBuildUpload(path: named.path, bytes: bytes),
                uploadCount: 1, uploadBytes: bytes))
        }
        let uploadedBuild = actual?.buildIdForVersion
        if namedBuild != nil
            || (uploadedBuild != nil && uploadedBuild != actual?.attachedBuildId) {
            steps.append(PlanStep(
                id: "apple.attachBuild", system: .apple, kind: .change,
                summary: "Attach the build to version \(versionName)",
                title: "Attach the build to the version",
                requests: [RequestSketch("PATCH",
                                         "/v1/appStoreVersions/{id}/relationships/build")],
                operation: .appleAttachBuild))
        }
        if let encryption = manifest.review?.usesNonExemptEncryption,
           encryption != actual?.buildUsesNonExemptEncryption {
            steps.append(PlanStep(
                id: "apple.buildCompliance", system: .apple, kind: .change,
                summary: "Export compliance declaration",
                title: "Write the build export compliance declaration",
                requests: [RequestSketch("PATCH", "/v1/builds/{id}")],
                operation: .appleBuildCompliance))
        }

        // 8b. The export compliance declaration. The build flag above answers
        // Apple's question; an app that uses non-exempt encryption and claims
        // no exemption owes this on top of it.
        if manifest.review?.encryption != nil {
            steps.append(PlanStep(
                id: "apple.encryption", system: .apple, kind: .add,
                summary: "export compliance declaration"
                    + (manifest.review?.encryption?.documentPath == nil
                        ? "" : "  ·  with a document"),
                title: "Write the export compliance declaration",
                requests: [RequestSketch("POST", "/v1/appEncryptionDeclarations"),
                           RequestSketch("POST", "/v1/appEncryptionDeclarationDocuments"),
                           RequestSketch("PATCH", "/v1/builds/{id}")],
                operation: .appleEncryptionDeclaration,
                // Apple keeps one declaration per submission and offers no
                // read that says whether this one matches.
                comparison: .unverified))
        }

        // 9. The review details. An attachment carries no comparable field, so
        // a manifest that names one always writes.
        if let review = manifest.review,
           review.contactEmail?.isEmpty == false || review.notes?.isEmpty == false
            || review.attachments?.isEmpty == false {
            let differs = appleReviewDetailChanges(review, actual)
            if !differs.isEmpty {
                steps.append(PlanStep(
                    id: "apple.reviewDetails", system: .apple,
                    kind: actual?.reviewDetailId == nil ? .add : .change,
                    summary: "review details  \(differs.joined(separator: ", "))",
                    title: "Write the review details",
                    requests: [RequestSketch(actual?.reviewDetailId == nil ? "POST" : "PATCH",
                                             "/v1/appStoreReviewDetails")],
                    operation: .appleReviewDetails,
                    comparison: actual == nil ? .unverified : .verified))
            }
        }

        // 10. The age rating. An app that already carries the rating it wants
        // writes nothing, because every answer here matches the store.
        let ageRating = appleAgeRatingChanges(manifest.review, actual)
        let bandDiffers = manifest.review?.kidsAgeBand.map {
            !$0.isEmpty && AgeRatingAnswer.text($0) != actual?.ageRating["kidsAgeBand"]
        } ?? false
        if !ageRating.write.isEmpty || bandDiffers {
            let count = ageRating.write.count + (bandDiffers ? 1 : 0)
            steps.append(PlanStep(
                id: "apple.ageRating", system: .apple, kind: .change,
                summary: "Age rating: \(count) \(count == 1 ? "answer" : "answers") "
                    + (ageRating.write.keys.sorted() + (bandDiffers ? ["kidsAgeBand"] : []))
                        .joined(separator: ", "),
                title: "Write the age rating answers",
                requests: [RequestSketch("PATCH", "/v1/ageRatingDeclarations/{id}")],
                operation: .appleAgeRating,
                comparison: actual == nil ? .unverified : .verified))
        }

        // 11. The purchases. The per-product read carries the names, the
        // localizations, the prices, and the territories, so the plan names
        // the products that differ instead of always saying "write them all".
        let purchaseCount = manifest.purchases?.count ?? 0
        if purchaseCount > 0 {
            let diff = appleCatalogDiff(manifest, actual, kind: .purchases)
            if !diff.changes.isEmpty {
                steps.append(PlanStep(
                    id: "apple.purchases", system: .apple, kind: .change,
                    summary: diff.summary,
                    title: "Write \(purchaseCount) purchases",
                    requests: [RequestSketch("GET", "/v1/apps/{id}/inAppPurchasesV2"),
                               RequestSketch("POST", "/v2/inAppPurchases"),
                               RequestSketch("POST", "/v1/inAppPurchasePriceSchedules"),
                               RequestSketch("POST", "/v2/inAppPurchaseLocalizations"),
                               RequestSketch("POST", "/v1/inAppPurchaseAvailabilities"),
                               RequestSketch("POST", "/v1/promotedPurchases")],
                    operation: .applePurchases,
                    comparison: diff.verified ? .verified : .unverified))
            }
        }

        // 11b. The subscription catalog, then the offers on top of it.
        let planCount = manifest.subscriptions?.reduce(0) { $0 + $1.plans.count } ?? 0
        if planCount > 0 {
            let diff = appleCatalogDiff(manifest, actual, kind: .subscriptions)
            if !diff.changes.isEmpty {
                steps.append(PlanStep(
                    id: "apple.subscriptions", system: .apple, kind: .change,
                    summary: diff.summary,
                    title: "Write \(planCount) subscriptions",
                    requests: [RequestSketch("POST", "/v1/subscriptionGroups"),
                               RequestSketch("POST", "/v1/subscriptions"),
                               RequestSketch("POST", "/v1/subscriptionVersions"),
                               RequestSketch("POST", "/v2/subscriptionLocalizations"),
                               RequestSketch("DELETE", "/v2/subscriptionLocalizations/{id}"),
                               RequestSketch("POST", "/v1/subscriptionGroupVersions"),
                               RequestSketch("POST", "/v2/subscriptionGroupLocalizations"),
                               RequestSketch("DELETE", "/v2/subscriptionGroupLocalizations/{id}"),
                               RequestSketch("POST", "/v1/subscriptionPrices"),
                               RequestSketch("POST", "/v1/subscriptionPlanAvailabilities"),
                               RequestSketch("PATCH", "/v1/subscriptionPlanAvailabilities/{id}")],
                    operation: .appleSubscriptions,
                    comparison: diff.verified ? .verified : .unverified))
            }
        }
        let offerCount = manifest.subscriptions?
            .reduce(0) { $0 + $1.plans.reduce(0) { $0 + ($1.offers?.count ?? 0) } } ?? 0
        if offerCount > 0 {
            let diff = appleOfferDiff(manifest, actual)
            if !diff.changes.isEmpty {
                steps.append(PlanStep(
                    id: "apple.subscriptionOffers", system: .apple, kind: .change,
                    summary: diff.summary,
                    title: "Write \(offerCount) subscription offers",
                    requests: [RequestSketch("POST", "/v1/subscriptionIntroductoryOffers"),
                               RequestSketch("POST", "/v1/subscriptionOfferCodes"),
                               RequestSketch("POST", "/v1/subscriptionOfferCodeCustomCodes"),
                               RequestSketch("POST", "/v1/subscriptionOfferCodeOneTimeUseCodes"),
                               RequestSketch("POST", "/v1/subscriptionPromotionalOffers"),
                               RequestSketch("POST", "/v1/winBackOffers")],
                    operation: .appleSubscriptionOffers,
                    comparison: diff.verified ? .verified : .unverified))
            }
        }
        // 11c. The offer codes of a one-time purchase. The subscription twin
        // already rides inside the subscription offer step.
        for purchase in manifest.purchases ?? [] {
            let codes = (purchase.offers ?? []).filter { $0.kind == .offerCode }
            guard !codes.isEmpty else { continue }
            steps.append(PlanStep(
                id: "apple.purchaseOfferCodes.\(purchase.id)", system: .apple, kind: .add,
                summary: "\(codes.count) offer codes on \(purchase.id)  (draft)",
                title: "Write \(codes.count) offer codes on \(purchase.id)",
                requests: [RequestSketch("POST", "/v1/inAppPurchaseOfferCodes"),
                           RequestSketch("POST", "/v1/inAppPurchaseOfferCodeCustomCodes"),
                           RequestSketch("POST", "/v1/inAppPurchaseOfferCodeOneTimeUseCodes")],
                operation: .applePurchaseOfferCodes(productId: purchase.id),
                // The writer reads the held names and skips the ones Apple has.
                comparison: .unverified))
        }

        if let days = (manifest.subscriptions ?? []).compactMap(\.gracePeriodDays).first,
           actual?.gracePeriodDays != days || actual?.gracePeriodOptIn != true {
            steps.append(PlanStep(
                id: "apple.gracePeriod", system: .apple, kind: .change,
                summary: "billing grace period \(AppleDurations.gracePeriod(days: days))"
                    + (actual?.gracePeriodDays.map { " (now \($0) days)" } ?? ""),
                title: "Write the billing grace period",
                requests: [RequestSketch("PATCH", "/v1/subscriptionGracePeriods/{id}")],
                operation: .appleGracePeriod,
                comparison: actual == nil ? .unverified : .verified))
        }

        steps += appleTestFlightSteps(input)
        steps += appleGameCenterSteps(input)
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
        // The resolved point, not the amount that was asked for. Apple sells
        // at a point, so `appleAppPrice` writes the nearest one: a manifest
        // that says 4.90 against a store that holds 4.99 is the same price,
        // and comparing the raw amount planned a write that changed nothing.
        // `priceAmount` is that same nearest point, and it is nil only when
        // the ladder read failed, which is when the raw amount is the honest
        // thing to compare.
        if let pricing = manifest.pricing,
           (actual?.priceAmount ?? pricing.base.amount) != actual?.currentPriceAmount {
            steps.append(PlanStep(
                id: "apple.appPrice", system: .apple, kind: .change,
                summary: "app price schedule",
                title: "Write the app price schedule",
                requests: [RequestSketch("POST", "/v1/appPriceSchedules")],
                operation: .appleAppPrice))
        }
        let wantedAvailability = Dictionary(uniqueKeysWithValues:
            (manifest.pricing?.territories ?? []).map { ($0.territory, $0.available) })
        // A step is never planned for a write the App Store will not take.
        //
        // `availableInNewTerritories` is an attribute of the create and of
        // nothing else: once an app holds an availability record, Apple refuses
        // it on `apps`, refuses a PATCH of the record, and refuses a second
        // create. So on a live app this can differ and still not be work.
        //
        // It differed on every live app, because the value in the manifest was
        // never the developer's: saving a price wrote `true` as a default. The
        // plan offered "Write the territory availability" on an app whose
        // countries nobody had touched, and the run stopped there every time.
        // `Validator.availability` says the difference out loud instead, which
        // is the honest half of this: the app cannot do it and no longer
        // pretends it can.
        //
        // An app with no record yet is the create, and the create carries this
        // attribute, so there it is real work.
        let autoAvailabilityDiffers = manifest.pricing?.appleNewTerritories != nil
            && actual?.hasAvailabilityRecord != true
        // The same rule, one territory at a time. A territory the read does not
        // list is one this app knows nothing about, and `appleUpdateTerritories`
        // reports those rather than writing them.
        let territoryAvailabilityDiffers = wantedAvailability.contains { wanted in
            guard let held = actual?.territoryAvailability[wanted.key] else {
                return actual?.territoryAvailability.isEmpty ?? true
            }
            return held != wanted.value
        }
        if autoAvailabilityDiffers || territoryAvailabilityDiffers {
            steps.append(PlanStep(
                id: "apple.availability", system: .apple, kind: .change,
                summary: "territory availability",
                title: "Write the territory availability",
                requests: [RequestSketch("POST", "/v2/appAvailabilities")],
                operation: .appleAvailability))
        }
        // The end of a preorder charges everybody who ordered and starts the
        // download. It is the last Apple row for the same reason the release
        // button is the last tab.
        if (manifest.pricing?.territories ?? []).contains(where: { $0.endPreOrder == true }) {
            steps.append(PlanStep(
                id: "apple.endPreOrder", system: .apple, kind: .change,
                summary: "end the preorder  ·  every pre-order is charged",
                title: "End the preorder and put the app on sale",
                requests: [RequestSketch("POST", "/v1/endAppAvailabilityPreOrders")],
                operation: .appleEndPreOrder,
                comparison: .unverified))
        }
        return steps
    }

    // MARK: - TestFlight

    /// The App Store twin of the Google track testers.
    ///
    /// Every row here reaches a person: a new address receives an invitation,
    /// a build reaches a group, and a beta review takes a place in a queue.
    /// Each one compares what Apple already holds, so a second apply invites
    /// nobody twice.
    /// Whether a group Apple already holds carries every switch the manifest
    /// names for it.
    ///
    /// A key the manifest leaves out is not a `false`. It means the developer
    /// said nothing, so whatever Apple holds stays, and only a named value that
    /// disagrees earns a step.
    ///
    /// `internalGroup` is absent on purpose. Apple takes it on the create
    /// request alone, so a step raised for it would send a value Apple drops
    /// and the plan would repeat it on every apply.
    private static func betaGroupSettingsDiffer(
        _ group: Manifest.Release.TestFlight.Group,
        _ live: AppleTestFlightClient.BetaGroup?) -> Bool {
        func differs<Value: Equatable>(_ wanted: Value?, _ held: Value?) -> Bool {
            guard let wanted else { return false }
            return wanted != held
        }
        return differs(group.publicLink, live?.publicLink)
            // The cap was not compared, so a raised or a cleared limit left
            // the plan silent and the run never sent the new number.
            || differs(group.publicLinkLimit, live?.publicLinkLimit)
            || differs(group.automaticBuilds, live?.automaticBuilds)
            || differs(group.feedback, live?.feedback)
            || differs(group.iosBuildsOnMac, live?.iosBuildsOnMac)
            || differs(group.iosBuildsOnVision, live?.iosBuildsOnVision)
    }

    private static func appleTestFlightSteps(_ input: Input) -> [PlanStep] {
        guard let testFlight = input.manifest.release?.apple?.testFlight else { return [] }
        let actual = input.actual.apple
        let read = actual != nil
        var steps: [PlanStep] = []

        for group in testFlight.groups ?? [] {
            let live = actual?.betaGroups[group.name]
            if live == nil || betaGroupSettingsDiffer(group, live) {
                steps.append(PlanStep(
                    id: "apple.betaGroup.\(group.name)", system: .apple,
                    kind: live == nil ? .add : .change,
                    summary: "TestFlight group  \(group.name)"
                        + (live == nil ? "  create" : "  settings"),
                    title: "\(live == nil ? "Create" : "Update") the \(group.name) group",
                    requests: [RequestSketch(live == nil ? "POST" : "PATCH", "/v1/betaGroups")],
                    operation: .appleBetaGroup(name: group.name),
                    comparison: read ? .verified : .unverified))
            }

            // Apple emails every address it does not already hold, so the step
            // counts the difference and never the whole list.
            let wanted = (group.testers ?? []).map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let missing = wanted.filter { live?.testers.contains($0.lowercased()) != true }
            if !wanted.isEmpty, !read || !missing.isEmpty {
                steps.append(PlanStep(
                    id: "apple.betaTesters.\(group.name)", system: .apple, kind: .add,
                    summary: "TestFlight  \(group.name)  invite "
                        + (read ? "\(missing.count) of \(wanted.count)" : "\(wanted.count)")
                        + " testers",
                    title: "Invite \(missing.count) testers to \(group.name)",
                    requests: [RequestSketch("POST", "/v1/betaTesters")],
                    operation: .appleBetaTesters(group: group.name,
                                                 emails: read ? missing : wanted),
                    comparison: read ? .verified : .unverified))
            }

            // The build reaches the group, and through it every tester.
            //
            // Three ways to have one, and the step used to know only the last:
            // this run uploads it, Apple already processed one for this
            // version, or the App Store version holds one. A beta needs no
            // version, so an upload that never reached a version left every
            // group without the build it was created for.
            let uploading = applePath(input.manifest)
                .flatMap { resolve($0, root: input.root) } != nil
            let buildID = actual?.buildIdForVersion ?? actual?.attachedBuildId
            if uploading || (buildID != nil && live?.buildIds.contains(buildID!) != true) {
                steps.append(PlanStep(
                    id: "apple.betaBuild.\(group.name)", system: .apple, kind: .add,
                    summary: "TestFlight  \(group.name)  gets the build",
                    title: "Give the build to \(group.name)",
                    requests: [RequestSketch("POST", "/v1/betaGroups/{id}/relationships/builds")],
                    operation: .appleBetaBuild(group: group.name),
                    comparison: read ? .verified : .unverified))
            }
        }

        if let notes = testFlight.whatToTest, !notes.isEmpty {
            let differs = notes.contains { actual?.whatToTest[$0.key] != $0.value }
            if !read || differs {
                steps.append(PlanStep(
                    id: "apple.whatToTest", system: .apple, kind: .change,
                    summary: "what to test  \(notes.count) locales",
                    title: "Write the What to Test notes",
                    requests: [RequestSketch("POST", "/v1/betaBuildLocalizations")],
                    operation: .appleWhatToTest,
                    comparison: read ? .verified : .unverified))
            }
        }
        // The TestFlight page of the app. It carries no build, so it appears
        // even before an artifact reaches Apple.
        if let wanted = testFlight.localizations, !wanted.isEmpty {
            let verified = actual?.betaAppLocalizationsRead == true
            let differs = wanted.contains { locale, text in
                actual?.betaAppLocalizations[locale] != text
            }
            if !verified || differs {
                steps.append(PlanStep(
                    id: "apple.betaAppLocalizations", system: .apple, kind: .change,
                    summary: "TestFlight page  \(wanted.count) locales",
                    title: "Write the TestFlight page",
                    requests: [RequestSketch("POST", "/v1/betaAppLocalizations")],
                    operation: .appleBetaAppLocalizations,
                    comparison: verified ? .verified : .unverified))
            }
        }

        // The licence every external tester accepts before the first install.
        // Apple fills it with its own standard text, so a manifest that names
        // none leaves that alone rather than blanking it.
        if let agreement = testFlight.licenseAgreement,
           actual?.betaLicenseAgreement != agreement {
            let verified = actual?.betaLicenseAgreement != nil
            steps.append(PlanStep(
                id: "apple.betaLicenseAgreement", system: .apple, kind: .change,
                summary: "TestFlight  the tester licence  \(agreement.count) characters",
                title: "Write the beta licence agreement",
                requests: [RequestSketch("PATCH", "/v1/betaLicenseAgreements/{id}")],
                operation: .appleBetaLicenseAgreement,
                comparison: verified ? .verified : .unverified))
        }

        // The beta review contact. Apple keeps one per app, and the values come
        // from `review`. The condition was `review != nil`, so an empty review
        // block wrote the contact on every apply and blanked what Apple held.
        // No read covers this resource, so "keep" here means the manifest has
        // to name a value before anything is sent.
        if input.manifest.review?.hasBetaReviewContact == true {
            steps.append(PlanStep(
                id: "apple.betaReviewDetail", system: .apple, kind: .change,
                summary: "TestFlight  the beta review contact",
                title: "Write the beta review contact",
                requests: [RequestSketch("PATCH", "/v1/betaAppReviewDetails/{id}")],
                operation: .appleBetaReviewDetail,
                comparison: .unverified))
        }

        if let notify = testFlight.autoNotify, !read || notify != actual?.betaAutoNotify {
            steps.append(PlanStep(
                id: "apple.betaAutoNotify", system: .apple, kind: .change,
                summary: "TestFlight  \(notify ? "notify" : "do not notify") the testers",
                title: "Set the tester notification",
                requests: [RequestSketch("PATCH", "/v1/buildBetaDetails/{id}")],
                operation: .appleBetaAutoNotify(notify),
                comparison: read ? .verified : .unverified))
        }
        // The queue is the irreversible half of TestFlight, so it is the last
        // row and it never repeats once Apple holds a submission.
        if testFlight.submitForBetaReview == true, actual?.betaReviewSubmitted != true {
            steps.append(PlanStep(
                id: "apple.betaReview", system: .apple, kind: .add,
                summary: "TestFlight  send the build to beta review",
                title: "Send the build to beta review",
                requests: [RequestSketch("POST", "/v1/betaAppReviewSubmissions")],
                operation: .appleBetaReview,
                comparison: read ? .verified : .unverified))
        }
        return steps
    }

    // MARK: - Game Center

    /// Whether one Game Center object carries every value the manifest names.
    ///
    /// It follows `betaGroupSettingsDiffer` exactly: a key the manifest leaves
    /// out is not a `false`. It means the developer said nothing, whatever
    /// Apple holds stays, and only a named value that disagrees earns a step.
    ///
    /// The comparison is between two flattenings of the same values as text,
    /// so `10` and `10.0` are one value and a duration is compared as the ISO
    /// 8601 string Apple was sent.
    static func gameCenterObjectDiffers(
        _ wanted: GameCenterRow, _ live: AppleGameCenterCatalogClient.Object?) -> Bool {
        guard let live else { return true }
        var held = live.attributes
        if let name = live.referenceName { held["referenceName"] = name }
        if let archived = live.archived { held["archived"] = archived ? "true" : "false" }
        // The vendor identifier is the key and never differs: this row was
        // found by it.
        return wanted.write.comparable.contains { key, value in held[key] != value }
    }

    /// One locale row of one object, against the locale Apple holds.
    private static func gameCenterLocaleDiffers(
        _ wanted: [String: String],
        _ live: AppleGameCenterCatalogClient.Localization?) -> Bool {
        guard let live else { return true }
        return wanted.contains { key, value in live.values[key] != value }
    }

    /// Whether the file on disk is the one Apple holds.
    ///
    /// Apple returns no checksum on a Game Center image and its update request
    /// takes `uploaded` alone, so the name and the byte count are the whole
    /// comparison. A store that reported neither counts as different, and the
    /// apply compares again before it spends an upload.
    private static func gameCenterImageDiffers(_ url: URL, name: String?,
                                               size: Int?) -> Bool {
        guard let name, let size else { return true }
        return name != url.lastPathComponent || Int64(size) != fileSize(url)
    }

    /// Everything the Gaming tab writes, in dependency order.
    ///
    /// **A failed detail read produces nothing.** `read == false` means the
    /// detail read threw rather than answering "this app is not a game", and a
    /// create against a detail that already exists answers 409. No read at all
    /// is a different state: the steps appear and say the comparison is a
    /// guess, exactly as the TestFlight rows do.
    ///
    /// **Leaderboards come first** among the five families, because a set, an
    /// activity and a challenge all point at one.
    ///
    /// **The App Store version is last**, because it is the only step here that
    /// reaches a player.
    private static func appleGameCenterSteps(_ input: Input) -> [PlanStep] {
        guard let wanted = input.manifest.gameCenter else { return [] }
        let live = input.actual.apple?.gameCenter
        if let live, !live.read { return [] }
        let read = live?.read == true
        var steps: [PlanStep] = []

        func mark(_ family: AppleGameCenterCatalogClient.Family) -> ComparisonConfidence {
            guard read, live?.unreadFamilies.contains(family.rawValue) != true else {
                return .unverified
            }
            return .verified
        }

        // 1. The configuration itself.
        if let detail = gameCenterDetailStep(wanted, live: live, read: read) {
            steps.append(detail)
        }

        // 2. The group. A group is account-wide, so a name the account already
        // holds is used rather than made a second time. The step also appears
        // when the account holds the group and this app is not in it, because
        // pointing the detail at it is the same call either way.
        if let group = wanted.group, !group.isEmpty,
           live?.groups[group] == nil || live?.detail?.groupName != group {
            let exists = live?.groups[group] != nil
            steps.append(PlanStep(
                id: "apple.gameCenter.group.\(group)", system: .apple,
                kind: exists ? .change : .add,
                summary: "Game Center  group  \(group)"
                    + (exists ? "  this game joins it" : "  create"),
                title: "\(exists ? "Join" : "Create") the \(group) group",
                requests: [RequestSketch(exists ? "PATCH" : "POST", "/v1/gameCenterGroups")],
                operation: .appleGameCenterGroup(name: group),
                comparison: read ? .verified : .unverified))
        }

        // 3 to 11. The five families, leaderboards first.
        let order: [AppleGameCenterCatalogClient.Family] =
            [.leaderboard, .achievement, .leaderboardSet, .activity, .challenge]
        var images: [PlanStep] = []
        for family in order {
            for row in wanted.rows(family) where !row.id.isEmpty {
                let object = live?.objects(family)[row.id]
                steps += gameCenterObjectSteps(row, live: object, mark: mark(family))
                images += gameCenterImageSteps(row, live: object, root: input.root,
                                               mark: mark(family))
            }
            // The board Game Center opens on, once the boards exist. It is a
            // step of its own and not part of the detail, because the detail
            // is created before any leaderboard is and a relationship cannot
            // name an object that has not been made yet.
            guard family == .leaderboard, let board = wanted.defaultLeaderboard,
                  !board.isEmpty, board != live?.detail?.defaultLeaderboardVendorID
            else { continue }
            steps.append(PlanStep(
                id: "apple.gameCenter.defaultLeaderboard", system: .apple, kind: .change,
                summary: "Game Center  opens on \(board)",
                title: "Open Game Center on \(board)",
                requests: [RequestSketch("PATCH", "/v1/gameCenterDetails/{id}")],
                operation: .appleGameCenterDefaultLeaderboard,
                comparison: read ? .verified : .unverified))
        }

        // 12. The uploads, together, because each one carries a progress bar.
        steps += images

        // 13 and 14. Matchmaking. None of it needs a build either.
        steps += gameCenterMatchmakingSteps(wanted, live: live, read: read)

        // 15. What publishes all of it.
        for version in (wanted.appVersions ?? [:]).keys.sorted() {
            let row = wanted.appVersions?[version]
            let liveVersion = live?.appVersions[version]
            let differs = liveVersion == nil
                || (row?.enabled != nil && row?.enabled != liveVersion?.enabled)
                || gameCenterCompatibilityDiffers(row?.compatibility, liveVersion, in: live)
            guard differs else { continue }
            steps.append(PlanStep(
                id: "apple.gameCenter.appVersion.\(version)", system: .apple,
                kind: liveVersion == nil ? .add : .change,
                summary: "Game Center  \(version) carries the configuration",
                title: "Give \(version) the Game Center configuration",
                requests: [RequestSketch(liveVersion == nil ? "POST" : "PATCH",
                                         "/v1/gameCenterAppVersions")],
                operation: .appleGameCenterAppVersion(version: version),
                comparison: read ? .verified : .unverified))
        }
        return steps
    }

    /// The detail step: the configuration itself, and the one attribute it
    /// carries that this app manages.
    ///
    /// The group and the opening leaderboard are steps of their own, because
    /// each names an object that has to exist first. `arcadeEnabled` is read
    /// only and Apple marks `challengeEnabled` deprecated, so neither is ever
    /// compared or sent.
    private static func gameCenterDetailStep(_ wanted: Manifest.GameCenter,
                                             live: ActualState.Apple.GameCenter?,
                                             read: Bool) -> PlanStep? {
        let detail = live?.detail
        let missing = wanted.enabled == true && detail == nil
        let minimumsDiffer = wanted.challengesMinimumPlatformVersions.map {
            Set($0) != Set(detail?.challengesMinimumPlatformVersions ?? [])
        } ?? false
        guard missing || minimumsDiffer else { return nil }

        var says: [String] = []
        if missing { says.append("create") }
        if minimumsDiffer { says.append("challenge minimums") }
        return PlanStep(
            id: "apple.gameCenter.detail", system: .apple,
            kind: missing ? .add : .change,
            summary: "Game Center  \(says.joined(separator: ", "))",
            title: missing ? "Create the Game Center configuration"
                : "Write the Game Center configuration",
            requests: [RequestSketch(missing ? "POST" : "PATCH", "/v1/gameCenterDetails")],
            operation: .appleGameCenterDetail,
            comparison: read ? .verified : .unverified)
    }

    /// One object, its locales, and the links it owns.
    private static func gameCenterObjectSteps(
        _ row: GameCenterRow, live: AppleGameCenterCatalogClient.Object?,
        mark: ComparisonConfidence) -> [PlanStep] {
        let family = row.family
        var steps: [PlanStep] = []
        let prefix = "apple.gameCenter.\(family.rawValue).\(row.id)"

        if gameCenterObjectDiffers(row, live) {
            steps.append(PlanStep(
                id: prefix, system: .apple, kind: live == nil ? .add : .change,
                summary: "Game Center  \(family.noun)  \(row.name)"
                    + (row.write.archived == true ? "  archived" : ""),
                title: "\(live == nil ? "Create" : "Update") the \(row.name) \(family.noun)",
                requests: [RequestSketch(live == nil ? "POST" : "PATCH", family.objectPath)],
                operation: .appleGameCenterObject(family: family.rawValue, id: row.id),
                comparison: mark))
        }

        for code in row.locales.keys.sorted() {
            let values = row.locales[code] ?? [:]
            guard !values.isEmpty,
                  gameCenterLocaleDiffers(values, live?.localizations[code]) else { continue }
            steps.append(PlanStep(
                id: "\(prefix).\(code)", system: .apple,
                kind: live?.localizations[code] == nil ? .add : .change,
                summary: "Game Center  \(family.noun)  \(row.name)  \(code)",
                title: "Write the \(code) text of \(row.name)",
                requests: [RequestSketch("POST",
                                         AppleGameCenterCatalogClient.localizationPath(family))],
                operation: .appleGameCenterLocale(family: family.rawValue, id: row.id,
                                                  locale: code),
                comparison: mark))
        }

        // The set members, the activity links and the challenge board. Each
        // one sends the difference, so a link somebody added in the console
        // this morning is not dropped by a replace.
        if let members = row.members, Set(members) != (live?.linkedIDs ?? []) {
            steps.append(PlanStep(
                id: "\(prefix).members", system: .apple, kind: .change,
                summary: "Game Center  set  \(row.name)  \(members.count) leaderboards",
                title: "Write the boards inside \(row.name)",
                requests: [RequestSketch(
                    "POST",
                    "/v2/gameCenterLeaderboardSets/{id}/relationships/gameCenterLeaderboards")],
                operation: .appleGameCenterMembers(set: row.id),
                comparison: mark))
        }
        if family == .activity {
            let achievementsDiffer = row.linkedAchievements
                .map { Set($0) != (live?.linkedAchievementIDs ?? []) } ?? false
            let boardsDiffer = row.linkedLeaderboards
                .map { Set($0) != (live?.linkedIDs ?? []) } ?? false
            if achievementsDiffer || boardsDiffer {
                steps.append(PlanStep(
                    id: "\(prefix).links", system: .apple, kind: .change,
                    summary: "Game Center  activity  \(row.name)  what it awards",
                    title: "Write what \(row.name) awards",
                    requests: [RequestSketch(
                        "POST", "/v1/gameCenterActivities/{id}/relationships/achievementsV2")],
                    operation: .appleGameCenterLinks(activity: row.id),
                    comparison: mark))
            }
        }
        if family == .challenge, let board = row.leaderboard, !board.isEmpty,
           live?.linkedIDs != [board] {
            steps.append(PlanStep(
                id: "\(prefix).leaderboard", system: .apple, kind: .change,
                summary: "Game Center  challenge  \(row.name)  scores from \(board)",
                title: "Point \(row.name) at \(board)",
                requests: [RequestSketch(
                    "PATCH", "/v1/gameCenterChallenges/{id}/relationships/leaderboardV2")],
                operation: .appleGameCenterChallengeLeaderboard(challenge: row.id),
                comparison: mark))
        }
        return steps
    }

    /// One step per image, because each one is an upload.
    private static func gameCenterImageSteps(
        _ row: GameCenterRow, live: AppleGameCenterCatalogClient.Object?, root: URL?,
        mark: ComparisonConfidence) -> [PlanStep] {
        let family = row.family
        let prefix = "apple.gameCenter.image.\(family.rawValue).\(row.id)"
        var steps: [PlanStep] = []

        func step(id: String, locale: String?, path: String, url: URL, label: String) {
            steps.append(PlanStep(
                id: id, system: .apple, kind: .change,
                summary: "Game Center  \(family.noun)  \(row.name)  \(label)",
                title: "Upload the \(label) of \(row.name)",
                requests: [RequestSketch("POST", family.imagePath)],
                operation: .appleGameCenterImage(family: family.rawValue, id: row.id,
                                                 locale: locale, path: path),
                uploadCount: 1, uploadBytes: fileSize(url), comparison: mark))
        }

        if let path = row.defaultImage, !path.isEmpty, let url = resolve(path, root: root),
           gameCenterImageDiffers(url, name: live?.defaultImageFileName,
                                  size: live?.defaultImageFileSize) {
            step(id: "\(prefix).default", locale: nil, path: path, url: url,
                 label: "fallback image")
        }
        for code in row.images.keys.sorted() {
            guard let path = row.images[code], !path.isEmpty,
                  let url = resolve(path, root: root) else { continue }
            let localization = live?.localizations[code]
            guard gameCenterImageDiffers(url, name: localization?.imageFileName,
                                         size: localization?.imageFileSize) else { continue }
            step(id: "\(prefix).\(code)", locale: code, path: path, url: url,
                 label: "\(code) image")
        }
        return steps
    }

    /// The rule sets and the queues. Apple keys both by reference name, so a
    /// renamed one is a new one and the old stays until somebody deletes it.
    private static func gameCenterMatchmakingSteps(
        _ wanted: Manifest.GameCenter, live: ActualState.Apple.GameCenter?,
        read: Bool) -> [PlanStep] {
        guard let matchmaking = wanted.matchmaking else { return [] }
        let verified: ComparisonConfidence =
            read && live?.unreadFamilies.contains("matchmaking") != true
                ? .verified : .unverified
        var steps: [PlanStep] = []

        for set in matchmaking.ruleSets ?? [] where !set.name.isEmpty {
            let liveSet = live?.ruleSets[set.name]
            guard liveSet == nil || gameCenterRuleSetDiffers(set, liveSet) else { continue }
            let inside = (set.rules?.count ?? 0) + (set.teams?.count ?? 0)
            steps.append(PlanStep(
                id: "apple.gameCenter.ruleSet.\(set.name)", system: .apple,
                kind: liveSet == nil ? .add : .change,
                summary: "Game Center  rule set  \(set.name)"
                    + (inside > 0 ? "  \(inside) rules and teams" : ""),
                title: "\(liveSet == nil ? "Create" : "Update") the \(set.name) rule set",
                requests: [RequestSketch(liveSet == nil ? "POST" : "PATCH",
                                         "/v1/gameCenterMatchmakingRuleSets")],
                operation: .appleGameCenterRuleSet(name: set.name),
                comparison: verified))
        }

        for queue in matchmaking.queues ?? [] where !queue.name.isEmpty {
            let liveQueue = live?.queues[queue.name]
            let differs = liveQueue == nil
                || (queue.classicBundleIds.map { Set($0) != Set(liveQueue?.classicBundleIds ?? []) }
                    ?? false)
            guard differs else { continue }
            steps.append(PlanStep(
                id: "apple.gameCenter.queue.\(queue.name)", system: .apple,
                kind: liveQueue == nil ? .add : .change,
                summary: "Game Center  queue  \(queue.name)"
                    + (queue.ruleSet.map { "  matches with \($0)" } ?? ""),
                title: "\(liveQueue == nil ? "Create" : "Update") the \(queue.name) queue",
                requests: [RequestSketch(liveQueue == nil ? "POST" : "PATCH",
                                         "/v1/gameCenterMatchmakingQueues")],
                operation: .appleGameCenterQueue(name: queue.name),
                comparison: verified))
        }
        return steps
    }

    /// A rule set, its rules and its teams, against what the account holds.
    /// They are one step, so one disagreement anywhere raises it.
    private static func gameCenterRuleSetDiffers(
        _ wanted: Manifest.GameCenter.RuleSet,
        _ live: AppleGameCenterMatchmakingClient.RuleSet?) -> Bool {
        func differs<Value: Equatable>(_ wanted: Value?, _ held: Value?) -> Bool {
            guard let wanted else { return false }
            return wanted != held
        }
        if differs(wanted.ruleLanguageVersion, live?.ruleLanguageVersion) { return true }
        if let players = wanted.players, players.count == 2,
           players[0] != live?.minPlayers || players[1] != live?.maxPlayers {
            return true
        }
        for rule in wanted.rules ?? [] {
            guard let held = live?.rules[rule.name] else { return true }
            if differs(rule.description, held.description) { return true }
            if differs(rule.type, held.type) { return true }
            if differs(rule.expression, held.expression) { return true }
            if differs(rule.weight, held.weight) { return true }
        }
        for team in wanted.teams ?? [] {
            guard let held = live?.teams[team.name] else { return true }
            if let players = team.players, players.count == 2,
               players[0] != held.minPlayers || players[1] != held.maxPlayers {
                return true
            }
        }
        return false
    }

    /// The older versions whose scores one version keeps. The manifest names
    /// version strings and Apple answers with its own resource ids, so the
    /// comparison goes through the version map that was already read.
    private static func gameCenterCompatibilityDiffers(
        _ wanted: [String]?, _ row: AppleGameCenterClient.AppVersion?,
        in state: ActualState.Apple.GameCenter?) -> Bool {
        guard let wanted else { return false }
        let ids = Set(wanted.compactMap { state?.appVersions[$0]?.id })
        return ids != (row?.compatibilityVersionIDs ?? [])
    }


    // MARK: - The App Store marketing resources

    /// Each block writes only when the manifest holds it. None of these has a
    /// Google twin, so none of them appears on the Google side.
    private static func appleMarketingSteps(_ input: Input) -> [PlanStep] {
        guard let marketing = input.manifest.marketing else { return [] }
        let actual = input.actual.apple
        let read = actual != nil
        var steps: [PlanStep] = []

        // Each block compares the names that Apple holds. A name that Apple
        // already carries is skipped, because these writers create by name and
        // a second create would make a duplicate.
        //
        // The localized text under a page, an experiment, or an event has no
        // read of its own. A resource that carries some keeps its step, and
        // that step says that nobody compared the text.
        if let pages = marketing.customProductPages, !pages.isEmpty {
            // Either spelling, the same rule the apply uses. See
            // `StoreIdentity`: this asked by name while the apply asked by
            // key, so the plan could call a page missing that the apply was
            // about to find, and the other way round.
            let missing = pages.filter {
                !StoreIdentity.holds(key: $0.key, name: $0.name,
                                     in: actual?.customProductPageNames ?? [:])
            }
            let localized = pages.contains { $0.locales?.isEmpty == false }
            if !read || !missing.isEmpty || localized {
                steps.append(PlanStep(
                    id: "apple.customProductPages", system: .apple, kind: .change,
                    summary: appleNameSummary("custom product pages", missing.map(\.name),
                                              total: pages.count, read: read),
                    title: "Write \(pages.count) custom product pages",
                    requests: [RequestSketch("POST", "/v1/appCustomProductPages"),
                               RequestSketch("POST", "/v1/appCustomProductPageLocalizations")],
                    operation: .appleCustomProductPages,
                    comparison: read && !localized ? .verified : .unverified))
            }
        }
        if let experiments = marketing.experiments, !experiments.isEmpty {
            let treatments = experiments.reduce(0) { $0 + $1.treatments.count }
            let missing = experiments.filter {
                !StoreIdentity.holds(key: $0.key, name: $0.name,
                                     in: actual?.experiments ?? [:])
            }
            // Every experiment carries treatments, and no read returns them.
            if !read || !missing.isEmpty || treatments > 0 {
                steps.append(PlanStep(
                    id: "apple.experiments", system: .apple, kind: .change,
                    summary: appleNameSummary("experiments", missing.map(\.name),
                                              total: experiments.count, read: read)
                        + "  ·  \(treatments) treatments (not started)",
                    title: "Write \(experiments.count) product page experiments",
                    requests: [RequestSketch("POST", "/v2/appStoreVersionExperiments"),
                               RequestSketch("POST", "/v1/appStoreVersionExperimentTreatments")],
                    operation: .appleExperiments,
                    comparison: read && treatments == 0 ? .verified : .unverified))
            }
        }
        if let events = marketing.events, !events.isEmpty {
            let missing = events.filter { actual?.appEventNames[$0.key] == nil }
            let localized = events.contains { $0.locales?.isEmpty == false }
            if !read || !missing.isEmpty || localized {
                steps.append(PlanStep(
                    id: "apple.events", system: .apple, kind: .change,
                    summary: appleNameSummary("in-app events", missing.map(\.key),
                                              total: events.count, read: read),
                    title: "Write \(events.count) in-app events",
                    requests: [RequestSketch("POST", "/v1/appEvents"),
                               RequestSketch("POST", "/v1/appEventLocalizations")],
                    operation: .appleAppEvents,
                    comparison: read && !localized ? .verified : .unverified))
            }
        }
        if let eula = marketing.eula, !eula.text.isEmpty,
           !read || eula.text != actual?.eulaText
            || (eula.territories.map { Set($0) != actual?.eulaTerritories } ?? false) {
            steps.append(PlanStep(
                id: "apple.eula", system: .apple, kind: .change,
                summary: "licence agreement  \(eula.text.count) characters"
                    + (actual?.eulaText == nil ? "" : " (replaces the current one)"),
                title: "Write the licence agreement",
                requests: [RequestSketch("POST", "/v1/endUserLicenseAgreements")],
                operation: .appleEULA,
                comparison: read ? .verified : .unverified))
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
        if let nomination = marketing.nomination,
           !read || !actual!.nominationNames.contains(nomination.name) {
            steps.append(PlanStep(
                id: "apple.nomination", system: .apple, kind: .change,
                summary: "nomination  \(nomination.name)",
                title: "Write the featuring nomination",
                requests: [RequestSketch("POST", "/v1/nominations")],
                operation: .appleNomination,
                comparison: read ? .verified : .unverified))
        }
        if let accessibility = marketing.accessibility, !accessibility.supports.isEmpty,
           !read || Set(accessibility.supports) != actual!.accessibilitySupports {
            let missing = Set(accessibility.supports)
                .subtracting(actual?.accessibilitySupports ?? [])
            steps.append(PlanStep(
                id: "apple.accessibility", system: .apple, kind: .change,
                summary: "accessibility  \(accessibility.supports.count) features"
                    + (read ? "  ·  \(missing.count) to add" : ""),
                title: "Write the accessibility declaration",
                requests: [RequestSketch("POST", "/v1/accessibilityDeclarations")],
                operation: .appleAccessibility,
                comparison: read ? .verified : .unverified))
        }
        if let clip = marketing.appClip {
            // The experience exists or it does not, and its localized titles
            // have no read. A clip that names locales keeps its step.
            let localized = clip.locales?.isEmpty == false
                || clip.advancedExperiences?.isEmpty == false
            let held = read && actual?.hasAppClipExperience == true
                && (clip.action.map { actual!.appClipExperienceActions.contains($0) } ?? true)
            if !held || localized {
                steps.append(PlanStep(
                    id: "apple.appClip", system: .apple, kind: .change,
                    summary: "app clip default experience",
                    title: "Write the App Clip default experience",
                    requests: [RequestSketch("POST", "/v1/appClipDefaultExperiences"),
                               RequestSketch("POST", "/v1/appClipDefaultExperienceLocalizations")],
                    operation: .appleAppClip,
                    comparison: read && !localized ? .verified : .unverified))
            }
        }
        return steps
    }

    /// `3 of 5 to write · alpha, beta`, or the plain count before a read.
    static func appleNameSummary(_ noun: String, _ missing: [String],
                                 total: Int, read: Bool) -> String {
        guard read else { return "\(total) \(noun)" }
        let named = missing.prefix(3).joined(separator: ", ")
        return "\(missing.count) of \(total) \(noun) to write"
            + (named.isEmpty ? "" : "  ·  \(named)")
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
            appendChange(&changes, .name, manifest.listingText(locale: code, field: .name),
                         listing?.title)
            appendChange(&changes, .googleShortDescription, googleShortDescription(manifest, code),
                         listing?.shortDescription)
            appendChange(&changes, .description, managedText(manifest, code, .description),
                         listing?.fullDescription)
            appendChange(&changes, .googleVideo, managedText(manifest, code, .googleVideo),
                         listing?.video)
            // A null in the manifest clears the field, and the apply sends an
            // empty string for it. `appendChange` reads the flattened text,
            // where a cleared field and an absent key look alike, so the row
            // that says "clear it" can only come from here.
            let entry = manifest.listing?.locales[code]
            appendClear(&changes, .googleShortDescription,
                        entry?.google?.shortDescription ?? .unmanaged,
                        fallback: entry?.subtitle, listing?.shortDescription)
            appendClear(&changes, .description, entry?.description ?? .unmanaged,
                        fallback: nil, listing?.fullDescription)
            appendClear(&changes, .googleVideo, entry?.google?.video ?? .unmanaged,
                        fallback: nil, listing?.video)
            if !changes.isEmpty {
                body.append(PlanStep(
                    id: "google.listing.\(code)", system: .google,
                    kind: listing == nil ? .add : .change,
                    summary: "\(code)  \(changes.joined(separator: ", "))",
                    title: "Write the \(code) listing",
                    // A locale Google already holds is patched, so an
                    // unmanaged field keeps whatever the Play Console holds.
                    // A new one is written whole.
                    requests: [RequestSketch(listing == nil ? "PUT" : "PATCH",
                                             "/edits/{editId}/listings/\(code)")],
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

        // Only a real CSV. Google owns the question ids, and the four the app
        // used to synthesize were its own invention, so that body could only
        // be refused. The step no longer appears without the file.
        if manifest.review?.dataSafetyCSV?.isEmpty == false {
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
                summary: artifactSummary(file, bytes: bytes, prefix: "bundle "),
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
                summary: artifactSummary(file, bytes: bytes, prefix: "apk "),
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

    /// Whether a base plan or a purchase option still needs its switch.
    ///
    /// Google keeps one state per base plan and per purchase option, and the
    /// catalog read already carries it. A product that already sits in the
    /// wanted state needs no call.
    static func googleStateStep(productId: String, active: Bool,
                                actual: ActualState.Google?)
        -> (now: String, comparison: ComparisonConfidence)? {
        guard let live = actual?.catalog[productId]?.basePlanState else {
            // No read means no comparison. The switch still runs, and the plan
            // says that nobody verified it.
            return ("", .unverified)
        }
        guard (live == "ACTIVE") != active else { return nil }
        return ("  ·  now \(live.lowercased())", .verified)
    }

    /// Which offers Google does not hold yet.
    ///
    /// The batch write carries every offer of the product, because one call
    /// costs less than a call per offer. The summary names the offers that are
    /// missing, and the step goes when Google holds them all.
    static func googleOfferWrite(_ offers: [Manifest.Offer], productId: String,
                                 actual: ActualState.Google?)
        -> (summary: String, comparison: ComparisonConfidence)? {
        guard let live = actual?.catalog[productId] else {
            return ("\(offers.count) offers on \(productId)", .unverified)
        }
        let missing = offers.filter { live.offerStates[$0.id] == nil }
        guard !missing.isEmpty else { return nil }
        let named = missing.prefix(3).map(\.id).joined(separator: ", ")
        return ("\(missing.count) of \(offers.count) offers on \(productId)  ·  \(named)",
                .verified)
    }

    // MARK: - The Google catalog diff

    /// Which products differ from the manifest, and in which fields.
    ///
    /// `verified` is false when a wanted product exists in the store and its
    /// detail could not be read. The plan then says `unverified` rather than
    /// claim a diff that nobody checked.
    /// The review detail fields that differ from what Apple holds.
    ///
    /// An attachment has no readable counterpart, so a manifest that names one
    /// always lists it and the upload repeats.
    /// The age rating fields to write, and the ones Apple does not have.
    ///
    /// One definition for the plan, the run, the validator, and the sheet. An
    /// answer that matches the store is not a change, so an app that already
    /// carries its rating writes nothing and keeps what it has.
    ///
    /// A key the read never returned is a key Apple has no attribute for, and
    /// sending one fails the whole apply with a 409. The read decides, so a
    /// field Apple adds needs no release here.
    public static func appleAgeRatingChanges(
        _ review: Manifest.Review?, _ actual: ActualState.Apple?
    ) -> (write: [String: AgeRatingAnswer], unknown: [String]) {
        let wanted = review?.ageRatingAnswers ?? [:]
        guard !wanted.isEmpty else { return ([:], []) }
        // With no read there is nothing to compare against and nothing to
        // check a name against, so the apply writes nothing.
        let held = actual?.ageRating ?? [:]
        guard !held.isEmpty else { return ([:], []) }

        var write: [String: AgeRatingAnswer] = [:]
        var unknown: [String] = []
        for (key, value) in wanted {
            guard let current = held[key] else { unknown.append(key); continue }
            guard current != value else { continue }
            write[key] = value
        }
        return (write, unknown.sorted())
    }

    static func appleReviewDetailChanges(_ review: Manifest.Review,
                                         _ actual: ActualState.Apple?) -> [String] {
        var changes: [String] = []
        func compare(_ label: String, _ wanted: String?, _ live: String?) {
            guard let wanted, !wanted.isEmpty, wanted != live else { return }
            changes.append(label)
        }
        compare("contact email", review.contactEmail, actual?.reviewContactEmail)
        compare("first name", review.contactFirstName, actual?.reviewContactFirstName)
        compare("last name", review.contactLastName, actual?.reviewContactLastName)
        compare("phone", review.contactPhone, actual?.reviewContactPhone)
        compare("notes", review.notes, actual?.reviewNotes)
        if let required = review.demoAccountRequired,
           required != actual?.reviewDemoAccountRequired {
            changes.append("demo account")
        }
        if review.attachments?.isEmpty == false { changes.append("attachments") }
        return changes
    }

    // MARK: - The App Store catalog diff

    enum AppleCatalogKind { case purchases, subscriptions }

    /// The App Store twin of `googleCatalogDiff`.
    ///
    /// The two stores shape a product differently, so the two diffs stay
    /// apart. The rule is the same: name the products that differ, and say so
    /// when a read failed instead of showing a diff that nobody verified.
    static func appleCatalogDiff(_ manifest: Manifest, _ actual: ActualState.Apple?,
                                 kind: AppleCatalogKind)
        -> (changes: [String], summary: String, verified: Bool) {
        var changes: [String] = []
        var verified = actual != nil
        /// A field that the write sends and no read returns. It keeps the step
        /// and it makes the row honest about what nobody compared.
        var unreadableFields = false

        func compare(id: String, exists: Bool,
                     wanted: ActualState.Apple.CatalogProduct) {
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
            if wanted.managesLocales && !live.localesRead {
                verified = false
                fields.append("localizations unread")
            } else {
                if wanted.managesLocales,
                   Set(wanted.locales.keys) != Set(live.locales.keys) {
                    fields.append("locales")
                }
                for (locale, text) in wanted.locales.sorted(by: { $0.key < $1.key }) {
                    let current = live.locales[locale]
                    if text.name != current?.name { fields.append("name") }
                    if let detail = text.description, detail != (current?.description ?? "") {
                        fields.append("description")
                    }
                }
            }
            for (territory, price) in wanted.prices
            where appleNormalizedPrice(live.prices[territory]) != price {
                fields.append("price")
            }
            if !wanted.availableTerritories.isEmpty,
               wanted.availableTerritories != live.availableTerritories {
                fields.append("territories")
            }
            if !wanted.subscriptionPlanTerritories.isEmpty {
                if !live.subscriptionPlanAvailabilityRead {
                    verified = false
                    fields.append("plan availability unread")
                } else if wanted.subscriptionPlanTerritories
                    != live.subscriptionPlanTerritories {
                    fields.append("territories")
                }
            }
            if let promoted = wanted.promoted, promoted != live.promoted {
                fields.append("promoted")
            }
            if let duration = wanted.duration, duration != live.duration {
                fields.append("duration")
            }
            if let note = wanted.reviewNote, note != live.reviewNote {
                fields.append("review note")
            }
            let unique = NSOrderedSet(array: fields).compactMap { $0 as? String }
            guard !unique.isEmpty else { return }
            changes.append("\(id)  \(unique.joined(separator: ", "))")
        }

        if kind == .purchases {
            for purchase in manifest.purchases ?? [] {
                var wanted = ActualState.Apple.CatalogProduct()
                wanted.productId = purchase.id
                wanted.locales = appleWantedLocales(purchase.locales, fallbackName: purchase.id)
                // A purchase that names no locale manages none, the same rule
                // the plans below follow. Claiming otherwise compared an empty
                // wanted set against the names Apple holds, so every purchase
                // read as changed forever and the apply rewrote products that
                // matched the manifest already.
                wanted.managesLocales = purchase.locales?.isEmpty == false
                if let price = purchase.price {
                    wanted.prices[applePriceTerritory(price)] = applePriceText(price)
                }
                wanted.availableTerritories = Set(purchase.availableTerritories ?? [])
                wanted.promoted = purchase.promotedPurchase
                wanted.reviewNote = purchase.reviewNote
                compare(id: purchase.id,
                        exists: actual?.purchaseIds.contains(purchase.id) ?? false,
                        wanted: wanted)
                // The screenshot is an upload and the content flag has no
                // readable counterpart, so a manifest that names either one
                // keeps the step and the write repeats.
                if purchase.reviewScreenshot?.isEmpty == false
                    || purchase.contentHosting != nil {
                    unreadableFields = true
                    if !changes.contains(where: { $0.hasPrefix(purchase.id) }) {
                        changes.append("\(purchase.id)  review screenshot or content")
                    }
                }
            }
        } else {
            for group in manifest.subscriptions ?? [] {
                // The write covers the group as well as its plans, so a group
                // that Apple does not hold, or whose localizations differ,
                // keeps the step even when every plan matches.
                let reference = group.groupName ?? group.groupId
                if let live = actual {
                    if !live.subscriptionGroupNames.contains(reference) {
                        changes.append("\(reference)  group create")
                    } else if let wanted = group.locales, !wanted.isEmpty {
                        let held = live.subscriptionGroupLocales[reference]
                        if held == nil { verified = false }
                        let differs = wanted.contains { locale, text in
                            (text.name ?? reference) != held?[locale]?.name
                        }
                        if differs { changes.append("\(reference)  group name") }
                    }
                }
                for plan in group.plans {
                    var wanted = ActualState.Apple.CatalogProduct()
                    wanted.productId = plan.id
                    // The writer skips the localizations when the plan names
                    // none, so the diff skips them too.
                    wanted.locales = appleWantedLocales(plan.locales, fallbackName: plan.id)
                    wanted.managesLocales = plan.locales != nil
                    if let price = plan.price {
                        wanted.prices[applePriceTerritory(price)] = applePriceText(price)
                    }
                    wanted.duration = plan.duration
                    if let type = plan.applePlanType,
                       let territories = plan.availableTerritories, !territories.isEmpty {
                        wanted.subscriptionPlanTerritories[type] = Set(territories)
                    }
                    compare(id: plan.id,
                            exists: actual?.subscriptionIds.contains(plan.id) ?? false,
                            wanted: wanted)
                    // The screenshot is an upload with no readable counterpart,
                    // so a plan that names one keeps the step and the write
                    // repeats. The purchase branch follows the same rule.
                    if plan.reviewScreenshot?.isEmpty == false {
                        unreadableFields = true
                        if !changes.contains(where: { $0.hasPrefix(plan.id) }) {
                            changes.append("\(plan.id)  review screenshot")
                        }
                    }
                }
            }
        }

        let noun = kind == .purchases ? "purchases" : "subscriptions"
        let summary = changes.count <= 3
            ? changes.joined(separator: "  ·  ")
            : "\(changes.count) \(noun) differ  ·  \(changes.prefix(2).joined(separator: "  ·  "))  ·  …"
        return (changes, summary, verified && !unreadableFields)
    }

    /// The subscription offers that Apple does not already hold.
    ///
    /// Apple names a promotional offer by its code and a win back offer by its
    /// reference name. It names no introductory offer at all, so an
    /// introductory offer stays in the diff and the write repeats. The write
    /// is idempotent, and the summary now says which offer it sends.
    static func appleOfferDiff(_ manifest: Manifest, _ actual: ActualState.Apple?)
        -> (changes: [String], summary: String, verified: Bool) {
        var changes: [String] = []
        var verified = actual != nil

        for group in manifest.subscriptions ?? [] {
            for plan in group.plans {
                for offer in plan.offers ?? [] {
                    let live = actual?.catalog[plan.id]
                    if live?.offerCount == nil { verified = false }
                    guard live?.offerIds.contains(offer.id) != true else { continue }
                    changes.append("\(plan.id)  \(offer.id)")
                }
            }
        }

        let summary = changes.count <= 3
            ? changes.joined(separator: "  ·  ")
            : "\(changes.count) offers differ  ·  \(changes.prefix(2).joined(separator: "  ·  "))  ·  …"
        return (changes, summary, verified)
    }

    /// The localizations that the App Store writers send. `name` falls back to
    /// the product id and `description` to the empty string, so the diff and
    /// the write agree on what an unset field means.
    static func appleWantedLocales(_ locales: [String: Manifest.ProductLocale]?,
                                   fallbackName: String)
        -> [String: ActualState.Apple.CatalogProduct.ProductLocale] {
        var result: [String: ActualState.Apple.CatalogProduct.ProductLocale] = [:]
        for (locale, text) in locales ?? [:] {
            var value = ActualState.Apple.CatalogProduct.ProductLocale()
            value.name = text.name ?? fallbackName
            value.description = text.description ?? ""
            result[locale] = value
        }
        return result
    }

    /// Apple keys a price by a three letter territory, and `USA` is its
    /// default the same way `US` is the Google one.
    static func applePriceTerritory(_ price: Price) -> String {
        price.territory ?? "USA"
    }

    /// The customer price, in the form both sides of the diff compare.
    ///
    /// A decimal literal cannot hold 4.99 exactly, so an unrounded string
    /// carries the error and every price reads as a change forever. The Google
    /// side avoids this through units and nanos; the App Store takes a plain
    /// decimal string, so both sides round to the same place instead.
    static func applePriceText(_ price: Price) -> String {
        appleNormalizedPrice(NSDecimalNumber(decimal: price.amount).stringValue) ?? ""
    }

    static func appleNormalizedPrice(_ text: String?) -> String? {
        guard let text, var value = Price.amount(from: text) else { return nil }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 6, .plain)
        return NSDecimalNumber(decimal: rounded).stringValue
    }

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
            if let active = purchase.active,
               let state = googleStateStep(productId: purchase.id, active: active,
                                           actual: input.actual.google) {
                steps.append(PlanStep(
                    id: "google.purchaseOptionState.\(purchase.id)", system: .google,
                    kind: .change,
                    summary: "purchase option  \(purchase.id)  "
                        + "\(active ? "activate" : "deactivate")\(state.now)",
                    title: "\(active ? "Activate" : "Deactivate") \(purchase.id)",
                    requests: [RequestSketch(
                        "POST", "/monetization/oneTimeProducts/{id}/purchaseOptions:batchUpdateStates")],
                    operation: .googlePurchaseOptionState(productId: purchase.id,
                                                          purchaseOptionId: purchase.id,
                                                          active: active),
                    comparison: state.comparison))
            }
            if let offers = purchase.offers, !offers.isEmpty {
                // The content write and the state switch are two independent
                // steps. An offer whose content already matches can still need
                // its switch, so neither one gates the other.
                if let write = googleOfferWrite(offers, productId: purchase.id,
                                                actual: input.actual.google) {
                    steps.append(PlanStep(
                        id: "google.oneTimeOffers.\(purchase.id)", system: .google, kind: .change,
                        summary: write.summary,
                        title: "Write \(offers.count) offers on \(purchase.id)",
                        requests: [RequestSketch(
                            "POST",
                            "/monetization/oneTimeProducts/{id}/purchaseOptions/{option}/offers:batchUpdate")],
                        operation: .googleOneTimeOffers(productId: purchase.id),
                        comparison: write.comparison))
                }
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
                if let active = plan.active,
                   let state = googleStateStep(productId: plan.id, active: active,
                                               actual: input.actual.google) {
                    steps.append(PlanStep(
                        id: "google.basePlanState.\(plan.id)", system: .google, kind: .change,
                        summary: "base plan  \(basePlanId)  "
                            + "\(active ? "activate" : "deactivate")\(state.now)",
                        title: "\(active ? "Activate" : "Deactivate") the \(basePlanId) base plan",
                        requests: [RequestSketch(
                            "POST",
                            "/monetization/subscriptions/{id}/basePlans/{plan}:\(active ? "activate" : "deactivate")")],
                        operation: .googleBasePlanState(productId: plan.id,
                                                        basePlanId: basePlanId,
                                                        active: active),
                        comparison: state.comparison))
                }
                if let offers = plan.offers, !offers.isEmpty {
                    if let write = googleOfferWrite(offers, productId: plan.id,
                                                    actual: input.actual.google) {
                        steps.append(PlanStep(
                            id: "google.subscriptionOffers.\(plan.id)", system: .google,
                            kind: .change,
                            summary: write.summary,
                            title: "Write \(offers.count) offers on \(plan.id)",
                            requests: [RequestSketch(
                                "POST",
                                "/monetization/subscriptions/{id}/basePlans/{plan}/offers:batchUpdate")],
                            operation: .googleSubscriptionOffers(productId: plan.id,
                                                                 basePlanId: basePlanId),
                            comparison: write.comparison))
                    }
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
                // A migration moves the existing subscribers onto the current
                // regional price. When Google already sells at the wanted
                // price there is nothing left to move, so the step goes.
                if plan.migrateExistingSubscribers == true {
                    let live = input.actual.google?.catalog[plan.id]
                    let region = plan.price?.territory ?? "US"
                    let wanted = plan.price.map(googlePriceText)
                    let settled = wanted != nil && live?.prices[region] == wanted
                    if !settled {
                        steps.append(PlanStep(
                            id: "google.migratePrices.\(plan.id)", system: .google, kind: .change,
                            summary: "migrate the existing subscribers of \(plan.id)"
                                + (live?.prices[region].map { "  ·  now \($0)" } ?? ""),
                            title: "Migrate the prices of \(plan.id)",
                            requests: [RequestSketch(
                                "POST",
                                "/monetization/subscriptions/{id}/basePlans:batchMigratePrices")],
                            operation: .googleMigratePrices(productId: plan.id,
                                                            basePlanId: basePlanId),
                            comparison: live == nil ? .unverified : .verified))
                    }
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

        // The same rule for a one-time product. Google offers no archive here,
        // and a delete would break an installed app that still asks for the
        // product, so the purchase option goes inactive instead. That stops
        // every new sale and it keeps what a customer already owns.
        let wantedPurchases = Set((manifest.purchases ?? []).map(\.id))
        for orphan in (input.actual.google?.oneTimeProductIds ?? [])
            .subtracting(wantedPurchases).sorted() {
            steps.append(PlanStep(
                id: "google.deactivate.\(orphan)", system: .google, kind: .remove,
                summary: "purchase  \(orphan)  stop the sale",
                title: "Stop the sale of \(orphan)",
                requests: [RequestSketch(
                    "POST", "/monetization/oneTimeProducts/{id}/purchaseOptions:batchUpdateStates")],
                operation: .googlePurchaseOptionState(productId: orphan,
                                                      purchaseOptionId: orphan, active: false)))
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
        // The Mac App Store is a third RevenueCat app, not a variant of the
        // App Store one. A manifest that names it gets its own product, and a
        // manifest that leaves it empty drops the row.
        let appIds = manifest.monetization?.revenuecat?.appIds
        let storeApps: [(key: String, label: String)] = provider == .revenuecat
            ? [(appIds?.appStore ?? "", "app_store"),
               (appIds?.macAppStore ?? "", "mac_app_store"),
               (appIds?.playStore ?? "", "play_store")]
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

        // Adapty attaches on the product itself, so `providerAttach` returns
        // at once and the step would write nothing.
        if provider == .revenuecat {
            for entitlement in manifest.entitlements ?? [] {
                let products = manifest.products(for: entitlement.key)
                guard !products.isEmpty else { continue }
                let live = actual?.entitlementProducts[entitlement.key]
                let missing = Set(products).subtracting(live ?? [])
                guard live == nil || !missing.isEmpty else { continue }
                steps.append(PlanStep(
                    id: "provider.attach.\(entitlement.key)", system: .provider, kind: .change,
                    summary: live == nil
                        ? "entitlement  \(entitlement.key)  attach \(products.count) products"
                        : "entitlement  \(entitlement.key)  attach \(missing.count) of \(products.count) products",
                    title: "Attach \(products.count) products to \(entitlement.key)",
                    requests: [providerRequest(provider, "attach the products")],
                    operation: .providerAttach(entitlement: entitlement.key,
                                               products: products),
                    comparison: live == nil ? .unverified : .verified))
            }
        }

        for offering in manifest.offerings ?? [] {
            let known = actual?.offeringKeys.contains(offering.key) == true
            let live = actual?.offeringProducts[offering.key]
            let wanted = offering.products ?? []
            // The package list and the current flag are the two things the
            // write changes. Both matching means the offering is already there.
            let currentDiffers = (offering.isCurrent ?? false)
                && actual?.currentOfferingKey != offering.key
            guard live == nil || live != wanted || currentDiffers else { continue }
            steps.append(PlanStep(
                id: "provider.offering.\(offering.key)", system: .provider,
                kind: known ? .change : .add,
                summary: "offering  \(offering.key)  \(wanted.count) packages"
                    + (live.map { "  ·  now \($0.count)" } ?? ""),
                title: "Write the \(offering.key) offering",
                requests: [providerRequest(provider, "write the offering")],
                operation: .providerOffering(key: offering.key),
                comparison: live == nil ? .unverified : .verified))
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

    /// Why a set of pictures is being sent again, in one clause.
    ///
    /// Screenshots are the whole weight of an update, so "replace with 5
    /// screenshots · 12 MB" is the row a developer stops at, and it used to
    /// give no reason at all. The commonest question about this app was why it
    /// wanted to send pictures the store already had, and the plan knew the
    /// answer every time: the version it writes to holds none, or the bytes on
    /// this Mac are not the bytes the store took.
    ///
    /// The comparison is by content, never by file name: Apple returns the MD5
    /// it was given at upload and Google returns a SHA-256. Re-exporting an
    /// identical-looking image changes those, and that is a real difference —
    /// the store holds the older bytes.
    static func mediaReason(read: Bool, starting: [String]?, desired: [String]) -> String {
        guard read else { return "the store was not read" }
        guard let starting, !starting.isEmpty else { return "the store holds none" }
        if Set(starting) == Set(desired) { return "the same pictures, in another order" }
        let shared = Set(starting).intersection(desired).count
        guard shared > 0 else {
            return desired.count == starting.count
                ? "all \(desired.count) differ"
                : "the store holds \(starting.count)"
        }
        return "\(desired.count - shared) of \(desired.count) differ"
    }

    private static func mediaSteps(_ input: Input, store: Store) -> [PlanStep] {
        let manifest = input.manifest
        var steps: [PlanStep] = []
        let locales = Array(manifest.media?.screenshots?.keys ?? [:].keys).sorted()

        for code in locales {
            for deviceClass in Manifest.DeviceClass.allCases {
                // Per store, so an override sends this store its own pictures
                // and the other store keeps the shared ones.
                let paths = manifest.mediaPaths(locale: code, deviceClass: deviceClass,
                                                store: store)
                guard !paths.isEmpty else { continue }
                let uploads = mediaUploads(paths, deviceClass: deviceClass, store: store,
                                           root: input.root)
                guard !uploads.isEmpty else { continue }

                let key = "\(code)/\(uploads[0].bucket)"
                let held: Set<String>
                switch store {
                case .apple:
                    held = input.actual.apple?.screenshotChecksums[key] ?? []
                case .google:
                    held = input.actual.google?.imageHashes[key] ?? []
                }
                let desired = uploads.map { store == .apple ? $0.md5 : $0.sha256 }
                // The pictures the next version starts with, which for an
                // update are the ones Apple carries over from the released
                // version. A set that already matches uploads nothing, and
                // that is the whole cost of an update: the text is bytes and
                // the screenshots are megabytes.
                //
                // Apple keeps its order and Google does not, so Apple compares
                // the list and Google compares the set.
                let starting = store == .apple
                    ? input.actual.apple?.startingScreenshotOrder(key)
                    : Array(held)
                let orderedMatches = store == .apple
                    ? starting == desired
                    : held == Set(desired)
                guard !orderedMatches else { continue }
                // Whether anybody checked. With no read there are no checksums,
                // so the skip above cannot fire and every set looks new: an
                // update whose credentials had lapsed read "replace with 5
                // screenshots" in the same green as a set that really had
                // changed. The upload is still right, because an unknown store
                // is not a matching one, but the plan may not call it verified.
                let read = store == .apple
                    ? input.actual.apple != nil
                    : input.actual.google != nil
                let bytes = uploads.reduce(Int64(0)) { $0 + $1.bytes }
                let label = store == .apple ? "screenshots" : "\(uploads[0].bucket)"
                let reason = mediaReason(read: read, starting: starting, desired: desired)
                steps.append(PlanStep(
                    id: "\(store.rawValue).media.\(code).\(deviceClass.rawValue)",
                    system: store == .apple ? .apple : .google, kind: .add,
                    summary: "replace with \(uploads.count) \(label)  ·  \(bytesText(bytes))  ·  \(reason)  (\(code))",
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
                    uploadCount: uploads.count, uploadBytes: bytes,
                    comparison: read ? .verified : .unverified))
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

    /// One changed field, named the way the developer names it.
    ///
    /// The count stays, because the length is what a store rejects a field
    /// for, and "chars" became "characters" for the same reason the name did.
    private static func appendChange(_ list: inout [String], _ field: ListingTextField,
                                     _ wanted: String, _ current: String?) {
        guard !wanted.isEmpty else { return }
        guard wanted != (current ?? "") else { return }
        list.append("\(field.label) (\(wanted.count) characters)")
    }

    /// One field the manifest asks Google to empty, named as such.
    ///
    /// A null in `store.yaml` is not the same as a missing key: the missing
    /// key leaves the Play Console alone, and the null wipes the field. Only
    /// the second is a change, and only when Google holds something to wipe.
    ///
    /// - Parameter fallback: the field the apply reads when this one is
    ///   unmanaged, which the short description has and the others do not.
    static func appendClear(_ list: inout [String], _ field: ListingTextField,
                            _ managed: Managed<String>,
                            fallback: Managed<String>?, _ current: String?) {
        let clears = switch managed {
        case .clear: true
        // An unmanaged field, or one holding an empty value, hands over to
        // the fallback, and then the fallback decides.
        case .unmanaged: fallback.map { if case .clear = $0 { true } else { false } } ?? false
        case .value(let text): text.isEmpty
            && (fallback.map { if case .clear = $0 { true } else { false } } ?? false)
        }
        guard clears, !(current ?? "").isEmpty else { return }
        list.append("\(field.label) (cleared)")
    }

    static func managedText(_ manifest: Manifest, _ code: String,
                            _ field: ListingTextField) -> String {
        manifest.listingText(locale: code, field: field)
    }

    static func googleShortDescription(_ manifest: Manifest, _ code: String) -> String {
        let override = manifest.listingText(locale: code, field: .googleShortDescription)
        return override.isEmpty ? manifest.listingText(locale: code, field: .subtitle) : override
    }

    /// The steps that no store API can ever confirm.
    ///
    /// Google publishes the data safety labels through a write and offers no
    /// read of them, so this row can never become a diff. It is separate from
    /// a row that merely failed to read, because no amount of work here would
    /// close it.
    static let unreadableStepPrefixes = ["google.dataSafety"]

    /// Marks the rows that no read backs.
    ///
    /// Every other step now compares real store state and marks itself, so
    /// this only forces the rows on `unreadableStepPrefixes` and then collects
    /// whatever marked itself along the way.
    private static func markUnverifiedComparisons(_ result: inout PlanResult) {
        var unreadable: [String] = []
        var unverified: [String] = []
        for index in result.steps.indices {
            let isUnreadable = unreadableStepPrefixes.contains {
                result.steps[index].id.hasPrefix($0)
            }
            guard isUnreadable || result.steps[index].comparison == .unverified else { continue }
            result.steps[index].comparison = .unverified
            if !result.steps[index].summary.hasPrefix("unverified · ") {
                result.steps[index].summary = "unverified · " + result.steps[index].summary
            }
            if isUnreadable { unreadable.append(result.steps[index].id) }
            else { unverified.append(result.steps[index].id) }
        }
        if !unverified.isEmpty {
            result.findings.append(Finding(
                id: "plan.unverified", severity: .warning,
                message: "\(Self.rows(unverified.count)) the store did not answer for. They may repeat.",
                location: "Summary", fix: .plan))
        }
        if !unreadable.isEmpty {
            result.findings.append(Finding(
                id: "plan.unreadable", severity: .warning,
                message: "\(Self.rows(unreadable.count)) no read can confirm. They repeat by design.",
                location: "Summary", fix: .plan))
        }
    }

    private static func rows(_ count: Int) -> String {
        count == 1 ? "1 row" : "\(count) rows"
    }

    /// Apple's three release types, as the sentence each one means.
    ///
    /// `AFTER_APPROVAL`, `MANUAL`, and `SCHEDULED` are API constants. The
    /// Summary tab is the screen a developer reads before they let the app
    /// write to a live store, and a constant in shouting case tells them
    /// nothing about what their customers will see or when.
    static func appleReleaseLabel(_ manifest: Manifest) -> String {
        switch manifest.release?.apple?.releaseType?.rawValue {
        case "AFTER_APPROVAL": "as soon as Apple approves it"
        case "MANUAL": "when you release it yourself"
        case "SCHEDULED": "on the date you scheduled"
        case let other?: other
        case nil: "not set"
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

    /// How old the artifact is, in the words an upload row uses.
    ///
    /// An upload row named the file and its size and never said when it was
    /// made, so a build from last month read exactly like one made a minute
    /// ago. The manifest names a path, not a moment, and the file at that path
    /// is whatever was last written there: a developer who rebuilt their app
    /// somewhere else has an old artifact sitting under the same name.
    ///
    /// The age is the one field that tells those two apart, and this is the
    /// row the developer reads immediately before Apply sends the bytes.
    ///
    /// `// ponytail: the age, not a policy. No threshold refuses an upload,
    /// // because a legitimate artifact can be a week old and only the person
    /// // pressing the button knows which one this is.`
    public static func builtText(_ file: URL, now: Date = Date()) -> String? {
        guard let date = try? file.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate else { return nil }
        let minutes = Int(now.timeIntervalSince(date) / 60)
        guard minutes >= 1 else { return "built just now" }
        if minutes < 60 { return "built \(count(minutes, "minute")) ago" }
        let hours = minutes / 60
        if hours < 24 { return "built \(count(hours, "hour")) ago" }
        return "built \(count(hours / 24, "day")) ago"
    }

    private static func count(_ value: Int, _ noun: String) -> String {
        "\(value) \(noun)\(value == 1 ? "" : "s")"
    }

    /// `file.aab · 41 MB · built 3 days ago`, for an upload row.
    static func artifactSummary(_ file: URL, bytes: Int64, prefix: String) -> String {
        [prefix + file.lastPathComponent, bytesText(bytes), builtText(file)]
            .compactMap { $0 }
            .joined(separator: "  ·  ")
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
