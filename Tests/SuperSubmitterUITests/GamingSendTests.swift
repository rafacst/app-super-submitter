import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// The button on the Gaming tab.
///
/// The claim it rests on is that **nothing on that tab needs a build**. So the
/// target has to take every Game Center row and no build row: a send that
/// dragged an upload along would turn "fix the sort order of one leaderboard"
/// into "ship the artifact on disk".

@Suite @MainActor struct GamingSendTests {

    /// Every Game Center row, and nothing that belongs to a build, a listing or
    /// a beta.
    @Test func theSendTargetTakesEveryGameCenterRowAndNoBuildRow() {
        let taken = ["apple.gameCenter.detail", "apple.gameCenter.group.Studio",
                     "apple.gameCenter.defaultLeaderboard",
                     "apple.gameCenter.leaderboard.board",
                     "apple.gameCenter.leaderboard.board.en-US",
                     "apple.gameCenter.image.achievement.win.en-US",
                     "apple.gameCenter.leaderboardSet.all.members",
                     "apple.gameCenter.ruleSet.Ranked", "apple.gameCenter.queue.Fast",
                     "apple.gameCenter.appVersion.1.4.0",
                     "apple.build", "apple.buildCompliance", "apple.attachBuild",
                     "apple.betaGroup.QA", "apple.locale.en-US", "apple.media.phone",
                     "google.listing.en-US"]
            .filter { id in
                DirectApplyTarget.gameCenter.prefixes.contains { id.hasPrefix($0) }
            }

        #expect(taken == ["apple.gameCenter.detail", "apple.gameCenter.group.Studio",
                          "apple.gameCenter.defaultLeaderboard",
                          "apple.gameCenter.leaderboard.board",
                          "apple.gameCenter.leaderboard.board.en-US",
                          "apple.gameCenter.image.achievement.win.en-US",
                          "apple.gameCenter.leaderboardSet.all.members",
                          "apple.gameCenter.ruleSet.Ranked", "apple.gameCenter.queue.Fast",
                          "apple.gameCenter.appVersion.1.4.0"])
        #expect(DirectApplyTarget.gameCenter.destination([.apple, .google]) == "Game Center")
        #expect(DirectApplyTarget.gameCenter.noun == "Game Center rows")
    }

    /// The button reads the errors the apply would otherwise meet halfway
    /// through, with the rows before them already written.
    @Test func theButtonRefusesToSendWhatAppleWouldRefuse() {
        let state = AppState()
        state.manifest.setAppleApp(appID: "1", bundleID: "com.studio.game")
        // Every value Apple marks required on a create, which is what the tab
        // writes when a developer adds a row.
        func achievement(points: Int) -> Manifest.GameCenter.Achievement {
            .init(id: "win", name: "First win", points: points, repeatable: false,
                  showBeforeEarned: true)
        }
        state.manifest.gameCenter = Manifest.GameCenter(
            enabled: true,
            appVersions: ["1.4.0": .init(enabled: true)],
            achievements: [achievement(points: 10)])

        #expect(state.gameCenterErrors().isEmpty)

        // 1 to 100 for one achievement. Apple refuses 300.
        state.manifest.gameCenter?.achievements = [achievement(points: 300)]
        state.invalidatePlan()
        #expect(state.gameCenterErrors().map(\.id) == ["gameCenter.points.win"])
        #expect(state.gameCenterErrors().allSatisfy { $0.fix == .gaming })

        // A row Apple has never seen and cannot create: no name, and neither
        // switch answered.
        state.manifest.gameCenter?.achievements = [.init(id: "win", points: 10)]
        state.invalidatePlan()
        #expect(state.gameCenterErrors().map(\.id)
            == ["gameCenter.achievement.incomplete.win"])
    }
}
