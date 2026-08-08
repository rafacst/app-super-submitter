import Foundation

/// Apple's newer way to change subscription metadata: a versioned draft.
///
/// The old model edits the live localizations and then submits the group. The
/// versioned model puts the edit in a draft that carries its own state through
/// review, so the name a customer reads today survives while the new one waits
/// for a reviewer, and a rejection costs the live product nothing.
///
/// The run still writes the live localizations, because that is what an account
/// without a draft takes and it is what every existing manifest expects. This
/// is the other path, on a button: create the draft, push the manifest's own
/// names and descriptions onto it, and watch its state.
///
/// `// ponytail: reads and two writes, no plan rows. A draft is a submission
/// // workflow and not a desired state, so the planner has nothing to diff.`
public struct AppleSubscriptionVersionsClient: Sendable {
    private let api: StoreAPI

    public init(api: StoreAPI) {
        self.api = api
    }

    // MARK: - What Apple answers

    /// One product that can carry a draft: a group, or a subscription in one.
    public struct Product: Sendable, Equatable, Identifiable {
        public var id: String
        public var kind: Kind
        /// The reference name of a group, or the product id of a subscription.
        public var name: String
        /// The group a subscription belongs to. Nil on a group itself.
        public var groupID: String?
        public var draft: Draft?

        public init(id: String, kind: Kind, name: String, groupID: String? = nil,
                    draft: Draft? = nil) {
            self.id = id
            self.kind = kind
            self.name = name
            self.groupID = groupID
            self.draft = draft
        }

        public enum Kind: String, Sendable, Equatable { case group, subscription }
    }

    /// One versioned draft, and where it is in review.
    public struct Draft: Sendable, Equatable, Identifiable {
        public var id: String
        public var version: Int?
        /// `PREPARE_FOR_SUBMISSION`, `WAITING_FOR_REVIEW`, `IN_REVIEW`,
        /// `APPROVED`, `REJECTED`, and the rest.
        public var state: String?
        /// The locales the draft already carries, with the name each one
        /// holds, so the panel can say what a reviewer will read.
        public var localizations: [String: String] = [:]

        public init(id: String, version: Int? = nil, state: String? = nil,
                    localizations: [String: String] = [:]) {
            self.id = id
            self.version = version
            self.state = state
            self.localizations = localizations
        }

        /// A draft nobody has submitted yet. Apple takes a localization write
        /// on that one alone, so it is what the buttons check.
        public var isEditable: Bool {
            state == nil || state == "PREPARE_FOR_SUBMISSION"
        }
    }

    // MARK: - The reads

