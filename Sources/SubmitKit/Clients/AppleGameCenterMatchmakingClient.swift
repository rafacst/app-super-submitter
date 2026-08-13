import Foundation

/// Matchmaking: the rule sets that score a pairing, the rules and teams inside
/// them, and the queues players wait in.
///
/// **None of it needs a build.** A rule set is account-wide, like a group, and
/// Apple takes a change to one the moment it is sent. So the Gaming tab writes
/// these from its own button and the plan carries them like any other row.
///
/// **Keyed by reference name.** Apple gives matchmaking no vendor identifier,
/// so the reference name is the key here, and it is what a queue points at.
/// Renaming a rule set in `store.yaml` therefore creates a second one rather
/// than renaming the first, exactly as renaming a TestFlight group does.
public struct AppleGameCenterMatchmakingClient: Sendable {
    private let api: StoreAPI

    public init(api: StoreAPI) {
        self.api = api
    }

    // MARK: - What the account holds

    public struct RuleSet: Sendable, Equatable {
        public var id: String
        public var referenceName: String
        public var minPlayers: Int?
        public var maxPlayers: Int?
        public var ruleLanguageVersion: Int?
        /// The rules and the teams, each keyed by their own reference name.
        public var rules: [String: Rule] = [:]
        public var teams: [String: Team] = [:]

        public init(id: String, referenceName: String) {
            self.id = id
            self.referenceName = referenceName
        }
    }

    public struct Rule: Sendable, Equatable {
        public var id: String
        public var referenceName: String
        public var description: String?
        public var type: String?
        public var expression: String?
        public var weight: Double?

        public init(id: String, referenceName: String) {
            self.id = id
            self.referenceName = referenceName
        }
    }

    public struct Team: Sendable, Equatable {
        public var id: String
        public var referenceName: String
        public var minPlayers: Int?
        public var maxPlayers: Int?

        public init(id: String, referenceName: String) {
            self.id = id
            self.referenceName = referenceName
        }
    }

    public struct Queue: Sendable, Equatable {
        public var id: String
        public var referenceName: String
        public var classicBundleIds: [String] = []
        /// The rule set this queue matches with, as Apple's resource id.
        public var ruleSetID: String?

        public init(id: String, referenceName: String) {
            self.id = id
            self.referenceName = referenceName
        }
    }

    // MARK: - The read

    /// Every rule set of the account, with its rules and its teams.
    ///
    /// The rules and the teams cost one request each per set. They are read
    /// rather than guessed because the plan compares them: a rule that this
    /// read missed would be created a second time under the same name.
    public func ruleSets() async throws -> [String: RuleSet] {
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/gameCenterMatchmakingRuleSets?limit=200").data)

        var result: [String: RuleSet] = [:]
        for item in payload["data"].array {
            guard let id = item["id"].string else { continue }
            let attributes = item["attributes"]
            guard let name = attributes["referenceName"].string, !name.isEmpty else { continue }
            var set = RuleSet(id: id, referenceName: name)
            set.minPlayers = attributes["minPlayers"].int
            set.maxPlayers = attributes["maxPlayers"].int
            set.ruleLanguageVersion = attributes["ruleLanguageVersion"].int
            set.rules = await rules(ruleSetID: id)
            set.teams = await teams(ruleSetID: id)
            result[name] = set
        }
        return result
    }

    /// Every queue of the account, by reference name.
    public func queues() async throws -> [String: Queue] {
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/gameCenterMatchmakingQueues?limit=200").data)

        var result: [String: Queue] = [:]
        for item in payload["data"].array {
            guard let id = item["id"].string,
                  let name = item["attributes"]["referenceName"].string,
                  !name.isEmpty else { continue }
            var queue = Queue(id: id, referenceName: name)
            queue.classicBundleIds = item["attributes"]["classicMatchmakingBundleIds"]
                .array.compactMap(\.string)
            queue.ruleSetID = item["relationships"]["ruleSet"]["data"]["id"].string
            result[name] = queue
        }
        return result
    }

    private func rules(ruleSetID: String) async -> [String: Rule] {
        guard let response = try? await api.apple(
            "GET", "/v1/gameCenterMatchmakingRuleSets/\(ruleSetID)/rules?limit=200")
        else { return [:] }

        var result: [String: Rule] = [:]
        for item in JSON(data: response.data)["data"].array {
            guard let id = item["id"].string,
                  let name = item["attributes"]["referenceName"].string else { continue }
            var rule = Rule(id: id, referenceName: name)
            rule.description = item["attributes"]["description"].string
            rule.type = item["attributes"]["type"].string
            rule.expression = item["attributes"]["expression"].string
            rule.weight = item["attributes"]["weight"].double
            result[name] = rule
        }
        return result
    }

    private func teams(ruleSetID: String) async -> [String: Team] {
        guard let response = try? await api.apple(
            "GET", "/v1/gameCenterMatchmakingRuleSets/\(ruleSetID)/teams?limit=200")
        else { return [:] }

        var result: [String: Team] = [:]
        for item in JSON(data: response.data)["data"].array {
            guard let id = item["id"].string,
                  let name = item["attributes"]["referenceName"].string else { continue }
            var team = Team(id: id, referenceName: name)
            team.minPlayers = item["attributes"]["minPlayers"].int
            team.maxPlayers = item["attributes"]["maxPlayers"].int
            result[name] = team
        }
        return result
    }

    // MARK: - The writes

