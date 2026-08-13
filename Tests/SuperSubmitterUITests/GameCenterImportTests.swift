import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// Bringing a game that already ships into `store.yaml`.
///
/// The read answers with Apple's own spelling of every closed value, and the
/// docs mirror on disk documents the endpoints without documenting the
/// attribute names. So the import matches loosely, and these are the checks
/// that the loose matching actually lands the right value rather than quietly
/// writing a default that contradicts the store on screen.
@MainActor
@Suite struct GameCenterImportTests {

    private func workspace() throws -> (AppState, URL) {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(ManifestFile.defaultName)
        var manifest = Manifest()
        manifest.setAppleApp(appID: "1", bundleID: "com.studio.game")
        try ManifestFile.save(manifest, to: url)
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        try state.load(from: url)
        return (state, folder)
    }

    private func object(_ vendorID: String, name: String,
                        attributes: [String: String] = [:],
                        localizations: [String: [String: String]] = [:])
        -> AppleGameCenterCatalogClient.Object {
        var made = AppleGameCenterCatalogClient.Object(id: "res-\(vendorID)",
                                                       vendorIdentifier: vendorID)
        made.referenceName = name
        made.attributes = attributes
        for (locale, values) in localizations {
            var row = AppleGameCenterCatalogClient.Localization(id: "loc-\(locale)")
            row.values = values
            made.localizations[locale] = row
        }
        return made
    }

    private func live(_ state: AppState,
                      achievements: [AppleGameCenterCatalogClient.Object] = [],
                      leaderboards: [AppleGameCenterCatalogClient.Object] = []) {
        var block = ActualState.Apple.GameCenter()
        block.read = true
        block.detail = AppleGameCenterClient.Detail(id: "detail-1")
        block.achievements = Dictionary(
            achievements.map { ($0.vendorIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        block.leaderboards = Dictionary(
            leaderboards.map { ($0.vendorIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        var apple = state.actualState.apple ?? ActualState.Apple()
        apple.gameCenter = block
        state.actualState.apple = apple
    }

    // MARK: - What the store holds that the manifest does not

    @Test func onlyTheObjectsTheManifestHasNeverHeardOfAreOffered() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }

        live(state, achievements: [object("a.first", name: "First"),
                                   object("a.second", name: "Second")])
        state.turnOnGameCenter()
        #expect(state.storeOnly(.achievement).count == 2)

        state.importObject(.achievement, object("a.first", name: "First"))
        #expect(state.storeOnly(.achievement).map(\.vendorIdentifier) == ["a.second"])
        // And a second press of the same row changes nothing, because the id
        // is the key and the manifest already holds it.
        state.importObject(.achievement, object("a.first", name: "First"))
        #expect(state.achievements.count == 1)
    }

    @Test func bringingInEveryObjectLeavesNoneBehind() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }

        live(state, achievements: [object("a.one", name: "One"),
                                   object("a.two", name: "Two"),
                                   object("a.three", name: "Three")])
        state.turnOnGameCenter()
        state.importEveryObject(.achievement)

        #expect(state.achievements.count == 3)
        #expect(state.storeOnly(.achievement).isEmpty)
    }

    // MARK: - The mapping itself

    @Test func anAchievementKeepsItsPointsItsSwitchesAndItsWords() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }

        state.turnOnGameCenter()
        state.importObject(.achievement, object(
            "a.first", name: "First win",
            attributes: ["points": "25", "repeatable": "true",
                         "showBeforeEarned": "false"],
            localizations: ["en-US": ["name": "First win",
                                      // Apple's own longer spelling, which the
                                      // manifest calls `beforeEarned`.
                                      "beforeEarnedDescription": "Win a match.",
                                      "afterEarnedDescription": "You won."]]))

        let made = try #require(state.achievements.first)
        #expect(made.id == "a.first")
        #expect(made.name == "First win")
        #expect(made.points == 25)
        #expect(made.repeatable == true)
        #expect(made.showBeforeEarned == false)
        #expect(made.locales?["en-US"]?.beforeEarned == "Win a match.")
        #expect(made.locales?["en-US"]?.afterEarned == "You won.")
    }

    /// The one that would silently lie. A leaderboard that ranks low scores
    /// first, imported as `desc` because the spelling did not match, puts the
    /// wrong answer on screen beside a store that says the opposite.
    @Test func aLeaderboardKeepsApplesOwnSpellingOfEveryClosedValue() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }

        state.turnOnGameCenter()
        state.importObject(.leaderboard, object(
            "l.fastest", name: "Fastest lap",
            attributes: ["scoreSortType": "ASCENDING",
                         "submissionType": "MOST_RECENT_SCORE",
                         "defaultFormatter": "ELAPSED_TIME_CENTISECOND",
                         "visibility": "HIDDEN",
                         "scoreRangeStart": "0", "scoreRangeEnd": "600000"]))

        let made = try #require(state.leaderboards.first)
        #expect(made.sort == .asc)
        #expect(made.submission == .mostRecent)
        #expect(made.format == "ELAPSED_TIME_CENTISECOND")
        #expect(made.visibility == .hidden)
        #expect(made.scoreRange == [0, 600_000])
    }

    @Test func aHighScoreBoardIsNotReadAsALowScoreOne() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }

        state.turnOnGameCenter()
        state.importObject(.leaderboard, object(
            "l.high", name: "High score",
            attributes: ["scoreSortType": "DESCENDING",
                         "submissionType": "BEST_SCORE"]))

        let made = try #require(state.leaderboards.first)
        #expect(made.sort == .desc)
        #expect(made.submission == .best)
    }

    /// An attribute the read never answered with must not become a value.
    /// An absent key means "do not manage", and a default written here would
    /// send a value the developer never chose.
    @Test func anAttributeTheStoreDidNotAnswerWithStaysAbsent() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }

        state.turnOnGameCenter()
        state.importObject(.achievement, object("a.bare", name: "Bare"))

        let made = try #require(state.achievements.first)
        #expect(made.points == nil)
        #expect(made.repeatable == nil)
        #expect(made.showBeforeEarned == nil)
        #expect(made.archived == nil)
        #expect(made.locales == nil)
    }

    @Test func aSetKeepsTheBoardsAppleSaysAreInIt() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }

        state.turnOnGameCenter()
        var set = object("s.all", name: "All boards")
        set.linkedIDs = ["l.high", "l.fastest"]
        state.importObject(.leaderboardSet, set)

        #expect(state.leaderboardSets.first?.leaderboards == ["l.fastest", "l.high"])
    }

    // MARK: - Telling the three read states apart

    @Test func aReadThatFailedIsNotAnAppWithoutAGame() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }

        // Nothing read yet.
        #expect(state.liveGameCenter == nil)
        #expect(!state.gameCenterReadFailed)

        // Read, and this app is simply not a game.
        var apple = ActualState.Apple()
        var block = ActualState.Apple.GameCenter()
        block.read = true
        apple.gameCenter = block
        state.actualState.apple = apple
        #expect(!state.gameCenterReadFailed)
        #expect(state.liveGameCenter?.exists == false)

        // The read failed, and every count on the tab is the manifest alone.
        block.read = false
        apple.gameCenter = block
        state.actualState.apple = apple
        #expect(state.gameCenterReadFailed)
    }
}
