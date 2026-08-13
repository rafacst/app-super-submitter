import Foundation

/// The five families of Game Center object: achievements, leaderboards,
/// leaderboard sets, activities and challenges.
///
/// **One reader, five families.** Apple gives all five the same shape under
/// different resource names: an object carries a vendor identifier, it hangs
/// versions, and a version hangs the localizations a player actually reads. So
/// `Family` holds the names and one set of methods walks them.
/// `AppleProductImages.ProductImageFamily` already proves the pattern here.
///
/// **v2 and never v1.** Apple marks the v1 achievement, leaderboard and
/// leaderboard set families deprecated, with every localization, image and
/// release resource that hangs off them. A v2 object carries a version, and
/// that version is what a localization attaches to. Activities and challenges
/// are new enough to have only one version, so their paths are v1 and that is
/// not a deprecation.
///
/// **Nothing here deletes from a plan step.** A delete discards every score and
/// every earned achievement behind the object, and no call brings them back, so
/// it lives behind the destructive button on the card where it can name what it
/// takes with it. The manifest archives instead, which is reversible.
public struct AppleGameCenterCatalogClient: Sendable {
    private let api: StoreAPI

    public init(api: StoreAPI) {
        self.api = api
    }

    public enum Family: String, Sendable, CaseIterable {
        case achievement, leaderboard, leaderboardSet, activity, challenge

        /// What a person calls the family, for a panel heading and for the one
        /// line a failed read appends to `state.failures`.
        public var label: String {
            switch self {
            case .achievement: "achievements"
            case .leaderboard: "leaderboards"
            case .leaderboardSet: "leaderboard sets"
            case .activity: "activities"
            case .challenge: "challenges"
            }
        }

        /// The same word for one of them. It is spelled out rather than taken
        /// off `label`, because dropping the last letter of "activities" gives
        /// "activitie".
        public var noun: String {
            switch self {
            case .achievement: "achievement"
            case .leaderboard: "leaderboard"
            case .leaderboardSet: "set"
            case .activity: "activity"
            case .challenge: "challenge"
            }
        }

        /// The panel this family is edited on, which is the anchor a fix
        /// button scrolls to and the id `FieldIndex` gives it.
        public var anchor: String {
            switch self {
            case .achievement: "gaming.achievements"
            case .leaderboard: "gaming.leaderboards"
            case .leaderboardSet: "gaming.leaderboardSets"
            case .activity: "gaming.activities"
            case .challenge: "gaming.challenges"
            }
        }

        /// The relationship on the detail that lists every object.
        ///
        /// Three of them carry the `V2` suffix, because the unsuffixed
        /// relationship still answers with the deprecated v1 objects.
        var detailRelationship: String {
            switch self {
            case .achievement: "gameCenterAchievementsV2"
            case .leaderboard: "gameCenterLeaderboardsV2"
            case .leaderboardSet: "gameCenterLeaderboardSetsV2"
            case .activity: "gameCenterActivities"
            case .challenge: "gameCenterChallenges"
            }
        }

        /// Where one object lives, and so where its versions hang.
        var objectPath: String {
            switch self {
            case .achievement: "/v2/gameCenterAchievements"
            case .leaderboard: "/v2/gameCenterLeaderboards"
            case .leaderboardSet: "/v2/gameCenterLeaderboardSets"
            case .activity: "/v1/gameCenterActivities"
            case .challenge: "/v1/gameCenterChallenges"
            }
        }

        /// Where one version lives, and so where its localizations hang.
        var versionPath: String {
            switch self {
            case .achievement: "/v2/gameCenterAchievementVersions"
            case .leaderboard: "/v2/gameCenterLeaderboardVersions"
            case .leaderboardSet: "/v2/gameCenterLeaderboardSetVersions"
            case .activity: "/v1/gameCenterActivityVersions"
            case .challenge: "/v1/gameCenterChallengeVersions"
            }
        }

        /// Whether the family links to other objects, and what the link means.
        /// A set holds leaderboards; nothing else reads a link on this pass.
        var membersRelationship: String? {
            self == .leaderboardSet ? "gameCenterLeaderboards" : nil
        }

