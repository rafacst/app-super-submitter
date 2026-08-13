import CryptoKit
import Foundation
import Testing
@testable import SubmitKit

/// What the Game Center write sends, and what the plan raises before it.
///
/// Every check here guards a shape Apple refuses silently or loudly, and the
/// app cannot see either one from the outside: a create that carries `archived`
/// is a fault, a create with no inline version is a fault, a localization hung
/// from the object instead of the version writes nothing a player reads, and a
/// `PATCH` on a members relationship drops a leaderboard somebody added in the
/// console that morning.

// MARK: - The recorder

private final class GameCenterLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(method: String, path: String, data: [String: Any])] = []

    func record(_ request: URLRequest) {
        // `URLSession` hands a `URLProtocol` the body as a stream, so
        // `httpBody` is nil by the time it arrives here.
        var payload = request.httpBody
        if payload == nil, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            var collected = Data()
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                guard read > 0 else { break }
                collected.append(contentsOf: buffer[..<read])
            }
            stream.close()
            payload = collected
        }
        let body = payload.flatMap { try? JSONSerialization.jsonObject(with: $0) }
            as? [String: Any]
        lock.withLock {
            entries.append((request.httpMethod ?? "", request.url?.path ?? "",
                            body?["data"] as? [String: Any] ?? [:]))
        }
    }

    var calls: [String] { lock.withLock { entries.map { "\($0.method) \($0.path)" } } }
    var paths: [String] { lock.withLock { entries.map(\.path) } }

    func data(_ method: String, _ pathContains: String) -> [String: Any] {
        lock.withLock {
            entries.first { $0.method == method && $0.path.contains(pathContains) }?.data ?? [:]
        }
    }

    func attributes(_ method: String, _ pathContains: String) -> [String: Any] {
        data(method, pathContains)["attributes"] as? [String: Any] ?? [:]
    }

    func relationships(_ method: String, _ pathContains: String) -> [String: Any] {
        data(method, pathContains)["relationships"] as? [String: Any] ?? [:]
    }
}

private final class GameCenterStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var log = GameCenterLog()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.log.record(request)
        let body = #"{"data":{"id":"made-1","attributes":{"uploadOperations":[]}}}"#
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func catalogClient() -> AppleGameCenterCatalogClient {
    GameCenterStub.log = GameCenterLog()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [GameCenterStub.self]
    let credential = AppleCredential(
        keyID: "ABCD123456", issuerID: "issuer",
        privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation,
        fileName: "AuthKey_ABCD123456.p8")
    return AppleGameCenterCatalogClient(api: StoreAPI(
        credentials: StoreCredentials(apple: credential), record: { _ in },
        session: URLSession(configuration: configuration)))
}

private func achievementRow() -> GameCenterRow {
    var block = Manifest.GameCenter()
    block.achievements = [.init(id: "com.studio.game.first_win", name: "First win",
                                points: 10, repeatable: false, showBeforeEarned: true,
                                archived: true)]
    return block.rows(.achievement)[0]
}

// MARK: - The writes

@Suite(.serialized)
struct GameCenterWriteTests {

    /// The create carries the inline version Apple marks required, and hangs
    /// from the detail when the manifest names no group.
    @Test func aNewObjectCarriesAnInlineVersionAndHangsFromTheDetail() async throws {
        let client = catalogClient()
        _ = try await client.ensureObject(family: .achievement, detailID: "detail-1",
                                          groupID: nil, achievementRow().write,
                                          existing: nil)

        let relationships = GameCenterStub.log.relationships("POST", "gameCenterAchievements")
        let versions = relationships["versions"] as? [String: Any]
        let inline = (versions?["data"] as? [[String: Any]])?.first
        #expect(inline?["type"] as? String == "gameCenterAchievementVersions")
        // No id: the version does not exist yet, and Apple makes it.
        #expect(inline?["id"] == nil)
        #expect(relationships["gameCenterDetail"] != nil)
        #expect(relationships["gameCenterGroup"] == nil)
    }

