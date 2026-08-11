import AppKit
import Foundation
import SubmitKit

/// A copy of the work, kept where an app update cannot reach it.
///
/// Not the store's draft, which is the unsubmitted version an upload creates
/// in App Store Connect or Google Play. This one never leaves the Mac.
///
/// Two things hold what a developer has done here. `store.yaml` holds the
/// listing, the catalog and the answers, and it lives in the developer's own
/// folder. The list of linked apps holds where those files are, and it lives in
/// this app's user defaults. The second one is the one an update can lose, and
/// losing it loses the sidebar: the files are still on disk, and nothing points
/// at them any more.
///
/// So a draft is both: the record of every linked app, and the text of the file
/// each one points at. It is written on demand, never automatically, because a
/// copy that is rewritten by itself is a copy that can be overwritten with the
/// damage it exists to undo.
///
/// It carries no key, no password and no token. Those live in the Keychain,
/// which an app update does not touch, and a plain file is the one place they
/// may never be.
struct Draft: Codable {
    var savedAt: Date
    var apps: [App]

    struct App: Codable, Identifiable {
        var id: UUID
        var name: String
        var manifestPath: String
        /// The whole file, as text. Nil when it could not be read, so the
        /// record of the app survives even when its file did not.
        var yaml: String?
    }
}

/// The drafts on disk, newest first.
struct DraftStore {
    let folder: URL

    init(storage: BuildStorage = BuildStorage()) {
        folder = storage.drafts
    }

    /// How many are kept. A draft is a few kilobytes of text, and the point of
    /// keeping more than one is the day the newest was written after the
    /// damage.
    static let keep = 20

    /// Sorts on the date inside the file rather than on the file name or the
    /// modification date. The name is for a human reading the folder; the date
    /// is the fact.
    func list() -> [Draft] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(Draft.self, from: data)
            }
            .sorted { $0.savedAt > $1.savedAt }
    }

    @discardableResult
    func write(_ draft: Draft) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = folder.appendingPathComponent("draft-\(Self.stamp(draft.savedAt)).json")
        try encoder.encode(draft).write(to: url, options: .atomic)
        prune()
        return url
    }

    /// The oldest go once there are more than `keep`. By name, which sorts by
    /// time because the stamp is fixed width and starts at the year.
    private func prune() {
        let files = ((try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for file in files.dropFirst(Self.keep) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// `2026-08-11-142309`. Sortable, and readable in Finder.
    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: date)
    }
}

// MARK: - Saving one, and getting one back

@MainActor
extension AppState {

    /// Everything the app holds about every linked app, right now.
    ///
    /// `flushSave` first, and it is the whole reason this is not one line: the
    /// file on disk is up to 250 ms behind the keyboard, and a draft that
    /// copies the file before that write lands is a draft missing the last
    /// thing the developer typed.
    func draftOfEverything() -> Draft {
        flushSave()
        return Draft(savedAt: Date(), apps: linkedApps.map { record in
            Draft.App(id: record.id, name: record.name, manifestPath: record.manifestPath,
                      yaml: try? String(contentsOfFile: record.manifestPath, encoding: .utf8))
        })
    }

    func saveDraft() {
        do {
            try DraftStore().write(draftOfEverything())
            draftSavedAt = Date()
        } catch {
            errorMessage = "The draft could not be written. \(error.localizedDescription)"
        }
    }

    func revealDrafts() {
        let folder = BuildStorage().drafts
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    /// Puts back what is missing, and only what is missing.
    ///
    /// A `store.yaml` that is still on disk is never written over, whatever the
    /// draft holds: the file is the developer's work and the draft is older
    /// than it by definition. What comes back is the file that is gone and the
    /// link that no longer points anywhere, which is what an update loses.
    ///
    /// A full revert is a separate act with a separate risk, and the folder
    /// button is how to do it: the draft is readable text.
    func restore(_ draft: Draft) {
        flushSave()
        var files = 0
        var apps = 0
        for app in draft.apps {
            let url = URL(fileURLWithPath: app.manifestPath)
            if !FileManager.default.fileExists(atPath: app.manifestPath), let yaml = app.yaml {
                do {
                    try FileManager.default.createDirectory(
                        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try yaml.write(to: url, atomically: true, encoding: .utf8)
                    files += 1
                } catch {
                    // Keep whatever came back before the refusal. A half
                    // recovery that is on disk is worth more than a report
                    // about the half that is not.
                    persistLinkedApps()
                    errorMessage = "\(app.name) could not be written back. \(error.localizedDescription)"
                    return
                }
            }
            guard FileManager.default.fileExists(atPath: app.manifestPath),
                  !linkedApps.contains(where: { $0.manifestPath == app.manifestPath }) else {
                continue
            }
            linkedApps.append(LinkedAppRecord(id: app.id, name: app.name,
                                              manifestPath: app.manifestPath))
            apps += 1
        }
        guard files > 0 || apps > 0 else {
            errorMessage = "Nothing was missing. Every app in that draft is already here."
            return
        }
        persistLinkedApps()
        // The window is standing on an empty sidebar when the list was the
        // thing that went, so the first app back is the one to open.
        if manifestURL == nil, let first = linkedApps.first {
            link(manifestAt: URL(fileURLWithPath: first.manifestPath))
        }
        errorMessage = "\(apps) \(apps == 1 ? "app is" : "apps are") back in the sidebar, "
            + "and \(files) \(files == 1 ? "store.yaml file was" : "store.yaml files were") written back."
    }
}