    /// Every group of the app and every subscription in it, each with the
    /// newest draft it carries.
    ///
    /// One product whose version read fails keeps an empty draft and costs no
    /// other row its answer: an account that predates the versioned model
    /// answers 404 on every one of them, which is a state.
    public func products(appID: String) async throws -> [Product] {
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appID)/subscriptionGroups",
            query: [URLQueryItem(name: "include", value: "subscriptions"),
                    URLQueryItem(name: "limit", value: "200")]).data)

        var subscriptionsOfGroup: [String: [(id: String, name: String)]] = [:]
        for item in payload["included"].array where item["type"].string == "subscriptions" {
            guard let id = item["id"].string,
                  let groupID = item["relationships"]["group"]["data"]["id"].string
                    ?? item["relationships"]["subscriptionGroup"]["data"]["id"].string else {
                continue
            }
            subscriptionsOfGroup[groupID, default: []].append(
                (id, item["attributes"]["productId"].string ?? id))
        }
        // A subscription that names no group back still belongs to one, and
        // Apple fills the group's own side of the relationship, so that side
        // is read as well and the two are merged.
        var result: [Product] = []
        for group in payload["data"].array {
            guard let groupID = group["id"].string else { continue }
            var children = subscriptionsOfGroup[groupID] ?? []
            if children.isEmpty {
                let named = Set(group["relationships"]["subscriptions"]["data"].array
                    .compactMap { $0["id"].string })
                children = payload["included"].array
                    .filter { named.contains($0["id"].string ?? "") }
                    .compactMap { item in
                        guard let id = item["id"].string else { return nil }
                        return (id, item["attributes"]["productId"].string ?? id)
                    }
            }
            result.append(Product(
                id: groupID, kind: .group,
                name: group["attributes"]["referenceName"].string ?? groupID,
                draft: await newestDraft(kind: .group, productID: groupID)))
            for child in children.sorted(by: { $0.name < $1.name }) {
                result.append(Product(
                    id: child.id, kind: .subscription, name: child.name, groupID: groupID,
                    draft: await newestDraft(kind: .subscription, productID: child.id)))
            }
        }
        return result
    }

    /// The newest draft of one product, with the locales it carries.
    ///
    /// Apple returns the versions oldest first, so the newest is the last one
    /// with the highest version number.
    private func newestDraft(kind: Product.Kind, productID: String) async -> Draft? {
        let path = kind == .group
            ? "/v1/subscriptionGroups/\(productID)/versions"
            : "/v1/subscriptions/\(productID)/versions"
        guard let response = try? await api.apple(
            "GET", path, query: [URLQueryItem(name: "limit", value: "200")]) else { return nil }
        let versions = JSON(data: response.data)["data"].array.compactMap(Self.parseDraft)
        guard var newest = versions.max(by: { ($0.version ?? 0) < ($1.version ?? 0) }) else {
            return nil
        }
        newest.localizations = await localizations(kind: kind, draftID: newest.id)
        return newest
    }

    /// The locales a draft carries, with the name each one shows.
    public func localizations(kind: Product.Kind, draftID: String) async -> [String: String] {
        let path = kind == .group
            ? "/v1/subscriptionGroupVersions/\(draftID)/localizations"
            : "/v1/subscriptionVersions/\(draftID)/localizations"
        guard let response = try? await api.apple(
            "GET", path, query: [URLQueryItem(name: "limit", value: "200")]) else { return [:] }
        return JSON(data: response.data)["data"].array
            .reduce(into: [:]) { result, item in
                guard let locale = item["attributes"]["locale"].string else { return }
                result[locale] = item["attributes"]["name"].string ?? ""
            }
    }

    // MARK: - The writes

    /// **This creates a draft on the account.** Nothing a customer sees changes
    /// until somebody submits the draft and Apple approves it.
    ///
    /// Apple refuses a second draft while one is open, and that refusal is the
    /// right answer: the open one is where the edit belongs.
    @discardableResult
    public func createDraft(kind: Product.Kind, productID: String) async throws -> Draft {
        let (path, type, relationship, parentType) = kind == .group
            ? ("/v1/subscriptionGroupVersions", "subscriptionGroupVersions",
               "subscriptionGroup", "subscriptionGroups")
            : ("/v1/subscriptionVersions", "subscriptionVersions",
               "subscription", "subscriptions")
        let payload = JSON(data: try await api.apple("POST", path, body: [
            "data": [
                "type": type,
                "relationships": [relationship: [
                    "data": ["type": parentType, "id": productID]]],
            ],
        ]).data)
        guard let draft = Self.parseDraft(payload["data"]) else {
            throw ConnectionError.invalidResponse
        }
        return draft
    }

    /// Writes the localized metadata onto a draft, from what the manifest says.
    ///
    /// A locale the draft already carries is patched, and one it does not is
    /// created, which is the rule every other localization in this app follows.
    /// Nothing is deleted: a locale the manifest dropped stays on the draft,
    /// because a draft is a submission and not a desired state.
    public func writeLocalizations(kind: Product.Kind, draftID: String,
                                   locales: [String: (name: String, description: String?)])
        async throws {
        guard !locales.isEmpty else { return }
        let listPath = kind == .group
            ? "/v1/subscriptionGroupVersions/\(draftID)/localizations"
            : "/v1/subscriptionVersions/\(draftID)/localizations"
        let createPath = kind == .group
            ? "/v2/subscriptionGroupLocalizations" : "/v2/subscriptionLocalizations"
        let type = kind == .group
            ? "subscriptionGroupLocalizations" : "subscriptionLocalizations"
        let versionType = kind == .group
            ? "subscriptionGroupVersions" : "subscriptionVersions"

        let existing = JSON(data: try await api.apple(
            "GET", listPath, query: [URLQueryItem(name: "limit", value: "200")]).data)
        let byLocale = existing.idsByLocale

        for (locale, text) in locales.sorted(by: { $0.key < $1.key }) {
            var attributes: [String: Any] = ["name": text.name]
            // A group localization takes no description. Sending one is a 400,
            // so the key only appears where Apple accepts it.
            if kind == .subscription, let detail = text.description, !detail.isEmpty {
                attributes["description"] = detail
            }
            if let id = byLocale[locale] {
                try await api.apple("PATCH", "\(createPath)/\(id)", body: [
                    "data": ["type": type, "id": id, "attributes": attributes],
                ])
                continue
            }
            attributes["locale"] = locale
            try await api.apple("POST", createPath, body: [
                "data": [
                    "type": type,
                    "attributes": attributes,
                    "relationships": ["version": [
                        "data": ["type": versionType, "id": draftID]]],
                ],
            ])
        }
    }

    static func parseDraft(_ item: JSON) -> Draft? {
        guard let id = item["id"].string else { return nil }
        return Draft(id: id,
                     version: item["attributes"]["version"].int,
                     state: item["attributes"]["state"].string)
    }
}
