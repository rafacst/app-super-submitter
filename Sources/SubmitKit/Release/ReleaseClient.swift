import Foundation

/// The two irreversible calls. Spec section 7.9.
///
/// Each method releases **one** store. There is no method here that releases
/// both, and nothing chains the two, because a failure between two
/// irreversible calls leaves one store in review and one store not.
public struct ReleaseClient: Sendable {
    private let api: StoreAPI

    public init(api: StoreAPI) {
        self.api = api
    }

    /// Step 4 is the point of no return. Steps 1 to 3 are reversible.
    public func releaseApple(appID: String, platform: String,
                             versionID: String) async throws -> String {
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

        // The purchases join the same submission, so one Apple review covers
        // the version and the purchases together.
        let purchases = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appID)/inAppPurchasesV2?limit=200").data)
        for purchase in purchases["data"].array {
            guard let versionId = purchase["relationships"]["inAppPurchaseVersion"]["data"]["id"]
                .string else { continue }
            await addItem(to: submissionID, relationship: "inAppPurchaseV2",
                          type: "inAppPurchases", id: versionId)
        }

        await addMarketingItems(appID: appID, versionID: versionID,
                                submissionID: submissionID)
        await submitSubscriptions(appID: appID)

        try await api.apple("PATCH", "/v1/reviewSubmissions/\(submissionID)", body: [
            "data": ["type": "reviewSubmissions", "id": submissionID,
                     "attributes": ["submitted": true]],
        ])
        return submissionID
    }

    /// One item on the open review submission.
    ///
    /// A single item that Apple refuses is never a reason to abandon the
    /// version submission. Step 4 still holds the whole decision, and a
    /// rejected item leaves the version untouched.
    ///
    /// `// ponytail: one add, six callers. Six copies of the same body would
    /// // drift on the seventh resource Apple adds.`
    private func addItem(to submissionID: String, relationship: String,
                         type: String, id: String) async {
        _ = try? await api.apple("POST", "/v1/reviewSubmissionItems", body: [
            "data": [
                "type": "reviewSubmissionItems",
                "relationships": [
                    "reviewSubmission": ["data": ["type": "reviewSubmissions",
                                                  "id": submissionID]],
                    relationship: ["data": ["type": type, "id": id]],
                ],
            ],
        ])
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
                                   submissionID: String) async {
        if let events = try? await api.apple(
            "GET", "/v1/apps/\(appID)/appEvents?limit=200") {
            for event in JSON(data: events.data)["data"].array
            where event["attributes"]["eventState"].string == "READY_FOR_REVIEW" {
                guard let id = event["id"].string else { continue }
                await addItem(to: submissionID, relationship: "appEvent",
                              type: "appEvents", id: id)
            }
        }

        // A custom product page submits its newest version, never the page.
        if let pages = try? await api.apple(
            "GET", "/v1/apps/\(appID)/appCustomProductPages?limit=200") {
            for page in JSON(data: pages.data)["data"].array {
                guard let pageID = page["id"].string,
                      let versions = try? await api.apple(
                        "GET", "/v1/appCustomProductPages/\(pageID)"
                            + "/appCustomProductPageVersions?limit=200") else { continue }
                for version in JSON(data: versions.data)["data"].array
                where version["attributes"]["state"].string == "PREPARE_FOR_SUBMISSION" {
                    guard let id = version["id"].string else { continue }
                    await addItem(to: submissionID,
                                  relationship: "appCustomProductPageVersion",
                                  type: "appCustomProductPageVersions", id: id)
                }
            }
        }

        if let experiments = try? await api.apple(
            "GET", "/v1/appStoreVersions/\(versionID)"
                + "/appStoreVersionExperimentsV2?limit=200") {
            for experiment in JSON(data: experiments.data)["data"].array
            where experiment["attributes"]["state"].string == "PREPARE_FOR_SUBMISSION" {
                guard let id = experiment["id"].string else { continue }
                await addItem(to: submissionID,
                              relationship: "appStoreVersionExperimentV2",
                              type: "appStoreVersionExperiments", id: id)
            }
        }
    }

    /// The subscriptions and their groups.
    ///
    /// Apple keeps these off `reviewSubmissionItems` and gives each one its own
    /// submission resource, so a subscription never joins the version
    /// submission. It reaches the same queue by its own call.
    ///
    /// `READY_TO_SUBMIT` is the whole window. Apple refuses every other state,
    /// including the approved one, so the filter is what keeps the loop quiet
    /// on a second release.
    private func submitSubscriptions(appID: String) async {
        guard let groups = try? await api.apple(
            "GET", "/v1/apps/\(appID)/subscriptionGroups?include=subscriptions&limit=200")
        else { return }
        let payload = JSON(data: groups.data)

        for group in payload["data"].array {
            guard let id = group["id"].string else { continue }
            _ = try? await api.apple("POST", "/v1/subscriptionGroupSubmissions", body: [
                "data": [
                    "type": "subscriptionGroupSubmissions",
                    "relationships": ["subscriptionGroup": [
                        "data": ["type": "subscriptionGroups", "id": id]]],
                ],
            ])
        }

        for subscription in payload["included"].array
        where subscription["type"].string == "subscriptions"
            && subscription["attributes"]["state"].string == "READY_TO_SUBMIT" {
            guard let id = subscription["id"].string else { continue }
            _ = try? await api.apple("POST", "/v1/subscriptionSubmissions", body: [
                "data": [
                    "type": "subscriptionSubmissions",
                    "relationships": ["subscription": [
                        "data": ["type": "subscriptions", "id": id]]],
                ],
            ])
        }
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
        try await api.apple("PATCH", "/v1/reviewSubmissions/\(id)", body: [
            "data": ["type": "reviewSubmissions", "id": id, "attributes": ["canceled": true]],
        ])
    }

    /// Releases a version Apple has already approved and is holding for the
    /// developer. App Store Connect accepts this only in
    /// `PENDING_DEVELOPER_RELEASE`, and the request cannot be undone.
    public func releaseApprovedAppleVersion(versionID: String) async throws -> String {
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
