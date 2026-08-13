import Foundation

/// Game Center, as the runner applies it.
///
/// **Nothing here needs a build.** App Store Connect takes every call in this
/// file the moment it is sent, which is why the Gaming tab carries a button of
/// its own. What none of it does is reach a player: a configuration ships with
/// the App Store version that carries it, and `appleGameCenterAppVersion` is
/// the step that names that version.
///
/// **The detail is the parent of everything.** Every other call needs its id,
/// so `gameCenterDetailID()` resolves it from this run, from the read, or from
/// Apple, and fails the step with a sentence rather than sending a request with
/// an empty id in the path.
///
/// **Nothing here deletes.** Archiving is an attribute the manifest carries and
/// the object step writes. A delete discards every score behind the object, so
/// it lives behind the destructive button on the card.
extension Runner {

    private typealias Catalog = AppleGameCenterCatalogClient

    // MARK: - The configuration

    /// Creates the configuration when Apple holds none, and writes the one
    /// attribute this app manages on it.
    func appleGameCenterDetail() async throws {
        guard let wanted = manifest.gameCenter else { return }
        let client = AppleGameCenterClient(api: api)
        let detailID = try await client.ensureDetail(
            appID: appleAppID, existing: actual.apple?.gameCenter?.detail)
        appleGameCenterDetailID = detailID

        // The challenge minimums are a relationship to App Store versions, so
        // the version strings the manifest holds are resolved to Apple's own
        // ids first. A string that names no version of this app is left out
        // rather than sent: Apple would fault the whole request over it.
        guard let minimums = wanted.challengesMinimumPlatformVersions else { return }
        let versions = try await client.appStoreVersions(appID: appleAppID)
        // Every platform that ships the named version, because challenges are
        // offered per platform and one string covers both.
        let ids = versions.filter { minimums.contains($0.versionString) }.map(\.id)
        // Apple takes a `PATCH` alone here, so an empty list clears what it
        // holds. A manifest that named versions and matched none of them is a
        // mistake, not an instruction to clear them.
        guard !minimums.isEmpty, ids.isEmpty else {
            try await client.setChallengeMinimums(detailID: detailID, versionIDs: ids)
            return
        }
        throw RunError.uploadFailed(
            "The App Store has no version \(minimums.joined(separator: " or ")) for this app, so challenges have no version to start from. Challenges start at an App Store version of this game, such as 1.4.0, and not at an OS version.")
    }

    /// The group this game shares its objects with, and the detail pointed at
    /// it.
    ///
    /// A group is account-wide, so a name the account already holds is reused.
    /// The app never deletes one from an apply: other games are in it.
    func appleGameCenterGroup(name: String) async throws {
        let client = AppleGameCenterClient(api: api)
        let id = try await client.ensureGroup(
            named: name, existing: actual.apple?.gameCenter?.groups[name])
        appleGameCenterGroupIDs[name] = id
        try await client.setGroup(detailID: try await gameCenterDetailID(), groupID: id)
    }

    /// The board Game Center opens on.
    ///
    /// It runs after the leaderboards, because a relationship cannot name an
    /// object that does not exist yet. A manifest that names a board no family
    /// row holds writes nothing: the validator has already said so.
    func appleGameCenterDefaultLeaderboard() async throws {
        guard let board = manifest.gameCenter?.defaultLeaderboard, !board.isEmpty,
              let id = gameCenterObjectID(family: .leaderboard, vendorID: board) else { return }
        try await AppleGameCenterClient(api: api).setDefaultLeaderboard(
            detailID: try await gameCenterDetailID(), leaderboardID: id)
    }

    // MARK: - The five families

    /// One object: created under the detail or the group, or changed in place.
    func appleGameCenterObject(family: String, id: String) async throws {
        guard let family = Catalog.Family(rawValue: family),
              let row = gameCenterRow(family: family, id: id) else { return }
        let catalog = Catalog(api: api)
        let existing = actual.apple?.gameCenter?.objects(family)[id]

        let objectID = try await catalog.ensureObject(
            family: family, detailID: try await gameCenterDetailID(),
            groupID: try await gameCenterGroupID(), row.write, existing: existing)
        appleGameCenterObjectIDs[gameCenterKey(family, id)] = objectID

        // The address a player without the game is sent to lives on the
        // activity's version, so writing it needs one.
        guard let fallback = row.fallbackURL, !fallback.isEmpty, family == .activity else {
            return
        }
        let versionID = try await gameCenterVersionID(family: family, row: row,
                                                      objectID: objectID)
        try await catalog.setActivityFallbackURL(versionID: versionID, fallback)
    }

