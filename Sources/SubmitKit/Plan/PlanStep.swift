import Foundation

public enum ChangeKind: String, Sendable, Equatable {
    case add = "+", change = "~", remove = "-"
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
    case appleReviewDetails
    case appleAgeRating
    case applePurchases
    case applePhasedRelease
    case appleAvailability

    case googleOpenEdit
    case googleListing(String)
    case googleDetails
    case googleImages(locale: String, imageType: String, files: [MediaUpload])
    case googleBundleUpload(path: String, bytes: Int64)
    case googleTrack
    case googleProducts
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

    public init(id: String, system: PlanSystem, kind: ChangeKind, summary: String,
                title: String, requests: [RequestSketch], operation: PlanOperation,
                uploadCount: Int = 0, uploadBytes: Int64 = 0) {
        self.id = id
        self.system = system
        self.kind = kind
        self.summary = summary
        self.title = title
        self.requests = requests
        self.operation = operation
        self.uploadCount = uploadCount
        self.uploadBytes = uploadBytes
    }

    /// The upload steps are the ones that need a progress bar and a cancel
    /// button, because they are the only steps that take minutes.
    public var isUpload: Bool { uploadCount > 0 }
}

/// Where a validation error is fixed. SubmitKit names the tab; the app maps it
/// to its own `Tab`, so the kit never imports SwiftUI.
public enum FixTarget: String, Sendable, Equatable {
    case stores, build, details, media, money, reviewInfo, plan
}

public struct Finding: Sendable, Equatable, Identifiable {
    public enum Severity: String, Sendable, Equatable {
        case error, warning
    }

    public var id: String
    public var severity: Severity
    public var message: String
    public var location: String
    public var fix: FixTarget

    public init(id: String, severity: Severity, message: String, location: String,
                fix: FixTarget) {
        self.id = id
        self.severity = severity
        self.message = message
        self.location = location
        self.fix = fix
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

    /// An error blocks the apply. A warning needs one acknowledgement.
    public var isBlocked: Bool { !errors.isEmpty }

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
