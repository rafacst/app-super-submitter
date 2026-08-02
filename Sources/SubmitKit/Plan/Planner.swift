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

        // 9. The review details.
        if let review = manifest.review,
           review.contactEmail?.isEmpty == false || review.notes?.isEmpty == false {
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
        if let answers = manifest.review?.ageRatingAnswers, !answers.isEmpty {
            steps.append(PlanStep(
                id: "apple.ageRating", system: .apple, kind: .change,
                summary: "age rating  \(answers.count) answers",
                title: "Write the age rating answers",
                requests: [RequestSketch("PATCH", "/v1/ageRatingDeclarations/{id}")],
                operation: .appleAgeRating))
        }

        // 11. The purchases and the subscriptions.
        let purchaseCount = (manifest.purchases?.count ?? 0)
            + (manifest.subscriptions?.reduce(0) { $0 + $1.plans.count } ?? 0)
        if purchaseCount > 0 {
            steps.append(PlanStep(
                id: "apple.purchases", system: .apple, kind: .change,
                summary: "\(purchaseCount) products in the catalog",
                title: "Write \(purchaseCount) purchases",
                requests: [RequestSketch("GET", "/v2/inAppPurchases"),
                           RequestSketch("POST", "/v2/inAppPurchases")],
                operation: .applePurchases))
        }

        // 12 and 13.
        if manifest.release?.apple?.phasedRelease == true {
            steps.append(PlanStep(
                id: "apple.phased", system: .apple, kind: .add,
                summary: "phased release over 7 days",
                title: "Turn on the phased release",
                requests: [RequestSketch("POST", "/v1/appStoreVersionPhasedReleases")],
                operation: .applePhasedRelease))
        }
        if manifest.pricing?.autoConvertOtherTerritories != nil {
            steps.append(PlanStep(
                id: "apple.availability", system: .apple, kind: .change,
                summary: "territory availability",
                title: "Write the territory availability",
                requests: [RequestSketch("POST", "/v2/appAvailabilities")],
                operation: .appleAvailability))
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

        if manifest.review?.contactEmail?.isEmpty == false {
            body.append(PlanStep(
                id: "google.details", system: .google, kind: .change,
                summary: "contact  \(manifest.review?.contactEmail ?? "")",
                title: "Write the contact details",
                requests: [RequestSketch("PATCH", "/edits/{editId}/details")],
                operation: .googleDetails))
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

        let track = manifest.release?.google?.track ?? "production"
        body.append(PlanStep(
            id: "google.track", system: .google, kind: .change,
            summary: "track \(track)  release draft",
            title: "Write the \(track) track, draft",
            requests: [RequestSketch("PATCH", "/edits/{editId}/tracks/\(track)")],
            operation: .googleTrack))

        let productCount = (manifest.purchases?.count ?? 0)
            + (manifest.subscriptions?.count ?? 0)
        if productCount > 0 {
            body.append(PlanStep(
                id: "google.products", system: .google, kind: .change,
                summary: "\(productCount) products in the catalog",
                title: "Write \(productCount) products",
                requests: [RequestSketch("POST", "/monetization/onetimeproducts:batchUpdate"),
                           RequestSketch("POST", "/monetization/subscriptions:batchUpdate")],
                operation: .googleProducts))
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
                // Spec 7.5: an upload whose checksum already matches is
                // skipped, and that is what makes an apply idempotent.
                let pending = uploads.filter { upload in
                    !held.contains(store == .apple ? upload.md5 : upload.sha256)
                }
                guard !pending.isEmpty else { continue }
                let bytes = pending.reduce(Int64(0)) { $0 + $1.bytes }
                let label = store == .apple ? "screenshots" : "\(pending[0].bucket)"
                steps.append(PlanStep(
                    id: "\(store.rawValue).media.\(code).\(deviceClass.rawValue)",
                    system: store == .apple ? .apple : .google, kind: .add,
                    summary: "\(pending.count) \(label)  ·  \(bytesText(bytes))  (\(code))",
                    title: "Upload \(pending.count) \(label) for \(code)",
                    requests: store == .apple
                        ? [RequestSketch("POST", "/v1/appScreenshotSets"),
                           RequestSketch("POST", "/v1/appScreenshots")]
                        : [RequestSketch("POST", "/edits/{editId}/listings/\(code)/images")],
                    operation: store == .apple
                        ? .appleScreenshots(locale: code, deviceClass: deviceClass.rawValue,
                                            files: pending)
                        : .googleImages(locale: code, imageType: pending[0].bucket,
                                        files: pending),
                    uploadCount: pending.count, uploadBytes: bytes))
            }

            // Apple takes a video file. Google takes a YouTube URL and no file.
            guard store == .apple else { continue }
            for deviceClass in Manifest.DeviceClass.allCases {
                let paths = manifest.mediaPaths(locale: code, deviceClass: deviceClass,
                                                previews: true)
                guard !paths.isEmpty else { continue }
                let files: [MediaUpload] = paths.compactMap { path in
                    guard let url = resolve(path, root: input.root) else { return nil }
                    return MediaUpload(path: path, url: url, bytes: fileSize(url), md5: "",
                                       sha256: "", bucket: deviceClass.rawValue)
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

    static func applePath(_ manifest: Manifest) -> String? {
        manifest.release?.build?.ios ?? manifest.release?.build?.macos
    }

    static func resolve(_ path: String, root: URL?) -> URL? {
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