    /// One locale of one object. It hangs from the version, never from the
    /// object, and a version players already hold gets a new one first.
    func appleGameCenterLocale(family: String, id: String, locale: String) async throws {
        guard let family = Catalog.Family(rawValue: family),
              let row = gameCenterRow(family: family, id: id),
              let values = row.locales[locale], !values.isEmpty else { return }
        let objectID = try await gameCenterResourceID(family: family, vendorID: id)
        let versionID = try await gameCenterVersionID(family: family, row: row,
                                                      objectID: objectID)
        try await Catalog(api: api).ensureLocalization(
            family: family, versionID: versionID, locale: locale, values: values,
            existing: gameCenterLocalization(family: family, id: id, locale: locale,
                                             versionID: versionID))
    }

    /// One picture: three calls, the same three every upload in this app makes.
    ///
    /// It compares before it spends the upload. Apple returns no checksum on a
    /// Game Center image, so the comparison is the file name and the byte
    /// count, which is what the plan compared too.
    func appleGameCenterImage(family: String, id: String, locale: String?,
                              path: String, index: Int) async throws {
        guard let family = Catalog.Family(rawValue: family),
              let row = gameCenterRow(family: family, id: id),
              let url = resolve(path) else { return }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let catalog = Catalog(api: api)
        let existing = actual.apple?.gameCenter?.objects(family)[id]
        let objectID = try await gameCenterResourceID(family: family, vendorID: id)
        let versionID = try await gameCenterVersionID(family: family, row: row,
                                                      objectID: objectID)

        // What Apple holds counts only when this run is writing onto the very
        // version that was read. A version players already have gets a new one
        // instead, and that new one carries no picture of ours: comparing
        // against the old version's image would skip the upload, and deleting
        // it would take the picture off what players are looking at now.
        let onTheVersionThatWasRead = versionID == existing?.draftVersionID
        let localization = gameCenterLocalization(family: family, id: id, locale: locale,
                                                  versionID: versionID)
        let held: (id: String?, name: String?, size: Int?) =
            if !onTheVersionThatWasRead { (nil, nil, nil) }
            else if locale != nil {
                (localization?.imageID, localization?.imageFileName,
                 localization?.imageFileSize)
            } else {
                (existing?.defaultImageID, existing?.defaultImageFileName,
                 existing?.defaultImageFileSize)
            }
        if held.name == url.lastPathComponent, held.size == data.count { return }

        let parent: Catalog.ImageParent
        if let locale {
            let localizationID = try await catalog.ensureLocalization(
                family: family, versionID: versionID, locale: locale,
                values: row.locales[locale] ?? [:], existing: localization)
            parent = .localization(localizationID)
        } else {
            parent = .version(versionID)
        }

        // Apple keeps one image per parent, so a replacement starts by
        // removing the one it holds.
        if let stale = held.id {
            try? await catalog.deleteImage(family: family, id: stale)
        }
        let reservation = try await catalog.reserveImage(
            family: family, parent: parent, fileName: url.lastPathComponent,
            fileSize: data.count)
        try await executeUploadOperations(reservation.operations, data: data, index: index,
                                          label: url.lastPathComponent)
        try await catalog.finishImage(family: family, id: reservation.id)
    }

    // MARK: - The links

    /// The boards inside a set. The difference, never the whole list.
    func appleGameCenterMembers(set: String) async throws {
        guard let row = gameCenterRow(family: .leaderboardSet, id: set),
              let wanted = row.members else { return }
        let live = actual.apple?.gameCenter?.leaderboardSets[set]
        let setID = try await gameCenterResourceID(family: .leaderboardSet, vendorID: set)
        let change = try await gameCenterLinkChange(
            family: .leaderboard, wanted: wanted, held: live?.linkedIDs ?? [])
        guard !change.add.isEmpty || !change.remove.isEmpty else { return }
        try await Catalog(api: api).setMembers(setID: setID, add: change.add,
                                               remove: change.remove)
    }

    /// What an activity awards and scores to.
    func appleGameCenterLinks(activity: String) async throws {
        guard let row = gameCenterRow(family: .activity, id: activity) else { return }
        let live = actual.apple?.gameCenter?.activities[activity]
        let activityID = try await gameCenterResourceID(family: .activity, vendorID: activity)

        let achievements = try await gameCenterLinkChange(
            family: .achievement, wanted: row.linkedAchievements,
            held: live?.linkedAchievementIDs ?? [])
        let leaderboards = try await gameCenterLinkChange(
            family: .leaderboard, wanted: row.linkedLeaderboards,
            held: live?.linkedIDs ?? [])
        try await Catalog(api: api).setActivityLinks(
            activityID: activityID, achievements: achievements, leaderboards: leaderboards)
    }

