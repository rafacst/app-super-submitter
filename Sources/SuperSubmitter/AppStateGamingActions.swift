import SubmitKit
import SwiftUI

/// The Game Center calls that sit outside the plan.
///
/// This is the Gaming twin of `AppStateAppleActions`. None of it is a desired
/// state, so none of it belongs in `store.yaml` or in a plan row: a delete
/// takes something away, a metric answers a question, and a test submission is
/// a developer checking their own game. Each one runs on a button and reports
/// its own result.
///
/// `AppStateGaming.swift` holds the other half, which writes the manifest and
/// calls nothing.
@MainActor
extension AppState {

    // MARK: - The deletes

    /// What one delete is about to take with it, in the words the confirmation
    /// uses.
    ///
    /// Apple discards every score and every earned achievement behind an
    /// object, and publishes no call that brings them back. So a delete is
    /// never a plan step and never a manifest key: it is a button, it names
    /// what it removes, and it says what goes with it.
    enum GameCenterDeletion: Equatable {
        case object(family: AppleGameCenterCatalogClient.Family, vendorID: String,
                    name: String)
        case group(name: String)
        case ruleSet(name: String)
        case rule(ruleSet: String, name: String)
        case team(ruleSet: String, name: String)
        case queue(name: String)
        case memberName(id: String, locale: String, set: String)

        var title: String {
            switch self {
            case .object(let family, _, let name): "Delete the \(family.noun) \(name)?"
            case .group(let name): "Delete the group \(name)?"
            case .ruleSet(let name): "Delete the rule set \(name)?"
            case .rule(_, let name): "Delete the rule \(name)?"
            case .team(_, let name): "Delete the team \(name)?"
            case .queue(let name): "Delete the queue \(name)?"
            case .memberName(_, let locale, let set): "Remove the \(locale) name in \(set)?"
            }
        }

        /// What it costs. Each sentence states the loss in the store's own
        /// terms, because that is the part no undo covers.
        var message: String {
            switch self {
            case .object(let family, let vendorID, _):
                "App Store Connect removes the \(family.noun) \(vendorID), and every score or earned achievement behind it goes with it. Apple publishes no call that brings them back. To stop managing it here and leave it in App Store Connect, use the trash button instead."
            case .group(let name):
                "App Store Connect removes the group \(name). Every game in that group loses the achievements and leaderboards it shared through it, and this app is not the only game that may be in it."
            case .ruleSet(let name):
                "App Store Connect removes the rule set \(name). Any queue that matches with it stops matching players."
            case .rule(_, let name):
                "App Store Connect removes the rule \(name). The rule set stops applying it to new match requests."
            case .team(_, let name):
                "App Store Connect removes the team \(name). The rule set stops assigning players to it."
            case .queue(let name):
                "App Store Connect removes the queue \(name). Players waiting in it stop being matched."
            case .memberName:
                "App Store Connect removes this name. Apple deprecated the call that writes one, so this app cannot put it back: the set's own localization is what names a set from here."
            }
        }
    }

    /// Runs one delete against App Store Connect, then forgets what the read
    /// said about it.
    ///
    /// The live state is trimmed rather than re-read. A whole read costs a
    /// hundred requests on a game with a real catalog, and the one thing that
    /// changed is the row that just went.
    func deleteInGameCenter(_ deletion: GameCenterDeletion) async {
        gamingActionMessage = ""
        gamingActionFailed = false
        let catalog = AppleGameCenterCatalogClient(api: readOnlyAPI())

        do {
            switch deletion {
            case .object(let family, let vendorID, _):
                guard let id = liveGameCenter?.objects(family)[vendorID]?.id else { return }
                try await catalog.delete(family: family, id: id)
                forgetGameCenterObject(family: family, vendorID: vendorID)
            case .group(let name):
                guard let id = liveGameCenter?.groups[name] else { return }
                try await AppleGameCenterClient(api: readOnlyAPI()).deleteGroup(id: id)
                actualState.apple?.gameCenter?.groups[name] = nil
            case .ruleSet(let name):
                guard let id = liveGameCenter?.ruleSets[name]?.id else { return }
                try await AppleGameCenterMatchmakingClient(api: readOnlyAPI())
                    .deleteRuleSet(id: id)
                actualState.apple?.gameCenter?.ruleSets[name] = nil
            case .rule(let set, let name):
                guard let id = liveGameCenter?.ruleSets[set]?.rules[name]?.id else { return }
                try await AppleGameCenterMatchmakingClient(api: readOnlyAPI())
                    .deleteRule(id: id)
                actualState.apple?.gameCenter?.ruleSets[set]?.rules[name] = nil
            case .team(let set, let name):
                guard let id = liveGameCenter?.ruleSets[set]?.teams[name]?.id else { return }
                try await AppleGameCenterMatchmakingClient(api: readOnlyAPI())
                    .deleteTeam(id: id)
                actualState.apple?.gameCenter?.ruleSets[set]?.teams[name] = nil
            case .queue(let name):
                guard let id = liveGameCenter?.queues[name]?.id else { return }
                try await AppleGameCenterMatchmakingClient(api: readOnlyAPI())
                    .deleteQueue(id: id)
                actualState.apple?.gameCenter?.queues[name] = nil
            case .memberName(let id, _, let set):
                try await catalog.deleteMemberLocalization(id: id)
                actualState.apple?.gameCenter?.memberLocalizations[set]?
                    .removeAll { $0.id == id }
            }
            gamingActionMessage = "Removed in App Store Connect."
            invalidatePlan()
        } catch {
            gamingActionFailed = true
            gamingActionMessage = error.localizedDescription
        }
    }

