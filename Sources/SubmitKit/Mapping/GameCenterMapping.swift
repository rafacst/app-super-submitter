import Foundation

/// One object of any Game Center family, flattened out of the manifest and into
/// Apple's own spelling.
///
/// **One mapping, two readers.** The planner compares these against what the
/// store holds and the runner sends them. Two mappings would drift, and the
/// second one always drifts toward a key Apple does not have, which is a 400
/// halfway through an apply.
///
/// The closed values are spelled the way `docs/appstore-connect-api` documents
/// them: `DESC`, `BEST_SCORE`, `SHOW_FOR_ALL`, `SYNCHRONOUS`, `LEADERBOARD`.
/// The manifest spells them the short way a developer reads, and this is the
/// one place the two meet.
struct GameCenterRow {
    typealias Family = AppleGameCenterCatalogClient.Family
    typealias Write = AppleGameCenterCatalogClient.Write

    var family: Family
    /// The vendor identifier. It is the key, never Apple's resource id, and it
    /// is what the game passes to GameKit.
    var id: String
    /// What the plan calls the row: the reference name when there is one.
    var name: String
    var write: Write
    /// Locale code to the attributes Apple takes for that family.
    var locales: [String: [String: String]] = [:]
    /// Locale code to the image path the manifest names, relative to it.
    var images: [String: String] = [:]
    /// The picture on the version, which the two v1 families carry and the
    /// three v2 families do not.
    var defaultImage: String?
    /// The address a player without the game is sent to. Apple keeps it on the
    /// activity's version rather than on the activity.
    var fallbackURL: String?
    /// The leaderboards inside a set, by vendor identifier and in order.
    var members: [String]?
    /// What an activity awards and scores to.
    var linkedAchievements: [String]?
    var linkedLeaderboards: [String]?
    /// The board a challenge scores from.
    var leaderboard: String?
}

extension Manifest.GameCenter {

    /// Every object of one family, in the order the manifest lists them.
    func rows(_ family: AppleGameCenterCatalogClient.Family) -> [GameCenterRow] {
        switch family {
        case .achievement: (achievements ?? []).map(Self.row)
        case .leaderboard: (leaderboards ?? []).map(Self.row)
        case .leaderboardSet: (leaderboardSets ?? []).map(Self.row)
        case .activity: (activities ?? []).map(Self.row)
        case .challenge: (challenges ?? []).map(Self.row)
        }
    }

    // MARK: - The five families

    private static func row(_ object: Achievement) -> GameCenterRow {
        var write = GameCenterRow.Write(vendorIdentifier: object.id)
        write.referenceName = object.name
        write.archived = object.archived
        if let points = object.points { write.numbers["points"] = points }
        if let repeatable = object.repeatable { write.flags["repeatable"] = repeatable }
        if let show = object.showBeforeEarned { write.flags["showBeforeEarned"] = show }
        if let properties = object.properties, !properties.isEmpty {
            write.maps["activityProperties"] = properties
        }

        var made = GameCenterRow(family: .achievement, id: object.id,
                                 name: object.name ?? object.id, write: write)
        for (code, row) in object.locales ?? [:] {
            made.locales[code] = compact([
                "name": row.name,
                "beforeEarnedDescription": row.beforeEarned,
                "afterEarnedDescription": row.afterEarned,
            ])
            made.images[code] = row.image
        }
        return made
    }

