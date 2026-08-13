import Foundation
import Testing
@testable import SubmitKit
@testable import SuperSubmitter

/// What the dry run is set to when an app opens.
///
/// It is on by default for a **new** app, and that is the whole rule. The app
/// used to decide it by looking for a `.super-submitter/runs` folder beside the
/// manifest, which answers a different question: a run log says this Mac has
/// run this app through Super Submitter. A fresh clone has none, a second Mac
/// has none, and a colleague has none, and all three of them were opening an
/// app that has been on sale for a year with the dry run on.
@MainActor
@Suite(.serialized) struct DryRunDefaultTests {

    private func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("dryrun-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// One app on disk, under the App Store id it is remembered by.
    private func app(appID: String, in folder: URL) throws -> URL {
        let home = folder.appendingPathComponent(appID)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let url = home.appendingPathComponent(ManifestFile.defaultName)
        var manifest = Manifest()
        manifest.setAppleApp(appID: appID, bundleID: "com.example.\(appID)", platforms: [.ios])
        try ManifestFile.save(manifest, to: url)
        return url
    }

    // MARK: - A published app

    /// The report: a live app reopened with the dry run on, so the first apply
    /// of the morning wrote nothing and said it had succeeded.
    @Test func aPublishedAppReopensWithTheDryRunOff() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let account = "test-\(UUID().uuidString)"

        let state = AppState(defaults: defaults, storeAccount: account)
        state.link(manifestAt: try app(appID: "1111", in: folder))
        state.rememberAppLiveness("1111", live: true)

        // A real relaunch: a new state over the same defaults, which reopens
        // the app that was last worked on.
        let relaunched = AppState(defaults: defaults, storeAccount: account)

        #expect(relaunched.currentAppKey == "1111")
        #expect(relaunched.dryRun == false)
    }

    /// The preference still decides for an app no store has taken.
    @Test func anUnpublishedAppFollowsThePreference() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let account = "test-\(UUID().uuidString)"

        let state = AppState(defaults: defaults, storeAccount: account)
        state.link(manifestAt: try app(appID: "2222", in: folder))
        state.rememberAppLiveness("2222", live: false)

        #expect(AppState(defaults: defaults, storeAccount: account).dryRun == true)

        // And it is the preference and not a constant.
        defaults.set(false, forKey: "dryRunByDefault")
        #expect(AppState(defaults: defaults, storeAccount: account).dryRun == false)
    }

    /// An app nobody has asked about keeps the safe default. Unknown is not a
    /// store saying the app has shipped.
    @Test func anUnknownAppKeepsTheSafeDefault() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let account = "test-\(UUID().uuidString)"

        let state = AppState(defaults: defaults, storeAccount: account)
        state.link(manifestAt: try app(appID: "3333", in: folder))

        #expect(state.appLiveStates["3333"] == nil)
        #expect(AppState(defaults: defaults, storeAccount: account).dryRun == true)
    }

    // MARK: - What no longer decides it

    /// A run log on this Mac says nothing about whether customers have the app.
    /// It was the whole of the old rule and it is now none of it.
    @Test func aLocalRunFolderAloneChangesNothing() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let account = "test-\(UUID().uuidString)"

        let url = try app(appID: "4444", in: folder)
        // The folder the old rule read, with a run in it.
        let runs = url.deletingLastPathComponent()
            .appendingPathComponent(".super-submitter/runs", isDirectory: true)
        try FileManager.default.createDirectory(at: runs, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: runs.appendingPathComponent("run.json"))

        let state = AppState(defaults: defaults, storeAccount: account)
        state.link(manifestAt: url)

        // Nobody has said this app shipped, so the safe default stands, run log
        // or no run log.
        #expect(AppState(defaults: defaults, storeAccount: account).dryRun == true)
    }

    /// Approved is not shipped. An app Apple has approved and the developer has
    /// never released has no customers, so it is still a new app here. This is
    /// the line `AppleVersionState.shipped` already draws, reused rather than
    /// drawn a second time.
    @Test func anApprovedFirstVersionIsNotAPublishedApp() {
        #expect(!AppleVersionState.shipped.contains("PENDING_DEVELOPER_RELEASE"))
        #expect(AppleVersionState.shipped.contains("READY_FOR_SALE"))

        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        // What the liveness read writes for an approved-but-never-released app.
        state.rememberAppLiveness("5555", live: false)
        #expect(!state.isAppLive(appKey: "5555"))
    }

    // MARK: - Two apps, one window

    /// Switching apps recomputes it for the app being opened, both ways round.
    @Test func switchingBetweenALiveAppAndANewOneSwitchesTheDefault() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let account = "test-\(UUID().uuidString)"

        let state = AppState(defaults: defaults, storeAccount: account)
        state.link(manifestAt: try app(appID: "6666", in: folder))
        state.link(manifestAt: try app(appID: "7777", in: folder))
        state.rememberAppLiveness("6666", live: true)
        state.rememberAppLiveness("7777", live: false)

        let live = try #require(state.linkedApps.firstIndex { $0.manifestPath.contains("6666") })
        let fresh = try #require(state.linkedApps.firstIndex { $0.manifestPath.contains("7777") })

        state.selectApp(at: live)
        #expect(state.currentAppKey == "6666")
        #expect(state.dryRun == false)

        state.selectApp(at: fresh)
        #expect(state.currentAppKey == "7777")
        #expect(state.dryRun == true)

        // And back, so the answer is recomputed and not merely inherited.
        state.selectApp(at: live)
        #expect(state.dryRun == false)
    }

    /// The default is a default. A developer about to touch a live listing
    /// turns the dry run back on, and nothing may take it off them again.
    @Test func theDeveloperCanStillTurnTheDryRunOnForAPublishedApp() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let account = "test-\(UUID().uuidString)"

        let state = AppState(defaults: defaults, storeAccount: account)
        state.link(manifestAt: try app(appID: "8888", in: folder))
        state.rememberAppLiveness("8888", live: true)

        let relaunched = AppState(defaults: defaults, storeAccount: account)
        #expect(relaunched.dryRun == false)

        relaunched.dryRun = true
        #expect(relaunched.dryRun == true)
    }
}
