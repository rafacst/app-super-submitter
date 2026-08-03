import Foundation
import SubmitKit

/// The App Store calls that sit outside the plan: the customer reviews and the
/// replies to them.
///
/// This is the twin of `AppStateGoogleActions`. None of it is a desired state,
/// so none of it belongs in `store.yaml` or in a plan row. Each call runs on a
/// button and reports its own result.
extension AppState {

    /// The app that these calls address, or nil when the manifest names none.
    /// `appleAppID` on `AppState` is the Stores tab's own field; the manifest
    /// is the one that says which app this is.
    var appleActionAppID: String? {
        let id = manifest.apps.apple?.appId ?? ""
        return id.isEmpty ? nil : id
    }

    func appleActions() -> AppleActionsClient {
        AppleActionsClient(api: readOnlyAPI())
    }

    /// The newest customer reviews. Apple keeps every review the app ever had,
    /// so this asks for one page of the newest.
    func appleReviews() async throws -> [AppleActionsClient.Review] {
        guard let appID = appleActionAppID else { return [] }
        return try await appleActions().reviews(appID: appID)
    }

    /// **This publishes public text under the listing.** The panel confirms it
    /// first. Apple takes one response per review, so a review that already
    /// carries one is patched and the reply never lands twice.
    func replyToAppleReview(id: String, responseId: String?, text: String) async throws {
        guard appleActionAppID != nil else {
            throw ConnectionError.http(400, "Connect App Store Connect on the Stores tab first.")
        }
        try await appleActions().replyToReview(reviewId: id, responseId: responseId, text: text)
    }

    /// Takes a published reply down. The review itself stays.
    func removeAppleReviewReply(responseId: String) async throws {
        try await appleActions().removeReply(responseId: responseId)
    }

    // MARK: - How the shipped app is doing

    /// The vitals of both stores, in one list, each row labelled by its store.
    ///
    /// Every call behind this is a read. A store that answers nothing adds no
    /// row, which is what a fresh release looks like.
    func storeVitals() async -> (apple: [StoreVitalsClient.Metric],
                                 google: [StoreVitalsClient.Metric],
                                 failures: [String]) {
        let client = StoreVitalsClient(api: readOnlyAPI())
        var apple: [StoreVitalsClient.Metric] = []
        var google: [StoreVitalsClient.Metric] = []
        var failures: [String] = []

        if stores.contains(.apple), let buildID = actualState.apple?.attachedBuildId {
            do { apple = try await client.appleVitals(buildID: buildID) }
            catch { failures.append("App Store: \(error.localizedDescription)") }
        }
        if stores.contains(.google), let packageName = googleActionPackage {
            do { google = try await client.googleVitals(packageName: packageName) }
            catch { failures.append("Google Play: \(error.localizedDescription)") }
        }
        return (apple, google, failures)
    }

    // MARK: - Xcode Cloud

    /// The Xcode Cloud workflows that build this app.
    func xcodeCloudWorkflows() async throws -> [XcodeCloudClient.Workflow] {
        guard let appID = appleActionAppID else { return [] }
        return try await XcodeCloudClient(api: readOnlyAPI()).workflows(appID: appID)
    }

    /// **This starts a build and spends compute minutes.** The panel confirms
    /// it first.
    func startXcodeCloudBuild(workflowID: String) async throws -> XcodeCloudClient.BuildRun {
        try await XcodeCloudClient(api: readOnlyAPI()).startBuild(workflowID: workflowID)
    }

    func xcodeCloudRuns(workflowID: String) async throws -> [XcodeCloudClient.BuildRun] {
        try await XcodeCloudClient(api: readOnlyAPI()).recentRuns(workflowID: workflowID)
    }

    /// The purchases Google voided: a refund, a chargeback, or a developer
    /// cancellation. It is a read, and it is the whole commerce surface the
    /// app touches. Issuing a refund moves real money, so no call here sends
    /// one and the developer does that in the Play Console.
    func googleVoidedPurchases() async throws -> [StoreVitalsClient.Voided] {
        guard let packageName = googleActionPackage else { return [] }
        return try await StoreVitalsClient(api: readOnlyAPI())
            .googleVoidedPurchases(packageName: packageName)
    }
}
