import Foundation

/// The App Store calls that answer a question or take one direct action.
///
/// This is the twin of `GoogleActionsClient`. None of it belongs in the plan,
/// because none of it is a desired state: a review reply happens once, on a
/// button, and the manifest holds no record of it.
///
/// Three calls here reach every App Store visitor: the review reply, the tag
/// visibility, and the treatment promotion. Each says so in its own comment,
/// and the caller confirms it, the same rule that `ReleaseClient` follows.
public struct AppleActionsClient: Sendable {
    private let api: StoreAPI

    public init(api: StoreAPI) {
        self.api = api
    }

    // MARK: - The reviews

    /// One customer review. The shape matches `GoogleActionsClient.Review`, so
    /// one panel draws both stores.
    public struct Review: Sendable, Equatable, Identifiable {
        public var id: String
        public var authorName: String?
        public var title: String?
        public var text: String?
        public var starRating: Int?
        public var territory: String?
        public var lastModified: Date?
        public var developerReply: String?
        /// The id of the existing response, so an edit patches it instead of
        /// making a second one.
        public var responseId: String?

        public init(id: String, authorName: String? = nil, title: String? = nil,
                    text: String? = nil, starRating: Int? = nil, territory: String? = nil,
                    lastModified: Date? = nil, developerReply: String? = nil,
                    responseId: String? = nil) {
            self.id = id
            self.authorName = authorName
            self.title = title
            self.text = text
            self.starRating = starRating
            self.territory = territory
            self.lastModified = lastModified
            self.developerReply = developerReply
            self.responseId = responseId
        }
    }

    /// Apple caps a response at this many characters.
    public static let replyLimit = 5970

    /// The newest reviews, with the response that each one already carries.
    ///
    /// Apple returns every review the app ever had, so this asks for one page
    /// and sorts by the newest. The response rides along in the same payload.
    public func reviews(appID: String, limit: Int = 100,
                        territory: String? = nil) async throws -> [Review] {
        var path = "/v1/apps/\(appID)/customerReviews"
            + "?limit=\(min(max(limit, 1), 200))&sort=-createdDate"
            + "&include=response"
        if let territory, !territory.isEmpty {
            path += "&filter%5Bterritory%5D=\(StateReader.escape(territory))"
        }
        let payload = JSON(data: try await api.apple("GET", path).data)

        // The responses arrive in `included`, keyed by their own id, and each
        // review names the one that belongs to it.
        var responses: [String: (id: String, body: String?)] = [:]
        for item in payload["included"].array
        where item["type"].string == "customerReviewResponses" {
            guard let id = item["id"].string else { continue }
            responses[id] = (id, item["attributes"]["responseBody"].string)
        }
        return payload["data"].array.compactMap { Self.parseReview($0, responses: responses) }
    }

