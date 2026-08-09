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

/// The light and dark switch in the header band.
///
/// One switch, and no words on it. Evoque puts a moon in the knob of a capsule
/// and Vocalyn draws a single sun glyph; neither labels its two states, and the
/// labels were the expensive part. A two-state pill reading "Light Dark" costs
/// about 90 points of a band that already carries a title, a question, and up
/// to five controls.
///
/// It writes the key the Settings picker writes, and nothing else, so the two
/// controls can never disagree about what the app is set to.
///
/// The switch has two states and `Appearance` has three, so System is the one
/// thing it cannot say. A right-click gives it back. Without that, the first
/// touch of this switch would move a person off System for good and Settings
/// would be the only way home — a trade worth three lines to avoid.
struct AppearanceSwitch: View {
    @AppStorage(Appearance.defaultsKey) private var appearance: Appearance = .system
    /// What the Mac is doing, for the case where the app is following it. A
    /// switch that shows a sun on a dark screen is a switch that is wrong.
    @Environment(\.colorScheme) private var scheme

    private var isDark: Bool {
        switch appearance {
        case .dark: true
        case .light: false
        case .system: scheme == .dark
        }
    }

    var body: some View {
        Button {
            withAnimation(.smooth(duration: 0.22)) {
                appearance = isDark ? .light : .dark
            }
            appearance.apply()
        } label: {
            // The knob moves on an offset, and the stack is centred. It used to
            // be the stack's own alignment that placed it, and an alignment is
            // not a number: there is nothing between leading and trailing to
            // interpolate, so the knob crossed the whole track in one frame
            // whatever animation was asked for. The same swap is why it sat
            // flush against the end cap with its shadow over the edge. Seven
            // points of travel leaves the two points of track at the ends that
            // it already had above and below. `SmallToggle` reads the same.
            ZStack {
                // The off track has to be visible against the band behind it,
                // which is why this is `controlEdge` and not `sep`. Same
                // reasoning as `SmallToggle`.
                Capsule().fill(isDark ? Theme.accent : Theme.controlEdge)
                Circle()
                    .fill(.white)
                    .frame(width: 16, height: 16)
                    .overlay(Image(systemName: isDark ? "moon.fill" : "sun.max.fill")
                        .font(.system(size: 9, weight: .bold))
                        // Both glyphs resolve in the appearance they name, so
                        // the sun is only ever the light-mode amber and the
                        // moon only ever the dark-mode blue. Each clears 3 to 1
                        // on the white knob.
                        .foregroundStyle(isDark ? Theme.accentFill : Theme.yellow)
                        .contentTransition(.symbolEffect(.replace)))
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                    .offset(x: isDark ? 7 : -7)
            }
            .frame(width: 34, height: 20)
            .padding(2)
            .contentShape(.rect)
            // On the switch and not only in the button's action. `appearance`
            // is `@AppStorage`, so the new value arrives back through the
            // defaults store and lands outside the transaction the action
            // opened. The button animated nothing for that reason.
            .animation(.smooth(duration: 0.22), value: isDark)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Match the Mac") {
                appearance = .system
                appearance.apply()
            }
        }
        .help("Light or dark. Right-click to match the Mac.")
        .accessibilityLabel("Appearance")
        .accessibilityValue(appearance == .system
                            ? "Matching the Mac, currently \(isDark ? "dark" : "light")"
                            : appearance.label)
    }
}