        /// Where an image of this family lives.
        ///
        /// v2 for the three families that have a v2, v1 for the two that were
        /// born after it. The path carries the version and the `type` in the
        /// body never does, exactly like the objects above.
        var imagePath: String {
            switch self {
            case .achievement: "/v2/gameCenterAchievementImages"
            case .leaderboard: "/v2/gameCenterLeaderboardImages"
            case .leaderboardSet: "/v2/gameCenterLeaderboardSetImages"
            case .activity: "/v1/gameCenterActivityImages"
            case .challenge: "/v1/gameCenterChallengeImages"
            }
        }

        var imageResourceType: String {
            switch self {
            case .achievement: "gameCenterAchievementImages"
            case .leaderboard: "gameCenterLeaderboardImages"
            case .leaderboardSet: "gameCenterLeaderboardSetImages"
            case .activity: "gameCenterActivityImages"
            case .challenge: "gameCenterChallengeImages"
            }
        }

        /// Whether the family carries a picture on the version as well as one
        /// per locale. Activities and challenges do; the other three do not,
        /// and asking Apple to include one on them is a 400.
        var hasDefaultImage: Bool { self == .activity || self == .challenge }
    }

    /// One object of any family, as App Store Connect holds it.
    public struct Object: Sendable, Equatable, Identifiable {
        /// Apple's own resource id. The manifest never names this.
        public var id: String
        /// The key. It is what the game passes to GameKit, and what the
        /// manifest matches on.
        public var vendorIdentifier: String
        public var referenceName: String?
        public var archived: Bool?
        /// Every other attribute Apple answered with, as text.
        ///
        /// A bag rather than a field per family, because the five families
        /// carry different attributes and this reader is one loop. Text rather
        /// than a typed value, because `ActualState` is `Equatable` and
        /// `Sendable` and a raw JSON value is neither.
        ///
        /// `// ponytail: text bag. If the plan ever needs to compare a number
        /// // with a tolerance rather than for equality, type it then.`
        public var attributes: [String: String] = [:]
        /// The newest version, which is the one a localization attaches to.
        public var draftVersionID: String?
        public var versionState: String?
        public var localizations: [String: Localization] = [:]
        /// The leaderboards this object points at, by vendor identifier: the
        /// members of a set, the boards an activity scores to, the one board a
        /// challenge scores from.
        public var linkedIDs: Set<String> = []
        /// The achievements an activity can award, by vendor identifier.
        public var linkedAchievementIDs: Set<String> = []
        /// The picture on the version itself, which activities and challenges
        /// carry and the other three families do not. It is what every locale
        /// falls back to, and the manifest's top-level `image:` writes it.
        public var defaultImageID: String?
        public var defaultImageFileName: String?
        public var defaultImageFileSize: Int?

        public init(id: String, vendorIdentifier: String) {
            self.id = id
            self.vendorIdentifier = vendorIdentifier
        }

        /// What the tab shows as the name of the row.
        public var displayName: String {
            if let referenceName, !referenceName.isEmpty { return referenceName }
            return vendorIdentifier
        }
    }

    /// One locale of one version.
    public struct Localization: Sendable, Equatable {
        public var id: String
        /// Every text attribute of the localization, by its Apple name.
        public var values: [String: String] = [:]
        public var imageID: String?
        /// The name and the byte count of the image Apple holds.
        ///
        /// Apple returns no checksum on a Game Center image, and the update
        /// request takes `uploaded` alone, so these two are what the plan
        /// compares a file on disk against.
        ///
        /// `// ponytail: name and size, not a checksum. Two different pictures
        /// // saved under one name at one byte count would not re-upload. Apple
        /// // publishes no checksum to do better with.`
        public var imageFileName: String?
        public var imageFileSize: Int?

        public init(id: String) {
            self.id = id
        }
    }

    // MARK: - The read

    /// Every object of one family, keyed by vendor identifier.
    ///
    /// The localizations cost one request per object for the versions and one
    /// for the newest version's locales, so a game with forty achievements
    /// costs about eighty requests here. `deep: false` reads the objects alone,
    /// which is what a panel needs to say how many the store holds.
    ///
    /// An object with no vendor identifier is skipped rather than keyed by
    /// something else. Every match in the plan is on that identifier, and a row
    /// keyed by a resource id would look like a create for an object that
    /// already exists.
    public func objects(family: Family, detailID: String,
                        deep: Bool = true) async throws -> [String: Object] {
        let payload = JSON(data: try await api.apple(
            "GET",
            "/v1/gameCenterDetails/\(detailID)/\(family.detailRelationship)?limit=200").data)

        var result: [String: Object] = [:]
        for item in payload["data"].array {
            guard var object = Self.parse(item) else { continue }
            if deep {
                await fill(&object, family: family)
            }
            result[object.vendorIdentifier] = object
        }
        return result
    }

