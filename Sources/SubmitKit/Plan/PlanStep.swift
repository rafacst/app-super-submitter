import Foundation

public enum ChangeKind: String, Sendable, Equatable {
    case add = "+", change = "~", remove = "-"
}

public enum ComparisonConfidence: String, Sendable, Equatable {
    case verified
    case unverified
}

/// One request, named before it is sent.
///
/// A dry run logs these and sends nothing, which is the whole point of the
/// toggle on tab 7. Spec section 7.2.
public struct RequestSketch: Sendable, Equatable {
    public var method: String
    public var path: String

    public init(_ method: String, _ path: String) {
        self.method = method
        self.path = path
    }
}

/// One file that a step uploads.
public struct MediaUpload: Sendable, Equatable {
    public var path: String
    public var url: URL
    public var bytes: Int64
    public var md5: String
    public var sha256: String
    /// The Apple `screenshotDisplayType`, or the Google `imageType`.
    public var bucket: String

    public init(path: String, url: URL, bytes: Int64, md5: String, sha256: String,
                bucket: String) {
        self.path = path
        self.url = url
        self.bytes = bytes
        self.md5 = md5
        self.sha256 = sha256
        self.bucket = bucket
    }
}

/// What the runner does, in the order that section 7.3 and 7.4 fix.
///
/// The step names the work. The values come from the manifest, which the
/// runner already holds, so the plan never carries a second copy of the text.
public enum PlanOperation: Sendable, Equatable {
    case appleEnsureVersion(String)
    case appleVersionAttributes
    case appleCategories
    case appleInfoLocale(String)
    case appleVersionLocale(String)
    case appleScreenshots(locale: String, deviceClass: String, files: [MediaUpload])
    case applePreviews(locale: String, deviceClass: String, files: [MediaUpload])
    case appleBuildUpload(path: String, bytes: Int64)
    case appleAttachBuild
    case appleBuildCompliance
    /// The export compliance declaration that a non-exempt app owes on top of
    /// the build flag.
    case appleEncryptionDeclaration
    /// Offer codes for a one-time purchase. The subscription twin already
    /// rides inside `appleSubscriptionOffers`.
    case applePurchaseOfferCodes(productId: String)
    /// Ends a preorder, which puts the app on sale. It is irreversible.
    case appleEndPreOrder
    case appleReviewDetails
    case appleAgeRating
    case applePurchases
    case applePhasedRelease
    case appleAvailability
    case appleAppPrice
    /// The subscription catalog: the groups, the subscriptions, the
    /// localizations, and the prices. The offers attach to it.
    case appleSubscriptions
    case appleSubscriptionOffers
    case appleGracePeriod
    case appleCustomProductPages
    case appleExperiments
    case appleAppEvents
    case appleEULA
    case appleRoutingCoverage(path: String, bytes: Int64)
    case appleNomination
    case appleAccessibility
    case appleAppClip
    /// TestFlight. The group, then the testers it invites, then the build it
    /// receives. The App Store twin of `googleTesters`.
    case appleBetaGroup(name: String)
    case appleBetaTesters(group: String, emails: [String])
    case appleBetaBuild(group: String)
    case appleWhatToTest
    case appleBetaAutoNotify(Bool)
    /// The TestFlight page of the app, and the contact for its review. Both
    /// belong to the app and neither one changes with a build.
    case appleBetaAppLocalizations
    case appleBetaLicenseAgreement
    case appleBetaReviewDetail
    /// Takes a place in the beta review queue. No call takes it back.
    case appleBetaReview

    case googleOpenEdit
    case googleListing(String)
    case googleDetails
    case googleDataSafety
    case googleDeleteListing(String)
    case googleImages(locale: String, imageType: String, files: [MediaUpload])
    case googleBundleUpload(path: String, bytes: Int64)
    case googleApkUpload(path: String, bytes: Int64)
    case googleExternalApk
    /// `kind` is `proguard` or `nativeCode`.
    case googleDeobfuscation(kind: String, path: String, bytes: Int64)
    /// `kind` is `main` or `patch`.
    case googleExpansionFile(kind: String, path: String, bytes: Int64)
    case googleCreateTrack(String)
    case googleTrack(String)
    /// The Google Groups that may install one track. A closed track without a
    /// group reaches nobody.
    case googleTesters(track: String)
    case googleProducts
    case googleDeviceTierConfig(path: String)
    /// The base plan and purchase option switches. Google keeps the product
    /// and stops the sale, so neither call deletes anything.
    case googleBasePlanState(productId: String, basePlanId: String, active: Bool)
    case googlePurchaseOptionState(productId: String, purchaseOptionId: String, active: Bool)
    case googleSubscriptionOffers(productId: String, basePlanId: String)
    case googleOneTimeOffers(productId: String)
    /// The offer switches. Google creates every offer in a draft state, so an
    /// offer that nobody activates sells nothing.
    case googleSubscriptionOfferStates(productId: String, basePlanId: String)
    case googleOneTimeOfferStates(productId: String)
    case googleMigratePrices(productId: String, basePlanId: String)
    /// Spec section 8, rule 6. The app archives; it never deletes.
    case googleArchiveSubscription(productId: String)
    case googleValidate
    case googleCommit

