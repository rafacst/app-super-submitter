import Foundation

/// The Game Center configuration of one app: whether it exists, the group it
/// shares its objects with, and the App Store versions that carry it.
///
/// `AppleGameCenterCatalogClient` holds the five families of object that hang
/// off the detail this client finds.
///
/// The tab shows what App Store Connect already holds beside what the manifest
/// asks for, and the button on it sends the difference. No write here needs a
/// build: a configuration is written the moment it is sent, and the App Store
/// version named in `ensureAppVersion` is what carries it to a player.
public struct AppleGameCenterClient: Sendable {
    private let api: StoreAPI

    public init(api: StoreAPI) {
        self.api = api
    }

    /// The configuration itself. `nil` means the app has no Game Center at all,
    /// which is the state of every app that is not a game.
    public struct Detail: Sendable, Equatable {
        public var id: String
        public var arcadeEnabled: Bool?
        public var challengeEnabled: Bool?
        public var groupID: String?
        public var groupName: String?
        public var defaultLeaderboardID: String?
        /// The vendor identifier of the default leaderboard, which is what the
        /// manifest names it by. Apple answers with its own resource id, so the
        /// catalog read fills this in once it knows both.
        public var defaultLeaderboardVendorID: String?
        /// The App Store versions from which challenges are offered, as the
        /// version strings a developer reads on the Build tab.
        ///
        /// Apple keeps these as a relationship to `appStoreVersions` and not
        /// as an attribute, so they are an App Store version of this app and
        /// never an OS version. One per platform, because an app that ships
        /// two platforms holds two versions under one string.
        public var challengesMinimumPlatformVersions: [String] = []
        /// The same, as Apple's own resource ids, which is what the write
        /// sends.
        public var challengesMinimumVersionIDs: Set<String> = []

        public init(id: String) {
            self.id = id
        }
    }

    /// One App Store version, and whether it carries the configuration.
    public struct AppVersion: Sendable, Equatable {
        public var id: String
        public var appStoreVersionID: String?
        public var versionString: String
        public var enabled: Bool?
        public var compatibilityVersionIDs: Set<String> = []

        public init(id: String, versionString: String) {
            self.id = id
            self.versionString = versionString
        }
    }

    // MARK: - The read

    /// The one request that says whether this app is a game at all.
    ///
    /// Apple answers 404 for an app with no configuration, and `api.apple`
    /// throws on that, so the caller reads a `nil` here as "no Game Center"
    /// rather than as a failure. That is the whole cost of this read for every
    /// app that is not a game.
    public func detail(appID: String) async throws -> Detail? {
        // The include is what turns the challenge minimums from a list of
        // resource ids into the version strings a developer reads. An
        // unsupported include is a 400, and losing the whole detail read would
        // stop the plan writing anything at all, so the plain read is the
        // fallback and the minimums are then simply unknown.
        let path = "/v1/apps/\(appID)/gameCenterDetail"
        let response: StoreAPI.Result
        do {
            response = try await api.apple(
                "GET", path + "?include=challengesMinimumPlatformVersions")
        } catch ConnectionError.http(404, let body) {
            // Not a game. The caller reads this as "no configuration", so it
            // has to stay a 404 rather than becoming a second, plain request.
            throw ConnectionError.http(404, body)
        } catch {
            response = try await api.apple("GET", path)
        }

        let payload = JSON(data: response.data)
        guard let id = payload["data"]["id"].string else { return nil }

        var detail = Detail(id: id)
        let attributes = payload["data"]["attributes"]
        detail.arcadeEnabled = attributes["arcadeEnabled"].bool
        detail.challengeEnabled = attributes["challengeEnabled"].bool

        let relationships = payload["data"]["relationships"]
        detail.groupID = relationships["gameCenterGroup"]["data"]["id"].string
        detail.defaultLeaderboardID = relationships["defaultLeaderboard"]["data"]["id"].string

        detail.challengesMinimumVersionIDs = Set(
            relationships["challengesMinimumPlatformVersions"]["data"].array
                .compactMap { $0["id"].string })
        var strings: [String] = []
        for item in payload["included"].array
        where item["type"].string == "appStoreVersions" {
            guard let versionID = item["id"].string,
                  detail.challengesMinimumVersionIDs.contains(versionID),
                  let versionString = item["attributes"]["versionString"].string else {
                continue
            }
            if !strings.contains(versionString) { strings.append(versionString) }
        }
        detail.challengesMinimumPlatformVersions = strings

        if let groupID = detail.groupID {
            detail.groupName = try? await groupName(id: groupID)
        }
        return detail
    }