    /// The vendor identifiers of the leaderboards inside one set.
    ///
    /// Apple answers with resource ids, so the caller passes the map it already
    /// read for the leaderboard family and this turns them back into the
    /// identifiers the manifest names.
    public func members(setID: String,
                        leaderboardsByResourceID: [String: String]) async -> Set<String> {
        await links(path: "/v2/gameCenterLeaderboardSets/\(setID)/gameCenterLeaderboards",
                    byResourceID: leaderboardsByResourceID)
    }

    /// What one activity awards and scores to.
    ///
    /// The `V2` relationships, whose v1 twins are deprecated. Two requests per
    /// activity, and they earn it: without them the plan would offer to write
    /// the same links on every apply, because it would have nothing to compare
    /// them against.
    public func activityLinks(activityID: String,
                              achievementsByResourceID: [String: String],
                              leaderboardsByResourceID: [String: String]) async
        -> (achievements: Set<String>, leaderboards: Set<String>) {
        async let achievements = links(
            path: "/v1/gameCenterActivities/\(activityID)/achievementsV2",
            byResourceID: achievementsByResourceID)
        async let leaderboards = links(
            path: "/v1/gameCenterActivities/\(activityID)/leaderboardsV2",
            byResourceID: leaderboardsByResourceID)
        return (await achievements, await leaderboards)
    }

    /// The board one challenge scores from, by vendor identifier.
    public func challengeLeaderboard(challengeID: String,
                                     leaderboardsByResourceID: [String: String]) async
        -> String? {
        guard let response = try? await api.apple(
            "GET", "/v1/gameCenterChallenges/\(challengeID)/leaderboardV2") else { return nil }
        let item = JSON(data: response.data)["data"]
        guard let id = item["id"].string else { return nil }
        return leaderboardsByResourceID[id] ?? item["attributes"]["vendorIdentifier"].string
    }

    /// One relationship, as the vendor identifiers the manifest names.
    ///
    /// Apple answers with its own resource ids, so the caller passes the map it
    /// already read and this turns them back. An object the map does not hold
    /// falls back to the vendor identifier in the response itself.
    private func links(path: String, byResourceID: [String: String]) async -> Set<String> {
        guard let response = try? await api.apple("GET", path + "?limit=200") else { return [] }
        return Set(JSON(data: response.data)["data"].array.compactMap { item -> String? in
            guard let id = item["id"].string else { return nil }
            return byResourceID[id] ?? item["attributes"]["vendorIdentifier"].string
        })
    }

    /// The name one board carries inside one set, in one locale.
    public struct MemberName: Sendable, Equatable, Identifiable {
        /// The localization's own resource id, which is what a delete needs.
        public var id: String
        public var locale: String
        /// The resource id of the board the name belongs to.
        public var leaderboardID: String?
        public var name: String

        public init(id: String, locale: String, name: String) {
            self.id = id
            self.locale = locale
            self.name = name
        }
    }

    /// The member names Apple already holds for one set.
    ///
    /// Read only, and it has to be. Apple deprecated `POST` and `PATCH` on
    /// `gameCenterLeaderboardSetMemberLocalizations` and left `GET` and
    /// `DELETE` live, so this app can show a name and offer to delete a stale
    /// one, and it can never write one.
    ///
    /// It reads the standalone collection under a filter, and not the set's own
    /// `relationships/localizations`. That relationship answers the **set's**
    /// v1 localizations as bare linkage stubs with no attributes at all, so a
    /// reader pointed at it finds no locale and no name and reports an empty
    /// list for a set that has plenty.
    public func memberLocalizations(setID: String) async -> [MemberName] {
        guard let response = try? await api.apple(
            "GET",
            "/v1/gameCenterLeaderboardSetMemberLocalizations?filter%5BgameCenterLeaderboardSet%5D=\(setID)&limit=200")
        else { return [] }

        return JSON(data: response.data)["data"].array.compactMap { item in
            guard let id = item["id"].string,
                  let locale = item["attributes"]["locale"].string else { return nil }
            var made = MemberName(id: id, locale: locale,
                                  name: item["attributes"]["name"].string ?? "")
            made.leaderboardID = item["relationships"]["gameCenterLeaderboard"]["data"]["id"]
                .string
            return made
        }
    }

