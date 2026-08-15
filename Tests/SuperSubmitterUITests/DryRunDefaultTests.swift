import Foundation
import Testing
@testable import SubmitKit
@testable import SuperSubmitter

/// What the dry run is set to when an app opens.
///
/// One rule, and no app is an exception to it: the Settings preference decides,
/// and it defaults to on. A published app used to open with the dry run off,
/// which handed the live-write default to the one app state where a wrong write
/// is read by customers. Liveness is still recorded, and other features still
/// read it. It no longer decides this.
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

    // MARK: - The preference decides

    /// The report: a live app opened with the dry run off, so the first apply of
    /// the morning wrote to a listing customers were reading, unasked.
    @Test func aPublishedAppFollowsThePreference() throws {
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
        #expect(relaunched.isAppLive(appKey: "1111"))
        #expect(relaunched.dryRun == true)

        // And it is the preference and not a constant, for a live app too.
        defaults.set(false, forKey: "dryRunByDefault")
        #expect(AppState(defaults: defaults, storeAccount: account).dryRun == false)
    }

    /// The same preference, for an app no store has taken.
    @Test func anUnpublishedAppFollowsThePreference() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let account = "test-\(UUID().uuidString)"

        let state = AppState(defaults: defaults, storeAccount: account)
        state.link(manifestAt: try app(appID: "2222", in: folder))
        state.rememberAppLiveness("2222", live: false)

        #expect(AppState(defaults: defaults, storeAccount: account).dryRun == true)

        defaults.set(false, forKey: "dryRunByDefault")
        #expect(AppState(defaults: defaults, storeAccount: account).dryRun == false)
    }

    /// A missing preference is the safe answer and not an empty one.
    @Test func noPreferenceMeansTheDryRunIsOn() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let account = "test-\(UUID().uuidString)"

        let state = AppState(defaults: defaults, storeAccount: account)
        state.link(manifestAt: try app(appID: "3333", in: folder))

        #expect(defaults.object(forKey: "dryRunByDefault") == nil)
        #expect(state.appLiveStates["3333"] == nil)
        #expect(AppState(defaults: defaults, storeAccount: account).dryRun == true)
    }

    // MARK: - What no longer decides it

    /// A run log on this Mac says nothing about whether customers have the app.
    /// It was the whole of the oldest rule and it is now none of it.
    @Test func aLocalRunFolderAloneChangesNothing() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let account = "test-\(UUID().uuidString)"

        let url = try app(appID: "4444", in: folder)
        // The folder that rule read, with a run in it.
        let runs = url.deletingLastPathComponent()
            .appendingPathComponent(".super-submitter/runs", isDirectory: true)
        try FileManager.default.createDirectory(at: runs, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: runs.appendingPathComponent("run.json"))

        let state = AppState(defaults: defaults, storeAccount: account)
        state.link(manifestAt: url)

        #expect(AppState(defaults: defaults, storeAccount: account).dryRun == true)
    }

    // MARK: - Two apps, one window

    /// Switching apps recomputes the preference, and liveness is no exception to
    /// it in either direction.
    @Test func switchingBetweenALiveAppAndANewOneKeepsThePreference() throws {
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
        #expect(state.dryRun == true)

        // The developer's own choice for this session, which the next app must
        // not inherit: the preference is recomputed and not carried over.
        state.dryRun = false
        state.selectApp(at: fresh)
        #expect(state.currentAppKey == "7777")
        #expect(state.dryRun == true)

        state.dryRun = false
        state.selectApp(at: live)
        #expect(state.dryRun == true)
    }

    /// An explicit `false` is still an answer the app takes, and it reaches both
    /// apps on a switch.
    @Test func anExplicitFalsePreferenceSurvivesAnAppSwitch() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(false, forKey: "dryRunByDefault")
        let account = "test-\(UUID().uuidString)"

        let state = AppState(defaults: defaults, storeAccount: account)
        state.link(manifestAt: try app(appID: "8888", in: folder))
        state.link(manifestAt: try app(appID: "9999", in: folder))
        state.rememberAppLiveness("8888", live: true)

        let live = try #require(state.linkedApps.firstIndex { $0.manifestPath.contains("8888") })
        let fresh = try #require(state.linkedApps.firstIndex { $0.manifestPath.contains("9999") })

        state.selectApp(at: live)
        #expect(state.dryRun == false)

        state.dryRun = true
        state.selectApp(at: fresh)
        #expect(state.dryRun == false)
    }

    /// The default is a default. The switch in the header is the developer's for
    /// the rest of the session, both ways round.
    @Test func theDeveloperCanStillSetItForAPublishedApp() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let account = "test-\(UUID().uuidString)"

        let state = AppState(defaults: defaults, storeAccount: account)
        state.link(manifestAt: try app(appID: "5555", in: folder))
        state.rememberAppLiveness("5555", live: true)

        let relaunched = AppState(defaults: defaults, storeAccount: account)
        #expect(relaunched.dryRun == true)

        relaunched.dryRun = false
        #expect(relaunched.dryRun == false)

        relaunched.dryRun = true
        #expect(relaunched.dryRun == true)
    }
}
