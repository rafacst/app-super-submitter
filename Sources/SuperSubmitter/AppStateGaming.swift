import SubmitKit
import SwiftUI

/// The `gameCenter` block of the Gaming tab.
///
/// Every binding here writes `store.yaml` and calls no store, exactly like the
/// TestFlight block: a Game Center object reaches a player through an App Store
/// version, so the plan on the Summary tab is what decides that anything is
/// sent. `AppleGameCenter.swift` is the other half.
///
/// The bindings are generic on purpose. Five object families carry the same
/// shapes, a text field, a switch, a chosen value, a locale row, and a function
/// per field would be about sixty of them, all the same four lines. One
/// function per shape is what the tab calls, with a key path saying which
/// field. `// ponytail: one binding per shape, not one per field.`
extension AppState {

    var gameCenter: Manifest.GameCenter? { manifest.gameCenter }

    /// Whether the block exists at all. Most apps are not games, so the tab
    /// opens on one sentence and one button until this is true.
    var hasGameCenter: Bool { manifest.gameCenter != nil }

    var achievements: [Manifest.GameCenter.Achievement] { gameCenter?.achievements ?? [] }
    var leaderboards: [Manifest.GameCenter.Leaderboard] { gameCenter?.leaderboards ?? [] }
    var leaderboardSets: [Manifest.GameCenter.LeaderboardSet] {
        gameCenter?.leaderboardSets ?? []
    }
    var gameActivities: [Manifest.GameCenter.Activity] { gameCenter?.activities ?? [] }
    var gameChallenges: [Manifest.GameCenter.Challenge] { gameCenter?.challenges ?? [] }
    var matchmakingRuleSets: [Manifest.GameCenter.RuleSet] {
        gameCenter?.matchmaking?.ruleSets ?? []
    }
    var matchmakingQueues: [Manifest.GameCenter.Queue] {
        gameCenter?.matchmaking?.queues ?? []
    }

    /// The leaderboards a chooser offers: what the game calls them, under the
    /// id the game passes to GameKit.
    ///
    /// A default leaderboard, a set member and a challenge all point at one of
    /// these, and each one used to be a hand-typed id. A chooser cannot be
    /// mistyped, and the validator's "names a leaderboard the manifest does not
    /// hold" then has almost nothing left to catch.
    var leaderboardChoices: [StoreValues.Choice] {
        leaderboards.map { .init($0.id, $0.name?.isEmpty == false ? $0.name! : $0.id) }
    }

    var achievementChoices: [StoreValues.Choice] {
        achievements.map { .init($0.id, $0.name?.isEmpty == false ? $0.name! : $0.id) }
    }

    var ruleSetChoices: [StoreValues.Choice] {
        matchmakingRuleSets.map { .init($0.name, $0.name) }
    }

    // MARK: - What App Store Connect already holds

    /// The last read of the store, or nil before any read has run.
    var liveGameCenter: ActualState.Apple.GameCenter? { actualState.apple?.gameCenter }

    /// Whether the read reached Game Center at all.
    ///
    /// Three states, and the tab has to tell them apart. No read yet, a read
    /// that answered "this app is not a game", and a read that failed. Only the
    /// last one means the numbers on screen are untrustworthy.
    var gameCenterReadFailed: Bool {
        guard let live = liveGameCenter else { return false }
        return !live.read
    }

    /// The object App Store Connect holds under one vendor identifier.
    func liveObject(_ family: AppleGameCenterCatalogClient.Family,
                    _ vendorID: String) -> AppleGameCenterCatalogClient.Object? {
        guard !vendorID.isEmpty else { return nil }
        return liveGameCenter?.objects(family)[vendorID]
    }

    /// The ids the manifest holds for one family.
    func manifestIDs(_ family: AppleGameCenterCatalogClient.Family) -> Set<String> {
        switch family {
        case .achievement: Set(achievements.map(\.id))
        case .leaderboard: Set(leaderboards.map(\.id))
        case .leaderboardSet: Set(leaderboardSets.map(\.id))
        case .activity: Set(gameActivities.map(\.id))
        case .challenge: Set(gameChallenges.map(\.id))
        }
    }

