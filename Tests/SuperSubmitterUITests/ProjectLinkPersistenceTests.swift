import Foundation
import Testing
@testable import SubmitKit
@testable import SuperSubmitter

/// The links to each app's "Build from project" folder, across a launch.
///
/// Every test here uses a `BuildStorage` root of its own. The links are one
/// list for the whole Mac, kept in Application Support, and a test that writes
/// the real one is a test that unlinks the developer's own projects.
@MainActor
@Suite(.serialized) struct ProjectLinkPersistenceTests {

    private func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("links-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// An app folder holding `store.yaml` and an Xcode project.
    @discardableResult
    private func makeApp(_ name: String, in root: URL) throws -> URL {
        let home = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let manifestURL = home.appendingPathComponent(ManifestFile.defaultName)
        try ManifestFile.save(Manifest(), to: manifestURL)
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent("\(name).xcodeproj"),
            withIntermediateDirectories: true)
        return manifestURL
    }

    private func container(_ name: String, under manifestURL: URL) -> DiscoveryResult.Container {
        DiscoveryResult.Container(
            path: manifestURL.deletingLastPathComponent()
                .appendingPathComponent(name).path,
            kind: name.hasSuffix("gradlew") ? .gradle : .project)
    }

    // MARK: - One bad record used to take every link with it

    /// The failure behind the report.
    ///
    /// `[LinkedSourceProject]` decodes all or nothing. One record this build
    /// cannot read threw, `loadProjects` answered the empty list, every app
    /// drew as unlinked, and the next link wrote that empty list back over the
    /// file. One unreadable record therefore deleted every good one.
    @Test func oneUnreadableRecordDoesNotEraseTheRest() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = BuildStorage(root: root)

        try storage.saveProjects([
            LinkedSourceProject(platform: .ios, rootPath: "/a", containerPath: "/a/A.xcodeproj",
                                containerKind: .project, manifestPath: "/a/store.yaml"),
            LinkedSourceProject(platform: .android, rootPath: "/b", containerPath: "/b/gradlew",
                                containerKind: .gradle, manifestPath: "/b/store.yaml"),
        ])

