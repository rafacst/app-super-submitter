import Foundation

public enum StepState: String, Sendable, Equatable {
    case pending, running, done, failed, skipped
}

public struct RunFailure: Sendable, Equatable {
    public var stepIndex: Int
    public var system: PlanSystem
    public var message: String
    /// True while the Google edit still exists, so an undo can delete it.
    /// After the commit the draft sits in the Play Console and no undo removes
    /// it. Spec section 11.1 states both limits on the panel.
    public var canUndoGoogleEdit: Bool
}

public enum RunEvent: Sendable {
    case step(index: Int, state: StepState, meta: String)
    case progress(index: Int, fraction: Double, detail: String)
    case log(String)
    case failure(RunFailure)
    /// Spec 11.2. A provider failure never holds a store draft.
    case providerFailed(String)
    case finished
}

/// Runs a plan. Spec sections 7.3 to 7.8.
///
/// **The run holds no irreversible step.** Every write ends in a draft, so
/// there is no two-phase commit here and no rollback engine. A failed run is
/// fixed by a re-run, because an apply is idempotent.
public actor Runner {
    public let plan: PlanResult
    let manifest: Manifest
    let actual: ActualState
    let root: URL?
    let api: StoreAPI
    let dryRun: Bool

    private let emit: @Sendable (RunEvent) -> Void
    private let log: RunLog?

    // What this run created. The undo needs it, and so does the next step.
    var appleVersionID: String?
    var appleInfoID: String?
    var appleInfoLocalizationIDs: [String: String] = [:]
    var appleVersionLocalizationIDs: [String: String] = [:]
    var appleBuildID: String?
    var googleEditID: String?
    var googleCommitted = false
    var googleVersionCode: Int?
    /// The APK upload reports its own code. An expansion file attaches to an
    /// APK and never to a bundle, so the two codes stay apart.
    var googleApkVersionCode: Int?
    /// The App Store subscription id of every product id that this run wrote.
    /// The offers attach to it, so the offer step reads this and never
    /// searches the store a second time.
    var appleSubscriptionIDsByProduct: [String: String] = [:]
    var createdProviderObjects: [(kind: String, id: String)] = []
    let reviewerCredential: ReviewerCredential?

    public init(plan: PlanResult, manifest: Manifest, actual: ActualState, root: URL?,
                credentials: StoreCredentials, dryRun: Bool,
                emit: @escaping @Sendable (RunEvent) -> Void) {
        self.plan = plan
        self.manifest = manifest
        self.actual = actual
        self.root = root
        self.dryRun = dryRun
        self.emit = emit
        self.reviewerCredential = credentials.reviewer
        let runLog = root.flatMap { try? RunLog(root: $0) }
        self.log = runLog
        let sink: CallRecorder = { call in
            let now = Date()
            emit(.log(call.line(at: now)))
            await runLog?.append(call, at: now)
        }
        self.api = StoreAPI(credentials: credentials, record: sink)
        self.appleVersionID = actual.apple?.versionId
        self.appleInfoID = actual.apple?.appInfoId
        self.appleInfoLocalizationIDs = actual.apple?.infoLocales
            .compactMapValues { $0.id } ?? [:]
        self.appleVersionLocalizationIDs = actual.apple?.versionLocales
            .compactMapValues { $0.id } ?? [:]
    }

    /// - Parameter from: the step to start at. A retry after a failure starts
    ///   at the failed step, and every earlier step already landed.
    public func run(from start: Int = 0) async {
        for index in plan.steps.indices where index >= start {
            let step = plan.steps[index]
            guard !Task.isCancelled else {
                await cleanUpGoogleEdit()
                await log?.close()
                return
            }
            emit(.step(index: index, state: .running, meta: ""))

            if dryRun {
                for sketch in step.requests {
                    await api.recordDryRun(system: step.system, method: sketch.method,
                                           path: sketch.path)
                }
                emit(.step(index: index, state: .done, meta: "dry run"))
                continue
            }

            let started = Date()
            do {
                try await perform(step, index: index)
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                emit(.step(index: index, state: .done, meta: "\(ms) ms"))
            } catch is CancellationError {
                await cleanUpGoogleEdit()
                await log?.close()
                return
            } catch {
                // A provider failure never blocks a store draft. The run
                // finishes and tab 9 gains a row. Spec section 11.2.
                if step.system == .provider {
                    emit(.step(index: index, state: .skipped, meta: "skipped"))
                    emit(.providerFailed(error.localizedDescription))
                    continue
                }
                emit(.step(index: index, state: .failed, meta: ""))
                emit(.failure(RunFailure(
                    stepIndex: index, system: step.system,
                    message: error.localizedDescription,
                    canUndoGoogleEdit: googleEditID != nil && !googleCommitted)))
                await log?.close()
                return
            }
        }
        await log?.close()
        emit(.finished)
    }

    /// Spec section 11.1. The undo deletes the Google edit when the run failed
    /// before the commit, and it archives the provider objects that this run
    /// created. It removes no Apple screenshot, because Apple keeps them in
    /// the version and a second apply reuses them by checksum.
    public func undo() async {
        await cleanUpGoogleEdit()
        for object in createdProviderObjects.reversed() {
            try? await archiveProviderObject(kind: object.kind, id: object.id)
        }
        createdProviderObjects = []
        await log?.close()
    }

    /// Runs the provider steps again, and nothing else. Spec 11.2, button 2.
    public func retryProvider() async {
        guard let first = plan.steps.firstIndex(where: { $0.system == .provider }) else { return }
        await run(from: first)
    }

    private func perform(_ step: PlanStep, index: Int) async throws {
        switch step.operation {
        case .appleEnsureVersion(let version): try await appleEnsureVersion(version)
        case .appleVersionAttributes: try await appleVersionAttributes()
        case .appleCategories: try await appleCategories()
        case .appleInfoLocale(let locale): try await appleInfoLocale(locale)
        case .appleVersionLocale(let locale): try await appleVersionLocale(locale)
        case .appleScreenshots(let locale, _, let files):
            try await appleScreenshots(locale: locale, files: files, index: index)
        case .applePreviews(let locale, _, let files):
            try await applePreviews(locale: locale, files: files, index: index)
        case .appleBuildUpload(let path, _): try await appleBuildUpload(path: path, index: index)
        case .appleAttachBuild: try await appleAttachBuild()
        case .appleReviewDetails: try await appleReviewDetails()
        case .appleAgeRating: try await appleAgeRating()
        case .applePurchases: try await applePurchases()
        case .applePhasedRelease: try await applePhasedRelease()
        case .appleAvailability: try await appleAvailability()
        case .appleSubscriptions: try await appleSubscriptions()
        case .appleSubscriptionOffers: try await appleSubscriptionOffers()
        case .appleGracePeriod: try await appleGracePeriod()
        case .appleCustomProductPages: try await appleCustomProductPages()
        case .appleExperiments: try await appleExperiments()
        case .appleAppEvents: try await appleAppEvents()
        case .appleEULA: try await appleEULA()
        case .appleRoutingCoverage(let path, _):
            try await appleRoutingCoverage(path: path, index: index)
        case .appleNomination: try await appleNomination()
        case .appleAccessibility: try await appleAccessibility()
        case .appleAppClip: try await appleAppClip()

        case .googleOpenEdit: try await googleOpenEdit()
        case .googleListing(let locale): try await googleListing(locale)
        case .googleDetails: try await googleDetails()
        case .googleImages(let locale, let imageType, let files):
            try await googleImages(locale: locale, imageType: imageType, files: files,
                                   index: index)
        case .googleBundleUpload(let path, _):
            try await googleBundleUpload(path: path, index: index)
        case .googleApkUpload(let path, _):
            try await googleApkUpload(path: path, index: index)
        case .googleExternalApk: try await googleExternalApk()
        case .googleDeobfuscation(let kind, let path, _):
            try await googleDeobfuscation(kind: kind, path: path, index: index)
        case .googleExpansionFile(let kind, let path, _):
            try await googleExpansionFile(kind: kind, path: path, index: index)
        case .googleCreateTrack(let track): try await googleCreateTrack(track)
        case .googleTrack(let track): try await googleTrack(track)
        case .googleProducts: try await googleProducts()
        case .googleDeviceTierConfig(let path): try await googleDeviceTierConfig(path: path)
        case .googleBasePlanState(let productId, let basePlanId, let active):
            try await googleBasePlanState(productId: productId, basePlanId: basePlanId,
                                          active: active)
        case .googlePurchaseOptionState(let productId, let purchaseOptionId, let active):
            try await googlePurchaseOptionState(productId: productId,
                                                purchaseOptionId: purchaseOptionId,
                                                active: active)
        case .googleSubscriptionOffers(let productId, let basePlanId):
            try await googleSubscriptionOffers(productId: productId, basePlanId: basePlanId)
        case .googleOneTimeOffers(let productId):
            try await googleOneTimeOffers(productId: productId)
        case .googleMigratePrices(let productId, let basePlanId):
            try await googleMigratePrices(productId: productId, basePlanId: basePlanId)
        case .googleArchiveSubscription(let productId):
            try await googleArchiveSubscription(productId: productId)
        case .googleValidate: try await googleValidate()
        case .googleCommit: try await googleCommit()

        case .providerProduct(let storeProductId, let appId):
            try await providerProduct(storeProductId: storeProductId, appId: appId)
        case .providerEntitlement(let key): try await providerEntitlement(key)
        case .providerAttach(let entitlement, let products):
            try await providerAttach(entitlement: entitlement, products: products)
        case .providerOffering(let key): try await providerOffering(key)
        case .providerArchive(let kind, let key):
            try await archiveProviderObject(kind: kind, id: key)
        }
    }

    /// A Google edit that nobody commits is invisible and it expires. The app
    /// deletes its own on any failure and on any cancellation. Spec 7.4.
    func cleanUpGoogleEdit() async {
        guard let editID = googleEditID, !googleCommitted, !dryRun else { return }
        _ = try? await api.google("DELETE", "\(googleBase)/edits/\(editID)")
        googleEditID = nil
        await log?.close()
    }

    func report(index: Int, fraction: Double, detail: String) {
        emit(.progress(index: index, fraction: fraction, detail: detail))
    }

    var googleBase: String {
        "/androidpublisher/v3/applications/\(StateReader.escape(manifest.apps.google?.packageName ?? ""))"
    }

    var appleAppID: String { manifest.apps.apple?.appId ?? "" }

    var applePlatform: String {
        manifest.apps.apple?.platforms.first?.rawValue ?? "IOS"
    }

    func resolve(_ path: String) -> URL? {
        Planner.resolve(path, root: root)
    }
}

public enum RunError: Error, LocalizedError {
    case missingVersion
    case missingBuild
    case missingEdit
    case missingLocalization(String)
    case uploadFailed(String)
    case processingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingVersion:
            "The App Store version could not be created or found."
        case .missingBuild:
            "The build file named in the manifest could not be read."
        case .missingEdit:
            "The Google edit is not open. Re-plan and run again."
        case .missingLocalization(let locale):
            "The \(locale) localization could not be created."
        case .uploadFailed(let detail):
            "The upload failed. \(detail)"
        case .processingFailed(let detail):
            "The store rejected the upload. \(detail)"
        }
    }
}
