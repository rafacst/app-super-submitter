import Foundation

/// The other direction. Everywhere else in this app asks App Store Connect a
/// question; a webhook is Apple telling the developer's own server something
/// happened, the moment it happens.
///
/// The Release tab polls for a state change on a timer. A webhook is the push
/// half of the same answer, and it lands in seconds rather than in minutes.
///
/// The catch is honest and worth saying on the panel: a Mac app is not running
/// most of the time, so the events go to whatever server the URL names, and
/// this app configures the hook and reads what Apple already delivered. It does
/// not receive one.
///
/// `secret` is the only value in this file that is a credential, and it never
/// reaches `store.yaml`, the run log, or this app's own storage. Apple takes it
/// once on the create, the developer's server verifies each delivery with it,
/// and no read ever gives it back.
public struct AppleWebhooksClient: Sendable {
    private let api: StoreAPI

    public init(api: StoreAPI) {
        self.api = api
    }

    /// What Apple will push. The whole published catalogue, in the order a
    /// developer meets them: the release states first, then the builds, then
    /// the tester feedback, then the alternative distribution ones that only a
    /// marketplace app uses.
    public static let eventTypes: [StoreValues.Choice] = [
        .init("APP_STORE_VERSION_APP_VERSION_STATE_UPDATED", "A version changed review state"),
        .init("BUILD_UPLOAD_STATE_UPDATED", "A build finished processing"),
        .init("BUILD_BETA_DETAIL_EXTERNAL_BUILD_STATE_UPDATED",
              "A build changed beta review state"),
        .init("BETA_FEEDBACK_CRASH_SUBMISSION_CREATED", "A tester sent a crash"),
        .init("BETA_FEEDBACK_SCREENSHOT_SUBMISSION_CREATED", "A tester sent a screenshot"),
        .init("BACKGROUND_ASSET_VERSION_STATE_UPDATED", "A background asset changed state"),
        .init("BACKGROUND_ASSET_VERSION_APP_STORE_RELEASE_STATE_UPDATED",
              "A background asset changed App Store release state"),
        .init("BACKGROUND_ASSET_VERSION_EXTERNAL_BETA_RELEASE_STATE_UPDATED",
              "A background asset changed beta release state"),
        .init("BACKGROUND_ASSET_VERSION_INTERNAL_BETA_RELEASE_CREATED",
              "A background asset reached internal testing"),
        .init("ALTERNATIVE_DISTRIBUTION_PACKAGE_VERSION_CREATED",
              "An alternative distribution package appeared"),
        .init("ALTERNATIVE_DISTRIBUTION_PACKAGE_AVAILABLE_UPDATED",
              "An alternative distribution package changed availability"),
        .init("ALTERNATIVE_DISTRIBUTION_TERRITORY_AVAILABILITY_UPDATED",
              "An alternative distribution territory changed"),
    ]

    public struct Hook: Sendable, Equatable, Identifiable {
        public var id: String
        public var name: String
        public var url: String
        public var enabled: Bool
        public var eventTypes: [String] = []

        public init(id: String, name: String, url: String, enabled: Bool = true,
                    eventTypes: [String] = []) {
            self.id = id
            self.name = name
            self.url = url
            self.enabled = enabled
            self.eventTypes = eventTypes
        }
    }

    /// One attempt Apple made against the URL, and what came back.
    public struct Delivery: Sendable, Equatable, Identifiable {
        public var id: String
        /// `SUCCEEDED`, `FAILED`, or `PENDING`.
        public var state: String?
        public var createdDate: Date?
        public var errorMessage: String?
        /// The HTTP status the developer's own server answered with.
        public var responseStatus: Int?
        public var redelivery: Bool

        public init(id: String, state: String? = nil, createdDate: Date? = nil,
                    errorMessage: String? = nil, responseStatus: Int? = nil,
                    redelivery: Bool = false) {
            self.id = id
            self.state = state
            self.createdDate = createdDate
            self.errorMessage = errorMessage
            self.responseStatus = responseStatus
            self.redelivery = redelivery
        }
    }

    // MARK: - The reads

