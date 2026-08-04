import Foundation

/// The App Store calls that answer a question or take one direct action.
///
/// This is the twin of `GoogleActionsClient`. None of it belongs in the plan,
/// because none of it is a desired state: a review reply happens once, on a
/// button, and the manifest holds no record of it.
///
/// One call here reaches every App Store visitor, and it says so in its own
/// comment. The caller confirms it, the same rule that `ReleaseClient` follows.
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
