import Foundation

public enum BuildPlatform: String, Codable, Sendable, CaseIterable {
    case ios, macos, android

    public var store: Store { self == .android ? .google : .apple }

    public var label: String {
        switch self {
        case .ios: "iOS"
        case .macos: "macOS"
        case .android: "Android"
        }
    }

    /// The generic archive destination. upload-spec section 8.5.
    public var appleDestination: String? {
        switch self {
        case .ios: "generic/platform=iOS"
        case .macos: "generic/platform=macOS"
        case .android: nil
        }
    }
}

/// upload-spec section 4.1. This record is machine-local. It never enters
/// `store.yaml` and it never goes in the developer's repository.
public struct LinkedSourceProject: Codable, Sendable, Equatable, Identifiable {
    public enum ContainerKind: String, Codable, Sendable {
        case workspace, project, gradle
    }

    public var id: UUID
    public var platform: BuildPlatform
    public var rootPath: String
    public var folderBookmark: Data?
    public var containerPath: String
    public var containerKind: ContainerKind
    /// The `store.yaml` this project builds for.
    ///
    /// The links are one list for the whole Mac, and the Build tab used to
    /// open whichever one was linked last. With ten apps in the sidebar that
    /// is nine wrong answers. Optional, so a list written before this field
    /// existed still decodes; those links match by folder instead.
    public var manifestPath: String?
    /// Apple: the scheme, the configuration. Android: the module, the variant.
    public var selection: Selection
    public var productIdentifier: String?
    public var createdAt: Date
    public var lastValidatedAt: Date?

    public init(id: UUID = UUID(), platform: BuildPlatform, rootPath: String,
                folderBookmark: Data? = nil, containerPath: String,
                containerKind: ContainerKind, manifestPath: String? = nil,
                selection: Selection = Selection(),
                productIdentifier: String? = nil, createdAt: Date = Date(),
                lastValidatedAt: Date? = nil) {
        self.id = id
        self.platform = platform
        self.rootPath = rootPath
        self.folderBookmark = folderBookmark
        self.containerPath = containerPath
        self.containerKind = containerKind
        self.manifestPath = manifestPath
        self.selection = selection
        self.productIdentifier = productIdentifier
        self.createdAt = createdAt
        self.lastValidatedAt = lastValidatedAt
    }

    public struct Selection: Codable, Sendable, Equatable {
        public var scheme: String?
        public var configuration: String?
        public var module: String?
        public var variantTask: String?
        public var javaHome: String?
        /// Off by default. Xcode may create App IDs, certificates, and
        /// profiles with it on. upload-spec section 8.6.
        public var allowProvisioningUpdates = false

        public init(scheme: String? = nil, configuration: String? = nil,
                    module: String? = nil, variantTask: String? = nil,
                    javaHome: String? = nil, allowProvisioningUpdates: Bool = false) {
            self.scheme = scheme
            self.configuration = configuration
            self.module = module
            self.variantTask = variantTask
            self.javaHome = javaHome
            self.allowProvisioningUpdates = allowProvisioningUpdates
        }

        public var isComplete: Bool {
            (scheme != nil && !(scheme ?? "").isEmpty)
                || (module != nil && variantTask != nil)
        }
    }

    public var rootURL: URL { URL(fileURLWithPath: rootPath) }
    public var containerURL: URL { URL(fileURLWithPath: containerPath) }
    public var displayName: String { rootURL.lastPathComponent }
}