    /// The board a challenge scores from.
    func appleGameCenterChallengeLeaderboard(challenge: String) async throws {
        guard let row = gameCenterRow(family: .challenge, id: challenge),
              let board = row.leaderboard, !board.isEmpty,
              let boardID = gameCenterObjectID(family: .leaderboard, vendorID: board) else {
            return
        }
        let challengeID = try await gameCenterResourceID(family: .challenge,
                                                         vendorID: challenge)
        try await Catalog(api: api).setChallengeLeaderboard(challengeID: challengeID,
                                                            leaderboardID: boardID)
    }

    // MARK: - Matchmaking

    /// One rule set, with its rules and its teams inside the one step.
    ///
    /// It creates and it changes, and it removes nothing: a rule the manifest
    /// stopped naming stays until somebody deletes it from its own card, where
    /// the button can say what stops matching.
    func appleGameCenterRuleSet(name: String) async throws {
        guard let wanted = manifest.gameCenter?.matchmaking?.ruleSets?
            .first(where: { $0.name == name }) else { return }
        let client = AppleGameCenterMatchmakingClient(api: api)
        let live = actual.apple?.gameCenter?.ruleSets[name]

        let id = try await client.ensureRuleSet(wanted, existing: live)
        appleGameCenterRuleSetIDs[name] = id
        for rule in wanted.rules ?? [] {
            try await client.ensureRule(ruleSetID: id, rule, existing: live?.rules[rule.name])
        }
        for team in wanted.teams ?? [] {
            try await client.ensureTeam(ruleSetID: id, team, existing: live?.teams[team.name])
        }
    }

    /// One queue, and the rule set it matches with.
    func appleGameCenterQueue(name: String) async throws {
        guard let wanted = manifest.gameCenter?.matchmaking?.queues?
            .first(where: { $0.name == name }) else { return }
        let client = AppleGameCenterMatchmakingClient(api: api)
        let ruleSetID = wanted.ruleSet.flatMap { setName in
            appleGameCenterRuleSetIDs[setName]
                ?? actual.apple?.gameCenter?.ruleSets[setName]?.id
        }
        _ = try await client.ensureQueue(
            wanted, ruleSetID: ruleSetID,
            existing: actual.apple?.gameCenter?.queues[name])
    }

    // MARK: - What publishes it

    /// The App Store version that carries the configuration.
    ///
    /// This is the last Game Center step and the only one that reaches a
    /// player. Apple publishes no call that releases a Game Center version on
    /// its own, so the configuration ships with the version named here.
    func appleGameCenterAppVersion(version: String) async throws {
        guard let wanted = manifest.gameCenter?.appVersions?[version] else { return }
        let live = actual.apple?.gameCenter
        let client = AppleGameCenterClient(api: api)

        // The version Apple already links, then the one this run is
        // publishing, then the App Store versions of the app. The last is one
        // request and it is what lets a game carry the configuration on a
        // version this run is not otherwise touching.
        var appStoreVersionID = live?.appVersions[version]?.appStoreVersionID
        if appStoreVersionID == nil, version == manifest.versionName(for: .apple) {
            appStoreVersionID = appleVersionID
        }
        if appStoreVersionID == nil {
            let versions = try await client.appStoreVersions(appID: appleAppID)
                .filter { $0.versionString == version }
            appStoreVersionID = (versions.first { $0.platform == applePlatform }
                ?? versions.first)?.id
        }
        guard let appStoreVersionID else {
            throw RunError.uploadFailed(
                "The App Store has no version \(version), so nothing can carry the Game Center configuration. Create the version first.")
        }
        let id = try await client.ensureAppVersion(
            appStoreVersionID: appStoreVersionID, enabled: wanted.enabled,
            existing: live?.appVersions[version])

        guard let compatibility = wanted.compatibility else { return }
        let held = live?.appVersions[version]?.compatibilityVersionIDs ?? []
        let ids = Set(compatibility.compactMap { live?.appVersions[$0]?.id })
        try await client.setCompatibility(appVersionID: id,
                                          add: Array(ids.subtracting(held)),
                                          remove: Array(held.subtracting(ids)))
    }

    // MARK: - The ids every step above needs

    /// The detail: from this run, from the read, or from Apple.
    ///
    /// A run that starts at a step past the detail one still needs it, and so
    /// does a direct apply that planned only some of the rows.
    private func gameCenterDetailID() async throws -> String {
        if let id = appleGameCenterDetailID { return id }
        if let id = actual.apple?.gameCenter?.detail?.id {
            appleGameCenterDetailID = id
            return id
        }
        let id = try await AppleGameCenterClient(api: api).ensureDetail(
            appID: appleAppID, existing: nil)
        appleGameCenterDetailID = id
        return id
    }

