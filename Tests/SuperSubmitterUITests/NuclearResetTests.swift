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

    /// The folder is the app's own: archives it made and logs it wrote. A
    /// `store.yaml` never lives in there, which is why this may remove it
    /// whole.
    @Test func theEraseRemovesTheAppOwnedFolderAndNothingAboveIt() throws {
        let (state, storage, root) = fixture()
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: storage.projects,
                                                withIntermediateDirectories: true)
        try Data("log".utf8).write(to: storage.projects.appendingPathComponent("a.log"))
        #expect(FileManager.default.fileExists(atPath: storage.root.path))

        state.eraseEverything(storage: storage)

        #expect(!FileManager.default.fileExists(atPath: storage.root.path))
        // The temporary directory that held it is still there. The erase takes
        // its own folder and never the one it happens to sit in.
        #expect(FileManager.default.fileExists(atPath: NSTemporaryDirectory()))
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
        state.showSettings = true

        state.eraseEverything(storage: storage)

        #expect(state.showOnboarding)
        #expect(state.showEntryScreen)
        #expect(!state.showSettings)
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