    /// The objects the store holds and the manifest does not.
    ///
    /// This is the whole reason the read is worth having on an editing tab. A
    /// developer whose game already has forty achievements in App Store Connect
    /// sees all forty here, and brings them into `store.yaml` with a button
    /// instead of retyping them.
    func storeOnly(_ family: AppleGameCenterCatalogClient.Family)
        -> [AppleGameCenterCatalogClient.Object] {
        let mine = manifestIDs(family)
        return (liveGameCenter?.objects(family) ?? [:]).values
            .filter { !mine.contains($0.vendorIdentifier) }
            .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
    }

    /// Brings one object the store holds into the manifest.
    ///
    /// It maps what it can read with confidence and leaves the rest. Apple's
    /// own spelling of a closed value is matched loosely on purpose: the read
    /// answers `DESCENDING` where another revision might answer `desc`, and a
    /// strict match would silently drop the field and write a default that
    /// contradicts the store.
    func importObject(_ family: AppleGameCenterCatalogClient.Family,
                      _ object: AppleGameCenterCatalogClient.Object) {
        editGameCenter { block in
            switch family {
            case .achievement:
                var list = block.achievements ?? []
                guard !list.contains(where: { $0.id == object.vendorIdentifier }) else { return }
                list.append(Self.achievement(from: object))
                block.achievements = list
            case .leaderboard:
                var list = block.leaderboards ?? []
                guard !list.contains(where: { $0.id == object.vendorIdentifier }) else { return }
                list.append(Self.leaderboard(from: object))
                block.leaderboards = list
            case .leaderboardSet:
                var list = block.leaderboardSets ?? []
                guard !list.contains(where: { $0.id == object.vendorIdentifier }) else { return }
                list.append(Self.leaderboardSet(from: object))
                block.leaderboardSets = list
            case .activity:
                var list = block.activities ?? []
                guard !list.contains(where: { $0.id == object.vendorIdentifier }) else { return }
                list.append(Self.activity(from: object))
                block.activities = list
            case .challenge:
                var list = block.challenges ?? []
                guard !list.contains(where: { $0.id == object.vendorIdentifier }) else { return }
                list.append(Self.challenge(from: object))
                block.challenges = list
            }
        }
    }

    /// Brings every object of one family across in one press.
    func importEveryObject(_ family: AppleGameCenterCatalogClient.Family) {
        for object in storeOnly(family) { importObject(family, object) }
    }

    // MARK: - Turning it on

    /// Writes `gameCenter.enabled: true` and calls nothing.
    ///
    /// The apply creates the detail in App Store Connect. A tab that made a
    /// store call on its first press would be the only editing tab that does.
    func turnOnGameCenter() {
        guard manifest.gameCenter == nil else { return }
        editGameCenter { $0.enabled = true }
    }

    /// Drops the whole block. Nothing is deleted in App Store Connect: the plan
    /// simply stops managing Game Center, and everything Apple holds stays.
    func removeGameCenter() {
        manifest.gameCenter = nil
        saveManifestReportingErrors()
    }

    // MARK: - The write path

    /// The one place the block is written. Creates it when it is absent, so no
    /// caller has to.
    func editGameCenter(_ edit: (inout Manifest.GameCenter) -> Void) {
        var block = manifest.gameCenter ?? Manifest.GameCenter()
        edit(&block)
        manifest.gameCenter = block
        saveManifestReportingErrors()
    }

    // MARK: - Bindings onto the block itself

    /// A text field on the block. Empty writes no key, because an absent key
    /// means "do not manage" and an empty string means "set it to nothing".
    func gameCenterText(_ field: WritableKeyPath<Manifest.GameCenter, String?>)
        -> Binding<String> {
        Binding(get: { self.gameCenter?[keyPath: field] ?? "" },
                set: { value in
                    let text = value.trimmingCharacters(in: .whitespaces)
                    self.editGameCenter { $0[keyPath: field] = text.isEmpty ? nil : text }
                })
    }

    /// A comma-separated list on the block, for the platform minimums.
    func gameCenterList(_ field: WritableKeyPath<Manifest.GameCenter, [String]?>)
        -> Binding<String> {
        Binding(get: { (self.gameCenter?[keyPath: field] ?? []).joined(separator: ", ") },
                set: { value in
                    let list = Self.splitList(value)
                    self.editGameCenter { $0[keyPath: field] = list.isEmpty ? nil : list }
                })
    }

    // MARK: - Bindings onto one object of a family

