import Foundation

/// Why the App Store would not take a submission.
public enum ReleaseError: Error, LocalizedError {
    /// Apple refused the submit and named no resource. `blockers` is what the
    /// app found by asking, one line per item.
    case submissionBlocked(reason: String, blockers: [String])

    public var errorDescription: String? {
        switch self {
        case .submissionBlocked(let reason, let blockers):
            """
            \(reason)

            \(blockers.count == 1 ? "This is what the submission is waiting on:"
                : "These are what the submission is waiting on:")
            \(blockers.map { "· \($0)" }.joined(separator: "\n"))

            Fix or remove the item above in App Store Connect, then send again. \
            Cancel the submission first if the same item keeps coming back, \
            because an open submission keeps the items it already holds.
            """
        }
    }
}

/// The two irreversible calls. Spec section 7.9.
///
/// Each method releases **one** store. There is no method here that releases
/// both, and nothing chains the two, because a failure between two
/// irreversible calls leaves one store in review and one store not.
public struct ReleaseClient: Sendable {
    private let api: StoreAPI
    /// The paywall boundary. Every method below that changes a store asks it
    /// first, immediately before the call it guards, so a screen that was
    /// opened while entitled cannot fire after the grant ends.
    private let access: any AccessGate

    public init(api: StoreAPI, access: any AccessGate) {
        self.api = api
        self.access = access
    }

    /// Step 4 is the point of no return. Steps 1 to 3 are reversible.
    public func releaseApple(appID: String, platform: String,
                             versionID: String) async throws -> String {
        try await access.authorize(.storeRelease)
        let drafts = try? await api.apple(
            "GET", "/v1/reviewSubmissions?filter%5Bapp%5D=\(appID)&limit=20")
        if let submissionID = drafts.map({ JSON(data: $0.data) })?["data"].array.first(where: {
            $0["attributes"]["state"].string == "READY_FOR_REVIEW"
                && $0["attributes"]["platform"].string == platform
        })?["id"].string {
            // A submission left open by an earlier attempt still holds that
            // attempt's items, so a refusal here is about one of them.
            try await submit(submissionID: submissionID, refused: [])
            return submissionID
        }
        let submission = JSON(data: try await api.apple("POST", "/v1/reviewSubmissions", body: [
            "data": [
                "type": "reviewSubmissions",
                "attributes": ["platform": platform],
                "relationships": ["app": ["data": ["type": "apps", "id": appID]]],
            ],
        ]).data)
        guard let submissionID = submission["data"]["id"].string else {
            throw ConnectionError.invalidResponse
        }

        try await api.apple("POST", "/v1/reviewSubmissionItems", body: [
            "data": [
                "type": "reviewSubmissionItems",
                "relationships": [
                    "reviewSubmission": ["data": ["type": "reviewSubmissions",
                                                  "id": submissionID]],
                    "appStoreVersion": ["data": ["type": "appStoreVersions", "id": versionID]],
                ],
            ],
        ])

        // Every add below is optional and every refusal is kept. Apple names
        // the resource when it turns an add away and names nothing at all when
        // it refuses the submit, so this list is the evidence.
        var refused: [String] = []

        // The purchases join the same submission, so one Apple review covers
        // the version and the purchases together.
        let purchases = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appID)/inAppPurchasesV2?limit=200").data)
        for purchase in purchases["data"].array {
            guard let purchaseID = purchase["id"].string,
                  let versionID = await editableVersionID(
                    path: "/v2/inAppPurchases/\(purchaseID)/versions") else { continue }
            let name = purchase["attributes"]["productId"].string ?? purchaseID
            if let line = await addItem(
                to: submissionID, relationship: "inAppPurchaseVersion",
                type: "inAppPurchaseVersions", id: versionID,
                label: "The in-app purchase \(name)") { refused.append(line) }
        }

        refused += await addMarketingItems(appID: appID, versionID: versionID,
                                           submissionID: submissionID)
        refused += await addSubscriptionItems(appID: appID, submissionID: submissionID)