        // A record carrying a platform this build's enum does not have, which
        // is what a newer build, or an older one, leaves behind.
        let file = storage.projects.appendingPathComponent("projects.json")
        var raw = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [[String: Any]])
        var stranger = raw[0]
        stranger["platform"] = "visionos"
        stranger["id"] = UUID().uuidString
        raw.append(stranger)
        try JSONSerialization.data(withJSONObject: raw).write(to: file)

        let loaded = storage.loadProjects()

        #expect(loaded.count == 2)
        #expect(loaded.contains { $0.manifestPath == "/a/store.yaml" })
        #expect(loaded.contains { $0.manifestPath == "/b/store.yaml" })
    }

    /// A record written before a field existed still loads. The list has
    /// gained `manifestPath`, `buildNumberOverride` and more, and a link made
    /// two versions ago may not vanish because of it.
    @Test func aRecordFromAnOlderBuildStillLoads() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = BuildStorage(root: root)
        try FileManager.default.createDirectory(at: storage.projects,
                                                withIntermediateDirectories: true)

        // The shape the first version of this file wrote: no manifestPath, no
        // bookmark, and a selection holding one key.
        let old: [[String: Any]] = [[
            "id": UUID().uuidString,
            "platform": "ios",
            "rootPath": "/Users/me/apps/deck",
            "containerPath": "/Users/me/apps/deck/Deck.xcodeproj",
            "containerKind": "project",
            "selection": ["allowProvisioningUpdates": false],
            "createdAt": 700_000_000.0,
        ]]
        try JSONSerialization.data(withJSONObject: old)
            .write(to: storage.projects.appendingPathComponent("projects.json"))

        let loaded = storage.loadProjects()

        #expect(loaded.count == 1)
        #expect(loaded.first?.rootPath == "/Users/me/apps/deck")
        #expect(loaded.first?.manifestPath == nil)
    }

    /// A file that is not a list at all still costs nothing. There is no link
    /// to salvage from it and none to lose.
    @Test func anUnreadableFileIsSimplyNoLinks() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = BuildStorage(root: root)
        try FileManager.default.createDirectory(at: storage.projects,
                                                withIntermediateDirectories: true)
        try Data("not json".utf8)
            .write(to: storage.projects.appendingPathComponent("projects.json"))

        #expect(storage.loadProjects().isEmpty)
    }

    // MARK: - A real relaunch

    /// Two apps, a project each, then a fresh `AppState` and `BuildFlow` the
    /// way a relaunch builds them. Each app opens its own project and not the
    /// one linked most recently.
    @Test func eachAppRestoresItsOwnProjectAfterARelaunch() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = BuildStorage(root: root.appendingPathComponent("Storage"))
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let account = "test-\(UUID().uuidString)"

        let oneURL = try makeApp("one", in: root)
        let twoURL = try makeApp("two", in: root)

        let state = AppState(defaults: defaults, storeAccount: account)
        state.link(manifestAt: oneURL)
        state.link(manifestAt: twoURL)

        // Link a project for the app that is open, then for the other.
        await BuildFlow(app: state, owner: state.openAppID, storage: storage)
            .select(container: container("two.xcodeproj", under: twoURL),
                    root: twoURL.deletingLastPathComponent())
        state.selectApp(at: try #require(
            state.linkedApps.firstIndex { $0.manifestPath == oneURL.path }))
        await BuildFlow(app: state, owner: state.openAppID, storage: storage)
            .select(container: container("one.xcodeproj", under: oneURL),
                    root: oneURL.deletingLastPathComponent())

        #expect(storage.loadProjects().count == 2)

        // The relaunch.
        let relaunched = AppState(defaults: defaults, storeAccount: account)
        for url in [oneURL, twoURL] {
            relaunched.selectApp(at: try #require(
                relaunched.linkedApps.firstIndex { $0.manifestPath == url.path }))
            let flow = BuildFlow(app: relaunched, owner: relaunched.openAppID, storage: storage)
            flow.loadSavedProject()
            #expect(flow.project?.manifestPath == url.path)
            #expect(flow.project?.rootPath == url.deletingLastPathComponent().path)
        }
    }

    /// One app can build for both stores, and the two links are separate. The
    /// Gradle folder must not replace the Xcode one.
    @Test func appleAndGoogleLinksForOneAppStayApart() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = BuildStorage(root: root.appendingPathComponent("Storage"))
        let manifest = "/Users/me/apps/mine/store.yaml"

        try storage.saveProjects([
            LinkedSourceProject(platform: .ios, rootPath: "/Users/me/apps/mine",
                                containerPath: "/Users/me/apps/mine/Mine.xcodeproj",
                                containerKind: .project, manifestPath: manifest),
            LinkedSourceProject(platform: .android, rootPath: "/Users/me/apps/mine/android",
                                containerPath: "/Users/me/apps/mine/android/gradlew",
                                containerKind: .gradle, manifestPath: manifest),
        ])

        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        state.manifestURL = URL(fileURLWithPath: manifest)
        let flow = BuildFlow(app: state, owner: state.openAppID, storage: storage)

        #expect(flow.savedProject(for: .apple)?.containerKind == .project)
        #expect(flow.savedProject(for: .google)?.containerKind == .gradle)
    }

    // MARK: - The bookmark

    /// A renamed folder keeps its link. The bookmark tracks the folder itself,
    /// which is the only reason to store one, and until now nothing resolved
    /// it: the saved path was the only route back.
    @Test func aRenamedProjectFolderIsFollowedAndWrittenBack() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let before = root.appendingPathComponent("deck")
        try FileManager.default.createDirectory(at: before, withIntermediateDirectories: true)
        let containerPath = before.appendingPathComponent("Deck.xcodeproj").path
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: containerPath),
                                                withIntermediateDirectories: true)

        var project = LinkedSourceProject(
            platform: .ios, rootPath: before.path,
            folderBookmark: try before.bookmarkData(includingResourceValuesForKeys: nil,
                                                    relativeTo: nil),
            containerPath: containerPath, containerKind: .project,
            manifestPath: before.appendingPathComponent("store.yaml").path)

        // The developer renames the folder in Finder.
        let after = root.appendingPathComponent("deck-ios")
        try FileManager.default.moveItem(at: before, to: after)

        #expect(BuildFlow.followBookmark(&project))
        #expect(project.rootPath == after.standardizedFileURL.path)
        // The container moved with the folder, keeping its own name.
        #expect(project.containerPath
                == after.standardizedFileURL.appendingPathComponent("Deck.xcodeproj").path)
    }

    /// A folder that has not moved is left exactly as it is, and answers that
    /// nothing needs writing back.
    @Test func anUnmovedFolderNeedsNoWrite() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("deck")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        var project = LinkedSourceProject(
            platform: .ios, rootPath: home.standardizedFileURL.path,
            folderBookmark: try home.bookmarkData(includingResourceValuesForKeys: nil,
                                                  relativeTo: nil),
            containerPath: home.appendingPathComponent("Deck.xcodeproj").path,
            containerKind: .project)
        let untouched = project

        #expect(!BuildFlow.followBookmark(&project))
        #expect(project == untouched)
    }

    /// A record with no bookmark, or one that resolves to nothing, keeps the
    /// saved path. A deleted folder is the preflight's report to make, not a
    /// reason to rewrite the record.
    @Test func aDeadBookmarkFallsBackToTheSavedPath() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let gone = root.appendingPathComponent("gone")
        try FileManager.default.createDirectory(at: gone, withIntermediateDirectories: true)
        let bookmark = try gone.bookmarkData(includingResourceValuesForKeys: nil, relativeTo: nil)
        try FileManager.default.removeItem(at: gone)

        var dead = LinkedSourceProject(
            platform: .ios, rootPath: gone.path, folderBookmark: bookmark,
            containerPath: gone.appendingPathComponent("Gone.xcodeproj").path,
            containerKind: .project)
        #expect(!BuildFlow.followBookmark(&dead))
        #expect(dead.rootPath == gone.path)

        var none = LinkedSourceProject(
            platform: .ios, rootPath: "/Users/me/apps/deck", folderBookmark: nil,
            containerPath: "/Users/me/apps/deck/Deck.xcodeproj", containerKind: .project)
        let untouched = none
        #expect(!BuildFlow.followBookmark(&none))
        #expect(none == untouched)
    }

    /// Rebasing is by path component and never by string prefix, the same rule
    /// `BuildStorage.owns` follows and for the same reason.
    @Test func onlyPathsUnderTheMovedFolderMove() {
        #expect(BuildFlow.rebase("/old/App.xcodeproj", from: "/old", to: "/new")
                == "/new/App.xcodeproj")
        #expect(BuildFlow.rebase("/old", from: "/old", to: "/new") == "/new")
        // A neighbour whose name merely starts the same way is a different
        // folder and does not move.
        #expect(BuildFlow.rebase("/old-two/App.xcodeproj", from: "/old", to: "/new")
                == "/old-two/App.xcodeproj")
        #expect(BuildFlow.rebase("/elsewhere/App.xcodeproj", from: "/old", to: "/new")
                == "/elsewhere/App.xcodeproj")
    }

    // MARK: - Linking touches nothing the developer owns

    /// Unlinking removes the record and no file. The project folder is the
    /// developer's, and this app never writes inside it or deletes from it.
    @Test func unlinkingLeavesEveryProjectFileWhereItIs() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = BuildStorage(root: root.appendingPathComponent("Storage"))
        let manifestURL = try makeApp("mine", in: root)
        let home = manifestURL.deletingLastPathComponent()
        let source = home.appendingPathComponent("main.swift")
        try Data("print(1)".utf8).write(to: source)

        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        state.manifestURL = manifestURL
        let flow = BuildFlow(app: state, owner: state.openAppID, storage: storage)
        await flow.select(container: container("mine.xcodeproj", under: manifestURL), root: home)
        #expect(storage.loadProjects().count == 1)

        flow.unlink()

        #expect(storage.loadProjects().isEmpty)
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(FileManager.default.fileExists(atPath: manifestURL.path))
        #expect(FileManager.default.fileExists(
            atPath: home.appendingPathComponent("mine.xcodeproj").path))
    }
}