    /// A text field on one object of any family.
    func objectText<Object>(_ list: WritableKeyPath<Manifest.GameCenter, [Object]?>,
                            _ index: Int,
                            _ field: WritableKeyPath<Object, String?>) -> Binding<String> {
        Binding(get: { self.object(list, index)?[keyPath: field] ?? "" },
                set: { value in
                    let text = value.trimmingCharacters(in: .whitespaces)
                    self.editObject(list, index) { $0[keyPath: field] = text.isEmpty ? nil : text }
                })
    }

    /// The `id` of an object, which is the one string that is never optional.
    ///
    /// It is the vendor identifier the game passes to GameKit. The tab warns
    /// beside the field rather than blocking the edit, because a developer
    /// renaming one has to be able to type through the middle of a word.
    func objectID<Object>(_ list: WritableKeyPath<Manifest.GameCenter, [Object]?>,
                          _ index: Int,
                          _ field: WritableKeyPath<Object, String>) -> Binding<String> {
        Binding(get: { self.object(list, index)?[keyPath: field] ?? "" },
                set: { value in
                    self.editObject(list, index) {
                        $0[keyPath: field] = value.trimmingCharacters(in: .whitespaces)
                    }
                })
    }

    /// A switch on one object. Touching it writes the key, so the plan sends a
    /// value the developer actually chose.
    func objectFlag<Object>(_ list: WritableKeyPath<Manifest.GameCenter, [Object]?>,
                            _ index: Int,
                            _ field: WritableKeyPath<Object, Bool?>,
                            default fallback: Bool = false) -> Binding<Bool> {
        Binding(get: { self.object(list, index)?[keyPath: field] ?? fallback },
                set: { value in self.editObject(list, index) { $0[keyPath: field] = value } })
    }

    /// A chosen value on one object, where the choice is one of a closed set.
    func objectChoice<Object, Value>(_ list: WritableKeyPath<Manifest.GameCenter, [Object]?>,
                                     _ index: Int,
                                     _ field: WritableKeyPath<Object, Value?>,
                                     default fallback: Value) -> Binding<Value> {
        Binding(get: { self.object(list, index)?[keyPath: field] ?? fallback },
                set: { value in self.editObject(list, index) { $0[keyPath: field] = value } })
    }

    /// A whole number on one object. Empty writes no key.
    func objectNumber<Object>(_ list: WritableKeyPath<Manifest.GameCenter, [Object]?>,
                              _ index: Int,
                              _ field: WritableKeyPath<Object, Int?>) -> Binding<String> {
        Binding(get: { self.object(list, index)?[keyPath: field].map(String.init) ?? "" },
                set: { value in
                    let text = value.trimmingCharacters(in: .whitespaces)
                    self.editObject(list, index) { $0[keyPath: field] = Int(text) }
                })
    }

    /// One end of a pair written as two numbers: a score range, a player count.
    ///
    /// The manifest holds `[0, 1000000]` because that is what the schema says,
    /// and the screen holds two separate boxes, because "the lowest score" and
    /// "the highest score" are two questions. Clearing either one drops the
    /// whole key, since half a range is not a range.
    func objectPair<Object>(_ list: WritableKeyPath<Manifest.GameCenter, [Object]?>,
                            _ index: Int,
                            _ field: WritableKeyPath<Object, [Int]?>,
                            at slot: Int) -> Binding<String> {
        Binding(get: {
            guard let pair = self.object(list, index)?[keyPath: field],
                  pair.indices.contains(slot) else { return "" }
            return String(pair[slot])
        }, set: { value in
            let text = value.trimmingCharacters(in: .whitespaces)
            self.editObject(list, index) { object in
                var pair = object[keyPath: field] ?? [0, 0]
                while pair.count < 2 { pair.append(0) }
                guard let number = Int(text) else {
                    object[keyPath: field] = nil
                    return
                }
                pair[slot] = number
                object[keyPath: field] = pair
            }
        })
    }

    /// A list of ids on one object: the members of a set, the achievements an
    /// activity awards. `MultiChoiceField` writes it as comma-separated text.
    func objectIDList<Object>(_ list: WritableKeyPath<Manifest.GameCenter, [Object]?>,
                              _ index: Int,
                              _ field: WritableKeyPath<Object, [String]?>) -> Binding<String> {
        Binding(get: { (self.object(list, index)?[keyPath: field] ?? []).joined(separator: ", ") },
                set: { value in
                    let ids = Self.splitList(value)
                    self.editObject(list, index) { $0[keyPath: field] = ids.isEmpty ? nil : ids }
                })
    }

