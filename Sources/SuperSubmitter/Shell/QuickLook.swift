import AppKit
import CryptoKit
import QuickLookUI

/// The system preview panel, for the screenshots on the Media tab.
///
/// The tab draws a grid of real image files at 150 points and holds the real
/// `URL` for each one. Until this existed, a developer who wanted to check a
/// screenshot at full size opened Finder and found it by hand, which is the
/// exact errand Quick Look has existed to remove since 2007.
///
/// One item at a time, on purpose. The panel takes an array and offers arrow
/// keys through it, but the tiles are grouped by device class and a single flat
/// list across every group would step from a phone screenshot to a Vision one
/// with nothing saying the group had changed.
///
/// `QLPreviewPanel` is a shared, app-wide panel and it does not take a data
/// source from whoever asks. It walks the responder chain for an object that
/// answers `acceptsPreviewPanelControl`, and hands control to the first one
/// that says yes. `AppDelegate` is that object: it sits in the chain behind
/// every window, so the panel works whichever window is key. See
/// `SuperSubmitterApp.swift`.
/// `@preconcurrency` on the conformance, and it is honest rather than a
/// silencer. `QLPreviewPanelDataSource` predates Swift concurrency and is
/// declared without isolation, but AppKit only ever calls a data source on the
/// main thread, so the two methods below are `@MainActor` in fact. The
/// attribute states the mismatch instead of hiding it, and turns it into a
/// runtime check rather than a compile-time error.
@MainActor
final class QuickLook: NSObject, @preconcurrency QLPreviewPanelDataSource {
    static let shared = QuickLook()

    private var url: NSURL?

    /// Where a failed download says so. The shell sets it once, the same way it
    /// hands `Updater` a way to close the sheets. See `SuperSubmitterApp`.
    ///
    /// A closure and not an `AppState` reference: this panel is app-wide and
    /// outlives any one app being open, and the four call sites are in three
    /// different views.
    static var report: ((String) -> Void)?

    /// Opens the panel on one file, or moves the open panel onto it.
    ///
    /// Pressing another tile while the panel is up replaces its contents
    /// rather than closing and reopening, which is what the panel does for
    /// Finder and what the report asks a popover to do for the same reason.
    ///
    /// A store URL is taken as well as a file. The live strips and the Store
    /// Page draw what the store shows today, and those are `https` addresses:
    /// the file check below turned every one of them into a press that did
    /// nothing at all. Quick Look previews a file, so a remote one is fetched
    /// to the cache first and the panel opens on that.
    static func show(_ url: URL) {
        switch route(url) {
        case let .present(file): present(file)
        case let .fetch(remote): showRemote(remote)
        case .missing: break
        }
    }

    /// What a press has to do before the panel can open, decided on its own so
    /// that a test can ask without a window server standing behind it.
    enum Route: Equatable {
        /// A file on this Mac. It opens straight away.
        case present(URL)
        /// A store address. It has to reach the disk first.
        case fetch(URL)
        /// A path naming no file. Nothing to show and nothing to fetch.
        case missing
    }

    /// `nonisolated` because it is a question about the disk and not about the
    /// window: nothing in it touches the panel.
    nonisolated static func route(_ url: URL) -> Route {
        guard url.isFileURL else { return .fetch(url) }
        return FileManager.default.fileExists(atPath: url.path) ? .present(url) : .missing
    }

    /// Downloads to the cache, then opens the panel on the local copy.
    ///
    /// Nothing here blocks the main actor: the fetch and the write both happen
    /// inside `RemotePreview`, which is not on it, and this returns at once so
    /// the click never holds a frame.
    private static func showRemote(_ url: URL) {
        Task {
            do {
                present(try await RemotePreview.localItem(for: url))
            } catch {
                // A press that does nothing is the bug this fixes, so a
                // failure says so rather than repeating it more quietly.
                report?("That screenshot could not be opened. \(error.localizedDescription)")
            }
        }
    }

    private static func present(_ url: URL) {
        shared.url = url as NSURL
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// Space bar behaviour: open on the file, or close if it is already up.
    ///
    /// This is what the key does in Finder, and the tile that calls it is the
    /// selected object, so the same key reads the same way.
    static func toggle(_ url: URL) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            show(url)
        }
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        url == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        url
    }
}

/// The store's own screenshots, on the disk, so Quick Look can open them.
///
/// Quick Look previews a file and nothing else. What the stores hand back is an
/// `https` address, so the picture has to be here before the panel can show it.
///
/// The caches directory and not Application Support: every byte in here is one
/// request away from being had again, which is exactly what `.cachesDirectory`
/// is for, and the system may empty it whenever it likes.
///
/// Not on the main actor. The fetch suspends and the write blocks, and the
/// window has to keep drawing through both.
enum RemotePreview {
    enum Failure: LocalizedError, Equatable {
        case notAPicture(Int)

        var errorDescription: String? {
            switch self {
            case let .notAPicture(status):
                "The store answered \(status) for it."
            }
        }
    }

    static var folder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Super Submitter/LivePreviews", isDirectory: true)
    }

    /// Where one remote address is kept.
    ///
    /// The name is a digest of the whole address, so two screenshots that end
    /// in `1290x2796bb.png` under different paths are two files, and the same
    /// screenshot asked for twice is one. Stable across launches, which a
    /// `Hasher` value is not: Swift seeds that per process, so it would miss
    /// every cache hit after a relaunch.
    ///
    /// The extension is carried over, because Quick Look picks its renderer off
    /// it. An address that ends in no extension gets `png`: both stores answer
    /// screenshots, and a preview of an unknown type shows a blank page.
    static func cacheURL(for remote: URL, in folder: URL) -> URL {
        let digest = SHA256.hash(data: Data(remote.absoluteString.utf8))
            .map { String(format: "%02x", $0) }.joined().prefix(32)
        let raw = remote.pathExtension.lowercased()
        let allowed = raw.count >= 2 && raw.count <= 4
            && raw.allSatisfy { $0.isLetter || $0.isNumber }
        return folder.appendingPathComponent("\(digest).\(allowed ? raw : "png")")
    }

    /// The local file for a remote address, fetched once and reused after that.
    ///
    /// `fetch` is a parameter so a test can prove the conversion without the
    /// live internet standing behind it.
    static func localItem(
        for remote: URL, in folder: URL? = nil,
        fetch: (URL) async throws -> Data = Self.download) async throws -> URL {
        let folder = folder ?? Self.folder
        let file = cacheURL(for: remote, in: folder)
        // A cached file is the whole point: a developer clicking along a strip
        // of ten screenshots asks for each one more than once.
        if FileManager.default.fileExists(atPath: file.path) { return file }
        let data = try await fetch(remote)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
        return file
    }

    /// A refused request is a failure and not an empty picture. Without this
    /// check a 403 page was written to the cache as a `.png` and the panel
    /// opened on it showing nothing, which is the silent no-op again.
    private static func download(_ remote: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: remote)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.notAPicture(http.statusCode)
        }
        return data
    }
}