    /// A manifest that names a group hangs the object from the group, so a
    /// second game in that group shares it.
    @Test func aGroupTakesTheObjectInsteadOfTheDetail() async throws {
        let client = catalogClient()
        _ = try await client.ensureObject(family: .achievement, detailID: "detail-1",
                                          groupID: "group-1", achievementRow().write,
                                          existing: nil)

        let relationships = GameCenterStub.log.relationships("POST", "gameCenterAchievements")
        #expect(relationships["gameCenterGroup"] != nil)
        #expect(relationships["gameCenterDetail"] == nil)
    }

    /// `archived` is on the change request alone. Apple's create request has no
    /// such attribute, and the vendor identifier is on the create alone,
    /// because on a change it is the key.
    @Test func archivedIsOnTheChangeAndTheIdentifierIsOnTheCreate() async throws {
        let creating = catalogClient()
        _ = try await creating.ensureObject(family: .achievement, detailID: "detail-1",
                                            groupID: nil, achievementRow().write,
                                            existing: nil)
        let create = GameCenterStub.log.attributes("POST", "gameCenterAchievements")
        #expect(create["archived"] == nil)
        #expect(create["vendorIdentifier"] as? String == "com.studio.game.first_win")
        #expect(create["points"] as? Int == 10)
        #expect(create["repeatable"] as? Bool == false)

        let changing = catalogClient()
        var held = AppleGameCenterCatalogClient.Object(
            id: "object-1", vendorIdentifier: "com.studio.game.first_win")
        held.referenceName = "First win"
        _ = try await changing.ensureObject(family: .achievement, detailID: "detail-1",
                                            groupID: nil, achievementRow().write,
                                            existing: held)
        let change = GameCenterStub.log.attributes("PATCH", "gameCenterAchievements")
        #expect(change["archived"] as? Bool == true)
        #expect(change["vendorIdentifier"] == nil)
    }

    /// A localization hangs from the version and never from the object. Apple
    /// publishes no route for the other shape.
    @Test func aLocalizationHangsFromTheVersion() async throws {
        let client = catalogClient()
        _ = try await client.ensureLocalization(
            family: .achievement, versionID: "version-1", locale: "en-US",
            values: ["name": "First win"], existing: nil)

        let relationships = GameCenterStub.log
            .relationships("POST", "gameCenterAchievementLocalizations")
        let version = (relationships["version"] as? [String: Any])?["data"] as? [String: Any]
        #expect(version?["id"] as? String == "version-1")
        #expect(version?["type"] as? String == "gameCenterAchievementVersions")
        #expect(GameCenterStub.log.attributes("POST", "Localizations")["locale"] as? String
                == "en-US")
    }

    /// A version players already hold is left alone. A localization written
    /// onto a live version changes what they are reading now.
    @Test func aLiveVersionIsNeverWrittenOnToAndGetsANewOneInstead() async throws {
        let client = catalogClient()
        var live = AppleGameCenterCatalogClient.Object(id: "object-1",
                                                       vendorIdentifier: "board")
        live.draftVersionID = "version-live"
        live.versionState = "LIVE"

        let made = try await client.ensureVersion(family: .leaderboard, objectID: "object-1",
                                                  existing: live)
        #expect(made == "made-1")
        #expect(GameCenterStub.log.calls
            .contains("POST /v2/gameCenterLeaderboardVersions"))

        // A draft is reused rather than duplicated.
        let second = catalogClient()
        live.versionState = "PREPARE_FOR_SUBMISSION"
        #expect(try await second.ensureVersion(family: .leaderboard, objectID: "object-1",
                                               existing: live) == "version-live")
        #expect(GameCenterStub.log.calls.isEmpty)
    }

    /// The member list is sent as the difference. A `PATCH` on the relationship
    /// replaces it, and a replace written from a stale read drops a board.
    @Test func setMembersAreSentAsTheDifferenceAndNeverAsAReplace() async throws {
        let client = catalogClient()
        try await client.setMembers(setID: "set-1", add: ["board-a"], remove: ["board-b"])

        let path = "/v2/gameCenterLeaderboardSets/set-1/relationships/gameCenterLeaderboards"
        #expect(GameCenterStub.log.calls == ["POST \(path)", "DELETE \(path)"])
        #expect(!GameCenterStub.log.calls.contains { $0.hasPrefix("PATCH") })
    }

    /// The three-call upload, and `uploaded` alone on the third. The Game
    /// Center image update request takes no checksum.
    @Test func anImageIsThreeCallsAndTheLastOneSendsUploadedAlone() async throws {
        let client = catalogClient()
        let reservation = try await client.reserveImage(
            family: .achievement, parent: .localization("locale-1"),
            fileName: "first_win.png", fileSize: 2_048)
        try await client.finishImage(family: .achievement, id: reservation.id)

        #expect(GameCenterStub.log.calls == [
            "POST /v2/gameCenterAchievementImages",
            "PATCH /v2/gameCenterAchievementImages/made-1",
        ])
        #expect(GameCenterStub.log.attributes("POST", "Images")["fileSize"] as? Int == 2_048)
        let finish = GameCenterStub.log.attributes("PATCH", "Images")
        #expect(finish["uploaded"] as? Bool == true)
        #expect(finish.count == 1)
    }

    /// Every path this client builds is the v2 one where a v2 exists. Apple
    /// marks the v1 achievement, leaderboard and leaderboard set families
    /// deprecated, with every localization, image and release under them.
    @Test func noPathReachesADeprecatedV1Family() async throws {
        let client = catalogClient()
        let deprecated = ["/v1/gameCenterAchievement", "/v1/gameCenterLeaderboard"]

        for family in [AppleGameCenterCatalogClient.Family.achievement, .leaderboard,
                       .leaderboardSet] {
            var block = Manifest.GameCenter()
            block.achievements = [.init(id: "a")]
            block.leaderboards = [.init(id: "a")]
            block.leaderboardSets = [.init(id: "a")]
            let row = block.rows(family)[0]

            _ = try await client.ensureObject(family: family, detailID: "detail-1",
                                              groupID: nil, row.write, existing: nil)
            _ = try await client.ensureVersion(family: family, objectID: "object-1",
                                               existing: nil)
            _ = try await client.ensureLocalization(family: family, versionID: "version-1",
                                                    locale: "en-US", values: ["name": "A"],
                                                    existing: nil)
            _ = try await client.reserveImage(family: family, parent: .version("version-1"),
                                              fileName: "a.png", fileSize: 1)
        }
        for path in GameCenterStub.log.paths {
            #expect(!deprecated.contains { path.hasPrefix($0) }, "\(path) is a v1 path")
        }
    }
}

