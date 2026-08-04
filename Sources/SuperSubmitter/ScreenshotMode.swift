import AppKit
import Foundation

/// Drives the app to one screen, in one appearance, for the website
/// screenshots. `tools/screenshots.sh` is the only caller.
///
/// The two things it removes from that script are the two that would otherwise
/// need a permission grant and still not be deterministic: clicking a sidebar
/// row through the accessibility API, and flipping the whole desktop between
/// light and dark to capture both themes.
///
/// It also hands the script the exact rectangle to capture, so no shell code
/// converts between the bottom-left origin that AppKit uses and the top-left
/// origin that `screencapture -R` wants.
///
/// ponytail: launch arguments, behind `#if DEBUG`. The notarized build carries
/// none of it. Delete this file the day a UI test produces the screenshots.
enum ScreenshotMode {

    /// The screen the run wants, or nil for a normal launch.
    static var screen: String? {
        #if DEBUG
        return value(for: "--screenshot")
        #else
        return nil
        #endif
    }

    static var isActive: Bool { screen != nil }

    /// A throwaway suite while a screenshot runs, so the demo app never joins
    /// the linked apps of the developer running the script. The script deletes
    /// the file afterwards.
    static var defaults: UserDefaults {
        guard isActive else { return .standard }
        return UserDefaults(suiteName: "com.rafacst.supersubmitter.screenshots") ?? .standard
    }

    /// The sidebar, whatever the developer running the script prefers.
    ///
    /// `navigationPosition` is an `@AppStorage` on the real defaults, so
    /// without this the chrome in the pictures follows whoever took them.
    /// The sidebar is the documented default and it shows the four zones.
    static var navigationPosition: NavigationPosition? {
        isActive ? .sidebar : nil
    }

    /// A Keychain account that holds nothing.
    ///
    /// The real one does. This binary is unsigned, and the items were written
    /// by a signed build, so every read raises the "allow access" dialog and
    /// blocks the main thread behind it. An account with no items answers
    /// `errSecItemNotFound` and asks nobody anything.
    static var storeAccount: String {
        isActive ? "screenshots-no-credentials" : "store-credentials"
    }

    /// Forces the appearance, so the script leaves the system setting alone.
    static func applyAppearance() {
        #if DEBUG
        switch value(for: "--appearance") {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        #endif
    }

    /// Puts the app on the named screen.
    @MainActor
    static func apply(to state: AppState) {
        #if DEBUG
        guard let screen else { return }
        // The welcome screen is the one that needs no app, so linking is
        // driven by the flag and never by the screen name.
        if let path = value(for: "--manifest") {
            state.link(manifestAt: URL(fileURLWithPath: path))
        }
        switch screen {
        case "welcome":
            state.showOnboarding = false
        case "onboarding":
            state.showOnboarding = true
        default:
            state.showOnboarding = false
            if let tab = Tab.allCases.first(where: { $0.title.lowercased() == screen }) {
                state.selectedTab = tab
            }
        }
        #endif
    }

    /// Sizes the window, puts it at a known place, and prints the rectangle
    /// that `screencapture -R` takes. The script waits for that line, so it
    /// also serves as "the window is up".
    @MainActor
    static func placeWindow() {
        #if DEBUG
        guard isActive,
              // The MenuBarExtra owns a window too. The real one is the big one.
              let window = NSApp.windows.filter(\.isVisible)
                  .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }),
              let screen = window.screen ?? NSScreen.main else { return }

        let visible = screen.visibleFrame
        let size = NSSize(width: min(1280, visible.width - 80),
                          height: min(820, visible.height - 80))
        let origin = NSPoint(x: visible.minX + 40, y: visible.maxY - size.height - 40)
        window.setFrame(NSRect(origin: origin, size: size), display: true)

        // `screencapture -R` photographs a rectangle of the screen, not a
        // window. Whatever sits on top lands in the picture, including the
        // editor of whoever runs this. Floating clears the normal window level
        // and keeps the shot to this app.
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()

        // `screencapture` counts from the top of the primary display, and
        // AppKit counts from the bottom of it.
        let frame = window.frame
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let top = primaryHeight - frame.maxY
        print("CAPTURE_RECT \(Int(frame.minX)),\(Int(top)),\(Int(frame.width)),\(Int(frame.height))")
        fflush(stdout)
        #endif
    }

    private static func value(for flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