    // MARK: - The recurring leaderboard

    /// Whether a board starts over on a schedule.
    ///
    /// A tick box, because that is the question: a board either runs forever or
    /// it repeats. Ticking it writes a recurrence with Apple's own common
    /// answer already in it, and clearing it drops the whole key, so a board
    /// that no longer repeats does not leave a half-written schedule behind.
    func leaderboardRecurs(_ index: Int) -> Binding<Bool> {
        Binding(get: { self.leaderboards[safe: index]?.recurrence != nil },
                set: { value in
                    self.editObject(\.leaderboards, index) { board in
                        board.recurrence = value ? .init(duration: "P1W",
                                                         rule: "FREQ=WEEKLY") : nil
                    }
                })
    }

    func recurrenceText(_ index: Int,
                        _ field: WritableKeyPath<Manifest.GameCenter.Recurrence, String?>)
        -> Binding<String> {
        Binding(get: { self.leaderboards[safe: index]?.recurrence?[keyPath: field] ?? "" },
                set: { value in
                    let text = value.trimmingCharacters(in: .whitespaces)
                    self.editObject(\.leaderboards, index) { board in
                        var recurrence = board.recurrence ?? .init()
                        recurrence[keyPath: field] = text.isEmpty ? nil : text
                        board.recurrence = recurrence
                    }
                })
    }

    // MARK: - Bindings onto one locale row of one object

    /// A text field in one locale of one object.
    ///
    /// The row exists for every locale the listing already holds, so the tab
    /// draws no locale picker of its own and a locale is never added here by
    /// accident. Clearing the last field of a locale drops the locale.
    func localeText<Object, Locale_>(
        _ list: WritableKeyPath<Manifest.GameCenter, [Object]?>,
        _ index: Int,
        _ locales: WritableKeyPath<Object, [String: Locale_]?>,
        _ code: String,
        _ field: WritableKeyPath<Locale_, String?>,
        empty: Locale_) -> Binding<String> {
        Binding(get: {
            self.object(list, index)?[keyPath: locales]?[code]?[keyPath: field] ?? ""
        }, set: { value in
            let text = value.trimmingCharacters(in: .whitespaces)
            self.editObject(list, index) { object in
                var rows = object[keyPath: locales] ?? [:]
                var row = rows[code] ?? empty
                row[keyPath: field] = text.isEmpty ? nil : text
                rows[code] = row
                object[keyPath: locales] = rows
            }
        })
    }

    // MARK: - Adding and removing

    /// A new row carries every value Apple marks required on a create.
    ///
    /// The two switches are written rather than left absent on purpose. Absent
    /// means "do not manage", which is the right default for a row that
    /// already exists in App Store Connect and the wrong one for a row that
    /// does not exist yet: Apple refuses that create, and the developer would
    /// meet the refusal as a red row on a card they had only just added.
    func addAchievement() {
        editGameCenter { block in
            var list = block.achievements ?? []
            list.append(.init(id: Self.newObjectID(prefix: "achievement",
                                                   taken: list.map(\.id)),
                              points: 10, repeatable: false, showBeforeEarned: true))
            block.achievements = list
        }
    }

    func addLeaderboard() {
        editGameCenter { block in
            var list = block.leaderboards ?? []
            list.append(.init(id: Self.newObjectID(prefix: "leaderboard",
                                                   taken: list.map(\.id)),
                              sort: .desc, submission: .best, format: "INTEGER"))
            block.leaderboards = list
        }
    }

    func addLeaderboardSet() {
        editGameCenter { block in
            var list = block.leaderboardSets ?? []
            list.append(.init(id: Self.newObjectID(prefix: "set", taken: list.map(\.id))))
            block.leaderboardSets = list
        }
    }

    func addGameActivity() {
        editGameCenter { block in
            var list = block.activities ?? []
            list.append(.init(id: Self.newObjectID(prefix: "activity", taken: list.map(\.id)),
                              playStyle: .synchronous, players: [2, 4]))
            block.activities = list
        }
    }

