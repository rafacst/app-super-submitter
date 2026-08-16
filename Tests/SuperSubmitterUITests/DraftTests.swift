import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// The copy that survives an app update, and getting it back.
///
/// The bug this guards: `store.yaml` lives in the developer's own folder and
/// the list of linked apps lives in this app's user defaults. An update that
/// loses the defaults loses the sidebar while every file is still on disk, and
/// the app then offers two doors that both start from nothing.
@Suite(.serialized)
@MainActor
struct DraftTests {

    private func workspace(name: String) throws -> (state: AppState, url: URL, folder: URL) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("draft-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(ManifestFile.defaultName)
        var manifest = Manifest()
        manifest.setAppleApp(appID: "1", bundleID: "com.example.\(name)")
        try ManifestFile.save(manifest, to: url)
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        state.link(manifestAt: url)
        return (state, url, folder)
    }

    private func store() -> (DraftStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("drafts-\(UUID().uuidString)")
        return (DraftStore(storage: BuildStorage(root: root)), root)
    }

    @Test func aDraftHoldsEveryLinkedAppAndItsFile() throws {
        let (state, url, folder) = try workspace(name: "one")
        defer { try? FileManager.default.removeItem(at: folder) }

        let draft = state.draftOfEverything()
        #expect(draft.apps.count == 1)
        #expect(draft.apps[0].manifestPath == url.path)
        #expect(draft.apps[0].yaml?.contains("com.example.one") == true)
    }

    /// The draft has to hold the keystroke that has not reached the disk yet.
    /// The manifest write is coalesced, so the file trails the keyboard by up
    /// to 250 ms and a copy taken before it lands is a copy of the last save.
    @Test func aDraftHoldsTheEditThatWasStillWaiting() throws {
        let (state, _, folder) = try workspace(name: "two")
        defer { try? FileManager.default.removeItem(at: folder) }

        state.manifest.addLocale("pt-BR")
        state.saveManifestReportingErrors()

        #expect(state.draftOfEverything().apps[0].yaml?.contains("pt-BR") == true)
    }

    @Test func aDraftGoesToDiskAndComesBackNewestFirst() throws {
        let (drafts, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }

        let old = Draft(savedAt: Date(timeIntervalSince1970: 1_000_000), apps: [])
        let new = Draft(savedAt: Date(timeIntervalSince1970: 2_000_000), apps: [])
        try drafts.write(old)
        try drafts.write(new)

        #expect(drafts.list().count == 2)
        #expect(drafts.list().first?.savedAt == new.savedAt)
    }

    @Test func onlyTheNewestTwentyAreKept() throws {
        let (drafts, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }

        for day in 1...25 {
            try drafts.write(Draft(savedAt: Date(timeIntervalSince1970: Double(day) * 86_400),
                                   apps: []))
        }
        let kept = drafts.list()
        #expect(kept.count == DraftStore.keep)
        #expect(kept.first?.savedAt == Date(timeIntervalSince1970: 25 * 86_400))
    }

    /// The whole point: the files are still there and nothing points at them.
    @Test func aRecoveryBringsBackAnAppThatLostItsLink() throws {
        let (state, url, folder) = try workspace(name: "three")
        defer { try? FileManager.default.removeItem(at: folder) }
        let draft = state.draftOfEverything()

        // What an update that clears the defaults leaves behind.
        state.linkedApps = []
        state.restore(draft)

        #expect(state.linkedApps.count == 1)
        #expect(state.linkedApps[0].manifestPath == url.path)
    }

    @Test func aRecoveryWritesBackAFileThatIsGone() throws {
        let (state, url, folder) = try workspace(name: "four")
        defer { try? FileManager.default.removeItem(at: folder) }
        let draft = state.draftOfEverything()

        state.linkedApps = []
        try FileManager.default.removeItem(at: url)
        state.restore(draft)

        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(try String(contentsOf: url, encoding: .utf8).contains("com.example.four"))
        #expect(state.linkedApps.count == 1)
    }

    /// The one a restore must never do. The file on disk is the developer's
    /// work and the draft is older than it by definition.
    @Test func aRecoveryNeverWritesOverAFileThatIsStillThere() throws {
        let (state, url, folder) = try workspace(name: "five")
        defer { try? FileManager.default.removeItem(at: folder) }
        let draft = state.draftOfEverything()

        state.manifest.addLocale("pt-BR")
        state.saveManifestReportingErrors()
        state.flushSave()
        state.linkedApps = []
        state.restore(draft)

        #expect(try String(contentsOf: url, encoding: .utf8).contains("pt-BR"))
    }

