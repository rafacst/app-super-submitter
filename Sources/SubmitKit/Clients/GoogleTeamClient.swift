import Foundation

/// Who may reach the Google Play developer account, and what each one may do.
///
/// This is the one Google surface that belongs to the account rather than to
/// an app, so nothing here takes a package name from the manifest and nothing
/// here reaches a plan. The plan compares a desired state of **one app**, and a
/// colleague is not a field of `store.yaml`.
///
/// Google publishes no "get my developer id" method. The id is the number in
/// the Play Console URL, and the caller supplies it. Every path below is built
/// from that id, so an empty one is refused here rather than sent.
///
/// The three writes reach a real person: an invitation lands in their inbox,
/// a permission change takes up to 48 hours to propagate, and a removal shuts
/// them out of the account. Each one says so, and the panel confirms them, the
/// same rule that `GoogleActionsClient` follows for a review reply.
///
/// `// ponytail: one client for the users and their grants. A grant only ever
/// // hangs off a user, so a second client would repeat the same name builder.`
public struct GoogleTeamClient: Sendable {
    private let api: StoreAPI

    public init(api: StoreAPI) {
        self.api = api
    }

    // MARK: - What Google answers

    /// One person with access to the developer account.
    public struct Member: Sendable, Equatable, Identifiable {
        /// The resource name, `developers/{developer}/users/{email}`. It is
        /// the id because every write addresses the user by it.
        public var id: String
        public var email: String
        /// `INVITED`, `ACCESS_GRANTED`, `ACCESS_EXPIRED`, and the rest.
        public var accessState: String?
        public var expirationTime: String?
        /// Google sets this when it did not show every permission the person
        /// holds, which happens for the account owner and for a caller that
        /// cannot manage every app. Such a row is read-only, and the panel
        /// says so rather than offering a write that would drop permissions.
        public var partial: Bool
        public var accountPermissions: [String] = []
        public var grants: [Grant] = []

        public init(id: String, email: String, accessState: String? = nil,
                    expirationTime: String? = nil, partial: Bool = false,
                    accountPermissions: [String] = [], grants: [Grant] = []) {
            self.id = id
            self.email = email
            self.accessState = accessState
            self.expirationTime = expirationTime
            self.partial = partial
            self.accountPermissions = accountPermissions
            self.grants = grants
        }
    }

    /// What one person may do with one app.
    public struct Grant: Sendable, Equatable, Identifiable {
        /// `developers/{developer}/users/{email}/grants/{packageName}`.
        public var id: String
        public var packageName: String
        public var permissions: [String] = []

        public init(id: String, packageName: String, permissions: [String] = []) {
            self.id = id
            self.packageName = packageName
            self.permissions = permissions
        }
    }

    // MARK: - The reads

    /// Everyone with access to the developer account.
    ///
    /// Google pages this, and a developer account with a hundred colleagues is
    /// ordinary, so the pages are followed to the end. The cap stops a broken
    /// `nextPageToken` from looping.
    public func members(developerId: String) async throws -> [Member] {
        let parent = try Self.developerPath(developerId)
        var result: [Member] = []
        var token: String?
        var pages = 0
        repeat {
            pages += 1
            var query = [URLQueryItem(name: "pageSize", value: "100")]
            if let token { query.append(URLQueryItem(name: "pageToken", value: token)) }
            let payload = JSON(data: try await api.google(
                "GET", "\(parent)/users", query: query).data)
            result += payload["users"].array.compactMap(Self.parseMember)
            token = payload["nextPageToken"].string
        } while token?.isEmpty == false && pages < 20
        return result
    }

    // MARK: - The writes

    /// **This sends an invitation to a real address.** Google emails the
    /// person, and they hold the permissions named here the moment they
    /// accept. Confirm the address and the permissions before this runs.
    ///
    /// `// ponytail: no expiry. Google takes an expirationTime and the panel
    /// // shows one that already exists; setting one is a Play Console job
    /// // until somebody asks for it here.`
    @discardableResult
    public func invite(developerId: String, email: String,
                       permissions: [String]) async throws -> Member {
        let parent = try Self.developerPath(developerId)
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.looksLikeAnAddress(address) else {
            throw ConnectionError.http(400, "\(email) is not an email address.")
        }
        let payload = JSON(data: try await api.google(
            "POST", "\(parent)/users",
            body: ["email": address, "developerAccountPermissions": permissions]).data)
        guard let member = Self.parseMember(payload) else {
            throw ConnectionError.invalidResponse
        }
        return member
    }