    // MARK: - The writes

    /// What one object create or change carries. The runner builds it from the
    /// manifest so the client never reads a manifest type of its own.
    public struct Write: Sendable, Equatable {
        public var vendorIdentifier: String
        public var referenceName: String?
        /// Archived, never deleted. It is on the change request alone: Apple's
        /// create request has no such attribute, and an object is not born
        /// archived.
        public var archived: Bool?
        /// The family's own attributes, already in Apple's spelling, split by
        /// the type Apple takes. A boolean sent as `"true"` is a 400, so the
        /// four maps stay apart rather than becoming one bag of text.
        public var attributes: [String: String] = [:]
        public var numbers: [String: Int] = [:]
        public var flags: [String: Bool] = [:]
        /// The `StringToStringMap` attributes: `activityProperties` on the two
        /// v2 families, `properties` on an activity.
        public var maps: [String: [String: String]] = [:]

        public init(vendorIdentifier: String) {
            self.vendorIdentifier = vendorIdentifier
        }

        /// - Parameter creating: true on a `POST`, which takes the vendor
        ///   identifier and refuses `archived`; false on a `PATCH`, which
        ///   takes `archived` and where the identifier is the key and never
        ///   changes.
        func body(creating: Bool) -> [String: Any] {
            var made: [String: Any] = [:]
            if creating { made["vendorIdentifier"] = vendorIdentifier }
            if let referenceName { made["referenceName"] = referenceName }
            if !creating, let archived { made["archived"] = archived }
            for (key, value) in attributes { made[key] = value }
            for (key, value) in numbers { made[key] = value }
            for (key, value) in flags { made[key] = value }
            for (key, value) in maps { made[key] = value }
            return made
        }

        /// Every named value as the read reports it, so the planner compares
        /// like with like.
        ///
        /// `ActualState` holds what Apple answered as text, because it is
        /// `Equatable` and `Sendable` and a raw JSON value is neither. This is
        /// the same flattening on the wanted side, and `archived` is in it:
        /// the store reports that one and a change to it earns a step.
        public var comparable: [String: String] {
            var made: [String: String] = [:]
            if let referenceName { made["referenceName"] = referenceName }
            if let archived { made["archived"] = archived ? "true" : "false" }
            for (key, value) in attributes { made[key] = value }
            for (key, value) in numbers { made[key] = String(value) }
            for (key, value) in flags { made[key] = value ? "true" : "false" }
            return made
        }
    }

    /// Creates the object, or changes the one Apple already holds.
    ///
    /// **Which parent it hangs from.** A manifest with no group hangs the
    /// object on the detail; a manifest that names a group hangs it on the
    /// group, so a second app in that group shares it. Apple publishes no call
    /// that moves an existing object between the two, so a change never sends
    /// a parent: the planner raises a warning naming the object instead, and a
    /// step with no call behind it would be a lie.
    ///
    /// The create carries an inline version, which Apple marks required on the
    /// v2 families. It sends the type alone, with no id, because the version
    /// does not exist yet.
    public func ensureObject(family: Family, detailID: String, groupID: String?,
                             _ wanted: Write, existing: Object?) async throws -> String {
        if let existing {
            _ = try await api.apple("PATCH", "\(family.objectPath)/\(existing.id)", body: [
                "data": [
                    "type": Self.resourceType(family),
                    "id": existing.id,
                    "attributes": wanted.body(creating: false),
                ],
            ])
            return existing.id
        }

        var relationships: [String: Any] = [:]
        if let groupID {
            relationships["gameCenterGroup"] = [
                "data": ["type": "gameCenterGroups", "id": groupID],
            ]
        } else {
            relationships["gameCenterDetail"] = [
                "data": ["type": "gameCenterDetails", "id": detailID],
            ]
        }
        relationships["versions"] = [
            "data": [["type": Self.versionResourceType(family)]],
        ]

        let response = try await api.apple("POST", family.objectPath, body: [
            "data": [
                "type": Self.resourceType(family),
                "attributes": wanted.body(creating: true),
                "relationships": relationships,
            ],
        ])
        guard let id = JSON(data: response.data)["data"]["id"].string else {
            throw ConnectionError.invalidResponse
        }
        return id
    }

