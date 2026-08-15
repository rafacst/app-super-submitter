import Foundation

/// TestFlight, as the runner applies it.
///
/// This is the App Store twin of the Google track testers. Google writes them
/// inside the edit that wraps a run; Apple keeps them on their own resources,
/// so each row is its own step and a failure names the group that failed.
///
/// Every call here reaches a person. The planner already compared what Apple
/// holds, so a step that runs is a step with real work in it.
extension Runner {

    func appleBetaGroup(name: String) async throws {
        guard let group = manifest.release?.apple?.testFlight?.groups?
            .first(where: { $0.name == name }) else { return }
        let client = AppleTestFlightClient(api: api)
        let id = try await client.ensureGroup(appID: appleAppID, group,
                                              existing: actual.apple?.betaGroups[name])
        appleBetaGroupIDs[name] = id
    }

    func appleBetaTesters(group name: String, emails: [String]) async throws {
        guard !emails.isEmpty else { return }
        let client = AppleTestFlightClient(api: api)
        let id = try await betaGroupID(name, client: client)
        _ = try await client.addTesters(
            groupID: id, emails: emails,
            existing: actual.apple?.betaGroups[name]?.testers ?? [])
    }

    func appleBetaBuild(group name: String) async throws {
        // Apple refuses a build on an internal group and faults the request,
        // which stops the run on a row that had nothing to do. An internal
        // group needs none: its testers get every build of the app.
        guard !internalBetaGroup(name) else { return }
        guard let buildID = attachedBuildID else {
            throw RunError.uploadFailed("No build is attached, so no group can receive one.")
        }
        let client = AppleTestFlightClient(api: api)
        try await client.addBuild(groupID: try await betaGroupID(name, client: client),
                                  buildID: buildID)
    }

    func appleWhatToTest() async throws {
        guard let notes = manifest.release?.apple?.testFlight?.whatToTest, !notes.isEmpty,
              let buildID = attachedBuildID else { return }
        try await AppleTestFlightClient(api: api).setWhatToTest(
            buildID: buildID, notes: notes, existing: actual.apple?.whatToTest ?? [:])
    }

    func appleBetaAutoNotify(_ enabled: Bool) async throws {
        guard let buildID = attachedBuildID else { return }
        try await AppleTestFlightClient(api: api).setAutoNotify(buildID: buildID, enabled)
    }

    /// The TestFlight page of the app. It needs no build, so it runs whether
    /// or not an artifact reached Apple.
    func appleBetaAppLocalizations() async throws {
        guard let wanted = manifest.release?.apple?.testFlight?.localizations,
              !wanted.isEmpty else { return }
        try await AppleTestFlightClient(api: api).setAppLocalizations(
            appID: appleAppID, wanted)
    }

    /// The licence every external tester accepts. Apple keeps one per app and
    /// creates it itself, so this only ever patches.
    func appleBetaLicenseAgreement() async throws {
        guard let text = manifest.release?.apple?.testFlight?.licenseAgreement else { return }
        try await AppleTestFlightClient(api: api).setLicenseAgreement(appID: appleAppID,
                                                                      text: text)
    }

    /// The contact that Apple reaches about a beta review. The demo account
    /// comes from the Keychain and never from `store.yaml`, the same rule the
    /// App Store review detail follows.
    func appleBetaReviewDetail() async throws {
        try await AppleTestFlightClient(api: api).setBetaReviewDetail(
            appID: appleAppID, review: manifest.review, reviewer: reviewerCredential)
    }

    func appleBetaReview() async throws {
        guard let buildID = attachedBuildID else {
            throw RunError.uploadFailed("No build is attached, so none can go to beta review.")
        }
        try await AppleTestFlightClient(api: api).submitForBetaReview(buildID: buildID)
    }

    /// The build this run works on: the one it uploaded, the newest processed
    /// build of this version, or the one the App Store version holds.
    ///
    /// `buildIdForVersion` was missing, and TestFlight is where that hurt.
    /// A build reaches Apple long before a version holds it, and a beta needs
    /// no version at all, so a developer who uploaded and went straight to
    /// TestFlight met "No build is attached" on a build Apple had processed
    /// hours ago. `AppleApply` has read the three in this order all along.
    private var attachedBuildID: String? {
        appleBuildID ?? actual.apple?.buildIdForVersion ?? actual.apple?.attachedBuildId
    }

    /// Whether the group is internal, by the manifest or by the last read.
    /// Apple settles the kind when it creates a group, so the read is the
    /// answer for a group the manifest says nothing about.
    private func internalBetaGroup(_ name: String) -> Bool {
        manifest.release?.apple?.testFlight?.groups?
            .first(where: { $0.name == name })?.internalGroup == true
            || actual.apple?.betaGroups[name]?.internalGroup == true
    }

    /// The group id, from this run or from the read. A group that neither one
    /// holds is created here rather than failing the step.
    private func betaGroupID(_ name: String,
                             client: AppleTestFlightClient) async throws -> String {
        if let id = appleBetaGroupIDs[name] { return id }
        if let id = actual.apple?.betaGroups[name]?.id { return id }
        guard let group = manifest.release?.apple?.testFlight?.groups?
            .first(where: { $0.name == name }) else {
            throw RunError.uploadFailed("The manifest names no TestFlight group \(name).")
        }
        let id = try await client.ensureGroup(appID: appleAppID, group, existing: nil)
        appleBetaGroupIDs[name] = id
        return id
    }
}
