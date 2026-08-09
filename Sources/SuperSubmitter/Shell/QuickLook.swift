import AppKit
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

    /// Opens the panel on one file, or moves the open panel onto it.
    ///
    /// Pressing another tile while the panel is up replaces its contents
    /// rather than closing and reopening, which is what the panel does for
    /// Finder and what the report asks a popover to do for the same reason.
    static func show(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
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