    private static func row(_ object: Leaderboard) -> GameCenterRow {
        var write = GameCenterRow.Write(vendorIdentifier: object.id)
        write.referenceName = object.name
        write.archived = object.archived
        if let sort = object.sort {
            write.attributes["scoreSortType"] = sort == .asc ? "ASC" : "DESC"
        }
        if let submission = object.submission {
            write.attributes["submissionType"] =
                submission == .best ? "BEST_SCORE" : "MOST_RECENT_SCORE"
        }
        if let format = object.format { write.attributes["defaultFormatter"] = format }
        if let visibility = object.visibility {
            write.attributes["visibility"] =
                visibility == .all ? "SHOW_FOR_ALL" : "HIDE_FOR_ALL"
        }
        if let range = object.scoreRange, range.count == 2 {
            write.numbers["scoreRangeStart"] = range[0]
            write.numbers["scoreRangeEnd"] = range[1]
        }
        // The duration is an ISO 8601 string and the app compares it as one.
        // Parsing `P1W` into components to compare it with `P7D` would be a
        // calendar of its own, and Apple answers with what it was sent.
        if let recurrence = object.recurrence {
            if let start = recurrence.start {
                write.attributes["recurrenceStartDate"] = start
            }
            if let duration = recurrence.duration {
                write.attributes["recurrenceDuration"] = duration
            }
            if let rule = recurrence.rule { write.attributes["recurrenceRule"] = rule }
        }
        if let properties = object.properties, !properties.isEmpty {
            write.maps["activityProperties"] = properties
        }

        var made = GameCenterRow(family: .leaderboard, id: object.id,
                                 name: object.name ?? object.id, write: write)
        for (code, row) in object.locales ?? [:] {
            made.locales[code] = compact([
                "name": row.name,
                "description": row.description,
                "formatterSuffix": row.suffix,
                "formatterSuffixSingular": row.suffixSingular,
                "formatterOverride": row.format,
            ])
            made.images[code] = row.image
        }
        return made
    }

    private static func row(_ object: LeaderboardSet) -> GameCenterRow {
        var write = GameCenterRow.Write(vendorIdentifier: object.id)
        write.referenceName = object.name

        var made = GameCenterRow(family: .leaderboardSet, id: object.id,
                                 name: object.name ?? object.id, write: write)
        made.members = object.leaderboards
        for (code, row) in object.locales ?? [:] {
            made.locales[code] = compact(["name": row.name])
            made.images[code] = row.image
        }
        return made
    }

    private static func row(_ object: Activity) -> GameCenterRow {
        var write = GameCenterRow.Write(vendorIdentifier: object.id)
        write.referenceName = object.name
        write.archived = object.archived
        if let style = object.playStyle {
            write.attributes["playStyle"] =
                style == .synchronous ? "SYNCHRONOUS" : "ASYNCHRONOUS"
        }
        if let players = object.players, players.count == 2 {
            write.numbers["minimumPlayersCount"] = players[0]
            write.numbers["maximumPlayersCount"] = players[1]
        }
        if let properties = object.properties, !properties.isEmpty {
            write.maps["properties"] = properties
        }

        var made = GameCenterRow(family: .activity, id: object.id,
                                 name: object.name ?? object.id, write: write)
        made.defaultImage = object.image
        made.fallbackURL = object.fallbackUrl
        made.linkedAchievements = object.achievements
        made.linkedLeaderboards = object.leaderboards
        for (code, row) in object.locales ?? [:] {
            made.locales[code] = compact(["name": row.name, "description": row.description])
            made.images[code] = row.image
        }
        return made
    }

    private static func row(_ object: Challenge) -> GameCenterRow {
        var write = GameCenterRow.Write(vendorIdentifier: object.id)
        write.referenceName = object.name
        write.archived = object.archived
        // Apple takes one kind today and spells it in capitals. The manifest
        // holds whatever the developer typed, so this uppercases rather than
        // matching a list: a second kind then still reaches Apple.
        if let type = object.type, !type.isEmpty {
            write.attributes["challengeType"] = type.uppercased()
        }
        if let repeatable = object.repeatable { write.flags["repeatable"] = repeatable }

        var made = GameCenterRow(family: .challenge, id: object.id,
                                 name: object.name ?? object.id, write: write)
        made.defaultImage = object.image
        made.leaderboard = object.leaderboard
        for (code, row) in object.locales ?? [:] {
            made.locales[code] = compact(["name": row.name, "description": row.description])
            made.images[code] = row.image
        }
        return made
    }

    /// The named values only. An absent key means "do not manage", so it never
    /// becomes an empty string that would blank what Apple holds.
    private static func compact(_ values: [String: String?]) -> [String: String] {
        values.compactMapValues { $0 }.filter { !$0.value.isEmpty }
    }
}
