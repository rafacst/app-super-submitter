import Foundation

/// TestFlight. The App Store twin of the Google track testers.
///
/// Google keeps its testers on an edit, so `GoogleApply` writes them inside
/// the edit that wraps a run. Apple keeps them on their own resources, so they
/// live here and the runner calls them one step at a time.
///
/// Every write in this file reaches a real person. Adding an address sends an
/// invitation, and a beta review submission takes a place in a queue. Nothing
/// here runs before tab 7 shows the step.
public struct AppleTestFlightClient: Sendable {
    private let api: StoreAPI

    public init(api: StoreAPI) {
        self.api = api
    }

    // MARK: - The read

    public struct BetaGroup: Sendable, Equatable {
        public var id: String
        public var name: String
        public var testers: Set<String> = []
        public var publicLink: Bool?
        public var publicLinkLimit: Int?
        public var automaticBuilds: Bool?
        /// The build ids that Apple already gave this group.
        public var buildIds: Set<String> = []

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    /// Every external group of the app, by name, with its testers.
    ///
    /// The tester read costs one request per group. A group whose testers
    /// cannot be read keeps an empty set, and the plan then says that nobody
    /// verified the membership rather than inviting everybody again.
    public func groups(appID: String) async throws -> [String: BetaGroup] {
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appID)/betaGroups?limit=200").data)
        var result: [String: BetaGroup] = [:]

        for item in payload["data"].array {
            guard var group = Self.parseGroup(item) else { continue }
            if let response = try? await api.apple(
                "GET", "/v1/betaGroups/\(group.id)/betaTesters?limit=200") {
                group.testers = Set(JSON(data: response.data)["data"].array
                    .compactMap { $0["attributes"]["email"].string?.lowercased() })
            }
            if let response = try? await api.apple(
                "GET", "/v1/betaGroups/\(group.id)/relationships/builds?limit=200") {
                group.buildIds = Set(JSON(data: response.data)["data"].array
                    .compactMap { $0["id"].string })
            }
            result[group.name] = group
        }
        return result
    }

    /// The "What to Test" notes that a build already carries, by locale.
    public func whatToTest(buildID: String) async throws -> [String: String] {
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/builds/\(buildID)/betaBuildLocalizations?limit=200").data)
        var result: [String: String] = [:]
        for item in payload["data"].array {
            guard let locale = item["attributes"]["locale"].string else { continue }
            result[locale] = item["attributes"]["whatsNew"].string ?? ""
        }
        return result
    }

    /// Whether Apple already holds a beta review submission for the build, and
    /// whether the build asks the testers to update by itself.
    public func buildBetaState(buildID: String) async throws
        -> (submitted: Bool, autoNotify: Bool?) {
        var submitted = false
        if let response = try? await api.apple(
            "GET", "/v1/builds/\(buildID)/betaAppReviewSubmission") {
            submitted = JSON(data: response.data)["data"]["id"].string != nil
        }
        var autoNotify: Bool?
        if let response = try? await api.apple(
            "GET", "/v1/builds/\(buildID)/buildBetaDetail") {
            autoNotify = JSON(data: response.data)["data"]["attributes"]["autoNotifyEnabled"].bool
        }
        return (submitted, autoNotify)
    }

    // MARK: - The writes

    /// Creates the group, or returns the one Apple already holds.
    @discardableResult
    public func ensureGroup(appID: String,
                            _ group: Manifest.Release.TestFlight.Group,
                            existing: BetaGroup?) async throws -> String {
        var attributes: [String: Any] = ["name": group.name]
        if let link = group.publicLink { attributes["publicLinkEnabled"] = link }
        if let limit = group.publicLinkLimit {
            attributes["publicLinkLimit"] = limit
            attributes["publicLinkLimitEnabled"] = true
        }
        if let automatic = group.automaticBuilds {
            attributes["hasAccessToAllBuilds"] = automatic
        }
        if let existing {
            try await api.apple("PATCH", "/v1/betaGroups/\(existing.id)", body: [
                "data": ["type": "betaGroups", "id": existing.id, "attributes": attributes],
            ])
            return existing.id
        }
        let created = JSON(data: try await api.apple("POST", "/v1/betaGroups", body: [
            "data": [
                "type": "betaGroups",
                "attributes": attributes,
                "relationships": ["app": ["data": ["type": "apps", "id": appID]]],
            ],
        ]).data)
        guard let id = created["data"]["id"].string else { throw ConnectionError.invalidResponse }
        return id
    }