    /// **This changes what a colleague may do.** Google takes up to 48 hours
    /// to propagate a permission change, so the list this sends is the whole
    /// account-level list and an omitted permission is a removed one.
    @discardableResult
    public func setAccountPermissions(member: String,
                                      permissions: [String]) async throws -> Member {
        let payload = JSON(data: try await api.google(
            "PATCH", Self.resourcePath(member),
            body: ["developerAccountPermissions": permissions],
            query: [URLQueryItem(name: "updateMask",
                                 value: "developerAccountPermissions")]).data)
        guard let updated = Self.parseMember(payload) else {
            throw ConnectionError.invalidResponse
        }
        return updated
    }

    /// **This shuts a colleague out of the whole developer account**, every
    /// app included. No call puts them back; a new invitation does, and they
    /// have to accept it again.
    public func removeMember(_ member: String) async throws {
        try await api.google("DELETE", Self.resourcePath(member))
    }

    /// **This gives a colleague access to one app.** The account-level
    /// permissions stay as they were; this adds the per-app ones.
    @discardableResult
    public func grant(member: String, packageName: String,
                      permissions: [String]) async throws -> Grant {
        guard !packageName.isEmpty else {
            throw ConnectionError.http(400, "A grant needs a package name.")
        }
        let payload = JSON(data: try await api.google(
            "POST", "\(Self.resourcePath(member))/grants",
            body: ["packageName": packageName,
                   "appLevelPermissions": permissions]).data)
        guard let created = Self.parseGrant(payload) else {
            throw ConnectionError.invalidResponse
        }
        return created
    }

    /// **This changes what a colleague may do with one app.** The list is the
    /// whole per-app list, so an omitted permission is a removed one.
    @discardableResult
    public func setGrantPermissions(grant: String,
                                    permissions: [String]) async throws -> Grant {
        let payload = JSON(data: try await api.google(
            "PATCH", Self.resourcePath(grant),
            body: ["appLevelPermissions": permissions],
            query: [URLQueryItem(name: "updateMask",
                                 value: "appLevelPermissions")]).data)
        guard let updated = Self.parseGrant(payload) else {
            throw ConnectionError.invalidResponse
        }
        return updated
    }

    /// **This takes one app away from a colleague.** Their account-level
    /// access stays, so they keep whatever that grants them.
    public func revokeGrant(_ grant: String) async throws {
        try await api.google("DELETE", Self.resourcePath(grant))
    }

    // MARK: - The paths

    /// `developers/{id}` under the v3 prefix, from the number in the Play
    /// Console URL. A developer who pasted the whole `developers/123` prefix
    /// gets the same path as one who pasted `123`.
    static func developerPath(_ developerId: String) throws -> String {
        var id = developerId.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.hasPrefix("developers/") { id = String(id.dropFirst("developers/".count)) }
        guard !id.isEmpty else {
            throw ConnectionError.http(
                400, "Enter the developer account id first. It is the number after /developers/ in the Play Console URL.")
        }
        return "/androidpublisher/v3/developers/\(StateReader.escape(id))"
    }

    /// A resource name that Google itself returned, as a request path.
    ///
    /// The email inside it carries an `@`, and a package name carries dots,
    /// and both are legal in a path segment. The slashes have to survive, so
    /// this escapes the name as a path and never as one component.
    static func resourcePath(_ name: String) -> String {
        "/androidpublisher/v3/\(StateReader.escape(name))"
    }

    /// One `@`, something on each side of it, and a dot in the domain. Google
    /// refuses the rest with a 400 that names nothing, and this refusal names
    /// the field the developer is looking at.
    public static func looksLikeAnAddress(_ value: String) -> Bool {
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains(".") ,
              !parts[1].hasPrefix("."), !parts[1].hasSuffix("."),
              !value.contains(where: \.isWhitespace) else { return false }
        return true
    }

    // MARK: - The parsers

    static func parseMember(_ item: JSON) -> Member? {
        guard let name = item["name"].string else { return nil }
        // Google names the resource after the address, so a payload that
        // somehow omits `email` still has one to show.
        let email = item["email"].string
            ?? name.split(separator: "/").last.map(String.init)
            ?? name
        return Member(
            id: name,
            email: email,
            accessState: item["accessState"].string,
            expirationTime: item["expirationTime"].string,
            partial: item["partial"].bool ?? false,
            accountPermissions: item["developerAccountPermissions"].array
                .compactMap(\.string).sorted(),
            grants: item["grants"].array.compactMap(parseGrant))
    }

    static func parseGrant(_ item: JSON) -> Grant? {
        guard let name = item["name"].string else { return nil }
        // A draft app carries no package name, and Google puts the app id in
        // the resource name instead. The row then shows that id.
        let package = item["packageName"].string.flatMap { $0.isEmpty ? nil : $0 }
            ?? name.split(separator: "/").last.map(String.init)
            ?? ""
        return Grant(id: name, packageName: package,
                     permissions: item["appLevelPermissions"].array
                        .compactMap(\.string).sorted())
    }
}