    func addGameChallenge() {
        editGameCenter { block in
            var list = block.challenges ?? []
            list.append(.init(id: Self.newObjectID(prefix: "challenge", taken: list.map(\.id)),
                              type: "leaderboard"))
            block.challenges = list
        }
    }

    /// Removes one object of any family.
    ///
    /// It removes the row from the manifest and nothing from App Store Connect.
    /// The object Apple holds keeps every score and every earned achievement,
    /// and the plan simply stops managing it. Archiving is the switch on the
    /// card, and that one does reach the store.
    func removeObject<Object>(_ list: WritableKeyPath<Manifest.GameCenter, [Object]?>,
                              at index: Int) {
        editGameCenter { block in
            var values = block[keyPath: list] ?? []
            guard values.indices.contains(index) else { return }
            values.remove(at: index)
            block[keyPath: list] = values.isEmpty ? nil : values
        }
    }

    // MARK: - Matchmaking

    func addRuleSet() {
        editMatchmaking { block in
            var list = block.ruleSets ?? []
            list.append(.init(name: "Rule set \(list.count + 1)", players: [2, 4],
                              ruleLanguageVersion: 1))
            block.ruleSets = list
        }
    }

    func addQueue() {
        editMatchmaking { block in
            var list = block.queues ?? []
            list.append(.init(name: "Queue \(list.count + 1)",
                              ruleSet: self.matchmakingRuleSets.first?.name))
            block.queues = list
        }
    }

    func removeRuleSet(at index: Int) {
        editMatchmaking { block in
            var list = block.ruleSets ?? []
            guard list.indices.contains(index) else { return }
            list.remove(at: index)
            block.ruleSets = list.isEmpty ? nil : list
        }
    }

    func removeQueue(at index: Int) {
        editMatchmaking { block in
            var list = block.queues ?? []
            guard list.indices.contains(index) else { return }
            list.remove(at: index)
            block.queues = list.isEmpty ? nil : list
        }
    }

    func addRule(ruleSet index: Int) {
        editRuleSet(index) { set in
            var rules = set.rules ?? []
            rules.append(.init(name: "Rule \(rules.count + 1)", type: "COMPATIBLE",
                               weight: 1))
            set.rules = rules
        }
    }

    func removeRule(ruleSet index: Int, at rule: Int) {
        editRuleSet(index) { set in
            var rules = set.rules ?? []
            guard rules.indices.contains(rule) else { return }
            rules.remove(at: rule)
            set.rules = rules.isEmpty ? nil : rules
        }
    }

    func addTeam(ruleSet index: Int) {
        editRuleSet(index) { set in
            var teams = set.teams ?? []
            teams.append(.init(name: "Team \(teams.count + 1)", players: [1, 1]))
            set.teams = teams
        }
    }

    func removeTeam(ruleSet index: Int, at team: Int) {
        editRuleSet(index) { set in
            var teams = set.teams ?? []
            guard teams.indices.contains(team) else { return }
            teams.remove(at: team)
            set.teams = teams.isEmpty ? nil : teams
        }
    }

    /// A text field on a rule set, a queue, a rule, or a team.
    ///
    /// Matchmaking hangs two levels deep, so it takes its own pair of helpers
    /// rather than the object ones above: a rule belongs to a rule set, not to
    /// the block.
    func ruleSetText(_ index: Int,
                     _ field: WritableKeyPath<Manifest.GameCenter.RuleSet, String>)
        -> Binding<String> {
        Binding(get: { self.matchmakingRuleSets[safe: index]?[keyPath: field] ?? "" },
                set: { value in
                    self.editRuleSet(index) {
                        $0[keyPath: field] = value.trimmingCharacters(in: .whitespaces)
                    }
                })
    }

    func ruleSetPair(_ index: Int, at slot: Int) -> Binding<String> {
        Binding(get: {
            guard let pair = self.matchmakingRuleSets[safe: index]?.players,
                  pair.indices.contains(slot) else { return "" }
            return String(pair[slot])
        }, set: { value in
            self.editRuleSet(index) { set in
                var pair = set.players ?? [0, 0]
                while pair.count < 2 { pair.append(0) }
                guard let number = Int(value.trimmingCharacters(in: .whitespaces)) else {
                    set.players = nil
                    return
                }
                pair[slot] = number
                set.players = pair
            }
        })
    }

