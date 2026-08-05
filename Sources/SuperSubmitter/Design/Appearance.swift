import AppKit
import SwiftUI

/// Light, dark, or whatever the Mac is set to.
///
/// Every colour in `Theme` is already a light and dark pair that resolves from
/// the view's appearance, so this sets `NSApp.appearance` and the whole app
/// follows. `preferredColorScheme` would move the SwiftUI colours and leave
/// the AppKit controls in Settings on the other side.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    static let defaultsKey = "appearance"

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// nil hands the choice back to the Mac.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    @MainActor
    func apply() {
        NSApp.appearance = nsAppearance
    }

    /// The stored choice, applied at launch before any window draws.
    ///
    /// A screenshot run pins the appearance from the command line, so this
    /// leaves it alone rather than fight it for the same property.
    @MainActor
    static func applyStored(_ defaults: UserDefaults = .standard) {
        guard !ScreenshotMode.pinsAppearance else { return }
        let stored = defaults.string(forKey: defaultsKey) ?? ""
        (Appearance(rawValue: stored) ?? .system).apply()
    }
}
