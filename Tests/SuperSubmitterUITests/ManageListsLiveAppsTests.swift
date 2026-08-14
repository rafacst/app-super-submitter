import CryptoKit
import Foundation
import Testing
@testable import SubmitKit
@testable import SuperSubmitter

/// Which apps the Manage side lists.
///
/// Managing runs the app that is already live. A draft has no customers, no
/// listing anybody is reading and no crash rate, so every Manage screen it
/// opened was a screen about a store that holds nothing, and the app list
/// offered it beside the apps those screens are written for.
///
/// The answer is per app and has to survive a launch: the sidebar draws before
/// any read returns, and a Manage side that opens empty every morning and
/// fills itself once the sweep answers looks broken.
@MainActor
@Suite(.serialized) struct ManageListsLiveAppsTests {

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// One app on disk, with the App Store id it is remembered under.
    private func app(appID: String, in folder: URL) throws -> URL {
        let home = folder.appendingPathComponent(appID)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let url = home.appendingPathComponent(ManifestFile.defaultName)
        var manifest = Manifest()
        manifest.setAppleApp(appID: appID, bundleID: "com.example.\(appID)", platforms: [.ios])
        try ManifestFile.save(manifest, to: url)
        return url
    }

    /// A folder with the file and no store id in it, which is what the first
    /// door writes for an app that has never been anywhere.
    private func newApp(named name: String, in folder: URL) throws -> URL {
        let home = folder.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let url = home.appendingPathComponent(ManifestFile.defaultName)
        try ManifestFile.save(Manifest(), to: url)
        return url
    }

    private func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("manage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    // MARK: - The rule

    /// An app nobody has shipped is a Publish app and nothing else.
    @Test func aDraftIsNotOneOfTheAppsToManage() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        state.link(manifestAt: try app(appID: "1111", in: folder))
        state.rememberAppLiveness("1111", live: false)

        #expect(state.appRows.first?.isLive == false)
        #expect(!state.isAppLive(appKey: "1111"))
    }

    /// And one a store has shipped is on both sides, whichever app is open.
    @Test func anAppTheStoreShippedIsListedAndStaysListedAfterALaunch() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let account = "test-\(UUID().uuidString)"
        let state = AppState(defaults: defaults, storeAccount: account)
        let url = try app(appID: "1111", in: folder)
        state.link(manifestAt: url)

        state.rememberAppLiveness("1111", live: true)
        #expect(state.appRows.first?.isLive == true)