    func ruleText(_ index: Int, _ rule: Int,
                  _ field: WritableKeyPath<Manifest.GameCenter.Rule, String?>)
        -> Binding<String> {
        Binding(get: {
            self.matchmakingRuleSets[safe: index]?.rules?[safe: rule]?[keyPath: field] ?? ""
        }, set: { value in
            let text = value.trimmingCharacters(in: .whitespaces)
            self.editRuleSet(index) { set in
                guard set.rules?.indices.contains(rule) == true else { return }
                set.rules?[rule][keyPath: field] = text.isEmpty ? nil : text
            }
        })
    }

    func ruleName(_ index: Int, _ rule: Int) -> Binding<String> {
        Binding(get: { self.matchmakingRuleSets[safe: index]?.rules?[safe: rule]?.name ?? "" },
                set: { value in
                    self.editRuleSet(index) { set in
                        guard set.rules?.indices.contains(rule) == true else { return }
                        set.rules?[rule].name = value.trimmingCharacters(in: .whitespaces)
                    }
                })
    }

    func teamName(_ index: Int, _ team: Int) -> Binding<String> {
        Binding(get: { self.matchmakingRuleSets[safe: index]?.teams?[safe: team]?.name ?? "" },
                set: { value in
                    self.editRuleSet(index) { set in
                        guard set.teams?.indices.contains(team) == true else { return }
                        set.teams?[team].name = value.trimmingCharacters(in: .whitespaces)
                    }
                })
    }

    func teamPair(_ index: Int, _ team: Int, at slot: Int) -> Binding<String> {
        Binding(get: {
            guard let pair = self.matchmakingRuleSets[safe: index]?.teams?[safe: team]?.players,
                  pair.indices.contains(slot) else { return "" }
            return String(pair[slot])
        }, set: { value in
            self.editRuleSet(index) { set in
                guard set.teams?.indices.contains(team) == true else { return }
                var pair = set.teams?[team].players ?? [0, 0]
                while pair.count < 2 { pair.append(0) }
                guard let number = Int(value.trimmingCharacters(in: .whitespaces)) else {
                    set.teams?[team].players = nil
                    return
                }
                pair[slot] = number
                set.teams?[team].players = pair
            }
        })
    }

    func queueText(_ index: Int,
                   _ field: WritableKeyPath<Manifest.GameCenter.Queue, String?>)
        -> Binding<String> {
        Binding(get: { self.matchmakingQueues[safe: index]?[keyPath: field] ?? "" },
                set: { value in
                    let text = value.trimmingCharacters(in: .whitespaces)
                    self.editMatchmaking { block in
                        guard block.queues?.indices.contains(index) == true else { return }
                        block.queues?[index][keyPath: field] = text.isEmpty ? nil : text
                    }
                })
    }

    /// The bundle ids of older releases that share a queue.
    func queueBundleIDs(_ index: Int) -> Binding<String> {
        Binding(get: {
            (self.matchmakingQueues[safe: index]?.classicBundleIds ?? [])
                .joined(separator: ", ")
        }, set: { value in
            let list = Self.splitList(value)
            self.editMatchmaking { block in
                guard block.queues?.indices.contains(index) == true else { return }
                block.queues?[index].classicBundleIds = list.isEmpty ? nil : list
            }
        })
    }

    /// Which revision of Apple's rule language a set's expressions are written
    /// in.
    func ruleSetLanguageVersion(_ index: Int) -> Binding<String> {
        Binding(get: {
            self.matchmakingRuleSets[safe: index]?.ruleLanguageVersion.map(String.init) ?? ""
        }, set: { value in
            self.editRuleSet(index) {
                $0.ruleLanguageVersion = Int(value.trimmingCharacters(in: .whitespaces))
            }
        })
    }

    /// How much one rule counts against the others.
    func ruleWeight(_ index: Int, _ rule: Int) -> Binding<String> {
        Binding(get: {
            self.matchmakingRuleSets[safe: index]?.rules?[safe: rule]?.weight
                .map { String(format: "%g", $0) } ?? ""
        }, set: { value in
            self.editRuleSet(index) { set in
                guard set.rules?.indices.contains(rule) == true else { return }
                set.rules?[rule].weight = Double(value.trimmingCharacters(in: .whitespaces))
            }
        })
    }

