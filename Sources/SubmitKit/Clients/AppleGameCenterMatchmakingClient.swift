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

    // MARK: - The metrics

    /// The ten metric series Apple publishes for matchmaking.
    ///
    /// Every one is a `GET` and nothing here is stored. The app draws the
    /// window the store answers with and keeps none of it, which is the rule
    /// every metric in this app follows.
    public enum Metric: String, Sendable, CaseIterable, Identifiable {
        case classicRequests, ruleBasedRequests
        case queueRequests, queueSizes, sessions
        case experimentQueueRequests, experimentQueueSizes
        case booleanRuleResults, numberRuleResults, ruleErrors

        public var id: String { rawValue }

        /// What the series answers, in the words the panel shows.
        public var label: String {
            switch self {
            case .classicRequests: "Requests through invite matchmaking"
            case .ruleBasedRequests: "Requests through a rule set"
            case .queueRequests: "Requests into the queue"
            case .queueSizes: "Players waiting"
            case .sessions: "Sessions the queue formed"
            case .experimentQueueRequests: "Requests into the queue, experiment"
            case .experimentQueueSizes: "Players waiting, experiment"
            case .booleanRuleResults: "How often the rule passed"
            case .numberRuleResults: "What the rule scored"
            case .ruleErrors: "Rules that failed to run"
            }
        }

        /// Which resource the id in the path belongs to. The panel asks for
        /// that one and offers no metric it has no id for.
        public enum Owner: Sendable { case detail, queue, rule }

        public var owner: Owner {
            switch self {
            case .classicRequests, .ruleBasedRequests: .detail
            case .queueRequests, .queueSizes, .sessions,
                 .experimentQueueRequests, .experimentQueueSizes: .queue
            case .booleanRuleResults, .numberRuleResults, .ruleErrors: .rule
            }
        }

        func path(id: String) -> String {
            switch self {
            case .classicRequests:
                "/v1/gameCenterDetails/\(id)/metrics/classicMatchmakingRequests"
            case .ruleBasedRequests:
                "/v1/gameCenterDetails/\(id)/metrics/ruleBasedMatchmakingRequests"
            case .queueRequests:
                "/v1/gameCenterMatchmakingQueues/\(id)/metrics/matchmakingRequests"
            case .queueSizes:
                "/v1/gameCenterMatchmakingQueues/\(id)/metrics/matchmakingQueueSizes"
            case .sessions:
                "/v1/gameCenterMatchmakingQueues/\(id)/metrics/matchmakingSessions"
            case .experimentQueueRequests:
                "/v1/gameCenterMatchmakingQueues/\(id)/metrics/experimentMatchmakingRequests"
            case .experimentQueueSizes:
                "/v1/gameCenterMatchmakingQueues/\(id)/metrics/experimentMatchmakingQueueSizes"
            case .booleanRuleResults:
                "/v1/gameCenterMatchmakingRules/\(id)/metrics/matchmakingBooleanRuleResults"
            case .numberRuleResults:
                "/v1/gameCenterMatchmakingRules/\(id)/metrics/matchmakingNumberRuleResults"
            case .ruleErrors:
                "/v1/gameCenterMatchmakingRules/\(id)/metrics/matchmakingRuleErrors"
            }
        }
    }

    /// One metric series, as the table the Reports panel already draws.
    ///
    /// Apple answers a data point per window with a bag of named values, and
    /// the bag differs per metric. So the columns come from the answer rather
    /// than from a list in this file: a metric Apple adds a value to draws that
    /// value the day it appears, and none of the ten needs its own reader.
    /// - Parameter granularity: the width of one data point. `PT15M` is the
    ///   only value Apple's reference shows, so it is the default and the app
    ///   offers no chooser: a granularity Apple does not take is a 400 with
    ///   nothing on the screen to explain it.
    public func metric(_ metric: Metric, id: String,
                       granularity: String = "PT15M") async throws -> ReportTable {
        let payload = JSON(data: try await api.apple(
            "GET", metric.path(id: id) + "?granularity=\(granularity)&limit=200").data)

        var points: [(start: String, dimensions: [String: String],
                     values: [String: String])] = []
        var dimensionNames: [String] = []
        var valueNames: [String] = []
        for series in payload["data"].array {
            var dimensions: [String: String] = [:]
            for key in series["dimensions"].keys {
                let value = series["dimensions"][key]["data"]
                let text = value.string
                    ?? value.bool.map(String.init)
                    ?? value.int.map(String.init)
                    ?? value.double.map { String(format: "%g", $0) }
                if let text {
                    dimensions[key] = text
                    if !dimensionNames.contains(key) { dimensionNames.append(key) }
                }
            }
            for point in series["dataPoints"].array {
                let start = point["start"].string ?? ""
                var values: [String: String] = [:]
                for key in point["values"].keys {
                    let value = point["values"][key]
                    values[key] = value.string
                        ?? value.int.map(String.init)
                        ?? value.double.map { String(format: "%g", $0) }
                        ?? ""
                    if !valueNames.contains(key) { valueNames.append(key) }
                }
                points.append((start, dimensions, values))
            }
        }
        guard !points.isEmpty else { return ReportTable() }

        dimensionNames.sort()
        valueNames.sort()
        // Oldest first, so the chart reads left to right. Apple answers newest
        // first.
        points.sort { $0.start < $1.start }
        return ReportTable(
            columns: ["Date"] + dimensionNames + valueNames,
            rows: points.map { point in
                [point.start]
                    + dimensionNames.map { point.dimensions[$0] ?? "" }
                    + valueNames.map { point.values[$0] ?? "" }
            })
    }

    // MARK: - The rule set test

    /// One synthetic request in a rule set test.
    public struct TestRequest: Sendable, Equatable, Identifiable {
        public var id: String
        public var name: String
        public var playerCount: Int
        public var minPlayers: Int?
        public var maxPlayers: Int?
        public var secondsInQueue: Int?

        public init(id: String, name: String, playerCount: Int, minPlayers: Int? = nil,
                    maxPlayers: Int? = nil, secondsInQueue: Int? = nil) {
            self.id = id
            self.name = name
            self.playerCount = playerCount
            self.minPlayers = minPlayers
            self.maxPlayers = maxPlayers
            self.secondsInQueue = secondsInQueue
        }
    }

    /// One match the test produced: the requests it put together, by name.
    public struct TestMatch: Sendable, Equatable, Identifiable {
        public var id: Int
        public var requestNames: [String]

        public init(id: Int, requestNames: [String]) {
            self.id = id
            self.requestNames = requestNames
        }
    }

    /// Runs a rule set against synthetic players and answers the matches it
    /// made.
    ///
    /// **It changes nothing in the account.** Apple evaluates the rules and
    /// returns the result, so there is nothing to confirm and nothing to undo.
    /// The requests are inline creates: they exist for the length of this one
    /// call and Apple stores none of them.
    public func test(ruleSetID: String, requests: [TestRequest]) async throws -> [TestMatch] {
        let included = requests.map { request -> [String: Any] in
            var attributes: [String: Any] = [
                "requestName": request.name,
                "playerCount": request.playerCount,
            ]
            if let minPlayers = request.minPlayers { attributes["minPlayers"] = minPlayers }
            if let maxPlayers = request.maxPlayers { attributes["maxPlayers"] = maxPlayers }
            if let seconds = request.secondsInQueue { attributes["secondsInQueue"] = seconds }
            return [
                "type": "gameCenterMatchmakingTestRequests",
                "id": request.id,
                "attributes": attributes,
            ]
        }

        let response = try await api.apple("POST", "/v1/gameCenterMatchmakingRuleSetTests", body: [
            "data": [
                "type": "gameCenterMatchmakingRuleSetTests",
                "relationships": [
                    "matchmakingRuleSet": [
                        "data": ["type": "gameCenterMatchmakingRuleSets", "id": ruleSetID],
                    ],
                    "matchmakingRequests": [
                        "data": requests.map {
                            ["type": "gameCenterMatchmakingTestRequests", "id": $0.id]
                        },
                    ],
                ],
            ],
            "included": included,
        ])

        // `matchmakingResults` is an array of arrays: one inner array per
        // match, holding the requests that were put together.
        let results = JSON(data: response.data)["data"]["attributes"]["matchmakingResults"]
        return results.array.enumerated().map { index, match in
            TestMatch(id: index,
                      requestNames: match.array.compactMap { $0["requestName"].string })
        }
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