    /// The states a version is still editable in.
    ///
    /// A localization written onto a version players already have would change
    /// what they are reading now, so anything past review gets a new version
    /// instead. `PREPARE_FOR_SUBMISSION` is the ordinary draft;
    /// `READY_FOR_REVIEW` and the two rejections are drafts a developer is
    /// still holding.
    static let editableVersionStates: Set<String> = [
        "PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "REJECTED", "DEVELOPER_REJECTED",
    ]

    /// The version a localization attaches to.
    ///
    /// A create already made one inline, so this returns that. A version that
    /// is live, in review, or waiting to release is left alone and a new one
    /// takes the change.
    public func ensureVersion(family: Family, objectID: String,
                              existing: Object?) async throws -> String {
        if let versionID = existing?.draftVersionID,
           Self.editableVersionStates.contains(existing?.versionState ?? "PREPARE_FOR_SUBMISSION") {
            return versionID
        }
        // An object this run created already carries the inline version, so
        // read that rather than making a second one. Only for a new object:
        // for one Apple already holds, the newest version reaching here is a
        // version past editing, and returning it would rewrite what players
        // are reading now.
        if existing == nil, let response = try? await api.apple(
            "GET", "\(family.objectPath)/\(objectID)/versions?limit=1"),
           let id = JSON(data: response.data)["data"][0]["id"].string {
            return id
        }
        let response = try await api.apple("POST", family.versionPath, body: [
            "data": [
                "type": Self.versionResourceType(family),
                "relationships": [
                    Self.versionParent(family): [
                        "data": ["type": Self.resourceType(family), "id": objectID],
                    ],
                ],
            ],
        ])
        guard let id = JSON(data: response.data)["data"]["id"].string else {
            throw ConnectionError.invalidResponse
        }
        return id
    }

    /// One locale of one version.
    @discardableResult
    public func ensureLocalization(family: Family, versionID: String, locale: String,
                                   values: [String: String],
                                   existing: Localization?) async throws -> String {
        if let existing {
            _ = try await api.apple(
                "PATCH", "\(Self.localizationPath(family))/\(existing.id)", body: [
                    "data": [
                        "type": Self.localizationResourceType(family),
                        "id": existing.id,
                        "attributes": values,
                    ],
                ])
            return existing.id
        }
        var attributes = values
        attributes["locale"] = locale
        let response = try await api.apple("POST", Self.localizationPath(family), body: [
            "data": [
                "type": Self.localizationResourceType(family),
                "attributes": attributes,
                "relationships": [
                    "version": [
                        "data": ["type": Self.versionResourceType(family), "id": versionID],
                    ],
                ],
            ],
        ])
        guard let id = JSON(data: response.data)["data"]["id"].string else {
            throw ConnectionError.invalidResponse
        }
        return id
    }

    /// The address a player without the game is sent to.
    ///
    /// Apple keeps it on the activity's version and not on the activity, so it
    /// is written here rather than in `ensureObject`. Challenges have no twin.
    public func setActivityFallbackURL(versionID: String, _ url: String) async throws {
        _ = try await api.apple("PATCH", "/v1/gameCenterActivityVersions/\(versionID)", body: [
            "data": [
                "type": "gameCenterActivityVersions",
                "id": versionID,
                "attributes": ["fallbackUrl": url],
            ],
        ])
    }

    // MARK: - The images

    /// What an image hangs from: one locale, or the version every locale falls
    /// back to.
    public enum ImageParent: Sendable, Equatable {
        case localization(String)
        case version(String)
    }

