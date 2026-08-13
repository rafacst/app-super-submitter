import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// Leaving a tab is a write boundary.
///
/// The autosave coalesces for 250 ms and `ListingEditor` keeps a draft while
/// the developer types, so the last thing typed before a tab was clicked was
/// waiting in one of the two. Switching app, resigning active, quitting and
/// Command-S all drained them; changing tab did not, which is the most common
/// of the five.
@Suite(.serialized)
@MainActor
struct TabSwitchFlushTests {
    private func workspace() throws -> (state: AppState, url: URL, folder: URL) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("tab-flush-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(ManifestFile.defaultName)
        var manifest = Manifest()
        manifest.setAppleApp(appID: "1", bundleID: "com.example.app")
        try ManifestFile.save(manifest, to: url)
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        try state.load(from: url)
        return (state, url, folder)
    }

    private func onDisk(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// A field edited and then left by clicking another tab.
    @Test func changingTabWritesTheEditThatWasStillWaiting() throws {
        let (state, url, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        state.selectedTab = .details

        state.manifest.addLocale("pt-BR")
        state.saveManifestReportingErrors()
        #expect(!(try onDisk(url).contains("pt-BR")))

        state.selectedTab = .media

        #expect(try onDisk(url).contains("pt-BR"))
    }

    /// And the other half: characters the manifest has not seen at all, still
    /// sitting in the listing editor's own draft.
    @Test func changingTabCommitsAFieldStillHoldingText() throws {
        let (state, url, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        state.selectedTab = .details

        state.pendingListingEdit = {
            state.manifest.addLocale("de-DE")
            state.saveManifestReportingErrors()
            state.pendingListingEdit = nil
        }

        state.selectedTab = .media

        #expect(try onDisk(url).contains("de-DE"))
        #expect(state.pendingListingEdit == nil)
    }

    /// It goes to the file of the app that was open, which is the whole point
    /// of draining at a boundary rather than after it.
    @Test func theEditLandsInTheOpenAppsFile() throws {
        let (state, url, folder) = try workspace()
        let (_, other, otherFolder) = try workspace()
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: otherFolder)
        }

        state.selectedTab = .details
        state.manifest.addLocale("fr-FR")
        state.saveManifestReportingErrors()
        state.selectedTab = .media

        #expect(try onDisk(url).contains("fr-FR"))
        #expect(!(try onDisk(other).contains("fr-FR")))
    }

    /// A tab switch with nothing waiting writes nothing. The sidebar tick
    /// marks a save and fades, so a stamp for no reason is a tick that
    /// restarts for no reason, and this fires on every tab in the app.
    @Test func aTabSwitchWithNothingWaitingWritesNothing() throws {
        let (state, _, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }

        state.manifest.addLocale("pt-BR")
        state.saveManifestReportingErrors()
        state.flushSave()
        let stamp = state.lastSavedAt
        #expect(stamp != nil)

        state.selectedTab = .details
        state.selectedTab = .media
        state.selectedTab = .plan

        #expect(state.lastSavedAt == stamp)
    }

    /// Choosing the tab that is already open is not a boundary at all.
    @Test func reselectingTheSameTabDoesNothing() throws {
        let (state, url, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        state.selectedTab = .details

        state.manifest.addLocale("pt-BR")
        state.saveManifestReportingErrors()
        state.selectedTab = .details

        #expect(!(try onDisk(url).contains("pt-BR")))
    }

    /// The four boundaries that already flushed still do. This fix adds one
    /// and replaces none of them.
    @Test func theOtherWriteBoundariesAreUntouched() throws {
        let (state, url, folder) = try workspace()
        let (_, other, otherFolder) = try workspace()
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: otherFolder)
        }

        // Command-S.
        state.manifest.addLocale("pt-BR")
        state.saveManifestReportingErrors()
        state.saveNow()
        #expect(try onDisk(url).contains("pt-BR"))

        // The coalesced flush that resign-active and termination both call.
        state.manifest.addLocale("de-DE")
        state.saveManifestReportingErrors()
        state.flushSave()
        #expect(try onDisk(url).contains("de-DE"))

        // Swapping the document.
        state.manifest.addLocale("ja")
        state.saveManifestReportingErrors()
        try state.load(from: other)
        #expect(try onDisk(url).contains("ja"))
        #expect(!(try onDisk(other).contains("ja")))
    }
}
