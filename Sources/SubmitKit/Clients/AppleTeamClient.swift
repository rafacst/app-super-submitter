import Foundation

/// Who may reach the App Store Connect account, and what each one may do.
///
/// This is the App Store twin of `GoogleTeamClient`. Like that one, it belongs
/// to the account rather than to an app, so nothing here reaches `store.yaml`
/// or a plan row: the plan compares the desired state of **one app**, and a
/// colleague is not a field of a manifest.
///
/// Apple splits the list in two. A **user** has accepted and is on the team. An
/// **invitation** is an address that has not accepted yet, on its own resource
/// with its own id, and deleting it withdraws the invitation. The panel shows
/// both in one list, because "who is on this account" is one question.
///
/// The reads are free. Every write reaches a colleague: an invitation is an
/// email, a role change takes access away or gives it, and a removal shuts
/// somebody out. Each of those says so, and the panel confirms it, the same
/// rule the review reply follows.
public struct AppleTeamClient: Sendable {
    private let api: StoreAPI

    public init(api: StoreAPI) {
        self.api = api
    }

    // MARK: - What Apple answers

    /// One person on the account, whether they accepted yet or not.
    public struct Member: Sendable, Equatable, Identifiable {
        public var id: String
        /// The Apple Account address. Apple names it `username` on a user and
        /// `email` on an invitation, and both are the address.
        public var email: String
        public var firstName: String?
        public var lastName: String?
        /// `ADMIN`, `APP_MANAGER`, `DEVELOPER`, and the rest.
        public var roles: [String] = []
        /// Apple gives every app to a role that implies it, whatever the flag
        /// says, so a row that reads "every app" may be the role talking.
        public var allAppsVisible: Bool
        public var provisioningAllowed: Bool
        /// The App Store ids this person may see, when the account limits them.
        public var visibleApps: [String] = []
        /// An address Apple has emailed and nobody has accepted. It carries an
        /// invitation id and not a user id, so every write addresses it on the
        /// invitation resource.
        public var pending: Bool
        public var expirationDate: Date?

        public init(id: String, email: String, firstName: String? = nil,
                    lastName: String? = nil, roles: [String] = [],
                    allAppsVisible: Bool = false, provisioningAllowed: Bool = false,
                    visibleApps: [String] = [], pending: Bool = false,
                    expirationDate: Date? = nil) {
            self.id = id
            self.email = email
            self.firstName = firstName
            self.lastName = lastName
            self.roles = roles
            self.allAppsVisible = allAppsVisible
            self.provisioningAllowed = provisioningAllowed
            self.visibleApps = visibleApps
            self.pending = pending
            self.expirationDate = expirationDate
        }

        public var name: String {
            [firstName, lastName].compactMap { $0 }
                .filter { !$0.isEmpty }.joined(separator: " ")
        }

        /// The Account Holder and every Admin hold the whole account, and Apple
        /// refuses a write against them from a key that is not theirs. The
        /// panel says so rather than offering a control that will 403.
        public var isAccountOwner: Bool {
            roles.contains("ACCOUNT_HOLDER")
        }
    }

    // MARK: - The reads

    /// Everybody on the account: the users first, then the addresses Apple is
    /// still waiting on.
    ///
    /// The invitation read is optional. A key without the right role answers
    /// 403 on it, and the accepted users are still worth showing, so a refusal
    /// there costs no rows here.
    public func members() async throws -> [Member] {
        let users = JSON(data: try await api.apple(
            "GET", "/v1/users",
            query: [URLQueryItem(name: "limit", value: "200"),
                    URLQueryItem(name: "include", value: "visibleApps"),
                    URLQueryItem(name: "limit[visibleApps]", value: "50")]).data)
        var result = users["data"].array.compactMap { Self.parse($0, pending: false) }

        if let invited = try? await api.apple(
            "GET", "/v1/userInvitations",
            query: [URLQueryItem(name: "limit", value: "200"),
                    URLQueryItem(name: "include", value: "visibleApps"),
                    URLQueryItem(name: "limit[visibleApps]", value: "50")]) {
            result += JSON(data: invited.data)["data"].array
                .compactMap { Self.parse($0, pending: true) }
        }
        return result.sorted { $0.email.lowercased() < $1.email.lowercased() }
    }