// MARK: - The apply, where the version decides everything

/// A localization is written onto the version this run made, and never onto the
/// one players are reading.
///
/// This is the failure the version rule exists to stop. Apple hands back the
/// newest version of an object with its localizations; if that version is
/// `LIVE`, the run makes a new one, and the localization ids that came with the
/// read belong to the old version. Sending one of them is a `PATCH` on what
/// players are looking at right now.
extension GameCenterWriteTests {

/// Nested, so the one `.serialized` above covers both suites. They share the
/// recorder on `GameCenterStub`, and two suites running in parallel would each
/// see the other's calls.
@Suite struct Apply {

    private func runner(_ manifest: Manifest, _ actual: ActualState) -> Runner {
        GameCenterStub.log = GameCenterLog()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GameCenterStub.self]
        let credential = AppleCredential(
            keyID: "ABCD123456", issuerID: "issuer",
            privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation,
            fileName: "AuthKey_ABCD123456.p8")
        var manifest = manifest
        manifest.setAppleApp(appID: "app-1", bundleID: "com.studio.game")
        return Runner(plan: PlanResult(), manifest: manifest, actual: actual, root: nil,
                      credentials: StoreCredentials(apple: credential), dryRun: false,
                      access: GrantAll(), session: URLSession(configuration: configuration),
                      emit: { _ in })
    }

    private func board(versionState: String) -> ActualState {
        var live = AppleGameCenterCatalogClient.Object(id: "object-1",
                                                       vendorIdentifier: "board")
        live.referenceName = "High score"
        live.draftVersionID = "version-old"
        live.versionState = versionState
        var localization = AppleGameCenterCatalogClient.Localization(id: "localization-old")
        localization.values = ["name": "High score"]
        live.localizations = ["en-US": localization]

        var gameCenter = ActualState.Apple.GameCenter()
        gameCenter.read = true
        gameCenter.detail = AppleGameCenterClient.Detail(id: "detail-1")
        gameCenter.leaderboards = ["board": live]
        var apple = ActualState.Apple()
        apple.gameCenter = gameCenter
        var state = ActualState()
        state.apple = apple
        return state
    }