    /// Invites the addresses that the group does not already hold.
    ///
    /// Apple emails every new address, so this sends only the difference. It
    /// removes nobody: a tester who left the manifest keeps their build, and
    /// the developer removes them in App Store Connect on purpose.
    public func addTesters(groupID: String, emails: [String],
                           existing: Set<String>) async throws -> Int {
        let wanted = emails.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let missing = wanted.filter { !existing.contains($0.lowercased()) }
        guard !missing.isEmpty else { return 0 }
        // Apple takes one create per address, and the create carries the
        // group, so a new tester and a known one both land in one call each.
        for email in missing {
            let body: [String: Any] = [
                "data": [
                    "type": "betaTesters",
                    "attributes": ["email": email],
                    "relationships": [
                        "betaGroups": ["data": [["type": "betaGroups", "id": groupID]]],
                    ],
                ],
            ]
            do {
                try await api.apple("POST", "/v1/betaTesters", body: body)
            } catch ConnectionError.http(let status, _) where status == 409 {
                // Apple already knows the address. Attaching it to the group
                // is the remaining half of the work.
                try await api.apple(
                    "POST", "/v1/betaGroups/\(groupID)/relationships/betaTesters",
                    body: ["data": [["type": "betaTesters", "id": email]]])
            }
        }
        return missing.count
    }

    /// Gives one build to a group. Apple sends the build to every tester in it.
    public func addBuild(groupID: String, buildID: String) async throws {
        try await api.apple("POST", "/v1/betaGroups/\(groupID)/relationships/builds",
                            body: ["data": [["type": "builds", "id": buildID]]])
    }

    /// Writes the "What to Test" note of one build, per locale.
    public func setWhatToTest(buildID: String, notes: [String: String],
                              existing: [String: String]) async throws {
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/builds/\(buildID)/betaBuildLocalizations?limit=200").data)
        var idOfLocale: [String: String] = [:]
        for item in payload["data"].array {
            guard let locale = item["attributes"]["locale"].string,
                  let id = item["id"].string else { continue }
            idOfLocale[locale] = id
        }
        for (locale, text) in notes.sorted(by: { $0.key < $1.key })
        where existing[locale] != text {
            if let id = idOfLocale[locale] {
                try await api.apple("PATCH", "/v1/betaBuildLocalizations/\(id)", body: [
                    "data": ["type": "betaBuildLocalizations", "id": id,
                             "attributes": ["whatsNew": text]],
                ])
            } else {
                try await api.apple("POST", "/v1/betaBuildLocalizations", body: [
                    "data": [
                        "type": "betaBuildLocalizations",
                        "attributes": ["locale": locale, "whatsNew": text],
                        "relationships": ["build": ["data": ["type": "builds", "id": buildID]]],
                    ],
                ])
            }
        }
    }

    public func setAutoNotify(buildID: String, _ enabled: Bool) async throws {
        let detail = JSON(data: try await api.apple(
            "GET", "/v1/builds/\(buildID)/buildBetaDetail").data)
        guard let id = detail["data"]["id"].string else { return }
        try await api.apple("PATCH", "/v1/buildBetaDetails/\(id)", body: [
            "data": ["type": "buildBetaDetails", "id": id,
                     "attributes": ["autoNotifyEnabled": enabled]],
        ])
    }

    /// Sends the build to the beta review that an external group needs.
    ///
    /// This takes a place in a review queue. No call takes it back, so the
    /// runner reaches it only through a plan step the developer read.
    public func submitForBetaReview(buildID: String) async throws {
        try await api.apple("POST", "/v1/betaAppReviewSubmissions", body: [
            "data": [
                "type": "betaAppReviewSubmissions",
                "relationships": ["build": ["data": ["type": "builds", "id": buildID]]],
            ],
        ])
    }

    // MARK: - The parser

    static func parseGroup(_ item: JSON) -> BetaGroup? {
        let attributes = item["attributes"]
        guard let id = item["id"].string, let name = attributes["name"].string else { return nil }
        var group = BetaGroup(id: id, name: name)
        group.publicLink = attributes["publicLinkEnabled"].bool
        group.publicLinkLimit = attributes["publicLinkLimit"].int
        group.automaticBuilds = attributes["hasAccessToAllBuilds"].bool
        return group
    }
}