    /// Reserves one image, and answers its id and the operations that carry
    /// the bytes.
    ///
    /// The upload itself belongs to the runner, which already holds the helper
    /// every other upload in the app goes through: the retries, the progress
    /// and the cancellation are one implementation and not six.
    public func reserveImage(family: Family, parent: ImageParent, fileName: String,
                             fileSize: Int) async throws -> (id: String, operations: JSON) {
        let relationship: (name: String, type: String, id: String) = switch parent {
        case .localization(let id): ("localization", Self.localizationResourceType(family), id)
        case .version(let id): ("version", Self.versionResourceType(family), id)
        }
        let response = try await api.apple("POST", family.imagePath, body: [
            "data": [
                "type": family.imageResourceType,
                "attributes": ["fileName": fileName, "fileSize": fileSize],
                "relationships": [
                    relationship.name: [
                        "data": ["type": relationship.type, "id": relationship.id],
                    ],
                ],
            ],
        ])
        let payload = JSON(data: response.data)
        guard let id = payload["data"]["id"].string else {
            throw ConnectionError.invalidResponse
        }
        return (id, payload["data"]["attributes"]["uploadOperations"])
    }

    /// Tells Apple the bytes are there.
    ///
    /// `uploaded` and nothing else. The Game Center image update request takes
    /// no checksum, which is why the plan compares a file name and a byte
    /// count instead of one.
    public func finishImage(family: Family, id: String) async throws {
        _ = try await api.apple("PATCH", "\(family.imagePath)/\(id)", body: [
            "data": [
                "type": family.imageResourceType,
                "id": id,
                "attributes": ["uploaded": true],
            ],
        ])
    }

    /// Removes the picture Apple holds, which is what a replacement starts
    /// with: Apple keeps one image per localization.
    public func deleteImage(family: Family, id: String) async throws {
        _ = try await api.apple("DELETE", "\(family.imagePath)/\(id)")
    }

    /// The boards inside a set.
    ///
    /// The difference, never the whole list. A `PATCH` on this path replaces
    /// it, and a replace written from a stale read drops a leaderboard the
    /// developer added in the console that morning.
    public func setMembers(setID: String, add: [String], remove: [String]) async throws {
        let path = "/v2/gameCenterLeaderboardSets/\(setID)/relationships/gameCenterLeaderboards"
        try await link(path: path, type: "gameCenterLeaderboards", add: add, remove: remove)
    }

    /// What an activity awards and scores to.
    ///
    /// The `V2` relationships. Their v1 twins are deprecated and this app calls
    /// none of them.
    public func setActivityLinks(activityID: String,
                                 achievements: (add: [String], remove: [String]),
                                 leaderboards: (add: [String], remove: [String])) async throws {
        try await link(
            path: "/v1/gameCenterActivities/\(activityID)/relationships/achievementsV2",
            type: "gameCenterAchievements",
            add: achievements.add, remove: achievements.remove)
        try await link(
            path: "/v1/gameCenterActivities/\(activityID)/relationships/leaderboardsV2",
            type: "gameCenterLeaderboards",
            add: leaderboards.add, remove: leaderboards.remove)
    }

    /// The board a challenge scores from.
    ///
    /// `leaderboardV2`, never `leaderboard`. The unsuffixed relationship is the
    /// deprecated v1 twin.
    public func setChallengeLeaderboard(challengeID: String,
                                        leaderboardID: String) async throws {
        _ = try await api.apple(
            "PATCH", "/v1/gameCenterChallenges/\(challengeID)/relationships/leaderboardV2",
            body: ["data": ["type": "gameCenterLeaderboards", "id": leaderboardID]])
    }

    /// Removes an object from App Store Connect.
    ///
    /// Never a plan step. It is the destructive button on the card, because
    /// Apple discards every score and every earned achievement behind the
    /// object and no call brings them back.
    public func delete(family: Family, id: String) async throws {
        _ = try await api.apple("DELETE", "\(family.objectPath)/\(id)")
    }

    /// Removes one member name a set no longer wants. Apple left this delete
    /// live and deprecated the create beside it.
    public func deleteMemberLocalization(id: String) async throws {
        _ = try await api.apple(
            "DELETE", "/v1/gameCenterLeaderboardSetMemberLocalizations/\(id)")
    }

    // MARK: - Test data