    private func game() -> Manifest {
        var manifest = Manifest()
        manifest.gameCenter = Manifest.GameCenter(
            leaderboards: [.init(id: "board", name: "High score", sort: .desc,
                                 locales: ["en-US": .init(name: "Best run")])])
        return manifest
    }

    @Test func aLiveVersionTakesANewVersionAndANewLocalization() async throws {
        let runner = runner(game(), board(versionState: "LIVE"))
        try await runner.appleGameCenterLocale(family: "leaderboard", id: "board",
                                               locale: "en-US")

        let calls = GameCenterStub.log.calls
        #expect(calls.contains("POST /v2/gameCenterLeaderboardVersions"))
        // A create, on the version this run made. Not a change to the
        // localization that came back with the live version.
        #expect(calls.contains("POST /v2/gameCenterLeaderboardLocalizations"))
        #expect(!calls.contains("PATCH /v2/gameCenterLeaderboardLocalizations/localization-old"))
    }

    /// The draft half of the same rule: nothing new is made, and the
    /// localization Apple already holds is the one that changes.
    @Test func aDraftVersionIsWrittenOnToInPlace() async throws {
        let runner = runner(game(), board(versionState: "PREPARE_FOR_SUBMISSION"))
        try await runner.appleGameCenterLocale(family: "leaderboard", id: "board",
                                               locale: "en-US")

        #expect(GameCenterStub.log.calls
            == ["PATCH /v2/gameCenterLeaderboardLocalizations/localization-old"])
    }
}

}

// MARK: - What the plan raises

private func game(_ edit: (inout Manifest.GameCenter) -> Void = { _ in }) -> Manifest {
    var manifest = Manifest()
    manifest.setAppleApp(appID: "1", bundleID: "com.studio.game")
    var block = Manifest.GameCenter(enabled: true)
    block.appVersions = ["1.4.0": .init(enabled: true)]
    block.leaderboards = [.init(id: "board", name: "High score", sort: .desc)]
    edit(&block)
    manifest.gameCenter = block
    return manifest
}

/// A read that answered, with one leaderboard already up there.
private func stored(_ edit: (inout ActualState.Apple.GameCenter) -> Void = { _ in })
    -> ActualState {
    var state = ActualState()
    var gameCenter = ActualState.Apple.GameCenter()
    gameCenter.read = true
    gameCenter.detail = AppleGameCenterClient.Detail(id: "detail-1")
    var board = AppleGameCenterCatalogClient.Object(id: "object-1", vendorIdentifier: "board")
    board.referenceName = "High score"
    board.attributes = ["scoreSortType": "DESC"]
    gameCenter.leaderboards = ["board": board]
    var version = AppleGameCenterClient.AppVersion(id: "gcv-1", versionString: "1.4.0")
    version.enabled = true
    gameCenter.appVersions = ["1.4.0": version]
    edit(&gameCenter)

    var apple = ActualState.Apple()
    apple.gameCenter = gameCenter
    state.apple = apple
    return state
}

private func gameCenterSteps(_ manifest: Manifest, _ actual: ActualState) -> [PlanStep] {
    Planner.plan(Planner.Input(manifest: manifest, actual: actual, stores: [.apple]))
        .steps.filter { $0.id.hasPrefix("apple.gameCenter") }
}

@Suite struct GameCenterPlanTests {

    /// An absent key is not a `false`. The store keeps what it holds, and only
    /// a named value that disagrees earns a step.
    @Test func anAbsentKeyRaisesNoStepAndANamedOneThatDisagreesDoes() {
        #expect(gameCenterSteps(game(), stored()).isEmpty)

        let renamed = game { $0.leaderboards = [.init(id: "board", name: "Best run",
                                                      sort: .desc)] }
        #expect(gameCenterSteps(renamed, stored()).map(\.id)
            == ["apple.gameCenter.leaderboard.board"])