    /// **This publishes public text under the app listing.** Every App Store
    /// visitor reads it, and a second reply replaces the first one. Confirm
    /// the text with the developer before this runs.
    ///
    /// Apple takes one response per review. A review that already carries one
    /// is patched, so the reply never lands twice.
    @discardableResult
    public func replyToReview(reviewId: String, responseId: String?,
                              text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ConnectionError.http(400, "A review reply cannot be empty.")
        }
        guard trimmed.count <= Self.replyLimit else {
            throw ConnectionError.http(
                400,
                "Apple accepts \(Self.replyLimit) characters in a review reply. This one has \(trimmed.count).")
        }
        if let responseId {
            try await api.apple("PATCH", "/v1/customerReviewResponses/\(responseId)", body: [
                "data": ["type": "customerReviewResponses", "id": responseId,
                         "attributes": ["responseBody": trimmed]],
            ])
        } else {
            try await api.apple("POST", "/v1/customerReviewResponses", body: [
                "data": [
                    "type": "customerReviewResponses",
                    "attributes": ["responseBody": trimmed],
                    "relationships": [
                        "review": ["data": ["type": "customerReviews", "id": reviewId]],
                    ],
                ],
            ])
        }
        return trimmed
    }

    /// Takes the published reply down. The review itself stays.
    public func removeReply(responseId: String) async throws {
        try await api.apple("DELETE", "/v1/customerReviewResponses/\(responseId)")
    }

    /// Apple's own summary of the reviews, in the reader's words.
    ///
    /// Thousands of reviews page five at a time and nobody reads them. Apple
    /// summarizes them per locale and per platform, and one read gives the
    /// pulse that the list above cannot.
    ///
    /// It appears only for an app with enough reviews, so an empty answer is a
    /// state and not a failure.
    public struct ReviewSummary: Sendable, Equatable, Identifiable {
        public var id: String
        public var text: String
        public var locale: String?
        public var platform: String?
        public var createdDate: Date?

        public init(id: String, text: String, locale: String? = nil,
                    platform: String? = nil, createdDate: Date? = nil) {
            self.id = id
            self.text = text
            self.locale = locale
            self.platform = platform
            self.createdDate = createdDate
        }
    }

    public func reviewSummaries(appID: String) async throws -> [ReviewSummary] {
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appID)/customerReviewSummarizations",
            query: [URLQueryItem(name: "limit", value: "50")]).data)
        return payload["data"].array.compactMap { item in
            guard let id = item["id"].string,
                  let text = item["attributes"]["text"].string, !text.isEmpty else {
                return nil
            }
            return ReviewSummary(
                id: id, text: text,
                locale: item["attributes"]["locale"].string,
                platform: item["attributes"]["platform"].string,
                createdDate: item["attributes"]["createdDate"].string.flatMap(Self.date))
        }
    }

    // MARK: - The tags the App Store puts on the app

    /// One label the App Store applies to the app.
    ///
    /// Apple derives these itself from what the app is, and they steer where
    /// the store shows it. The developer does not create one, and no call
    /// deletes one. The only control Apple publishes is whether a tag is shown
    /// on the store, which is how a tag that misrepresents the app is dealt
    /// with.
    public struct Tag: Sendable, Equatable, Identifiable {
        public var id: String
        public var name: String
        public var visibleInAppStore: Bool

        public init(id: String, name: String, visibleInAppStore: Bool) {
            self.id = id
            self.name = name
            self.visibleInAppStore = visibleInAppStore
        }
    }

    public func tags(appID: String) async throws -> [Tag] {
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appID)/appTags",
            query: [URLQueryItem(name: "limit", value: "200")]).data)
        return payload["data"].array.compactMap { item in
            guard let id = item["id"].string else { return nil }
            return Tag(id: id,
                       name: item["attributes"]["name"].string ?? id,
                       visibleInAppStore: item["attributes"]["visibleInAppStore"].bool ?? true)
        }
    }

    /// **This changes what an App Store visitor sees on the product page.**
    /// Hiding a tag takes it off the page; Apple keeps the tag itself, and
    /// showing it again is the same call with the other value.
    public func setTagVisible(tagID: String, _ visible: Bool) async throws {
        try await api.apple("PATCH", "/v1/appTags/\(tagID)", body: [
            "data": ["type": "appTags", "id": tagID,
                     "attributes": ["visibleInAppStore": visible]],
        ])
    }

    // MARK: - Promoting an experiment treatment

    /// One treatment of one product page experiment, as the store holds it.
    public struct Treatment: Sendable, Equatable, Identifiable {
        public var id: String
        public var name: String
        public var experimentID: String
        public var experimentName: String
        /// The state of the experiment it belongs to, for example `RUNNING`.
        public var experimentState: String?

        public init(id: String, name: String, experimentID: String,
                    experimentName: String, experimentState: String? = nil) {
            self.id = id
            self.name = name
            self.experimentID = experimentID
            self.experimentName = experimentName
            self.experimentState = experimentState
        }
    }

    /// Every treatment under every experiment of one version.
    ///
    /// The Marketing tab writes the experiments and the treatments; this is the
    /// read that names what the store actually holds, because a promotion
    /// addresses Apple's ids and not the manifest's keys.
    public func treatments(versionID: String) async throws -> [Treatment] {
        let experiments = JSON(data: try await api.apple(
            "GET", "/v1/appStoreVersions/\(versionID)/appStoreVersionExperimentsV2",
            query: [URLQueryItem(name: "limit", value: "200")]).data)
        var result: [Treatment] = []
        for experiment in experiments["data"].array {
            guard let experimentID = experiment["id"].string else { continue }
            let name = experiment["attributes"]["name"].string ?? experimentID
            let state = experiment["attributes"]["state"].string
            guard let response = try? await api.apple(
                "GET",
                "/v2/appStoreVersionExperiments/\(experimentID)/appStoreVersionExperimentTreatments",
                query: [URLQueryItem(name: "limit", value: "200")]) else { continue }
            for item in JSON(data: response.data)["data"].array {
                guard let id = item["id"].string else { continue }
                result.append(Treatment(
                    id: id,
                    name: item["attributes"]["name"].string ?? id,
                    experimentID: experimentID,
                    experimentName: name,
                    experimentState: state))
            }
        }
        return result
    }

    /// **This makes one treatment the product page every App Store visitor
    /// sees.** It is the last step of an experiment: the winning treatment's
    /// screenshots and text replace the ones on the live page.
    ///
    /// Nothing here undoes it. Promoting a different treatment is the way
    /// back, and so is a new version.
    public func promote(versionID: String, treatmentID: String) async throws {
        try await api.apple("POST", "/v1/appStoreVersionPromotions", body: [
            "data": [
                "type": "appStoreVersionPromotions",
                "relationships": [
                    "appStoreVersion": [
                        "data": ["type": "appStoreVersions", "id": versionID]],
                    "appStoreVersionExperimentTreatment": [
                        "data": ["type": "appStoreVersionExperimentTreatments",
                                 "id": treatmentID]],
                ],
            ],
        ])
    }

    static func parseReview(_ item: JSON,
                            responses: [String: (id: String, body: String?)]) -> Review? {
        guard let id = item["id"].string else { return nil }
        let attributes = item["attributes"]
        var review = Review(id: id)
        review.authorName = attributes["reviewerNickname"].string
        review.title = attributes["title"].string
        review.text = attributes["body"].string
        review.starRating = attributes["rating"].int
        review.territory = attributes["territory"].string
        review.lastModified = attributes["createdDate"].string.flatMap(Self.date)
        if let responseID = item["relationships"]["response"]["data"]["id"].string {
            review.responseId = responseID
            review.developerReply = responses[responseID]?.body
        }
        return review
    }

    /// App Store Connect stamps a review in ISO 8601, with or without the
    /// fractional seconds.
    static func date(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: text)
            ?? ISO8601DateFormatter().date(from: text)
    }
}