        // The next launch draws the sidebar before any read returns.
        let relaunched = AppState(defaults: defaults, storeAccount: account)
        #expect(relaunched.isAppLive(appKey: "1111"))
        #expect(relaunched.appRows.first?.isLive == true)
    }

    /// An app nobody has asked about is not an app that is known to be a draft.
    ///
    /// The Manage side treats the two the same, because it lists what a store
    /// has shipped and neither of these is that. The sidebar does not: one
    /// wears the answer and the other says nobody has asked.
    @Test func anUnreadAppIsNeitherLiveNorCalledADraft() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        state.link(manifestAt: try app(appID: "1111", in: folder))

        #expect(state.appLiveStates["1111"] == nil)
        #expect(!state.isAppLive(appKey: "1111"))
        #expect(state.appMark(appKey: "1111").label == "Unknown")
    }

    /// A yes is never taken back, and a no writes only into the silence.
    ///
    /// An app pulled from sale was still published and its listing is still the
    /// one customers last read, so a later read that finds nothing on sale may
    /// not empty the Manage side.
    @Test func aYesOutlastsALaterNo() {
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")

        state.rememberAppLiveness("1111", live: true)
        state.rememberAppLiveness("1111", live: false)
        #expect(state.isAppLive(appKey: "1111"))

        state.rememberAppLiveness("2222", live: false)
        state.rememberAppLiveness("2222", live: true)
        #expect(state.isAppLive(appKey: "2222"))
    }

    /// A folder with no store id in it needs no request to answer for. Nothing
    /// on any store holds a record of an app that names none.
    @Test func anAppWithNoStoreIdAnswersWithoutAsking() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        state.link(manifestAt: try newApp(named: "Bill Split", in: folder))

        let record = try #require(state.linkedApps.first)
        await state.readAppLiveness(for: record)

        #expect(state.appLiveStates[record.id.uuidString] == false)
        #expect(state.appMark(appKey: record.id.uuidString).label == "Not on the store")
        #expect(state.appRows.first?.isLive == false)
    }

    /// Two half-filled apps are two apps. `apps.apple` is a block with an empty
    /// `appId` for every app whose store row is half written, so the key fell
    /// back to the empty string and both of them read whatever the last one
    /// learned.
    @Test func twoAppsWithNoIdsDoNotShareOneAnswer() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        state.link(manifestAt: try newApp(named: "One", in: folder))
        state.link(manifestAt: try newApp(named: "Two", in: folder))

        let keys = state.appRows.map(\.key)
        #expect(keys.count == 2)
        #expect(Set(keys).count == 2)
        #expect(!keys.contains(""))
    }

    /// The open app answers from the read it already has, so an app that goes
    /// live while it is open joins the Manage list on that read.
    @Test func theOpenAppAnswersFromItsOwnRead() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        state.link(manifestAt: try app(appID: "1111", in: folder))
        state.rememberAppLiveness("1111", live: false)
        #expect(state.appRows.first?.isLive == false)

        var apple = ActualState.Apple()
        apple.liveVersionString = "1.4"
        state.actualState.apple = apple

        #expect(state.isUpdatingLiveApp)
        #expect(state.appRows.first?.isLive == true)
        // And the answer is kept, so the row is still right when another app
        // is open and this read is gone.
        state.rememberOpenAppLiveState()
        #expect(state.isAppLive(appKey: "1111"))
    }

    /// Switching to Manage leaves an app that side does not list.
    ///
    /// Without this the developer arrived on the Manage tabs of an app the
    /// column beside them had just stopped showing.
    @Test func managingOpensAnAppItCanManage() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        state.link(manifestAt: try app(appID: "1111", in: folder))
        state.link(manifestAt: try app(appID: "2222", in: folder))
        state.rememberAppLiveness("1111", live: true)
        state.selectApp(at: 1)

        state.mode = .managing

        #expect(state.selectedAppIndex == 0, "The draft has nothing to manage.")

        // A developer whose apps are all drafts has nowhere to be sent, so
        // nothing moves.
        state.mode = .publishing
        state.selectApp(at: 1)
        state.appLiveStates = [:]
        state.mode = .managing
        #expect(state.selectedAppIndex == 1)
    }

    // MARK: - Where the answer comes from

    /// The sweep already fetches every version of every linked app. A live app
    /// whose next version is a draft reports `PREPARE_FOR_SUBMISSION`, which is
    /// the right answer to "is this app frozen?" and reads as "never shipped"
    /// to the question the Manage side asks. Both answers are in the one list.
    @Test func theSweepReadsShippedOffTheListItAlreadyFetches() async throws {
        let answer = try await standing(of: LiveWithADraftStub.self)
        #expect(answer?.state == "PREPARE_FOR_SUBMISSION")
        #expect(answer?.shipped == true)
    }

    /// Apple said yes and nobody can buy it yet. A first submission waiting for
    /// its release button has never been on the store.
    @Test func anApprovedFirstVersionHasNotShipped() async throws {
        let answer = try await standing(of: ApprovedOnlyStub.self)
        #expect(answer?.state == "PENDING_DEVELOPER_RELEASE")
        #expect(answer?.shipped == false)
    }

    private func standing(of stub: URLProtocol.Type) async throws
        -> (state: String, shipped: Bool)? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [stub]
        let credential = AppleCredential(
            keyID: "ABCD123456", issuerID: "issuer",
            privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation,
            fileName: "AuthKey_ABCD123456.p8")
        return await StoreImportReader(credentials: StoreCredentials(apple: credential),
                                       session: URLSession(configuration: configuration))
            .appleVersionState(appID: "1111")
    }

    /// Google Play answers this inside an edit and nowhere else, which is why
    /// it is asked once, when the app is linked. The production track and not
    /// the primary one: a build on an internal track is not an app the public
    /// can install.
    @Test func playAnswersOffTheProductionTrackAndLeavesNoEditBehind() async throws {
        let played = try await shipped(on: PlayLiveStub.self)
        #expect(played == true)
        #expect(PlayLiveStub.deleted, "A read never leaves an edit behind.")
    }

    /// A release nobody has rolled out is a draft, and a track with no release
    /// at all is an app the store has never put in front of anybody.
    @Test func aDraftReleaseIsNotAShippedApp() async throws {
        #expect(try await shipped(on: PlayDraftStub.self) == false)
        #expect(try await shipped(on: PlayInternalOnlyStub.self) == false)
    }

    /// A store that will not answer is not a store saying no. The app stays
    /// unknown and the next link or open asks again.
    @Test func aPlayReadThatFailsAnswersNothing() async throws {
        #expect(try await shipped(on: PlayRefusesStub.self) == nil)
    }

    private func shipped(on stub: URLProtocol.Type) async throws -> Bool? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [stub]
        // The OAuth route, whose token is already in hand. A service account
        // would sign a JWT and trade it at a second host for one.
        let credential = GoogleOAuthCredential(
            clientID: "client", accessToken: "token", refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3_600))
        return await StoreImportReader(credentials: StoreCredentials(googleOAuth: credential),
                                       session: URLSession(configuration: configuration))
            .googleProductionShipped(packageName: "com.example.app")
    }

    // MARK: - Where it shows

    /// The apps are the tab bar across the top of the window now, so the list
    /// this rule governs moved out of the sidebar with them.
    @Test func theTabBarListsTheAppsByIt() throws {
        let bar = try String(
            contentsOf: Self.root.appending(path: "Sources/SuperSubmitter/Shell/AppTabBar.swift"),
            encoding: .utf8)
        let sidebar = try String(
            contentsOf: Self.root.appending(path: "Sources/SuperSubmitter/Shell/Sidebar.swift"),
            encoding: .utf8)

        #expect(bar.contains("state.appRows"))
        // Every tab wears a word, and an app nobody has read wears "Unknown".
        #expect(sidebar.contains("let mark: AppleStanding\n"))
        #expect(bar.contains("AppStatusChip(mark: state.appMark(appKey: app.key))"))
        // And a tab says when its app is busy, which is the reason the bar
        // exists: a build the developer has switched away from is still running.
        #expect(bar.contains("state.isBuilding(appID: app.id)"))
    }

    /// Linking is where the question is asked, because it is the only moment
    /// that names one app rather than all of them.
    @Test func linkingTheFolderIsWhatAsksTheStores() throws {
        let source = try String(
            contentsOf: Self.root.appending(path: "Sources/SuperSubmitter/AppState.swift"),
            encoding: .utf8)
        #expect(source.contains("await readAppLiveness(for: record)"))
    }
}

