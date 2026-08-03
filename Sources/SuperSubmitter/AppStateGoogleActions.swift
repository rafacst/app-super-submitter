import Foundation
import SubmitKit

/// The Google calls that sit outside the plan: the reviews, the internal
/// share, and the app recovery.
///
/// None of them is a desired state, so none of them belongs in `store.yaml`
/// or in a plan row. Each one runs on a button and reports its own result.
///
/// `// ponytail: thin wrappers. Each one adds the package name and nothing
/// // else, which is the one thing every call site would otherwise repeat.`
extension AppState {

    /// The package that these calls address, or nil when the manifest names
    /// none. `googlePackageName` on `AppState` is the Stores tab's own field,
    /// which is empty until a connection lands; the manifest is the one that
    /// says which app this is.
    var googleActionPackage: String? {
        let name = manifest.apps.google?.packageName ?? ""
        return name.isEmpty ? nil : name
    }

    func googleActions() -> GoogleActionsClient {
        GoogleActionsClient(api: readOnlyAPI())
    }

    // MARK: - The reviews

    /// The newest reviews of the app. Google keeps a week of them, so an app
    /// that nobody reviewed lately answers with an empty list.
    func googleReviews() async throws -> [GoogleActionsClient.Review] {
        guard let packageName = googleActionPackage else { return [] }
        return try await googleActions().reviews(packageName: packageName)
    }

    /// **This publishes public text under the listing.** The panel confirms
    /// it first, and it re-reads the review afterwards so the row shows what
    /// Google actually stored.
    func replyToGoogleReview(id: String, text: String) async throws {
        guard let packageName = googleActionPackage else {
            throw ConnectionError.http(400, "Connect Google Play on the Stores tab first.")
        }
        try await googleActions().replyToReview(packageName: packageName, reviewId: id,
                                                text: text)
    }

    // MARK: - The APKs that Google signs

    /// The APKs Google generated for one version code.
    ///
    /// Play re-signs what it serves, so the file a device installs is never
    /// the App Bundle the developer uploaded. These are the files that match a
    /// crash report from the store.
    func googleGeneratedAPKs(versionCode: Int)
        async throws -> [GoogleActionsClient.GeneratedAPK] {
        guard let packageName = googleActionPackage else { return [] }
        return try await googleActions().generatedAPKs(packageName: packageName,
                                                       versionCode: versionCode)
    }

    /// Downloads one generated APK beside `store.yaml` and answers the file.
    func downloadGoogleAPK(_ apk: GoogleActionsClient.GeneratedAPK) async throws -> URL {
        guard let root = manifestRoot else {
            throw ConnectionError.http(400, "Open an app before downloading a build.")
        }
        return try await googleActions().downloadGeneratedAPK(
            apk, into: root.appendingPathComponent("Store Downloads"))
    }

    /// The version code that the store holds, for the generated APK read.
    var googleLatestVersionCode: Int? {
        actualState.google?.highestVersionCode
    }

    // MARK: - Internal app sharing

    /// The artifact that the manifest names, App Bundle first.
    ///
    /// Returns the path and whether it is a bundle, because Google takes the
    /// two through different endpoints.
    var googleSharableArtifact: (path: String, isBundle: Bool)? {
        if let bundle = manifest.release?.build?.android, !bundle.isEmpty {
            return (bundle, true)
        }
        if let apk = manifest.release?.build?.androidApk, !apk.isEmpty {
            return (apk, false)
        }
        return nil
    }

    /// Uploads the artifact to internal app sharing and answers its link.
    ///
    /// This touches no edit, no track, and no version code, so it collides
    /// with no release and it needs no plan.
    func shareGoogleArtifactInternally() async throws -> GoogleActionsClient.SharedArtifact {
        guard let packageName = googleActionPackage else {
            throw ConnectionError.http(400, "Connect Google Play on the Stores tab first.")
        }
        guard let artifact = googleSharableArtifact else {
            throw ConnectionError.http(400, "The manifest names no Android build to share.")
        }
        guard let url = Planner.resolve(artifact.path, root: manifestRoot) else {
            throw ConnectionError.http(400, "The build \(artifact.path) could not be read.")
        }
        return try await googleActions().shareInternally(packageName: packageName,
                                                         artifact: url,
                                                         isBundle: artifact.isBundle)
    }

    // MARK: - App recovery

    func googleRecoveryActions() async throws -> [GoogleActionsClient.RecoveryAction] {
        guard let packageName = googleActionPackage else { return [] }
        return try await googleActions().recoveryActions(packageName: packageName)
    }

    /// Creates a draft recovery for the version codes that Google already
    /// holds. A draft reaches nobody until the deploy button sends it.
    func createGoogleRecoveryDraft() async throws -> GoogleActionsClient.RecoveryAction {
        guard let packageName = googleActionPackage else {
            throw ConnectionError.http(400, "Connect Google Play on the Stores tab first.")
        }
        guard let versionCode = actualState.google?.highestVersionCode else {
            throw ConnectionError.http(
                400, "Read the stores on the Summary tab first, so the draft can name a version code.")
        }
        return try await googleActions().createRecoveryDraft(packageName: packageName,
                                                             versionCodes: [versionCode])
    }

    /// **This reaches every targeted installation, and no call takes it back.**
    /// The panel confirms it first.
    func deployGoogleRecovery(id: String) async throws {
        guard let packageName = googleActionPackage else {
            throw ConnectionError.http(400, "Connect Google Play on the Stores tab first.")
        }
        try await googleActions().deployRecovery(packageName: packageName, recoveryId: id)
    }

    /// Stops a deployed recovery. Every device that already took it keeps it.
    func cancelGoogleRecovery(id: String) async throws {
        guard let packageName = googleActionPackage else {
            throw ConnectionError.http(400, "Connect Google Play on the Stores tab first.")
        }
        try await googleActions().cancelRecovery(packageName: packageName, recoveryId: id)
    }

    /// Widens a draft recovery to every user. Google only ever adds to the
    /// targeting, so this call cannot narrow a live recovery.
    func widenGoogleRecovery(id: String) async throws {
        guard let packageName = googleActionPackage else {
            throw ConnectionError.http(400, "Connect Google Play on the Stores tab first.")
        }
        try await googleActions().addRecoveryTargeting(packageName: packageName,
                                                       recoveryId: id, allUsers: true)
    }
}