    /// Posts one score for one player, or one achievement's progress.
    ///
    /// **Neither one is a manifest value and neither ever appears in a plan.**
    /// They are the developer's own tool for checking that a board formats a
    /// score the way the game expects, and that an achievement unlocks where
    /// they think it does.
    ///
    /// `preReleased` says which side the entry lands on. It defaults to true
    /// everywhere in this app, so a mistaken press reaches the prerelease data
    /// and not the board that players are on.
    public func submitScore(bundleID: String, vendorIdentifier: String,
                            scopedPlayerID: String, score: Double,
                            preReleased: Bool = true) async throws {
        _ = try await api.apple("POST", "/v1/gameCenterLeaderboardEntrySubmissions", body: [
            "data": [
                "type": "gameCenterLeaderboardEntrySubmissions",
                "attributes": [
                    "bundleId": bundleID,
                    "vendorIdentifier": vendorIdentifier,
                    "scopedPlayerId": scopedPlayerID,
                    "score": score,
                    "preReleased": preReleased,
                ],
            ],
        ])
    }

    /// Posts achievement progress for one player, as a percentage.
    public func submitAchievement(bundleID: String, vendorIdentifier: String,
                                  scopedPlayerID: String, percentage: Int,
                                  preReleased: Bool = true) async throws {
        _ = try await api.apple("POST", "/v1/gameCenterPlayerAchievementSubmissions", body: [
            "data": [
                "type": "gameCenterPlayerAchievementSubmissions",
                "attributes": [
                    "bundleId": bundleID,
                    "vendorIdentifier": vendorIdentifier,
                    "scopedPlayerId": scopedPlayerID,
                    "percentageAchieved": percentage,
                    "preReleased": preReleased,
                ],
            ],
        ])
    }

    private func link(path: String, type: String,
                      add: [String], remove: [String]) async throws {
        if !add.isEmpty {
            _ = try await api.apple("POST", path,
                                    body: ["data": add.map { ["type": type, "id": $0] }])
        }
        if !remove.isEmpty {
            _ = try await api.apple("DELETE", path,
                                    body: ["data": remove.map { ["type": type, "id": $0] }])
        }
    }

    // MARK: - The resource names

    /// The `type` Apple wants in a request body. It is the plural resource
    /// name, and it is **not** the path: the v2 achievement path is
    /// `/v2/gameCenterAchievements` and the type on it is still
    /// `gameCenterAchievements`, with no version in it.
    static func resourceType(_ family: Family) -> String {
        switch family {
        case .achievement: "gameCenterAchievements"
        case .leaderboard: "gameCenterLeaderboards"
        case .leaderboardSet: "gameCenterLeaderboardSets"
        case .activity: "gameCenterActivities"
        case .challenge: "gameCenterChallenges"
        }
    }

    static func versionResourceType(_ family: Family) -> String {
        switch family {
        case .achievement: "gameCenterAchievementVersions"
        case .leaderboard: "gameCenterLeaderboardVersions"
        case .leaderboardSet: "gameCenterLeaderboardSetVersions"
        case .activity: "gameCenterActivityVersions"
        case .challenge: "gameCenterChallengeVersions"
        }
    }

    /// What a version calls its own object in a relationship.
    static func versionParent(_ family: Family) -> String {
        switch family {
        case .achievement: "gameCenterAchievement"
        case .leaderboard: "gameCenterLeaderboard"
        case .leaderboardSet: "gameCenterLeaderboardSet"
        case .activity: "gameCenterActivity"
        case .challenge: "gameCenterChallenge"
        }
    }

    static func localizationPath(_ family: Family) -> String {
        switch family {
        case .achievement: "/v2/gameCenterAchievementLocalizations"
        case .leaderboard: "/v2/gameCenterLeaderboardLocalizations"
        case .leaderboardSet: "/v2/gameCenterLeaderboardSetLocalizations"
        case .activity: "/v1/gameCenterActivityLocalizations"
        case .challenge: "/v1/gameCenterChallengeLocalizations"
        }
    }

    static func localizationResourceType(_ family: Family) -> String {
        switch family {
        case .achievement: "gameCenterAchievementLocalizations"
        case .leaderboard: "gameCenterLeaderboardLocalizations"
        case .leaderboardSet: "gameCenterLeaderboardSetLocalizations"
        case .activity: "gameCenterActivityLocalizations"
        case .challenge: "gameCenterChallengeLocalizations"
        }
    }

    // MARK: - The private half

