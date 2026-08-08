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

    // MARK: - Promoting an experiment treatment

    /// Every treatment the store holds for the version this app last read.
    ///
    /// The Marketing tab writes the experiments; this names what Apple holds,
    /// because a promotion addresses Apple's ids and not the manifest's keys.
    func appleTreatments() async throws -> [AppleActionsClient.Treatment] {
        guard let versionID = actualState.apple?.versionId else { return [] }
        return try await appleActions().treatments(versionID: versionID)
    }

    /// **This makes one treatment the page every App Store visitor sees.** The
    /// panel confirms it. Promoting a different treatment is the way back.
    func promoteAppleTreatment(_ treatmentID: String) async throws {
        guard let versionID = actualState.apple?.versionId else {
            throw ConnectionError.http(
                400, "Read the stores on the Summary tab first, so the app knows the version.")
        }
        try await appleActions().promote(versionID: versionID, treatmentID: treatmentID)
    }

    // MARK: - The two provisioning writes

    /// **This registers a device on the team.** It spends one slot of the
    /// yearly device quota, and Apple clears that quota once a year.
    func registerAppleDevice(name: String, platform: String, udid: String) async throws {
        try await AppleProvisioningClient(api: readOnlyAPI())
            .registerDevice(name: name, platform: platform, udid: udid)
    }

    /// **This reserves a bundle ID for the team.** No call here deletes one
    /// again, and it does not create the App Store record: Apple publishes no
    /// call for that, so the developer still makes the app once in the console.
    func createAppleBundleID(name: String, identifier: String,
                             platform: String) async throws {
        try await AppleProvisioningClient(api: readOnlyAPI())
            .createBundleID(name: name, identifier: identifier, platform: platform)
    }

    // MARK: - The people on the App Store Connect account

    func appleTeam() -> AppleTeamClient {
        AppleTeamClient(api: readOnlyAPI())
    }

    /// Everybody on the account, and every address Apple is still waiting on.
    func appleTeamMembers() async throws -> [AppleTeamClient.Member] {
        try await appleTeam().members()
    }

    /// **This emails a real address.** The panel confirms it. The person holds
    /// the roles named here from the moment they accept.
    ///
    /// An invitation that is not for every app is scoped to the app the
    /// manifest names, which is the app the developer is standing in. The
    /// account holder widens it in App Store Connect afterwards.
    func inviteAppleTeamMember(email: String, firstName: String, lastName: String,
                               roles: [String], allAppsVisible: Bool) async throws {
        try await appleTeam().invite(email: email, firstName: firstName,
                                     lastName: lastName, roles: roles,
                                     allAppsVisible: allAppsVisible,
                                     visibleApps: allAppsVisible ? []
                                        : [appleActionAppID].compactMap { $0 })
    }

    /// **This changes what a colleague may do.** The role list is the whole
    /// list, so a role left out is a role taken away.
    func setAppleTeamRoles(_ member: AppleTeamClient.Member, roles: [String],
                           allAppsVisible: Bool) async throws {
        try await appleTeam().setRoles(userID: member.id, roles: roles,
                                       allAppsVisible: allAppsVisible,
                                       provisioningAllowed: member.provisioningAllowed)
    }

    /// **This decides which apps a colleague sees.** Apple refuses the call
    /// while "every app" is on, so the flag goes off first.
    func setAppleTeamVisibleApps(_ member: AppleTeamClient.Member,
                                 appIDs: [String]) async throws {
        if member.allAppsVisible {
            try await appleTeam().setRoles(userID: member.id, roles: member.roles,
                                           allAppsVisible: false,
                                           provisioningAllowed: member.provisioningAllowed)
        }
        try await appleTeam().setVisibleApps(userID: member.id, appIDs: appIDs)
    }

    /// **This shuts a colleague out of the whole account.** The panel confirms
    /// it. No call puts them back; a new invitation does, and they have to
    /// accept it again.
    func removeAppleTeamMember(_ member: AppleTeamClient.Member) async throws {
        try await appleTeam().removeMember(member)
    }

    /// The purchases Google voided: a refund, a chargeback, or a developer
    /// cancellation. It is a read, and the lookup below is the other half of
    /// it. Issuing a refund moves real money, so no call here sends one and
    /// the developer does that in the Play Console.
    func googleVoidedPurchases() async throws -> [StoreVitalsClient.Voided] {
        guard let packageName = googleActionPackage else { return [] }
        return try await StoreVitalsClient(api: readOnlyAPI())
            .googleVoidedPurchases(packageName: packageName)
    }

    /// What one order id or one purchase token resolves to. A read, like the
    /// refunds above: it answers what a customer bought and changes nothing.
    func googlePurchaseLookup(query: String,
                              productId: String) async throws -> StoreVitalsClient.PurchaseLookup {
        guard let packageName = googleActionPackage else {
            return StoreVitalsClient.PurchaseLookup(
                notes: ["Name the package on tab 2 first. Google looks a purchase up under one app."])
        }
        return try await StoreVitalsClient(api: readOnlyAPI())
            .googlePurchaseLookup(packageName: packageName, query: query,
                                  productId: productId)
    }
}