    /// Creates the rule set, or changes the one the account already holds.
    ///
    /// Apple marks every attribute required on the create, so a manifest that
    /// names no player count would be refused. The validator says so before
    /// the apply starts; this sends what the manifest holds and nothing else.
    @discardableResult
    public func ensureRuleSet(_ wanted: Manifest.GameCenter.RuleSet,
                              existing: RuleSet?) async throws -> String {
        var attributes: [String: Any] = ["referenceName": wanted.name]
        if let players = wanted.players, players.count == 2 {
            attributes["minPlayers"] = players[0]
            attributes["maxPlayers"] = players[1]
        }
        if let version = wanted.ruleLanguageVersion {
            attributes["ruleLanguageVersion"] = version
        }

        if let existing {
            _ = try await api.apple(
                "PATCH", "/v1/gameCenterMatchmakingRuleSets/\(existing.id)", body: [
                    "data": [
                        "type": "gameCenterMatchmakingRuleSets",
                        "id": existing.id,
                        "attributes": attributes,
                    ],
                ])
            return existing.id
        }
        let response = try await api.apple("POST", "/v1/gameCenterMatchmakingRuleSets", body: [
            "data": ["type": "gameCenterMatchmakingRuleSets", "attributes": attributes],
        ])
        guard let id = JSON(data: response.data)["data"]["id"].string else {
            throw ConnectionError.invalidResponse
        }
        return id
    }

    /// One rule of one set.
    public func ensureRule(ruleSetID: String, _ wanted: Manifest.GameCenter.Rule,
                           existing: Rule?) async throws {
        var attributes: [String: Any] = ["referenceName": wanted.name]
        if let description = wanted.description { attributes["description"] = description }
        if let type = wanted.type { attributes["type"] = type }
        if let expression = wanted.expression { attributes["expression"] = expression }
        if let weight = wanted.weight { attributes["weight"] = weight }

        if let existing {
            _ = try await api.apple(
                "PATCH", "/v1/gameCenterMatchmakingRules/\(existing.id)", body: [
                    "data": [
                        "type": "gameCenterMatchmakingRules",
                        "id": existing.id,
                        "attributes": attributes,
                    ],
                ])
            return
        }
        _ = try await api.apple("POST", "/v1/gameCenterMatchmakingRules", body: [
            "data": [
                "type": "gameCenterMatchmakingRules",
                "attributes": attributes,
                "relationships": [
                    "ruleSet": [
                        "data": ["type": "gameCenterMatchmakingRuleSets", "id": ruleSetID],
                    ],
                ],
            ],
        ])
    }

    /// One team of one set.
    public func ensureTeam(ruleSetID: String, _ wanted: Manifest.GameCenter.Team,
                           existing: Team?) async throws {
        var attributes: [String: Any] = ["referenceName": wanted.name]
        if let players = wanted.players, players.count == 2 {
            attributes["minPlayers"] = players[0]
            attributes["maxPlayers"] = players[1]
        }

        if let existing {
            _ = try await api.apple(
                "PATCH", "/v1/gameCenterMatchmakingTeams/\(existing.id)", body: [
                    "data": [
                        "type": "gameCenterMatchmakingTeams",
                        "id": existing.id,
                        "attributes": attributes,
                    ],
                ])
            return
        }
        _ = try await api.apple("POST", "/v1/gameCenterMatchmakingTeams", body: [
            "data": [
                "type": "gameCenterMatchmakingTeams",
                "attributes": attributes,
                "relationships": [
                    "ruleSet": [
                        "data": ["type": "gameCenterMatchmakingRuleSets", "id": ruleSetID],
                    ],
                ],
            ],
        ])
    }

    /// Creates the queue, or changes the one the account already holds.
    ///
    /// The rule set is on the create request and Apple marks it required. The
    /// change request carries the attributes alone, so a queue that moves to a
    /// different rule set is a change App Store Connect makes and this app
    /// reports rather than performs.
    @discardableResult
    public func ensureQueue(_ wanted: Manifest.GameCenter.Queue, ruleSetID: String?,
                            existing: Queue?) async throws -> String {
        var attributes: [String: Any] = ["referenceName": wanted.name]
        if let bundleIDs = wanted.classicBundleIds {
            attributes["classicMatchmakingBundleIds"] = bundleIDs
        }

        if let existing {
            _ = try await api.apple(
                "PATCH", "/v1/gameCenterMatchmakingQueues/\(existing.id)", body: [
                    "data": [
                        "type": "gameCenterMatchmakingQueues",
                        "id": existing.id,
                        "attributes": attributes,
                    ],
                ])
            return existing.id
        }
        guard let ruleSetID else {
            throw ConnectionError.invalidResponse
        }
        let response = try await api.apple("POST", "/v1/gameCenterMatchmakingQueues", body: [
            "data": [
                "type": "gameCenterMatchmakingQueues",
                "attributes": attributes,
                "relationships": [
                    "ruleSet": [
                        "data": ["type": "gameCenterMatchmakingRuleSets", "id": ruleSetID],
                    ],
                ],
            ],
        ])
        guard let id = JSON(data: response.data)["data"]["id"].string else {
            throw ConnectionError.invalidResponse
        }
        return id
    }

    // MARK: - The deletes

    /// Never a plan step. Each one is the destructive button on its own card,
    /// where it can name what it is about to take with it: a queue in use
    /// stops matching players the moment it goes.
    public func deleteRuleSet(id: String) async throws {
        _ = try await api.apple("DELETE", "/v1/gameCenterMatchmakingRuleSets/\(id)")
    }

    public func deleteRule(id: String) async throws {
        _ = try await api.apple("DELETE", "/v1/gameCenterMatchmakingRules/\(id)")
    }

    public func deleteTeam(id: String) async throws {
        _ = try await api.apple("DELETE", "/v1/gameCenterMatchmakingTeams/\(id)")
    }

    public func deleteQueue(id: String) async throws {
        _ = try await api.apple("DELETE", "/v1/gameCenterMatchmakingQueues/\(id)")
    }
}
