import AppKit

/// What the app says about itself while the developer is looking at something
/// else.
///
/// Two signals share one tile, so they live together and one file decides which
/// of them wins.
///
/// - A **progress bar** across the foot of the icon while an apply is
///   uploading. The app tells the developer on screen that "Apple processes the
///   build after the upload. This is the longest wait in the app", and a wait
///   that long is a wait people leave. Until this existed the app said nothing
///   at all once its window was behind another one.
/// - A **badge** carrying the console steps still to do. Those are the steps no
///   API can perform, so the number is a number the developer can act on, which
///   is the only kind of badge worth drawing.
///
/// The progress wins while it is running. A bar and a badge on one 128 point
/// tile is two readings of the same icon, and the upload is the one with a
/// clock on it.
@MainActor
enum DockTile {
    private static let view = DockProgressView(
        frame: NSRect(x: 0, y: 0, width: 128, height: 128))
    /// The last whole percent drawn. See `progress(_:)`.
    private static var drawn = -1
    /// What the badge would say if no upload were covering it.
    private static var pendingBadge: String?

    /// The Dock tile, or nothing at all when there is no application.
    ///
    /// `NSApp` is an implicitly unwrapped optional and it is genuinely nil
    /// until an `NSApplication` exists. `swift test` never makes one, and the
    /// suite reaches this through `resetRunState` and `loadConsoleMarks`, so a
    /// bare `NSApp.dockTile` trapped the whole run. Optional chaining here
    /// rather than a guard at each call site: there is one reason the tile can
    /// be missing, so there is one place that knows about it.
    private static var tile: NSDockTile? { NSApp?.dockTile }

    /// Draws the bar. `fraction` is 0 to 1.
    ///
    /// Rounded to whole percent before anything is compared, because the
    /// uploader emits far more often than a 128 point tile can show. A 40 MB
    /// package reports hundreds of times, and every one of them would be a
    /// full redraw of the icon for a bar that moved by less than a pixel.
    static func progress(_ fraction: Double) {
        guard let tile else { return }
        let percent = Int((fraction * 100).rounded())
        guard percent != drawn else { return }
        drawn = percent
        view.fraction = max(0, min(1, fraction))
        if tile.contentView !== view {
            // The badge would draw over the bar. It is restored by `clear()`.
            tile.badgeLabel = nil
            tile.contentView = view
        }
        tile.display()
    }

    /// Puts the tile back to the plain app icon, and returns the badge to it.
    static func clear() {
        guard drawn != -1, let tile else { return }
        drawn = -1
        tile.contentView = nil
        tile.badgeLabel = pendingBadge
        tile.display()
    }

    /// The count of console steps still to do, or nothing at all for zero.
    ///
    /// Never "0". A badge that says the work is finished is a badge asking to
    /// be dismissed, and the absence of one already says it.
    static func badge(_ count: Int) {
        pendingBadge = count > 0 ? "\(count)" : nil
        // An upload owns the tile until it ends, and `clear()` restores this.
        guard drawn == -1, let tile else { return }
        tile.badgeLabel = pendingBadge
    }
}

/// The app icon with a bar across its foot.
///
/// `NSDockTile` hands its content view the whole 128 point tile and asks it to
/// draw, so the icon is drawn here too. Anything this view does not paint is
/// transparent, and an app that vanished from the Dock during an upload would
/// be a worse bug than the one this fixes.
private final class DockProgressView: NSView {
    var fraction = 0.0

    override func draw(_ dirtyRect: NSRect) {
        NSApp?.applicationIconImage?.draw(in: bounds)

        // Inset from the icon's own edge. The Dock draws the tile with a
        // little air around the artwork, and a bar hard against the bounds
        // reads as a bar belonging to the Dock rather than to this app.
        let track = NSRect(x: bounds.width * 0.12,
                           y: bounds.height * 0.10,
                           width: bounds.width * 0.76,
                           height: bounds.height * 0.10)
        let radius = track.height / 2

        // A dark trough under the fill, because the icon behind it is an
        // arbitrary picture and a light bar on a light icon is no bar at all.
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()
        NSColor.white.withAlphaComponent(0.35).setStroke()
        let edge = NSBezierPath(roundedRect: track.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: radius, yRadius: radius)
        edge.lineWidth = 1
        edge.stroke()

        // Nothing at all at zero. A rounded rectangle of zero width still
        // draws its two end caps, so an upload that had not started yet
        // showed a small filled dot that looked like progress.
        let inner = track.insetBy(dx: 2, dy: 2)
        guard fraction > 0 else { return }
        var fill = inner
        // Never narrower than its own cap, or the fill draws as a lens rather
        // than a bar for the first few percent.
        fill.size.width = max(inner.height, inner.width * fraction)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: fill,
                     xRadius: inner.height / 2, yRadius: inner.height / 2).fill()
    }
}