    /// The group the objects hang from, or nil when the manifest names none.
    ///
    /// Apple publishes no call that moves an existing object between a detail
    /// and a group, so this is read on a create and never on a change. The
    /// planner raises a warning naming the object instead.
    private func gameCenterGroupID() async throws -> String? {
        guard let name = manifest.gameCenter?.group, !name.isEmpty else { return nil }
        if let id = appleGameCenterGroupIDs[name] { return id }
        if let id = actual.apple?.gameCenter?.groups[name] { return id }
        let id = try await AppleGameCenterClient(api: api).ensureGroup(named: name,
                                                                       existing: nil)
        appleGameCenterGroupIDs[name] = id
        return id
    }

    /// The resource id of one object: from this run, or from the read.
    private func gameCenterObjectID(family: Catalog.Family, vendorID: String) -> String? {
        appleGameCenterObjectIDs[gameCenterKey(family, vendorID)]
            ?? actual.apple?.gameCenter?.objects(family)[vendorID]?.id
    }

    /// The same, and it creates the object when neither one holds it.
    ///
    /// A direct apply plans only the rows that differ, so a locale step can
    /// run for an object whose own step was not in the plan. Creating it here
    /// beats failing a step over an id the run could have found.
    private func gameCenterResourceID(family: Catalog.Family,
                                      vendorID: String) async throws -> String {
        if let id = gameCenterObjectID(family: family, vendorID: vendorID) { return id }
        guard let row = gameCenterRow(family: family, id: vendorID) else {
            throw RunError.uploadFailed(
                "The manifest names no \(family.noun) \(vendorID).")
        }
        let id = try await Catalog(api: api).ensureObject(
            family: family, detailID: try await gameCenterDetailID(),
            groupID: try await gameCenterGroupID(), row.write, existing: nil)
        appleGameCenterObjectIDs[gameCenterKey(family, vendorID)] = id
        return id
    }

    /// The version a localization or an image attaches to, made once per run.
    private func gameCenterVersionID(family: Catalog.Family, row: GameCenterRow,
                                     objectID: String) async throws -> String {
        let key = gameCenterKey(family, row.id)
        if let id = appleGameCenterVersionIDs[key] { return id }
        let id = try await Catalog(api: api).ensureVersion(
            family: family, objectID: objectID,
            existing: actual.apple?.gameCenter?.objects(family)[row.id])
        appleGameCenterVersionIDs[key] = id
        return id
    }

    /// One link list as the difference between what the manifest names and
    /// what Apple holds, in Apple's own resource ids.
    ///
    /// The difference and never the whole list: a replace written from a stale
    /// read drops a link somebody added in the console that morning.
    private func gameCenterLinkChange(family: Catalog.Family, wanted: [String]?,
                                      held: Set<String>) async throws
        -> (add: [String], remove: [String]) {
        guard let wanted else { return ([], []) }
        let target = Set(wanted)
        var add: [String] = []
        for vendorID in target.subtracting(held).sorted() {
            add.append(try await gameCenterResourceID(family: family, vendorID: vendorID))
        }
        // A link Apple holds and the manifest dropped is removed by its own
        // resource id, which the read already knows.
        let remove = held.subtracting(target).sorted().compactMap {
            actual.apple?.gameCenter?.objects(family)[$0]?.id
        }
        return (add, remove)
    }

    /// The localization Apple holds for one locale, and only when this run is
    /// writing onto the very version that was read.
    ///
    /// A version players already have is never written onto: `ensureVersion`
    /// makes a new one, and the localizations of the old version belong to it.
    /// Passing one of their ids on would `PATCH` what players are reading now
    /// instead of writing the new version.
    private func gameCenterLocalization(family: Catalog.Family, id: String, locale: String?,
                                        versionID: String) -> Catalog.Localization? {
        guard let locale else { return nil }
        let object = actual.apple?.gameCenter?.objects(family)[id]
        guard versionID == object?.draftVersionID else { return nil }
        return object?.localizations[locale]
    }

    /// The manifest row behind one step id.
    private func gameCenterRow(family: Catalog.Family, id: String) -> GameCenterRow? {
        manifest.gameCenter?.rows(family).first { $0.id == id }
    }

    private func gameCenterKey(_ family: Catalog.Family, _ vendorID: String) -> String {
        "\(family.rawValue)/\(vendorID)"
    }
}