    func queueName(_ index: Int) -> Binding<String> {
        Binding(get: { self.matchmakingQueues[safe: index]?.name ?? "" },
                set: { value in
                    self.editMatchmaking { block in
                        guard block.queues?.indices.contains(index) == true else { return }
                        block.queues?[index].name = value.trimmingCharacters(in: .whitespaces)
                    }
                })
    }

    // MARK: - The private half

    /// One object of a family, or nil when the index has moved under a row that
    /// is still on screen.
    private func object<Object>(_ list: WritableKeyPath<Manifest.GameCenter, [Object]?>,
                                _ index: Int) -> Object? {
        guard let values = gameCenter?[keyPath: list], values.indices.contains(index) else {
            return nil
        }
        return values[index]
    }

    private func editObject<Object>(_ list: WritableKeyPath<Manifest.GameCenter, [Object]?>,
                                    _ index: Int,
                                    _ edit: (inout Object) -> Void) {
        editGameCenter { block in
            guard var values = block[keyPath: list], values.indices.contains(index) else {
                return
            }
            edit(&values[index])
            block[keyPath: list] = values
        }
    }

    private func editMatchmaking(_ edit: (inout Manifest.GameCenter.Matchmaking) -> Void) {
        editGameCenter { block in
            var value = block.matchmaking ?? Manifest.GameCenter.Matchmaking()
            edit(&value)
            block.matchmaking = value
        }
    }

    private func editRuleSet(_ index: Int,
                             _ edit: (inout Manifest.GameCenter.RuleSet) -> Void) {
        editMatchmaking { block in
            guard block.ruleSets?.indices.contains(index) == true else { return }
            edit(&block.ruleSets![index])
        }
    }

    /// A starting id that reads like the ones a developer writes, and that no
    /// row already holds.
    ///
    /// It is built from the app's own bundle id when there is one, because a
    /// vendor identifier is global across the account and `first_win` alone
    /// collides with the next game in the same studio.
    private static func newObjectID(prefix: String, taken: [String]) -> String {
        let base = "\(prefix)_\(taken.count + 1)"
        guard taken.contains(base) else { return base }
        var number = taken.count + 2
        while taken.contains("\(prefix)_\(number)") { number += 1 }
        return "\(prefix)_\(number)"
    }

    // MARK: - Reading one store object into a manifest one

    private typealias LiveObject = AppleGameCenterCatalogClient.Object

    private static func achievement(from object: LiveObject)
        -> Manifest.GameCenter.Achievement {
        var made = Manifest.GameCenter.Achievement(id: object.vendorIdentifier)
        made.name = object.referenceName
        made.points = attribute(object, "points").flatMap(Int.init)
        made.repeatable = flag(object, "repeatable")
        made.showBeforeEarned = flag(object, "showBeforeEarned")
        made.archived = object.archived
        made.locales = locales(object) { texts in
            var row = Manifest.GameCenter.AchievementLocale()
            row.name = text(texts, "name")
            row.beforeEarned = text(texts, "beforeEarned")
            row.afterEarned = text(texts, "afterEarned")
            return row
        }
        return made
    }

    private static func leaderboard(from object: LiveObject)
        -> Manifest.GameCenter.Leaderboard {
        var made = Manifest.GameCenter.Leaderboard(id: object.vendorIdentifier)
        made.name = object.referenceName
        // Loose matching on purpose. Apple answers a closed value in its own
        // spelling, and a strict compare that missed would write a default that
        // contradicts the store the developer is looking at.
        if let sort = attribute(object, "scoreSortType", "sortType", "sort") {
            made.sort = sort.localizedCaseInsensitiveContains("asc") ? .asc : .desc
        }
        if let submission = attribute(object, "submissionType", "submission") {
            made.submission = submission.localizedCaseInsensitiveContains("recent")
                ? .mostRecent : .best
        }
        made.format = attribute(object, "defaultFormatter", "formatter", "format")
        if let visibility = attribute(object, "visibility") {
            made.visibility = visibility.localizedCaseInsensitiveContains("hidden")
                ? .hidden : .all
        }
        let low = attribute(object, "scoreRangeStart", "minimumScore").flatMap(Int.init)
        let high = attribute(object, "scoreRangeEnd", "maximumScore").flatMap(Int.init)
        if let low, let high { made.scoreRange = [low, high] }
        made.archived = object.archived
        made.locales = locales(object) { texts in
            var row = Manifest.GameCenter.LeaderboardLocale()
            row.name = text(texts, "name")
            row.description = text(texts, "description")
            row.suffix = text(texts, "suffix")
            row.suffixSingular = text(texts, "singular")
            row.format = text(texts, "formatterOverride")
            return row
        }
        return made
    }