        try await submit(submissionID: submissionID, refused: refused)
        return submissionID
    }

    /// The point of no return, and the one place that turns Apple's "check
    /// associated errors" into the errors themselves.
    private func submit(submissionID: String, refused: [String]) async throws {
        do {
            try await api.apple("PATCH", "/v1/reviewSubmissions/\(submissionID)", body: [
                "data": ["type": "reviewSubmissions", "id": submissionID,
                         "attributes": ["submitted": true]],
            ])
        } catch {
            let blockers = await submissionBlockers(submissionID: submissionID,
                                                    refused: refused)
            guard !blockers.isEmpty else { throw error }
            throw ReleaseError.submissionBlocked(reason: error.localizedDescription,
                                                 blockers: blockers)
        }
    }

    /// One item on the open review submission, and what Apple said if it
    /// refused the item.
    ///
    /// A single item that Apple refuses is never a reason to abandon the
    /// version submission. Step 4 still holds the whole decision, and a
    /// rejected item leaves the version untouched.
    ///
    /// The refusal is returned rather than dropped, because this is where Apple
    /// names the resource. The submit that follows answers "This resource
    /// cannot be reviewed, please check associated errors to see why" and names
    /// nothing at all, so a swallowed line here was the whole of the evidence.
    ///
    /// `// ponytail: one add, six callers. Six copies of the same body would
    /// // drift on the seventh resource Apple adds.`
    private func addItem(to submissionID: String, relationship: String,
                         type: String, id: String, label: String) async -> String? {
        do {
            _ = try await api.apple("POST", "/v1/reviewSubmissionItems", body: [
                "data": [
                    "type": "reviewSubmissionItems",
                    "relationships": [
                        "reviewSubmission": ["data": ["type": "reviewSubmissions",
                                                      "id": submissionID]],
                        relationship: ["data": ["type": type, "id": id]],
                    ],
                ],
            ])
            return nil
        } catch {
            return "\(label): \(error.localizedDescription)"
        }
    }

    /// What the submission holds and where each item stands, after Apple has
    /// refused to take it.
    ///
    /// Apple's own sentence for a refused submit names no resource, so this
    /// reads the items back and names them. `refused` carries the adds Apple
    /// turned away, which is the better evidence of the two, because this app
    /// knew the human name of the thing it was attaching.
    private func submissionBlockers(submissionID: String,
                                    refused: [String]) async -> [String] {
        var lines = refused
        guard let response = try? await api.apple(
            "GET", "/v1/reviewSubmissions/\(submissionID)/items?limit=200")
        else { return lines }
        for item in JSON(data: response.data)["data"].array {
            let state = item["attributes"]["state"].string ?? ""
            guard state != "READY_FOR_REVIEW", state != "ACCEPTED",
                  state != "APPROVED" else { continue }
            let named = Self.itemName(item)
            lines.append("\(named) is \(Self.stateText(state)).")
        }
        return lines
    }

    /// Which resource one item covers. Apple hangs thirteen relationships off
    /// a submission item and fills exactly one of them.
    static func itemName(_ item: JSON) -> String {
        let names: [(key: String, noun: String)] = [
            ("appStoreVersion", "The App Store version"),
            ("appCustomProductPageVersion", "A custom product page"),
            ("appStoreVersionExperimentV2", "A product page test"),
            ("appStoreVersionExperiment", "A product page test"),
            ("appEvent", "An in-app event"),
            ("inAppPurchaseVersion", "An in-app purchase"),
            ("subscriptionVersion", "A subscription"),
            ("subscriptionGroupVersion", "A subscription group"),
            ("backgroundAssetVersion", "A background asset"),
            ("gameCenterAchievementVersion", "A Game Center achievement"),
            ("gameCenterLeaderboardVersion", "A Game Center leaderboard"),
            ("gameCenterLeaderboardSetVersion", "A Game Center leaderboard set"),
            ("gameCenterActivityVersion", "A Game Center activity"),
            ("gameCenterChallengeVersion", "A Game Center challenge"),
        ]
        for entry in names {
            guard let id = item["relationships"][entry.key]["data"]["id"].string
            else { continue }
            return "\(entry.noun) (\(id))"
        }
        return "An item of this submission (\(item["id"].string ?? "unknown"))"
    }

    /// `NOT_READY_FOR_REVIEW` as "not ready for review".
    static func stateText(_ state: String) -> String {
        state.isEmpty ? "in a state Apple did not name"
            : state.replacingOccurrences(of: "_", with: " ").lowercased()
    }

    private func editableVersionID(path: String) async -> String? {
        guard let response = try? await api.apple(
            "GET", path, query: [URLQueryItem(name: "limit", value: "200")]) else { return nil }
        return AppleVersionSelection.editable(
            JSON(data: response.data)["data"].array)?["id"].string
    }

    /// The app events, the custom product pages, and the experiments.
    ///
    /// An apply creates all three as drafts. Without this, each one stays a
    /// draft after the release, and the developer finds it in App Store
    /// Connect weeks later with nothing to explain it.
    ///
    /// Apple accepts an item in one state only, so each read filters before it
    /// sends. A page or an event in any other state already reached a review.
    private func addMarketingItems(appID: String, versionID: String,
                                   submissionID: String) async -> [String] {
        var refused: [String] = []
        if let events = try? await api.apple(
            "GET", "/v1/apps/\(appID)/appEvents?limit=200") {
            for event in JSON(data: events.data)["data"].array
            where event["attributes"]["eventState"].string == "READY_FOR_REVIEW" {
                guard let id = event["id"].string else { continue }
                let name = event["attributes"]["referenceName"].string ?? id
                if let line = await addItem(
                    to: submissionID, relationship: "appEvent", type: "appEvents", id: id,
                    label: "The in-app event \(name)") { refused.append(line) }
            }
        }

        // A custom product page submits its newest version, never the page. The
        // page carries the name, and the name is what the developer has to go
        // and look at, so it is read here and not from the version.
        if let pages = try? await api.apple(
            "GET", "/v1/apps/\(appID)/appCustomProductPages?limit=200") {
            for page in JSON(data: pages.data)["data"].array {
                guard let pageID = page["id"].string,
                      let versions = try? await api.apple(
                        "GET", "/v1/appCustomProductPages/\(pageID)"
                            + "/appCustomProductPageVersions?limit=200") else { continue }
                let name = page["attributes"]["name"].string ?? pageID
                for version in JSON(data: versions.data)["data"].array
                where version["attributes"]["state"].string == "PREPARE_FOR_SUBMISSION" {
                    guard let id = version["id"].string else { continue }
                    if let line = await addItem(
                        to: submissionID, relationship: "appCustomProductPageVersion",
                        type: "appCustomProductPageVersions", id: id,
                        label: "The custom product page \(name)") { refused.append(line) }
                }
            }
        }

        if let experiments = try? await api.apple(
            "GET", "/v1/appStoreVersions/\(versionID)"
                + "/appStoreVersionExperimentsV2?limit=200") {
            for experiment in JSON(data: experiments.data)["data"].array
            where experiment["attributes"]["state"].string == "PREPARE_FOR_SUBMISSION" {
                guard let id = experiment["id"].string else { continue }
                let name = experiment["attributes"]["name"].string ?? id
                if let line = await addItem(
                    to: submissionID, relationship: "appStoreVersionExperimentV2",
                    type: "appStoreVersionExperiments", id: id,
                    label: "The product page test \(name)") { refused.append(line) }
            }
        }
        return refused
    }

    /// Add editable subscription and group versions to this review submission.
    private func addSubscriptionItems(appID: String, submissionID: String) async -> [String] {
        guard let groups = try? await api.apple(
            "GET", "/v1/apps/\(appID)/subscriptionGroups?include=subscriptions&limit=200")
        else { return [] }
        let payload = JSON(data: groups.data)
        var refused: [String] = []

        for group in payload["data"].array {
            guard let id = group["id"].string,
                  let versionID = await editableVersionID(
                    path: "/v1/subscriptionGroups/\(id)/versions") else { continue }
            let name = group["attributes"]["referenceName"].string ?? id
            if let line = await addItem(
                to: submissionID, relationship: "subscriptionGroupVersion",
                type: "subscriptionGroupVersions", id: versionID,
                label: "The subscription group \(name)") { refused.append(line) }
        }

        for subscription in payload["included"].array
        where subscription["type"].string == "subscriptions" {
            guard let id = subscription["id"].string,
                  let versionID = await editableVersionID(
                    path: "/v1/subscriptions/\(id)/versions") else { continue }
            let name = subscription["attributes"]["productId"].string ?? id
            if let line = await addItem(
                to: submissionID, relationship: "subscriptionVersion",
                type: "subscriptionVersions", id: versionID,
                label: "The subscription \(name)") { refused.append(line) }
        }
        return refused
    }

    /// The open submission that a cancel can still reach, if one exists.
    ///
    /// Apple takes the cancel before a reviewer opens the submission and
    /// refuses it after. The two states below are the whole window, so a caller
    /// that gets `nil` has nothing to cancel and needs no error.
    ///
    /// The id of the submission this app sent lives for one session only. A
    /// developer who quits and reopens still owns the submission, so the button
    /// reads the id back rather than trusting memory.
    public func cancellableAppleSubmission(appID: String) async throws -> String? {
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/reviewSubmissions?filter%5Bapp%5D=\(appID)&limit=20").data)
        return payload["data"].array.first { item in
            ["READY_FOR_REVIEW", "WAITING_FOR_REVIEW"]
                .contains(item["attributes"]["state"].string ?? "")
        }?["id"].string
    }

    /// The recovery, and its limit: this works only before the review starts.
    public func cancelAppleSubmission(id: String) async throws {
        try await access.authorize(.storeRelease)
        try await api.apple("PATCH", "/v1/reviewSubmissions/\(id)", body: [
            "data": ["type": "reviewSubmissions", "id": id, "attributes": ["canceled": true]],
        ])
    }

    /// Releases a version Apple has already approved and is holding for the
    /// developer. App Store Connect accepts this only in
    /// `PENDING_DEVELOPER_RELEASE`, and the request cannot be undone.
    public func releaseApprovedAppleVersion(versionID: String) async throws -> String {
        try await access.authorize(.storeRelease)
        let response = JSON(data: try await api.apple(
            "POST", "/v1/appStoreVersionReleaseRequests", body: [
                "data": [
                    "type": "appStoreVersionReleaseRequests",
                    "relationships": ["appStoreVersion": [
                        "data": ["type": "appStoreVersions", "id": versionID]]],
                ],
            ]).data)
        return response["data"]["id"].string ?? versionID
    }

    /// Step 3 is the point of no return.
    ///
    /// Google treats `versionCodes` as the complete list, not as an addition.
    /// A missing code drops that build from the track, so the app reads the
    /// track first and carries the full list back.
    public func releaseGoogle(packageName: String, track: String, status: String,
                              userFraction: Double?, versionName: String?) async throws -> String {
        try await access.authorize(.storeRelease)
        let base = "/androidpublisher/v3/applications/\(StateReader.escape(packageName))"
        let edit = JSON(data: try await api.google("POST", "\(base)/edits", body: [:]).data)
        guard let editID = edit["id"].string else { throw ConnectionError.invalidResponse }
        let editBase = "\(base)/edits/\(editID)"

        do {
            let current = JSON(data: try await api.google("GET", "\(editBase)/tracks/\(track)").data)
            let release = current["releases"].array.first
            let codes = release?["versionCodes"].array.compactMap(\.int) ?? []
            guard !codes.isEmpty else {
                throw ConnectionError.http(409, "The \(track) track holds no draft release.")
            }

            var body: [String: Any] = [
                "status": status,
                "versionCodes": codes.map(String.init),
            ]
            if status == "inProgress", let userFraction {
                body["userFraction"] = userFraction
            }
            if let name = versionName { body["name"] = name }
            if let notes = release?["releaseNotes"].array, !notes.isEmpty {
                body["releaseNotes"] = notes.map { note in
                    ["language": note["language"].string ?? "en-US",
                     "text": note["text"].string ?? ""]
                }
            }
            try await api.google("PATCH", "\(editBase)/tracks/\(track)",
                                 body: ["track": track, "releases": [body]])

            // No `changesNotSentForReview` this time. That is the difference
            // between an apply and a release.
            try await api.google("POST", "\(editBase):commit", body: [:])
            return editID
        } catch {
            _ = try? await api.google("DELETE", editBase)
            throw error
        }
    }

    /// The Google recovery, and its limit: a staged rollout only.
    public func haltGoogleRollout(packageName: String, track: String) async throws {
        try await access.authorize(.storeRelease)
        let base = "/androidpublisher/v3/applications/\(StateReader.escape(packageName))"
        let edit = JSON(data: try await api.google("POST", "\(base)/edits", body: [:]).data)
        guard let editID = edit["id"].string else { throw ConnectionError.invalidResponse }
        let editBase = "\(base)/edits/\(editID)"
        do {
            let current = JSON(data: try await api.google("GET", "\(editBase)/tracks/\(track)").data)
            let codes = current["releases"][0]["versionCodes"].array.compactMap(\.int)
            try await api.google("PATCH", "\(editBase)/tracks/\(track)", body: [
                "track": track,
                "releases": [["status": "halted", "versionCodes": codes.map(String.init)]],
            ])
            try await api.google("POST", "\(editBase):commit", body: [:])
        } catch {
            _ = try? await api.google("DELETE", editBase)
            throw error
        }
    }
}