    case providerProduct(storeProductId: String, appId: String)
    case providerEntitlement(key: String)
    case providerAttach(entitlement: String, products: [String])
    case providerOffering(key: String)
    /// Spec section 8, rule 6. The app archives; it never deletes.
    case providerArchive(kind: String, key: String)
}

public struct PlanStep: Sendable, Equatable, Identifiable {
    public var id: String
    public var system: PlanSystem
    public var kind: ChangeKind
    /// The diff line on tab 7.
    public var summary: String
    /// The step line on tab 8.
    public var title: String
    public var requests: [RequestSketch]
    public var operation: PlanOperation
    public var uploadCount: Int
    public var uploadBytes: Int64
    public var comparison: ComparisonConfidence

    public init(id: String, system: PlanSystem, kind: ChangeKind, summary: String,
                title: String, requests: [RequestSketch], operation: PlanOperation,
                uploadCount: Int = 0, uploadBytes: Int64 = 0,
                comparison: ComparisonConfidence = .verified) {
        self.id = id
        self.system = system
        self.kind = kind
        self.summary = summary
        self.title = title
        self.requests = requests
        self.operation = operation
        self.uploadCount = uploadCount
        self.uploadBytes = uploadBytes
        self.comparison = comparison
    }

    /// The upload steps are the ones that need a progress bar and a cancel
    /// button, because they are the only steps that take minutes.
    public var isUpload: Bool { uploadCount > 0 }
}

/// Where a validation error is fixed. SubmitKit names the tab; the app maps it
/// to its own `Tab`, so the kit never imports SwiftUI.
public enum FixTarget: String, Sendable, Equatable {
    case stores, build, betaTesting, details, media, money, marketing, reviewInfo,
         plan, release
}

public struct Finding: Sendable, Equatable, Identifiable {
    public enum Severity: String, Sendable, Equatable {
        /// The developer has to change something. It blocks the apply.
        case error
        /// Worth reading once. One acknowledgement and the apply runs.
        case warning
        /// Nothing is wrong. A store is holding the version and takes no write
        /// until it answers, so the apply waits instead of failing.
        ///
        /// It blocks the apply exactly like an error and reads nothing like
        /// one. A version in review is the ordinary result of shipping, and
        /// reporting it as a fault sent developers looking for the mistake
        /// they had made, which was none.
        case held

        /// Errors first, then warnings, then the holds. Three cases need a
        /// rank: a two-way `lhs.severity == .error` comparator is not a strict
        /// ordering once a third case exists, and `sort` may then trap.
        var rank: Int {
            switch self {
            case .error: 0
            case .warning: 1
            case .held: 2
            }
        }
    }

    public var id: String
    public var severity: Severity
    public var message: String
    public var location: String
    public var fix: FixTarget
    /// The `FieldAnchor` the fix button scrolls to, where one field starts the
    /// work. Nil sends the developer to the top of the tab, which is the right
    /// answer when the fix is a whole panel and a lie when it is one box.
    public var fixAnchor: String?

    public init(id: String, severity: Severity, message: String, location: String,
                fix: FixTarget, fixAnchor: String? = nil) {
        self.id = id
        self.severity = severity
        self.message = message
        self.location = location
        self.fix = fix
        self.fixAnchor = fixAnchor
    }
}

public struct PlanResult: Sendable, Equatable {
    public var steps: [PlanStep] = []
    public var findings: [Finding] = []
    public var readAt: Date?
    public var readFailures: [String] = []

    public init() {}

    public var errors: [Finding] { findings.filter { $0.severity == .error } }
    public var warnings: [Finding] { findings.filter { $0.severity == .warning } }
    /// What a store is holding. Not the developer's to fix, and it still stops
    /// the apply: the write would be refused.
    public var held: [Finding] { findings.filter { $0.severity == .held } }

    /// An error blocks the apply. A warning needs one acknowledgement. A hold
    /// blocks it too, and says so in the store's name rather than in the
    /// developer's.
    public var isBlocked: Bool { !errors.isEmpty || !held.isEmpty }

    public var writeCount: Int { steps.filter { !$0.isUpload }.count }
    public var uploadCount: Int { steps.reduce(0) { $0 + $1.uploadCount } }
    public var uploadBytes: Int64 { steps.reduce(0) { $0 + $1.uploadBytes } }

    public var isEmpty: Bool { steps.isEmpty }

    public func steps(for system: PlanSystem) -> [PlanStep] {
        steps.filter { $0.system == system }
    }

    public var systems: [PlanSystem] {
        PlanSystem.allCases.filter { system in steps.contains { $0.system == system } }
    }

    /// `142.6 MB`, the way tab 7 shows it.
    public var uploadSizeText: String {
        ByteCountFormatter.string(fromByteCount: uploadBytes, countStyle: .file)
    }
}
