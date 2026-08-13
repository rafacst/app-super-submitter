import Foundation

/// One row per store, at all times. Spec section 7.10.
public struct StoreStatus: Sendable, Equatable {
    public enum Phase: String, Sendable, Equatable {
        case noDraft, draft, inQueue, inReview, approved, live, rejected

        /// The label that tab 9 and the menu bar show.
        public var label: String {
            switch self {
            case .noDraft: "No draft yet"
            case .draft: "Draft, ready to release"
            case .inQueue: "Waiting for review"
            case .inReview: "In review"
            case .approved: "Approved, waiting for release"
            case .live: "Live"
            case .rejected: "Rejected"
            }
        }

        /// A released store is loud. A draft is quiet.
        public var isReleased: Bool {
            self != .noDraft && self != .draft
        }

        /// Terminal store states do not need a background poll. Approved is
        /// still transitional because it may later become live.
        public var needsPolling: Bool {
            self == .inQueue || self == .inReview || self == .approved
        }

        /// The store has the version and there is nothing left to prepare.
        ///
        /// A rejection is deliberately not here. That is the one answer that
        /// hands the version back and makes the checklist matter again.
        public var isPastPreparation: Bool {
            self == .inQueue || self == .inReview || self == .approved || self == .live
        }
    }

    public var store: Store
    public var phase: Phase
    public var detail: String
    public var checkedAt: Date?

    public init(store: Store, phase: Phase, detail: String, checkedAt: Date? = nil) {
        self.store = store
        self.phase = phase
        self.detail = detail
        self.checkedAt = checkedAt
    }

    public var storeName: String { store == .apple ? "App Store" : "Google Play" }
}

/// Reads the live state of a released version.
///
/// The app polls a store **only after a release for review**. A store that a
/// run prepared and nobody released reads `Draft, ready to release`, and no
/// poll is needed to know that.
public struct ReleaseStatusReader: Sendable {
    private let api: StoreAPI

    public init(api: StoreAPI) {
        self.api = api
    }

    public func readApple(versionID: String) async throws -> StoreStatus {
        let version = JSON(data: try await api.apple("GET",
                                                     "/v1/appStoreVersions/\(versionID)").data)
        let attributes = version["data"]["attributes"]
        let state = attributes["appVersionState"].string
            ?? attributes["appStoreState"].string ?? ""
        let versionString = attributes["versionString"].string ?? ""
        return StoreStatus(store: .apple, phase: Self.applePhase(state),
                           detail: versionString.isEmpty ? state : "Version \(versionString)",
                           checkedAt: Date())
    }

    public static func applePhase(_ state: String) -> StoreStatus.Phase {
        switch state {
        case "PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "DEVELOPER_REJECTED": .draft
        case "WAITING_FOR_REVIEW": .inQueue
        case "IN_REVIEW", "PENDING_APPLE_RELEASE": .inReview
        case "PENDING_DEVELOPER_RELEASE": .approved
        case "READY_FOR_DISTRIBUTION", "READY_FOR_SALE": .live
        case "REJECTED", "METADATA_REJECTED": .rejected
        default: .draft
        }
    }

    /// `GET .../edits` is not usable after a commit, so this reads the track
    /// releases directly.
    public func readGoogle(packageName: String, track: String) async throws -> StoreStatus {
        let path = "/androidpublisher/v3/applications/\(StateReader.escape(packageName))"
            + "/tracks/\(track)/releases"
        let payload = JSON(data: try await api.google("GET", path).data)
        let release = payload["releases"].array.max { lhs, rhs in
            Self.highestVersionCode(in: lhs) < Self.highestVersionCode(in: rhs)
        } ?? JSON(data: Data("{}".utf8))
        let state = release["releaseLifecycleState"].string ?? ""
        var detail = "\(track) track"
        if let name = release["releaseName"].string, !name.isEmpty {
            detail += " · \(name)"
        }
        return StoreStatus(store: .google, phase: Self.googlePhase(state), detail: detail,
                           checkedAt: Date())
    }

    private static func highestVersionCode(in release: JSON) -> Int {
        release["activeArtifacts"].array.compactMap { $0["versionCode"].int }.max() ?? -1
    }

    static func googlePhase(_ status: String) -> StoreStatus.Phase {
        switch status {
        case "RELEASE_LIFECYCLE_STATE_DRAFT", "RELEASE_LIFECYCLE_STATE_NOT_SENT_FOR_REVIEW":
            .draft
        case "RELEASE_LIFECYCLE_STATE_IN_REVIEW": .inReview
        case "RELEASE_LIFECYCLE_STATE_APPROVED_NOT_PUBLISHED": .approved
        case "RELEASE_LIFECYCLE_STATE_NOT_APPROVED": .rejected
        case "RELEASE_LIFECYCLE_STATE_PUBLISHED": .live
        default: .inQueue
        }
    }
}