    // MARK: - The writes

    /// **This emails a real address.** Apple sends an invitation, and the
    /// person holds the roles named here from the moment they accept it.
    ///
    /// `visibleApps` is what Apple wants when `allAppsVisible` is off. An empty
    /// list with the flag off gives them the account and no app, which is legal
    /// and is how somebody joins before the apps are decided.
    @discardableResult
    public func invite(email: String, firstName: String, lastName: String,
                       roles: [String], allAppsVisible: Bool,
                       provisioningAllowed: Bool = false,
                       visibleApps: [String] = []) async throws -> Member {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        // The address check is the Google client's, because an email address
        // is an email address and both stores refuse a malformed one with a
        // 400 that names nothing. A second copy here would drift.
        guard GoogleTeamClient.looksLikeAnAddress(address) else {
            throw ConnectionError.http(400, "\(email) is not an email address.")
        }
        guard !roles.isEmpty else {
            throw ConnectionError.http(400, "Apple wants at least one role on an invitation.")
        }
        var data: [String: Any] = [
            "type": "userInvitations",
            "attributes": [
                "email": address,
                "firstName": firstName.trimmingCharacters(in: .whitespaces),
                "lastName": lastName.trimmingCharacters(in: .whitespaces),
                "roles": roles,
                "allAppsVisible": allAppsVisible,
                "provisioningAllowed": provisioningAllowed,
            ],
        ]
        if !allAppsVisible, !visibleApps.isEmpty {
            data["relationships"] = ["visibleApps": [
                "data": visibleApps.map { ["type": "apps", "id": $0] }]]
        }
        let payload = JSON(data: try await api.apple(
            "POST", "/v1/userInvitations", body: ["data": data]).data)
        guard let member = Self.parse(payload["data"], pending: true) else {
            throw ConnectionError.invalidResponse
        }
        return member
    }

    /// **This changes what a colleague may do.** The role list is the whole
    /// list, so a role left out is a role taken away.
    public func setRoles(userID: String, roles: [String], allAppsVisible: Bool,
                         provisioningAllowed: Bool) async throws {
        try await api.apple("PATCH", "/v1/users/\(userID)", body: [
            "data": [
                "type": "users",
                "id": userID,
                "attributes": [
                    "roles": roles,
                    "allAppsVisible": allAppsVisible,
                    "provisioningAllowed": provisioningAllowed,
                ],
            ],
        ])
    }

    /// **This decides which apps a colleague can see.** The list is the whole
    /// list, so an app left out is an app taken away.
    ///
    /// Apple refuses this while `allAppsVisible` is on, because the flag
    /// already answers the question. The caller turns the flag off first.
    public func setVisibleApps(userID: String, appIDs: [String]) async throws {
        try await api.apple("PATCH", "/v1/users/\(userID)/relationships/visibleApps",
                            body: ["data": appIDs.map { ["type": "apps", "id": $0] }])
    }

    /// **This shuts a colleague out of the whole account.** No call puts them
    /// back; a new invitation does, and they have to accept it again.
    public func removeMember(_ member: Member) async throws {
        try await api.apple(
            "DELETE",
            member.pending ? "/v1/userInvitations/\(member.id)" : "/v1/users/\(member.id)")
    }

    // MARK: - The parser

    /// One row, from either resource. They carry the same attributes under
    /// two names for the address, so one parser reads both.
    static func parse(_ item: JSON, pending: Bool) -> Member? {
        guard let id = item["id"].string else { return nil }
        let attributes = item["attributes"]
        guard let email = attributes["username"].string ?? attributes["email"].string else {
            return nil
        }
        return Member(
            id: id,
            email: email,
            firstName: attributes["firstName"].string,
            lastName: attributes["lastName"].string,
            roles: attributes["roles"].array.compactMap(\.string),
            allAppsVisible: attributes["allAppsVisible"].bool ?? false,
            provisioningAllowed: attributes["provisioningAllowed"].bool ?? false,
            visibleApps: item["relationships"]["visibleApps"]["data"].array
                .compactMap { $0["id"].string },
            pending: pending,
            expirationDate: attributes["expirationDate"].string
                .flatMap(AppleActionsClient.date))
    }
}
