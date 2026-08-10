import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// Settings ▸ Nuclear.
///
/// The whole feature is a delete, so the test is about what survives it as
/// much as what does not. Everything here runs against a throwaway defaults
/// suite and a temporary folder: a test that reached the real ones would erase
/// the credentials of whoever ran it.
@Suite @MainActor struct NuclearResetTests {

    private func fixture() -> (AppState, BuildStorage, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nuclear-\(UUID().uuidString)", isDirectory: true)
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        return (state, BuildStorage(root: root), root)
    }

    @Test func theEraseEmptiesEveryDefaultTheAppWrote() throws {
        let (state, storage, root) = fixture()
        defer { try? FileManager.default.removeItem(at: root) }

        state.defaults.set("something", forKey: "linkedApps.v1")
        state.defaults.set(42, forKey: "pollIntervalMinutes")
        state.defaults.set(true, forKey: "hasSeenOnboarding")

        state.eraseEverything(storage: storage)

        #expect(state.defaults.object(forKey: "linkedApps.v1") == nil)
        #expect(state.defaults.object(forKey: "pollIntervalMinutes") == nil)
        #expect(state.defaults.object(forKey: "hasSeenOnboarding") == nil)
    }

    /// The byproducts go: archives this app built, artifacts it exported, run
    /// logs it wrote, scratch, and the list of paths to projects that live
    /// somewhere else entirely.
    @Test func theEraseRemovesWhatTheAppItselfWrote() throws {
        let (state, storage, root) = fixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let made = [storage.projects, storage.archives, storage.artifacts,
                    storage.runs, storage.scratch]
        for folder in made {
            try FileManager.default.createDirectory(at: folder,
                                                    withIntermediateDirectories: true)
            try Data("x".utf8).write(to: folder.appendingPathComponent("a.file"))
        }

        state.eraseEverything(storage: storage)

        for folder in made {
            #expect(!FileManager.default.fileExists(atPath: folder.path),
                    "\(folder.lastPathComponent) survived the erase")
        }
    }

    /// The one that matters. `Managed/` sits inside the same folder as the
    /// archives and the logs, but a managed app's `store.yaml` is in there:
    /// the listing text, the catalog and the review answers the user typed,
    /// with no second copy anywhere. Deleting the folder above it took all of
    /// that, which is the whole reason this erase names its targets one by one
    /// instead of removing the root.
    @Test func theEraseNeverTouchesAManagedAppsManifest() throws {
        let (state, storage, root) = fixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = try storage.managedFolder(name: "Fast Bill Split", identifier: "1234")
        let manifest = folder.appendingPathComponent("store.yaml")
        try Data("version: 1\n".utf8).write(to: manifest)

        state.eraseEverything(storage: storage)

        #expect(FileManager.default.fileExists(atPath: manifest.path),
                "the nuclear option deleted a manifest the user wrote")
        #expect(try String(contentsOf: manifest, encoding: .utf8) == "version: 1\n")
    }

    /// A linked app is a path to a file the developer keeps. Forgetting the
    /// list must never follow the path and delete the file at the end of it.
    @Test func theEraseForgetsThePathAndLeavesTheFile() throws {
        let (state, storage, root) = fixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let repo = root.appendingPathComponent("a-repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let manifest = repo.appendingPathComponent("store.yaml")
        try Data("version: 1\n".utf8).write(to: manifest)
        state.manifestURL = manifest

        state.eraseEverything(storage: storage)

        #expect(state.manifestURL == nil)
        #expect(FileManager.default.fileExists(atPath: manifest.path),
                "the nuclear option deleted the developer's own store.yaml")
    }

    @Test func theEraseForgetsEveryLinkedAppAndTheOpenManifest() throws {
        let (state, storage, root) = fixture()
        defer { try? FileManager.default.removeItem(at: root) }

        state.manifestURL = URL(fileURLWithPath: "/tmp/store.yaml")
        state.manifest.listing = Manifest.Listing(defaultLocale: "en-US", locales: [:])

        state.eraseEverything(storage: storage)

        #expect(state.linkedApps.isEmpty)
        #expect(state.manifestURL == nil)
        #expect(state.manifest.listing == nil)
    }

    /// The point of the feature: the app comes back the way a fresh install
    /// does. Landing on a blank tab instead would leave the user on a screen
    /// with nothing in it and no way to start.
    @Test func theEraseReturnsToTheFirstRunScreen() throws {
        let (state, storage, root) = fixture()
        defer { try? FileManager.default.removeItem(at: root) }

        state.showOnboarding = false
        state.showEntryScreen = false
        // Where the button is: the erase is ordered from the Settings tab.
        state.selectedTab = .settings

        state.eraseEverything(storage: storage)

        #expect(state.showOnboarding)
        #expect(state.showEntryScreen)
        // And the tab behind the first-run screen is the one a fresh install
        // opens on, not the screen the erase was ordered from.
        #expect(state.selectedTab == .stores)
    }

    /// Both gates close on the way through. One left open would put the dialog
    /// back on screen the next time Settings opened.
    @Test func theEraseClosesBothConfirmations() throws {
        let (state, storage, root) = fixture()
        defer { try? FileManager.default.removeItem(at: root) }

        state.nuclearFirstConfirm = true
        state.nuclearSecondConfirm = true

        state.eraseEverything(storage: storage)

        #expect(!state.nuclearFirstConfirm)
        #expect(!state.nuclearSecondConfirm)
    }
}