    /// The command is on every tab, in the corner of the band, and it is the
    /// last thing in the row so that it is the corner on every one of them.
    @Test func theSaveCommandIsTheLastThingInTheBand() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let shell = try String(
            contentsOf: root.appending(path: "Sources/SuperSubmitter/Shell/RootView.swift"),
            encoding: .utf8)
        let header = try #require(shell.range(of: "private struct ContentHeader"))
        let cluster = try #require(shell.range(of: "private struct HeaderCluster"))
        let band = String(shell[header.lowerBound..<cluster.lowerBound])
        let button = try #require(band.range(of: "DraftButton()"))
        let padding = try #require(band.range(of: ".padding(.leading, 20)"))

        #expect(shell.contains("Save draft"))
        #expect(button.upperBound < padding.lowerBound, "it is inside the row")
        // Nothing else in the row is drawn after it.
        #expect(!band[button.upperBound..<padding.lowerBound].contains("HeaderCluster"))
    }

    @Test func eachEditableTabHasItsRemoteDraftTarget() {
        let targets: [(Tab, DirectApplyTarget)] = [
            (.build, .build), (.betaTesting, .testFlight), (.details, .listing),
            (.media, .media), (.gaming, .gameCenter), (.availability, .availability),
            (.money, .money), (.marketing, .marketing), (.reviewInfo, .reviewInfo),
        ]
        for (tab, target) in targets {
            #expect(tab.remoteSaveTarget == target, "\(tab) has no remote draft target.")
        }
        for tab in [Tab.stores, .storePage, .plan, .release, .liveApp, .account, .settings] {
            #expect(tab.remoteSaveTarget == nil, "\(tab) must use its own store action.")
        }
    }

    @Test func theStorePreviewHasNoSaveControls() {
        #expect(!Tab.storePage.showsDraftControls)
        #expect(Tab.allCases.filter { !$0.showsDraftControls } == [.storePage])
    }

    @Test func theBuildRemoteSaveWritesBuildDraftRowsOnly() {
        for id in ["apple.version", "apple.buildCompliance", "google.bundle",
                   "google.track.production"] {
            #expect(DirectApplyTarget.build.owns(id), "The Build tab lost \(id).")
        }
        for id in ["apple.versionAttributes", "apple.phased", "apple.endPreOrder"] {
            #expect(!DirectApplyTarget.build.owns(id), "The Build tab must not write \(id).")
        }
    }

    @Test func theSaveCommandOffersLocalAndRemoteDestinations() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let shell = try String(
            contentsOf: root.appending(path: "Sources/SuperSubmitter/Shell/RootView.swift"),
            encoding: .utf8)

        #expect(shell.contains("Picker(\"Save destination\""))
        #expect(shell.contains("Text(\"Local\").tag(SaveDestination.local)"))
        #expect(shell.contains("Text(\"Remote\").tag(SaveDestination.remote)"))
        #expect(shell.contains("state.saveRemotely(target)"))
        #expect(shell.contains("Saved locally"))
        #expect(shell.contains("Saved remotely"))
    }

    @Test func aRemoteSaveOpensACompleteTemporaryTab() {
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        state.selectedTab = .details

        state.beginRemoteSave(.listing)

        #expect(state.selectedTab == .remoteSave)
        #expect(state.remoteSaveVisible)
        #expect(Destination.rows(in: .send, hasApp: true, remoteSaveVisible: true)
            .map(\.title) == ["Summary", "Release", "Remote save"])

        state.recordRemoteSave(
            APICall(system: "apple", method: "PATCH", path: "/v1/localizations/1",
                    status: 200, durationMs: 18),
            at: Date(timeIntervalSince1970: 0))

        #expect(state.remoteSaveLoggedCalls == 1)
        #expect(state.remoteSaveLogLines.first?.contains("PATCH") == true)

        state.selectedTab = .details

        #expect(!state.remoteSaveVisible)
        #expect(state.remoteSaveLogLines.isEmpty)
        #expect(!Destination.rows(in: .send, hasApp: true,
                                  remoteSaveVisible: state.remoteSaveVisible)
            .contains { $0.tab == .remoteSave })
    }

    @Test func aRecoveryAddsNoAppTwice() throws {
        let (state, _, folder) = try workspace(name: "six")
        defer { try? FileManager.default.removeItem(at: folder) }

        state.restore(state.draftOfEverything())

        #expect(state.linkedApps.count == 1)
    }
}
