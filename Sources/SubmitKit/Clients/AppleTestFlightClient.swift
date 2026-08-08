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

    // MARK: - The app-level TestFlight page

    /// The TestFlight page of the app, by locale.
    ///
    /// This is not `whatToTest`. That one belongs to a build and it changes
    /// every release. These four fields belong to the app, and a tester reads
    /// them on the TestFlight invitation.
    public func appLocalizations(appID: String) async throws
        -> [String: Manifest.Release.TestFlight.Localization] {
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appID)/betaAppLocalizations?limit=200").data)
        var result: [String: Manifest.Release.TestFlight.Localization] = [:]
        for item in payload["data"].array {
            let attributes = item["attributes"]
            guard let locale = attributes["locale"].string else { continue }
            result[locale] = Manifest.Release.TestFlight.Localization(
                description: attributes["description"].string,
                feedbackEmail: attributes["feedbackEmail"].string,
                marketingUrl: attributes["marketingUrl"].string,
                privacyPolicyUrl: attributes["privacyPolicyUrl"].string)
        }
        return result
    }

    /// Writes the TestFlight page. Apple takes a PATCH for a locale it holds
    /// and a POST for one it does not, the same rule as every other
    /// localization in this app.
    public func setAppLocalizations(
        appID: String,
        _ wanted: [String: Manifest.Release.TestFlight.Localization]) async throws {
        let held = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appID)/betaAppLocalizations?limit=200").data)
        var ids: [String: String] = [:]
        for item in held["data"].array {
            guard let locale = item["attributes"]["locale"].string,
                  let id = item["id"].string else { continue }
            ids[locale] = id
        }

        for (locale, text) in wanted.sorted(by: { $0.key < $1.key }) {
            var attributes: [String: Any] = [:]
            if let value = text.description { attributes["description"] = value }
            if let value = text.feedbackEmail { attributes["feedbackEmail"] = value }
            if let value = text.marketingUrl { attributes["marketingUrl"] = value }
            if let value = text.privacyPolicyUrl { attributes["privacyPolicyUrl"] = value }
            guard !attributes.isEmpty else { continue }

            if let id = ids[locale] {
                try await api.apple("PATCH", "/v1/betaAppLocalizations/\(id)", body: [
                    "data": ["type": "betaAppLocalizations", "id": id,
                             "attributes": attributes],
                ])
            } else {
                attributes["locale"] = locale
                try await api.apple("POST", "/v1/betaAppLocalizations", body: [
                    "data": [
                        "type": "betaAppLocalizations",
                        "attributes": attributes,
                        "relationships": ["app": ["data": ["type": "apps", "id": appID]]],
                    ],
                ])
            }
        }
    }

    // MARK: - The licence every external tester accepts

    /// The beta licence agreement, or nil when the read failed.
    ///
    /// Apple creates one per app and fills it with its own standard text, so
    /// this always exists on a real app. An empty string is a real answer and
    /// means the agreement carries no text.
    public func licenseAgreement(appID: String) async throws -> String? {
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appID)/betaLicenseAgreement").data)
        guard payload["data"]["id"].string != nil else { return nil }
        return payload["data"]["attributes"]["agreementText"].string ?? ""
    }

    /// **Every external tester accepts this before the first install.** A
    /// wrong or stale agreement is the kind that blocks external testing, and
    /// the plan shows the row before the run sends it.
    ///
    /// Apple keeps one agreement per app and creates it itself, so this only
    /// ever patches. An app whose agreement cannot be read is left alone
    /// rather than guessed at.
    public func setLicenseAgreement(appID: String, text: String) async throws {
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appID)/betaLicenseAgreement").data)
        guard let id = payload["data"]["id"].string else {
            throw ConnectionError.http(
                404, "Apple holds no beta licence agreement for this app yet.")
        }
        try await api.apple("PATCH", "/v1/betaLicenseAgreements/\(id)", body: [
            "data": ["type": "betaLicenseAgreements", "id": id,
                     "attributes": ["agreementText": text]],
        ])
    }

    /// The contact that Apple reaches about a beta review, and the demo
    /// account that a reviewer signs in with.
    ///
    /// Apple creates one detail per app with the build, so this only ever
    /// patches. The values come from `manifest.review` and the Keychain, the
    /// same two sources the App Store review detail already reads.
    public func setBetaReviewDetail(appID: String, review: Manifest.Review?,
                                    reviewer: ReviewerCredential?) async throws {
        guard let detail = try? await api.apple(
            "GET", "/v1/apps/\(appID)/betaAppReviewDetail"),
              let id = JSON(data: detail.data)["data"]["id"].string else { return }

        var attributes: [String: Any] = [:]
        if let value = review?.contactFirstName { attributes["contactFirstName"] = value }
        if let value = review?.contactLastName { attributes["contactLastName"] = value }
        if let value = review?.contactEmail { attributes["contactEmail"] = value }
        if let value = review?.contactPhone { attributes["contactPhone"] = value }
        if let value = review?.notes { attributes["notes"] = value }
        // An unanswered question is not the answer "no". This sent `false`
        // whenever the manifest said nothing, which overwrote whatever Apple
        // held and also defeated the empty check below.
        if let required = review?.demoAccountRequired {
            attributes["demoAccountRequired"] = required
        }
        if review?.demoAccountRequired == true, let reviewer {
            attributes["demoAccountName"] = reviewer.username
            attributes["demoAccountPassword"] = reviewer.password
        }
        guard !attributes.isEmpty else { return }

        try await api.apple("PATCH", "/v1/betaAppReviewDetails/\(id)", body: [
            "data": ["type": "betaAppReviewDetails", "id": id, "attributes": attributes],
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