    /// Drops one object from the live state after Apple removed it.
    private func forgetGameCenterObject(family: AppleGameCenterCatalogClient.Family,
                                        vendorID: String) {
        switch family {
        case .achievement: actualState.apple?.gameCenter?.achievements[vendorID] = nil
        case .leaderboard: actualState.apple?.gameCenter?.leaderboards[vendorID] = nil
        case .leaderboardSet: actualState.apple?.gameCenter?.leaderboardSets[vendorID] = nil
        case .activity: actualState.apple?.gameCenter?.activities[vendorID] = nil
        case .challenge: actualState.apple?.gameCenter?.challenges[vendorID] = nil
        }
    }

    // MARK: - The metrics

    /// Which resources a metric can be asked about, by the name a developer
    /// gave them. The panel offers no metric it has no id for.
    func gameCenterMetricTargets(_ owner: AppleGameCenterMatchmakingClient.Metric.Owner)
        -> [StoreValues.Choice] {
        switch owner {
        case .detail:
            (liveGameCenter?.detail?.id).map { [.init($0, "This game")] } ?? []
        case .queue:
            (liveGameCenter?.queues ?? [:]).values
                .sorted { $0.referenceName < $1.referenceName }
                .map { .init($0.id, $0.referenceName) }
        case .rule:
            (liveGameCenter?.ruleSets ?? [:]).values
                .sorted { $0.referenceName < $1.referenceName }
                .flatMap { set in
                    set.rules.values.sorted { $0.referenceName < $1.referenceName }
                        .map { .init($0.id, "\(set.referenceName) · \($0.referenceName)") }
                }
        }
    }

    /// One metric series, drawn and then dropped.
    ///
    /// It stores nothing. The panel holds the table while it is on screen and
    /// the next read asks Apple again, which is the rule every metric in this
    /// app follows.
    func readGameCenterMetric(_ metric: AppleGameCenterMatchmakingClient.Metric,
                              id: String) async -> ReportTable {
        gamingActionMessage = ""
        gamingActionFailed = false
        do {
            return try await AppleGameCenterMatchmakingClient(api: readOnlyAPI())
                .metric(metric, id: id)
        } catch {
            gamingActionFailed = true
            gamingActionMessage = error.localizedDescription
            return ReportTable()
        }
    }

    // MARK: - Test data

    /// Runs a rule set against synthetic players.
    ///
    /// No confirmation, because there is nothing to undo: Apple evaluates the
    /// rules and answers, and the requests exist for the length of the call.
    func testGameCenterRuleSet(named name: String, requests: Int,
                               playersPerRequest: Int) async
        -> [AppleGameCenterMatchmakingClient.TestMatch] {
        gamingActionMessage = ""
        gamingActionFailed = false
        guard let id = liveGameCenter?.ruleSets[name]?.id else {
            gamingActionFailed = true
            gamingActionMessage = "App Store Connect holds no rule set called \(name). Send it first."
            return []
        }
        let synthetic = (1...max(1, requests)).map { number in
            AppleGameCenterMatchmakingClient.TestRequest(
                id: "request-\(number)", name: "Request \(number)",
                playerCount: max(1, playersPerRequest))
        }
        do {
            let matches = try await AppleGameCenterMatchmakingClient(api: readOnlyAPI())
                .test(ruleSetID: id, requests: synthetic)
            gamingActionMessage = matches.isEmpty
                ? "The rule set matched nobody. Every request was refused."
                : "\(matches.count) \(matches.count == 1 ? "match" : "matches") from \(synthetic.count) requests."
            return matches
        } catch {
            gamingActionFailed = true
            gamingActionMessage = error.localizedDescription
            return []
        }
    }

    /// Posts one score for one player.
    ///
    /// The bundle id comes from the manifest, because Apple keys the
    /// submission by it and a developer should not retype what the Stores tab
    /// already holds.
    func submitGameCenterScore(leaderboard: String, playerID: String, score: Double,
                               preReleased: Bool) async {
        await submitTestData {
            try await AppleGameCenterCatalogClient(api: self.readOnlyAPI()).submitScore(
                bundleID: $0, vendorIdentifier: leaderboard, scopedPlayerID: playerID,
                score: score, preReleased: preReleased)
            return "Score sent to \(leaderboard)\(preReleased ? " on the prerelease side" : "")."
        }
    }

    /// Posts achievement progress for one player, as a percentage.
    func submitGameCenterAchievement(achievement: String, playerID: String,
                                     percentage: Int, preReleased: Bool) async {
        await submitTestData {
            try await AppleGameCenterCatalogClient(api: self.readOnlyAPI())
                .submitAchievement(
                    bundleID: $0, vendorIdentifier: achievement, scopedPlayerID: playerID,
                    percentage: percentage, preReleased: preReleased)
            return "\(percentage)% sent to \(achievement)\(preReleased ? " on the prerelease side" : "")."
        }
    }

    /// The bundle id, the reporting, and the one failure path that both
    /// submissions share.
    private func submitTestData(_ send: (String) async throws -> String) async {
        gamingActionMessage = ""
        gamingActionFailed = false
        let bundleID = manifest.apps.apple?.bundleId ?? ""
        guard !bundleID.isEmpty else {
            gamingActionFailed = true
            gamingActionMessage = "The manifest names no bundle id, and Apple keys a test submission by it. Fill it in on the Stores tab."
            return
        }
        do { gamingActionMessage = try await send(bundleID) }
        catch {
            gamingActionFailed = true
            gamingActionMessage = error.localizedDescription
        }
    }
}