    private static func leaderboardSet(from object: LiveObject)
        -> Manifest.GameCenter.LeaderboardSet {
        var made = Manifest.GameCenter.LeaderboardSet(id: object.vendorIdentifier)
        made.name = object.referenceName
        let members = object.linkedIDs.sorted()
        made.leaderboards = members.isEmpty ? nil : members
        made.locales = locales(object) { texts in
            var row = Manifest.GameCenter.SetLocale()
            row.name = text(texts, "name")
            return row
        }
        return made
    }

    private static func activity(from object: LiveObject) -> Manifest.GameCenter.Activity {
        var made = Manifest.GameCenter.Activity(id: object.vendorIdentifier)
        made.name = object.referenceName
        if let style = attribute(object, "playStyle") {
            made.playStyle = style.localizedCaseInsensitiveContains("async")
                ? .asynchronous : .synchronous
        }
        let low = attribute(object, "minimumPlayersCount", "minPlayers").flatMap(Int.init)
        let high = attribute(object, "maximumPlayersCount", "maxPlayers").flatMap(Int.init)
        if let low, let high { made.players = [low, high] }
        made.fallbackUrl = attribute(object, "fallbackURL", "fallbackUrl")
        made.archived = object.archived
        made.locales = locales(object) { texts in
            var row = Manifest.GameCenter.ActivityLocale()
            row.name = text(texts, "name")
            row.description = text(texts, "description")
            return row
        }
        return made
    }

    private static func challenge(from object: LiveObject)
        -> Manifest.GameCenter.Challenge {
        var made = Manifest.GameCenter.Challenge(id: object.vendorIdentifier)
        made.name = object.referenceName
        made.type = attribute(object, "challengeType", "type")
        made.repeatable = flag(object, "repeatable")
        made.archived = object.archived
        made.locales = locales(object) { texts in
            var row = Manifest.GameCenter.ChallengeLocale()
            row.name = text(texts, "name")
            row.description = text(texts, "description")
            return row
        }
        return made
    }

    private static func attribute(_ object: LiveObject, _ names: String...) -> String? {
        text(object.attributes, names)
    }

    private static func flag(_ object: LiveObject, _ name: String) -> Bool? {
        switch attribute(object, name)?.lowercased() {
        case "true": true
        case "false": false
        default: nil
        }
    }

    /// One value out of a bag of them, by exact key, then by case, then by
    /// substring.
    ///
    /// The substring pass is what catches Apple naming a field
    /// `beforeEarnedDescription` where the manifest calls it `beforeEarned`.
    /// The mirror on disk documents the endpoints and not the attribute names,
    /// so the reader matches rather than assumes.
    ///
    /// `// ponytail: three passes over a handful of keys. Pin the exact names
    /// // when a response is in front of you.`
    private static func text(_ values: [String: String], _ names: [String]) -> String? {
        for name in names {
            if let match = values[name], !match.isEmpty { return match }
        }
        for name in names {
            let key = values.keys.first {
                $0.compare(name, options: .caseInsensitive) == .orderedSame
            }
            if let key, let match = values[key], !match.isEmpty { return match }
        }
        for name in names {
            let key = values.keys.first { $0.localizedCaseInsensitiveContains(name) }
            if let key, let match = values[key], !match.isEmpty { return match }
        }
        return nil
    }

    private static func text(_ values: [String: String], _ name: String) -> String? {
        text(values, [name])
    }

    /// The locale rows of one object, built by the family's own mapping.
    ///
    /// Returns nil rather than an empty map, because an absent key means "do
    /// not manage" and an empty one would start managing nothing.
    private static func locales<Row>(_ object: LiveObject,
                                     _ build: ([String: String]) -> Row) -> [String: Row]? {
        guard !object.localizations.isEmpty else { return nil }
        var rows: [String: Row] = [:]
        for (code, localization) in object.localizations {
            rows[code] = build(localization.values)
        }
        return rows
    }
}