/// upload-spec section 4.2. Immutable after inspection, because it is what the
/// upload confirmation shows and what the upload uses.
public struct BuildCandidate: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var platform: BuildPlatform
    public var productName: String
    public var productIdentifier: String
    public var marketingVersion: String
    public var buildVersion: String
    public var artifactPath: String
    public var artifactSize: Int64
    public var sha256: String
    public var signingSummary: SigningSummary
    public var sourceRevision: SourceRevision?
    public var createdAt: Date
    public var preflightSnapshot: PreflightSnapshot?
    /// Every field where the artifact disagrees with the preflight or with
    /// `store.yaml`. A build script can change a version, so a difference
    /// always means something.
    public var mismatches: [Mismatch]

    public init(id: UUID = UUID(), platform: BuildPlatform, productName: String,
                productIdentifier: String, marketingVersion: String, buildVersion: String,
                artifactPath: String, artifactSize: Int64, sha256: String,
                signingSummary: SigningSummary = SigningSummary(),
                sourceRevision: SourceRevision? = nil, createdAt: Date = Date(),
                preflightSnapshot: PreflightSnapshot? = nil, mismatches: [Mismatch] = []) {
        self.id = id
        self.platform = platform
        self.productName = productName
        self.productIdentifier = productIdentifier
        self.marketingVersion = marketingVersion
        self.buildVersion = buildVersion
        self.artifactPath = artifactPath
        self.artifactSize = artifactSize
        self.sha256 = sha256
        self.signingSummary = signingSummary
        self.sourceRevision = sourceRevision
        self.createdAt = createdAt
        self.preflightSnapshot = preflightSnapshot
        self.mismatches = mismatches
    }

    public var artifactURL: URL { URL(fileURLWithPath: artifactPath) }

    public var sizeText: String {
        ByteCountFormatter.string(fromByteCount: artifactSize, countStyle: .file)
    }

    /// upload-spec section 5.2.
    public var logicalIdentity: String {
        "\(platform.rawValue)+\(productIdentifier)+\(marketingVersion)+\(buildVersion)+\(sha256)"
    }

    public var blockingMismatches: [Mismatch] {
        mismatches.filter(\.blocksUpload)
    }

    public struct Mismatch: Sendable, Equatable, Identifiable {
        public var field: String
        public var expected: String
        public var actual: String
        /// A wrong identifier writes to another app. A wrong version needs a
        /// fresh remote check and one more confirmation.
        public var blocksUpload: Bool
        public var id: String { field }

        public init(field: String, expected: String, actual: String, blocksUpload: Bool) {
            self.field = field
            self.expected = expected
            self.actual = actual
            self.blocksUpload = blocksUpload
        }
    }

    /// No private key material, ever. upload-spec section 9.12.
    public struct SigningSummary: Sendable, Equatable {
        public var style: String?
        public var team: String?
        public var identity: String?
        public var profile: String?
        public var certificateSubject: String?
        public var certificateFingerprint: String?
        public var verified: Bool?
        public var verificationDetail: String?

        public init(style: String? = nil, team: String? = nil, identity: String? = nil,
                    profile: String? = nil, certificateSubject: String? = nil,
                    certificateFingerprint: String? = nil, verified: Bool? = nil,
                    verificationDetail: String? = nil) {
            self.style = style
            self.team = team
            self.identity = identity
            self.profile = profile
            self.certificateSubject = certificateSubject
            self.certificateFingerprint = certificateFingerprint
            self.verified = verified
            self.verificationDetail = verificationDetail
        }
    }

    /// Informational only. It never blocks anything.
    public struct SourceRevision: Sendable, Equatable {
        public var commit: String
        public var branch: String?
        public var isDirty: Bool

        public init(commit: String, branch: String? = nil, isDirty: Bool = false) {
            self.commit = commit
            self.branch = branch
            self.isDirty = isDirty
        }

        public var label: String {
            "\(branch.map { "\($0) · " } ?? "")\(commit.prefix(8))\(isDirty ? " (dirty)" : "")"
        }
    }
}

/// What the preflight screen showed, before the build ran. Never the final
/// truth: build settings expand, and scripts change values.
public struct PreflightSnapshot: Sendable, Equatable {
    public var productName: String?
    public var productIdentifier: String?
    public var marketingVersion: String?
    public var buildVersion: String?
    public var team: String?
    public var signingStyle: String?
    public var signingIdentity: String?
    public var provisioningProfile: String?
    public var toolchain: String?
    public var sdk: String?
    public var containerPath: String?
    public var scheme: String?
    public var configuration: String?
    public var destination: String?
    public var module: String?
    public var variantTask: String?
    public var javaVersion: String?
    public var gradleVersion: String?
    public var androidSDKPath: String?
    public var outputExpectation: String?
    /// The fields the preflight could not read. Android marks several,
    /// because Gradle computes them. upload-spec section 9.6.
    public var uncertainFields: Set<String> = []
    public var remoteConflict: String?
    public var signingReady: Bool?

    public init() {}

    public func isUncertain(_ field: String) -> Bool { uncertainFields.contains(field) }
}