/// An app on sale with the next version in preparation: the ordinary state of
/// an app that is published and being worked on.
private final class LiveWithADraftStub: URLProtocol, @unchecked Sendable {
    static let body = """
    {"data":[
      {"id":"v-140","type":"appStoreVersions",
       "attributes":{"versionString":"1.4","appVersionState":"READY_FOR_SALE"}},
      {"id":"v-150","type":"appStoreVersions",
       "attributes":{"versionString":"1.5","appVersionState":"PREPARE_FOR_SUBMISSION"}}
     ]}
    """

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { answer(Self.body) }
    override func stopLoading() {}
}

/// A first submission Apple has approved and nobody has released.
private final class ApprovedOnlyStub: URLProtocol, @unchecked Sendable {
    static let body = """
    {"data":[
      {"id":"v-100","type":"appStoreVersions",
       "attributes":{"versionString":"1.0",
                     "appVersionState":"PENDING_DEVELOPER_RELEASE"}}
     ]}
    """

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { answer(Self.body) }
    override func stopLoading() {}
}

/// The three requests one Play answer costs: the edit, the tracks inside it,
/// and the edit thrown away.
private class PlayStub: URLProtocol, @unchecked Sendable {
    /// What the tracks read answers. One per subclass.
    class var tracks: String { #"{"tracks":[]}"# }
    /// Whether the edit was cleaned up, which the reader owes the developer
    /// whatever the answer was.
    nonisolated(unsafe) static var deleted = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let path = request.url?.path ?? ""
        switch request.httpMethod {
        case "POST": answer(#"{"id":"edit-1"}"#)
        case "DELETE":
            type(of: self).deleted = true
            answer("{}")
        default: answer(path.hasSuffix("/tracks") ? type(of: self).tracks : "{}")
        }
    }
}

/// An app the public can install: a production release with a build in it.
private final class PlayLiveStub: PlayStub, @unchecked Sendable {
    override class var tracks: String {
        #"""
        {"tracks":[
          {"track":"internal","releases":[{"status":"completed","versionCodes":["9"]}]},
          {"track":"production","releases":[{"status":"completed","versionCodes":["8"]}]}
        ]}
        """#
    }
}

/// A release the developer is holding back. Nobody can install it.
private final class PlayDraftStub: PlayStub, @unchecked Sendable {
    override class var tracks: String {
        #"{"tracks":[{"track":"production","releases":[{"status":"draft","versionCodes":["8"]}]}]}"#
    }
}

/// Testers have it and the store does not. The production track answers, and
/// the primary one would have called this app published.
private final class PlayInternalOnlyStub: PlayStub, @unchecked Sendable {
    override class var tracks: String {
        #"{"tracks":[{"track":"internal","releases":[{"status":"completed","versionCodes":["9"]}]}]}"#
    }
}

/// The service account cannot see this package.
private final class PlayRefusesStub: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 403,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"error":{"code":403}}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

private extension URLProtocol {
    func answer(_ body: String) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