    public func hooks(appID: String) async throws -> [Hook] {
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appID)/webhooks",
            query: [URLQueryItem(name: "limit", value: "200")]).data)
        return payload["data"].array.compactMap(Self.parseHook)
    }

    /// What Apple already sent, newest first. This is the only place a failing
    /// endpoint shows itself, because Apple never says so anywhere else.
    public func deliveries(hookID: String, limit: Int = 25) async throws -> [Delivery] {
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/webhooks/\(hookID)/deliveries",
            query: [URLQueryItem(name: "limit", value: String(min(max(limit, 1), 200)))]).data)
        return payload["data"].array.compactMap(Self.parseDelivery)
            .sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
    }

    // MARK: - The writes

    /// **This tells Apple to start pushing events to a URL.** Every event named
    /// here reaches that address, so the address has to be the developer's own.
    ///
    /// The secret goes to Apple and is never stored here. Apple signs each
    /// delivery with it, and the receiving server verifies the signature.
    @discardableResult
    public func create(appID: String, name: String, url: String, secret: String,
                       eventTypes: [String], enabled: Bool = true) async throws -> Hook {
        let address = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address.lowercased().hasPrefix("https://") else {
            throw ConnectionError.http(400, "Apple delivers to an https address only.")
        }
        guard !eventTypes.isEmpty else {
            throw ConnectionError.http(400, "Pick at least one event for Apple to send.")
        }
        guard !secret.isEmpty else {
            throw ConnectionError.http(
                400, "Apple wants a secret. Your server verifies each delivery with it.")
        }
        let payload = JSON(data: try await api.apple("POST", "/v1/webhooks", body: [
            "data": [
                "type": "webhooks",
                "attributes": [
                    "name": name.isEmpty ? address : name,
                    "url": address,
                    "secret": secret,
                    "enabled": enabled,
                    "eventTypes": eventTypes,
                ],
                "relationships": ["app": ["data": ["type": "apps", "id": appID]]],
            ],
        ]).data)
        guard let hook = Self.parseHook(payload["data"]) else {
            throw ConnectionError.invalidResponse
        }
        return hook
    }

    /// Turns the hook off, or on again. Apple keeps the configuration either
    /// way, so this is the reversible half of a delete.
    public func setEnabled(hookID: String, _ enabled: Bool) async throws {
        try await api.apple("PATCH", "/v1/webhooks/\(hookID)", body: [
            "data": ["type": "webhooks", "id": hookID,
                     "attributes": ["enabled": enabled]],
        ])
    }

    /// **This removes the configuration.** The secret goes with it, so a hook
    /// that comes back is a new one with a new secret.
    public func delete(hookID: String) async throws {
        try await api.apple("DELETE", "/v1/webhooks/\(hookID)")
    }

    /// Sends one test event, so the developer can see their own server answer
    /// before a real release depends on it.
    public func ping(hookID: String) async throws {
        try await api.apple("POST", "/v1/webhookPings", body: [
            "data": [
                "type": "webhookPings",
                "relationships": ["webhook": ["data": ["type": "webhooks", "id": hookID]]],
            ],
        ])
    }

    // MARK: - The parsers

    static func parseHook(_ item: JSON) -> Hook? {
        guard let id = item["id"].string else { return nil }
        let attributes = item["attributes"]
        return Hook(id: id,
                    name: attributes["name"].string ?? id,
                    url: attributes["url"].string ?? "",
                    enabled: attributes["enabled"].bool ?? true,
                    eventTypes: attributes["eventTypes"].array.compactMap(\.string))
    }

    static func parseDelivery(_ item: JSON) -> Delivery? {
        guard let id = item["id"].string else { return nil }
        let attributes = item["attributes"]
        return Delivery(
            id: id,
            state: attributes["deliveryState"].string,
            createdDate: attributes["createdDate"].string.flatMap(AppleActionsClient.date),
            errorMessage: attributes["errorMessage"].string,
            responseStatus: attributes["response"]["httpStatusCode"].int
                ?? attributes["response"]["statusCode"].int,
            redelivery: attributes["redelivery"].bool ?? false)
    }
}