    /// One object out of a `data` item. Nil when it carries no vendor id.
    private static func parse(_ item: JSON) -> Object? {
        guard let id = item["id"].string else { return nil }
        let attributes = item["attributes"]
        guard let vendor = attributes["vendorIdentifier"].string, !vendor.isEmpty else {
            return nil
        }

        var object = Object(id: id, vendorIdentifier: vendor)
        object.referenceName = attributes["referenceName"].string
        object.archived = attributes["archived"].bool
        // Everything else, as text. `keys` is empty for a missing attributes
        // block, so this is safe on a sparse answer.
        for key in attributes.keys where key != "vendorIdentifier" {
            guard let text = Self.text(attributes[key]) else { continue }
            object.attributes[key] = text
        }
        return object
    }

    /// A scalar as text. Anything else, an array or a nested object, is left
    /// out rather than stringified into something nobody can read.
    private static func text(_ value: JSON) -> String? {
        if let string = value.string { return string }
        if let bool = value.bool { return bool ? "true" : "false" }
        if let int = value.int { return String(int) }
        if let double = value.double { return String(double) }
        return nil
    }

    /// The newest version of one object, and that version's localizations.
    ///
    /// Every read here is optional. A version list that fails leaves the object
    /// with the attributes it already has, which is what the panel needs to say
    /// the object exists.
    private func fill(_ object: inout Object, family: Family) async {
        // Activities and challenges carry a second picture on the version
        // itself, which is the one the manifest's top-level `image:` writes.
        // The include costs nothing and is what tells a changed file from the
        // one Apple holds.
        var versionsPath = "\(family.objectPath)/\(object.id)/versions?limit=200"
        if family.hasDefaultImage { versionsPath += "&include=defaultImage" }
        var versionsResponse = try? await api.apple("GET", versionsPath)
        if versionsResponse == nil, family.hasDefaultImage {
            versionsResponse = try? await api.apple(
                "GET", "\(family.objectPath)/\(object.id)/versions?limit=200")
        }
        guard let response = versionsResponse else { return }
        let payload = JSON(data: response.data)

        // The newest version is the one a localization attaches to. Apple
        // returns them newest first, and the fallback is simply the first.
        let versions = payload["data"].array
        guard let newest = versions.first, let versionID = newest["id"].string else {
            return
        }
        object.draftVersionID = versionID
        object.versionState = newest["attributes"]["state"].string

        if let imageID = newest["relationships"]["defaultImage"]["data"]["id"].string {
            let files = Self.imageFiles(payload["included"])
            object.defaultImageID = imageID
            object.defaultImageFileName = files[imageID]?.name
            object.defaultImageFileSize = files[imageID]?.size
        }

        // `include=image` is what keeps the plan quiet about pictures: without
        // it the app cannot tell the file on disk from the one Apple holds,
        // and every apply would offer to upload every image again. The plain
        // read is the fallback, because an unsupported include is a 400 and
        // losing the whole localization list would be far worse: the plan
        // would then create localizations that exist, and Apple answers 409.
        let path = "\(family.versionPath)/\(versionID)/localizations?limit=200"
        var localeResponse = try? await api.apple("GET", path + "&include=image")
        if localeResponse == nil { localeResponse = try? await api.apple("GET", path) }
        guard let localizations = localeResponse else { return }
        let rows = JSON(data: localizations.data)

        let images = Self.imageFiles(rows["included"])
        for item in rows["data"].array {
            guard let id = item["id"].string,
                  let locale = item["attributes"]["locale"].string else { continue }
            var localization = Localization(id: id)
            for key in item["attributes"].keys where key != "locale" {
                guard let text = Self.text(item["attributes"][key]) else { continue }
                localization.values[key] = text
            }
            if let imageID = item["relationships"]["image"]["data"]["id"].string {
                localization.imageID = imageID
                localization.imageFileName = images[imageID]?.name
                localization.imageFileSize = images[imageID]?.size
            }
            object.localizations[locale] = localization
        }
    }

    /// The file name and byte count of every image in an `included` block.
    private static func imageFiles(_ included: JSON) -> [String: (name: String?, size: Int?)] {
        var result: [String: (name: String?, size: Int?)] = [:]
        for item in included.array {
            guard let id = item["id"].string else { continue }
            result[id] = (item["attributes"]["fileName"].string,
                          item["attributes"]["fileSize"].int)
        }
        return result
    }
}
