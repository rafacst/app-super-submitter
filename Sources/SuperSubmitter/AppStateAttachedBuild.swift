import SubmitKit
import SwiftUI

/// The build a store write attaches its data and changes to.
///
/// App Store Connect gives a version one build; Google Play's release *is* the
/// artifact. Either way a store write needs one, and until a build is attached
/// every edit stays on this Mac. The record is `store.yaml` itself, the same
/// file the Build tab already writes: a chosen App Store build number, a named
/// binary path, or the App Bundle. A build made this session counts too, before
/// its path has landed in the file.
///
/// The implicit "take the highest processed build" is not an attachment. It is
/// the fallback the apply used when nobody chose, and this feature is the choice
/// being made on purpose, so the Build tab has to name one before an upload.
extension AppState {
    struct AttachedBuild: Equatable {
        var store: Store
        /// A short label for the header chip: "build 42", "app-release.aab".
        var label: String
    }

    /// Whether the indicator and the gate apply at all. An app with no store
    /// goes nowhere, so it has nothing to attach.
    var buildAttachApplies: Bool { !stores.isEmpty }

    /// The build attached for one store, read from `store.yaml` first and from
    /// this session's build second. Nil is "no build attached, changes local".
    func attachedBuild(for store: Store) -> AttachedBuild? {
        switch store {
        case .apple:
            if let number = manifest.release?.apple?.buildNumber, !number.isEmpty {
                return AttachedBuild(store: store, label: "build \(number)")
            }
            if let path = firstNonEmpty(manifest.release?.build?.ios,
                                        manifest.release?.build?.macos) {
                return AttachedBuild(store: store, label: Self.fileName(path))
            }
            if let built = builtThisSession(for: store) {
                return AttachedBuild(store: store, label: "build \(built.buildVersion)")
            }
            return nil
        case .google:
            if let path = firstNonEmpty(manifest.release?.build?.android,
                                        manifest.release?.build?.androidApk) {
                return AttachedBuild(store: store, label: Self.fileName(path))
            }
            if manifest.release?.google?.externalApk != nil {
                return AttachedBuild(store: store, label: "hosted APK")
            }
            if let built = builtThisSession(for: store) {
                return AttachedBuild(store: store, label: Self.fileName(built.artifactPath))
            }
            return nil
        }
    }

    func hasAttachedBuild(for store: Store) -> Bool { attachedBuild(for: store) != nil }

    /// The targeted stores with no build attached. Empty means an upload may
    /// write; otherwise every write to those stores stays local.
    var storesMissingBuild: [Store] {
        Store.allCases.filter { stores.contains($0) && !hasAttachedBuild(for: $0) }
    }

    /// The attached builds the open app has, in store order, for the chip.
    var attachedBuilds: [AttachedBuild] {
        Store.allCases.filter(stores.contains).compactMap { attachedBuild(for: $0) }
    }

    /// A build the open app produced this session, before its path has been
    /// written to `store.yaml`. Only the flow of the app on screen answers.
    private func builtThisSession(for store: Store) -> BuildCandidate? {
        buildFlow.builtCandidates.last { $0.platform.store == store && !$0.deleted }
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        values.compactMap { $0 }.first { !$0.isEmpty }
    }

    static func fileName(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    /// Opens the one place a build is chosen. Selecting the tab flips the shell
    /// to Publishing on its own, because Build is a Publishing tab. See
    /// `selectedTab`'s observer.
    func openBuildTabToAttach() {
        showEntryScreen = false
        selectedTab = .build
    }
}

extension PlanSystem {
    /// The store a plan step writes to. The provider is RevenueCat or Adapty,
    /// which is not a store and takes no build.
    var store: Store? {
        switch self {
        case .apple: .apple
        case .google: .google
        case .provider: nil
        }
    }
}