        // A different sort order is the same rule from the other side.
        let resorted = game { $0.leaderboards = [.init(id: "board", name: "High score",
                                                       sort: .asc)] }
        #expect(gameCenterSteps(resorted, stored()).count == 1)
    }

    /// A detail read that failed produces no step at all. A create against a
    /// detail that already exists answers 409.
    @Test func aFailedDetailReadProducesNoStep() {
        let failed = stored { state in
            state.read = false
            state.detail = nil
            state.leaderboards = [:]
            state.appVersions = [:]
        }
        #expect(gameCenterSteps(game(), failed).isEmpty)
    }

    /// A family whose own read failed still raises its steps, and says the
    /// comparison is a guess rather than inviting a silent duplicate.
    @Test func aFamilyThatFailedToReadIsMarkedUnverified() {
        let short = stored { state in
            state.leaderboards = [:]
            state.unreadFamilies = ["leaderboard"]
        }
        let step = gameCenterSteps(game(), short)
            .first { $0.id == "apple.gameCenter.leaderboard.board" }
        #expect(step?.comparison == .unverified)
    }

    /// The App Store version is the last Game Center step, because it is the
    /// only one that reaches a player.
    @Test func theAppStoreVersionStepIsLast() {
        let fresh = stored { state in
            state.leaderboards = [:]
            state.appVersions = [:]
            state.detail = nil
        }
        let steps = gameCenterSteps(game { $0.achievements = [.init(id: "win", points: 10)] },
                                    fresh)
        #expect(steps.last?.id == "apple.gameCenter.appVersion.1.4.0")
        // And the detail is first, because everything else hangs off it.
        #expect(steps.first?.id == "apple.gameCenter.detail")
    }

    /// The opening leaderboard is its own step, after the boards. The detail is
    /// created before any leaderboard exists, so it cannot name one.
    @Test func theOpeningBoardIsWrittenAfterTheBoardItNames() {
        let steps = gameCenterSteps(game { $0.defaultLeaderboard = "board" }, stored())
            .map(\.id)
        #expect(steps == ["apple.gameCenter.defaultLeaderboard"])
    }

    /// Apple takes 1 to 100 points for one achievement and 1000 across a game.
    @Test func thePointRulesEachProduceTheirFinding() {
        func errors(_ manifest: Manifest) -> [String] {
            Planner.plan(Planner.Input(manifest: manifest, actual: stored(),
                                       stores: [.apple]))
                .errors.map(\.id)
        }
        #expect(errors(game { $0.achievements = [.init(id: "win", points: 300)] })
            .contains("gameCenter.points.win"))
        let many = game {
            $0.achievements = (1...11).map { .init(id: "a\($0)", points: 100) }
        }
        #expect(errors(many).contains("gameCenter.pointsTotal"))
        #expect(!errors(game { $0.achievements = [.init(id: "win", points: 100)] })
            .contains("gameCenter.pointsTotal"))
    }

    /// A link that names an object the manifest does not hold is refused
    /// before the apply spends a request on it.
    @Test func aLinkToNothingIsAnError() {
        let manifest = game {
            $0.leaderboardSets = [.init(id: "all", leaderboards: ["board", "ghost"])]
            $0.challenges = [.init(id: "duel", leaderboard: "ghost")]
        }
        let errors = Planner.plan(Planner.Input(manifest: manifest, actual: stored(),
                                                stores: [.apple])).errors.map(\.id)
        #expect(errors.contains("gameCenter.set.all.ghost"))
        #expect(errors.contains("gameCenter.challenge.duel.board"))
    }

    /// Matchmaking is written from this tab too, and Apple marks both player
    /// counts required on a new rule set.
    @Test func aRuleSetWithoutPlayerCountsIsRefusedBeforeTheApply() {
        let manifest = game {
            $0.matchmaking = .init(ruleSets: [.init(name: "Ranked")],
                                   queues: [.init(name: "Fast", ruleSet: "Missing")])
        }
        let result = Planner.plan(Planner.Input(manifest: manifest, actual: stored(),
                                                stores: [.apple]))
        #expect(result.errors.map(\.id).contains("gameCenter.ruleSet.Ranked.players"))
        #expect(result.errors.map(\.id).contains("gameCenter.queue.Fast.ruleSet"))
        // The rows still plan: the button is what refuses to send them.
        #expect(result.steps.contains { $0.id == "apple.gameCenter.ruleSet.Ranked" })
    }
}
