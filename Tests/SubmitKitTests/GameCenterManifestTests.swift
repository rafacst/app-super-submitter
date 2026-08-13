import Foundation
import Testing
@testable import SubmitKit

/// The `gameCenter` block, from the Gaming tab.
///
/// The block is a schema and nothing else at this stage, so these are the
/// checks that catch a schema that stops meaning what the tab writes: a key
/// that no longer round-trips through YAML, an absent key that starts arriving
/// as a value, and a block that leaks into another tab's slice.
private func game() -> Manifest {
    var manifest = Manifest()
    manifest.setAppleApp(appID: "1", bundleID: "com.studio.game")
    manifest.addLocale("en-US", name: "Game")
    manifest.gameCenter = Manifest.GameCenter(
        enabled: true,
        group: "Studio shared",
        defaultLeaderboard: "com.studio.game.high_score",
        appVersions: ["1.4.0": .init(enabled: true, compatibility: ["1.3.0"])],
        achievements: [
            .init(id: "com.studio.game.first_win", name: "First win", points: 10,
                  repeatable: false, showBeforeEarned: true,
                  locales: ["en-US": .init(name: "First win",
                                           beforeEarned: "Win a match.",
                                           afterEarned: "You won a match.",
                                           image: "art/gc/first_win.png")]),
        ],
        leaderboards: [
            .init(id: "com.studio.game.high_score", name: "High score", sort: .desc,
                  submission: .best, format: "INTEGER", scoreRange: [0, 1_000_000],
                  visibility: .all,
                  recurrence: .init(start: "2026-09-01T00:00:00Z", duration: "P1W",
                                    rule: "FREQ=WEEKLY")),
        ],
        leaderboardSets: [
            .init(id: "com.studio.game.all_boards", name: "All boards",
                  leaderboards: ["com.studio.game.high_score"]),
        ],
        activities: [
            .init(id: "com.studio.game.coop_raid", playStyle: .synchronous,
                  players: [2, 4], achievements: ["com.studio.game.first_win"]),
        ],
        challenges: [
            .init(id: "com.studio.game.weekly_duel", type: "leaderboard",
                  leaderboard: "com.studio.game.high_score", repeatable: true),
        ],
        matchmaking: .init(
            ruleSets: [.init(name: "Ranked 2v2", players: [4, 4],
                             ruleLanguageVersion: 1,
                             teams: [.init(name: "Blue", players: [2, 2])],
                             rules: [.init(name: "Skill spread", type: "COMPATIBLE",
                                           expression: "abs(a - b) < 200", weight: 1)])],
            queues: [.init(name: "Ranked", ruleSet: "Ranked 2v2")]))
    return manifest
}

@Test func theGameCenterBlockSurvivesAYAMLRoundTrip() throws {
    let restored = try ManifestFile.decode(ManifestFile.encode(game()))
    let block = try #require(restored.gameCenter)

    #expect(block.enabled == true)
    #expect(block.group == "Studio shared")
    #expect(block.appVersions?["1.4.0"]?.compatibility == ["1.3.0"])
    // The whole point of the closed value sets: a spelling that stops decoding
    // is a field the tab can no longer write.
    #expect(block.leaderboards?.first?.sort == .desc)
    #expect(block.leaderboards?.first?.submission == .best)
    #expect(block.leaderboards?.first?.visibility == .all)
    #expect(block.leaderboards?.first?.scoreRange == [0, 1_000_000])
    #expect(block.leaderboards?.first?.recurrence?.rule == "FREQ=WEEKLY")
    #expect(block.activities?.first?.playStyle == .synchronous)
    #expect(block.activities?.first?.players == [2, 4])
    #expect(block.achievements?.first?.locales?["en-US"]?.beforeEarned == "Win a match.")
    #expect(block.matchmaking?.ruleSets?.first?.teams?.first?.name == "Blue")
    #expect(block.matchmaking?.ruleSets?.first?.rules?.first?.weight == 1)
    #expect(block.matchmaking?.queues?.first?.ruleSet == "Ranked 2v2")
}

/// An absent key means "do not manage", and it has to stay absent all the way
/// through the file. `archived: false` sends a value; no `archived` key sends
/// none, and the two are different instructions to the store.
@Test func aKeyTheManifestLeavesOutIsStillAbsentAfterARoundTrip() throws {
    var manifest = Manifest()
    manifest.gameCenter = Manifest.GameCenter(
        achievements: [.init(id: "com.studio.game.first_win")])

    let yaml = try ManifestFile.encode(manifest)
    #expect(!yaml.contains("archived"))
    #expect(!yaml.contains("repeatable"))

    let restored = try ManifestFile.decode(yaml)
    #expect(restored.gameCenter?.achievements?.first?.archived == nil)
    #expect(restored.gameCenter?.achievements?.first?.points == nil)
}

@Test func theGamingBlockHoldsGameCenterAndNothingElse() throws {
    #expect(ManifestBlock.gaming.keys == ["gameCenter"])

    let yaml = try ManifestFile.encode(game(), block: .gaming)
    #expect(yaml.contains("gameCenter:"))
    #expect(!yaml.contains("apps:"))
    #expect(!yaml.contains("listing:"))

    // And no other tab's slice carries it, so an edit on Media can never drop
    // a game's configuration.
    let media = try ManifestFile.encode(game(), block: .media)
    #expect(!media.contains("gameCenter:"))
}

@Test func editingTheGamingBlockLeavesEveryOtherBlockAlone() throws {
    let edited = """
        gameCenter:
          enabled: true
          achievements:
            - id: com.studio.game.second_win
              points: 25
        """

    let result = try ManifestFile.apply(edited, block: .gaming, to: game())

    #expect(result.gameCenter?.achievements?.count == 1)
    #expect(result.gameCenter?.achievements?.first?.id == "com.studio.game.second_win")
    #expect(result.gameCenter?.achievements?.first?.points == 25)
    // Nothing else moved.
    #expect(result.apps.apple?.bundleId == "com.studio.game")
    #expect(result.listing?.locales["en-US"] != nil)
}