    /// One App Store version of the app, as the two Game Center relationships
    /// that point at one need it.
    public struct StoreVersion: Sendable, Equatable {
        public var id: String
        public var versionString: String
        public var platform: String?
    }

    /// Every App Store version of the app.
    ///
    /// One version string can hold two rows: an app that ships iOS and macOS
    /// has a 1.4.0 on each. The challenge minimums want both, and the version
    /// that carries the configuration wants the one of this run's platform,
    /// so the platform travels with the id rather than being dropped here.
    public func appStoreVersions(appID: String) async throws -> [StoreVersion] {
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appID)/appStoreVersions?limit=200").data)
        return payload["data"].array.compactMap { item in
            guard let id = item["id"].string,
                  let versionString = item["attributes"]["versionString"].string else {
                return nil
            }
            return StoreVersion(id: id, versionString: versionString,
                                platform: item["attributes"]["platform"].string)
        }
    }

    /// The reference name of one group.
    ///
    /// The manifest names a group by that reference name, because a developer
    /// picked it and Apple's resource id means nothing to them.
    public func groupName(id: String) async throws -> String? {
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/gameCenterGroups/\(id)").data)
        return payload["data"]["attributes"]["referenceName"].string
    }

    /// Every group the account holds, as reference name to id.
    ///
    /// A group is account-wide rather than app-wide, so this is what a chooser
    /// on the tab offers and what the plan matches a named group against.
    public func groups() async throws -> [String: String] {
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/gameCenterGroups?limit=200").data)
        var result: [String: String] = [:]
        for item in payload["data"].array {
            guard let id = item["id"].string,
                  let name = item["attributes"]["referenceName"].string else { continue }
            result[name] = id
        }
        return result
    }

    // MARK: - The writes

    /// The detail, created when Apple holds none, and its id either way.
    ///
    /// A 409 means the detail exists and the read missed it. This is the one
    /// place in the whole apply that retries on a 409, and it earns the
    /// exception because a detail is the parent of every other call: without
    /// its id nothing else in the plan can run.
    public func ensureDetail(appID: String, existing: Detail?) async throws -> String {
        if let existing { return existing.id }
        do {
            let response = try await api.apple("POST", "/v1/gameCenterDetails", body: [
                "data": [
                    "type": "gameCenterDetails",
                    "relationships": [
                        "app": ["data": ["type": "apps", "id": appID]],
                    ],
                ],
            ])
            if let id = JSON(data: response.data)["data"]["id"].string { return id }
        } catch ConnectionError.http(409, _) {
            // Fall through and read the one Apple already holds.
        }
        guard let found = try await detail(appID: appID)?.id else {
            throw ConnectionError.invalidResponse
        }
        return found
    }

    /// Points the detail at a group, or at none.
    public func setGroup(detailID: String, groupID: String?) async throws {
        let data: Any = groupID.map { ["type": "gameCenterGroups", "id": $0] } ?? NSNull()
        _ = try await api.apple("PATCH", "/v1/gameCenterDetails/\(detailID)", body: [
            "data": [
                "type": "gameCenterDetails",
                "id": detailID,
                "relationships": ["gameCenterGroup": ["data": data]],
            ],
        ])
    }

    /// The board Game Center opens on.
    ///
    /// `defaultLeaderboardV2`, never `defaultLeaderboard`. The unsuffixed
    /// relationship points at the deprecated v1 leaderboard family, and this
    /// app writes only v2 objects, so the v1 relationship could never name one
    /// of them.
    public func setDefaultLeaderboard(detailID: String, leaderboardID: String?) async throws {
        let data: Any = leaderboardID.map { ["type": "gameCenterLeaderboards", "id": $0] }
            ?? NSNull()
        _ = try await api.apple("PATCH", "/v1/gameCenterDetails/\(detailID)", body: [
            "data": [
                "type": "gameCenterDetails",
                "id": detailID,
                "relationships": ["defaultLeaderboardV2": ["data": data]],
            ],
        ])
    }

    /// The App Store versions from which challenges are offered.
    ///
    /// The linkage carries `appStoreVersions` and Apple's own resource ids, so
    /// the caller resolves the version strings the manifest holds through
    /// `appStoreVersionIDs(appID:)` first. Apple publishes a `PATCH` alone
    /// here, so this one write does replace the whole list.
    public func setChallengeMinimums(detailID: String,
                                     versionIDs: [String]) async throws {
        _ = try await api.apple(
            "PATCH",
            "/v1/gameCenterDetails/\(detailID)/relationships/challengesMinimumPlatformVersions",
            body: ["data": versionIDs.map { ["type": "appStoreVersions", "id": $0] }])
    }

    /// The group, created when the account holds none by that reference name.
    ///
    /// A group is shared across every app in it, so this never deletes one. The
    /// delete lives behind the destructive button on the tab, where it can name
    /// what it is about to take with it.
    public func ensureGroup(named name: String, existing: String?) async throws -> String {
        if let existing { return existing }
        let response = try await api.apple("POST", "/v1/gameCenterGroups", body: [
            "data": [
                "type": "gameCenterGroups",
                "attributes": ["referenceName": name],
            ],
        ])
        guard let id = JSON(data: response.data)["data"]["id"].string else {
            throw ConnectionError.invalidResponse
        }
        return id
    }

    /// Links one App Store version to the configuration, and says whether it
    /// carries it.
    ///
    /// This is the step that reaches a player, and the only one. Apple
    /// publishes no call that releases a Game Center version on its own, so the
    /// configuration ships with the App Store version named here.
    @discardableResult
    public func ensureAppVersion(appStoreVersionID: String, enabled: Bool?,
                                 existing: AppVersion?) async throws -> String {
        if let existing {
            if let enabled, enabled != existing.enabled {
                _ = try await api.apple(
                    "PATCH", "/v1/gameCenterAppVersions/\(existing.id)", body: [
                        "data": [
                            "type": "gameCenterAppVersions",
                            "id": existing.id,
                            "attributes": ["enabled": enabled],
                        ],
                    ])
            }
            return existing.id
        }
        var attributes: [String: Any] = [:]
        if let enabled { attributes["enabled"] = enabled }
        var data: [String: Any] = [
            "type": "gameCenterAppVersions",
            "relationships": [
                "appStoreVersion": [
                    "data": ["type": "appStoreVersions", "id": appStoreVersionID],
                ],
            ],
        ]
        if !attributes.isEmpty { data["attributes"] = attributes }
        let response = try await api.apple("POST", "/v1/gameCenterAppVersions",
                                           body: ["data": data])
        guard let id = JSON(data: response.data)["data"]["id"].string else {
            throw ConnectionError.invalidResponse
        }
        return id
    }

    /// The older versions whose scores this one keeps.
    ///
    /// The difference, never the whole list. A replace written from a stale
    /// read drops a compatibility row somebody added in the console that
    /// morning.
    public func setCompatibility(appVersionID: String, add: [String],
                                 remove: [String]) async throws {
        let path = "/v1/gameCenterAppVersions/\(appVersionID)/relationships/compatibilityVersions"
        if !add.isEmpty {
            _ = try await api.apple("POST", path, body: ["data": add.map {
                ["type": "gameCenterAppVersions", "id": $0]
            }])
        }
        if !remove.isEmpty {
            _ = try await api.apple("DELETE", path, body: ["data": remove.map {
                ["type": "gameCenterAppVersions", "id": $0]
            }])
        }
    }

    /// Removes a group from the account. The destructive button on the tab is
    /// the only caller, and no plan step ever is.
    public func deleteGroup(id: String) async throws {
        _ = try await api.apple("DELETE", "/v1/gameCenterGroups/\(id)")
    }

    /// The App Store versions that carry the configuration, keyed by version
    /// string.
    ///
    /// Keyed by the version a developer reads on the Build tab, not by Apple's
    /// resource id, because the manifest names them that way. A row whose
    /// App Store version cannot be read keeps its own id as the key, so it
    /// still shows rather than vanishing.
    public func appVersions(detailID: String) async throws -> [String: AppVersion] {
        let payload = JSON(data: try await api.apple(
            "GET",
            "/v1/gameCenterDetails/\(detailID)/gameCenterAppVersions?limit=200&include=appStoreVersion").data)

        // The included block names each App Store version once, so the version
        // string costs no request of its own.
        var versionStrings: [String: String] = [:]
        for item in payload["included"].array where item["type"].string == "appStoreVersions" {
            guard let id = item["id"].string else { continue }
            versionStrings[id] = item["attributes"]["versionString"].string
        }

        var result: [String: AppVersion] = [:]
        for item in payload["data"].array {
            guard let id = item["id"].string else { continue }
            let appStoreVersionID = item["relationships"]["appStoreVersion"]["data"]["id"]
                .string
            let versionString = appStoreVersionID.flatMap { versionStrings[$0] } ?? id
            var version = AppVersion(id: id, versionString: versionString)
            version.appStoreVersionID = appStoreVersionID
            version.enabled = item["attributes"]["enabled"].bool
            version.compatibilityVersionIDs = Set(
                item["relationships"]["compatibilityVersions"]["data"].array
                    .compactMap { $0["id"].string })
            result[versionString] = version
        }
        return result
    }
}
