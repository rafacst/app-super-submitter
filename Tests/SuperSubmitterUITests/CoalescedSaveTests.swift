import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// The autosave writes once the typing stops, not once per character.
///
/// The bug this guards: every keystroke re-encoded the whole manifest through
/// Yams and wrote it atomically on the main actor, about 1.7 ms and one
/// temporary file per key on a 16 KB listing, so a text field lagged behind
/// the keyboard. Coalescing that is only safe while every boundary flushes,
/// which is what these tests hold in place.
@Suite(.serialized)
@MainActor
struct CoalescedSaveTests {
    private func workspace() throws -> (state: AppState, url: URL, folder: URL) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("coalesced-save-\(UUID().uuidString)")
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

    @Test func aKeystrokeDoesNotTouchTheDiskAndAFlushDoes() throws {
        let (state, url, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        let before = try onDisk(url)

        state.manifest.addLocale("pt-BR")
        state.saveManifestReportingErrors()

        #expect(try onDisk(url) == before)
        state.flushSave()
        #expect(try onDisk(url).contains("pt-BR"))
    }

    /// The one that would lose work. A pending write belongs to the app that
    /// is open, so it has to land before the next app takes the document.
    @Test func switchingAppsWritesTheEditThatWasStillWaiting() throws {
        let (state, url, folder) = try workspace()
        let (_, other, otherFolder) = try workspace()
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: otherFolder)
        }

        state.manifest.addLocale("pt-BR")
        state.saveManifestReportingErrors()
        try state.load(from: other)

        #expect(try onDisk(url).contains("pt-BR"))
        #expect(!(try onDisk(other).contains("pt-BR")))
    }

    /// The sidebar tick marks a save and fades. A flush with nothing waiting
    /// must not stamp the time, or the tick restarts for no reason.
    @Test func aFlushWithNothingWaitingSavesNothing() throws {
        let (state, _, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }

        state.manifest.addLocale("pt-BR")
        state.saveManifestReportingErrors()
        state.flushSave()
        let stamp = state.lastSavedAt
        #expect(stamp != nil)

        state.flushSave()
        #expect(state.lastSavedAt == stamp)
    }

    /// The other half of the same promise, for the characters that have not
    /// reached the manifest yet.
    ///
    /// `ListingEditor` keeps a draft while the developer types, so a key
    /// redraws one field instead of the whole window. Every boundary that
    /// writes or replaces the document has to empty that draft first, or a
    /// pause of typing is lost — or worse, lands in the next app's file.
    @Test func everyWriteBoundaryEmptiesAFieldStillHoldingText() throws {
        let (state, url, folder) = try workspace()
        let (_, other, otherFolder) = try workspace()
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: otherFolder)
        }

        func arm(_ locale: String) {
            state.pendingListingEdit = {
                state.manifest.addLocale(locale)
                state.saveManifestReportingErrors()
                state.pendingListingEdit = nil
            }
        }

        arm("pt-BR")
        state.flushSave()
        #expect(try onDisk(url).contains("pt-BR"))

        arm("de-DE")
        state.saveNow()
        #expect(try onDisk(url).contains("de-DE"))

        // The one that would put an edit in the wrong file: the document is
        // swapped while a field still holds characters.
        arm("fr-FR")
        try state.load(from: other)
        #expect(try onDisk(url).contains("fr-FR"))
        #expect(!(try onDisk(other).contains("fr-FR")))
    }

    /// Command-S goes straight to the disk, and it answers the waiting write
    /// rather than leaving it to land a moment later.
    @Test func savingByHandAnswersThePendingWrite() throws {
        let (state, url, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }

        state.manifest.addLocale("pt-BR")
        state.saveManifestReportingErrors()
        state.saveNow()
        #expect(try onDisk(url).contains("pt-BR"))

        let stamp = state.lastSavedAt
        state.flushSave()
        #expect(state.lastSavedAt == stamp)
    }
}
