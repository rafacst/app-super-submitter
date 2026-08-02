import Foundation

/// upload-spec section 5. An uncertain remote result enters
/// `recoveryRequired`, never `failed`, because a lost response is not proof
/// that nothing happened.
public enum UploadState: String, Codable, Sendable, CaseIterable {
    case unlinked
    case discovering
    case needsSelection
    case preflight
    case readyToBuild
    case building
    case inspectingArtifact
    case needsUploadConfirmation
    case uploading
    case processingOrValidating
    case complete
    case cancelling
    case cancelled
    case failed
    case recoveryRequired

    public var isActive: Bool {
        switch self {
        case .discovering, .preflight, .building, .inspectingArtifact, .uploading,
             .processingOrValidating, .cancelling: true
        default: false
        }
    }

    public var isTerminal: Bool {
        switch self {
        case .complete, .cancelled, .failed: true
        default: false
        }
    }

    /// The one place that says which move is legal.
    public func canMove(to next: UploadState) -> Bool {
        if next == .failed { return true }                       // any state may fail
        if next == .cancelling { return isActive }               // only active work cancels
        if self == .cancelling { return next == .cancelled || next == .recoveryRequired }
        if next == .recoveryRequired {
            return [.uploading, .processingOrValidating, .cancelling].contains(self)
        }
        return UploadState.forward[self]?.contains(next) ?? false
    }

    private static let forward: [UploadState: Set<UploadState>] = [
        .unlinked: [.discovering],
        .discovering: [.needsSelection, .preflight, .unlinked],
        .needsSelection: [.needsSelection, .preflight, .discovering],
        .preflight: [.readyToBuild, .needsSelection, .discovering],
        .readyToBuild: [.building, .preflight, .needsSelection, .discovering],
        .building: [.inspectingArtifact],
        .inspectingArtifact: [.needsUploadConfirmation, .complete],
        .needsUploadConfirmation: [.uploading, .preflight, .readyToBuild],
        .uploading: [.processingOrValidating, .complete],
        .processingOrValidating: [.complete],
        .recoveryRequired: [.complete, .failed, .uploading, .processingOrValidating],
        .complete: [.discovering, .preflight, .readyToBuild],
        .cancelled: [.discovering, .preflight, .readyToBuild],
        .failed: [.discovering, .preflight, .readyToBuild, .building,
                  .needsUploadConfirmation, .uploading],
    ]

    /// The label of the live run view. upload-spec section 10.4.
    public var stepTitle: String {
        switch self {
        case .unlinked, .discovering: "Validate the project"
        case .needsSelection: "Choose what to build"
        case .preflight: "Resolve the toolchain"
        case .readyToBuild: "Check the store"
        case .building: "Build the artifact"
        case .inspectingArtifact: "Inspect and verify the artifact"
        case .needsUploadConfirmation: "Confirm the upload"
        case .uploading: "Upload"
        case .processingOrValidating: "Process and validate"
        case .complete: "Finished"
        case .cancelling: "Cancel and reconcile"
        case .cancelled: "Cancelled"
        case .failed: "Failed"
        case .recoveryRequired: "Reconcile the store"
        }
    }
}

/// upload-spec section 4.3. Enough of this survives a relaunch to resume the
/// remote poll and the cleanup.
public struct UploadRun: Codable, Sendable, Equatable, Identifiable {
    public enum Cleanup: String, Codable, Sendable {
        case notNeeded, pending, complete, needsAttention
    }

    public var id: UUID
    public var state: UploadState
    public var platform: BuildPlatform
    public var linkedProjectID: UUID?
    public var candidateIdentity: String?
    /// Redacted, human-readable descriptions. Presentation only.
    public var commandPreviews: [String]
    public var remoteIDs: [String: String]
    public var startedAt: Date
    public var updatedAt: Date
    public var finishedAt: Date?
    public var cancelRequestedAt: Date?
    public var cleanupState: Cleanup
    public var lastError: BuildFailure?

    public init(id: UUID = UUID(), platform: BuildPlatform, linkedProjectID: UUID? = nil,
                state: UploadState = .unlinked, startedAt: Date = Date()) {
        self.id = id
        self.state = state
        self.platform = platform
        self.linkedProjectID = linkedProjectID
        self.candidateIdentity = nil
        self.commandPreviews = []
        self.remoteIDs = [:]
        self.startedAt = startedAt
        self.updatedAt = startedAt
        self.cleanupState = .notNeeded
    }

    /// Moves the state, or refuses. An illegal move is a defect, so it is
    /// reported rather than silently applied.
    @discardableResult
    public mutating func move(to next: UploadState, now: Date = Date()) -> Bool {
        guard state.canMove(to: next) else { return false }
        state = next
        updatedAt = now
        if next.isTerminal { finishedAt = now }
        return true
    }
}

/// upload-spec section 14. The category never discards the original cause.
public enum BuildErrorCategory: String, Codable, Sendable, CaseIterable {
    case projectAccess, projectDiscovery, selectionRequired, toolchainUnavailable
    case configuration, dependencyResolution, signing, build
    case artifactDiscovery, artifactValidation, remoteConflict, authentication
    case upload, remoteValidation, remoteAmbiguous, cleanup, cancelled

    /// True when the app must query the store before it tries again.
    public var needsReconciliation: Bool {
        self == .remoteAmbiguous || self == .cleanup
    }
}

public struct BuildFailure: Codable, Sendable, Equatable, Error, LocalizedError {
    public var category: BuildErrorCategory
    public var stage: String
    public var message: String
    /// The original domain and code, kept so the category never hides it.
    public var underlying: String?
    /// Redacted diagnostics, for **Copy Redacted Diagnostics**.
    public var diagnostics: String?
    public var recovery: String?
    /// What this run left behind, stated plainly on the panel.
    public var retainedArtifact: String?
    public var retainedRemoteEdit: String?

    public init(category: BuildErrorCategory, stage: String, message: String,
                underlying: String? = nil, diagnostics: String? = nil,
                recovery: String? = nil, retainedArtifact: String? = nil,
                retainedRemoteEdit: String? = nil) {
        self.category = category
        self.stage = stage
        self.message = message
        self.underlying = underlying
        self.diagnostics = diagnostics
        self.recovery = recovery
        self.retainedArtifact = retainedArtifact
        self.retainedRemoteEdit = retainedRemoteEdit
    }

    public var errorDescription: String? { message }

    /// The text that **Copy Redacted Diagnostics** puts on the pasteboard.
    public func report(redactor: Redactor = Redactor()) -> String {
        var lines = [
            "# Super Submitter diagnostics",
            "",
            "Stage: \(stage)",
            "Category: \(category.rawValue)",
            "Message: \(message)",
        ]
        if let underlying { lines.append("Underlying: \(underlying)") }
        if let recovery { lines.append("Recovery: \(recovery)") }
        if let retainedArtifact { lines.append("Retained artifact: \(retainedArtifact)") }
        if let retainedRemoteEdit { lines.append("Retained edit: \(retainedRemoteEdit)") }
        if let diagnostics {
            lines += ["", "```", redactor.redact(diagnostics), "```"]
        }
        return lines.joined(separator: "\n")
    }
}
