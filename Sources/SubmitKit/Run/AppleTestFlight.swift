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

    func appleBetaReview() async throws {
        guard let buildID = attachedBuildID else {
            throw RunError.uploadFailed("No build is attached, so none can go to beta review.")
        }
        try await AppleTestFlightClient(api: api).submitForBetaReview(buildID: buildID)
    }

    /// The build this run works on: the one it attached, or the one the store
    /// already holds on the version.
    private var attachedBuildID: String? {
        appleBuildID ?? actual.apple?.attachedBuildId
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
