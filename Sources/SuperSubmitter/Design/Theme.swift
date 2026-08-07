import SwiftUI

/// The design tokens, one for one with the mockup.
///
/// Every colour is a light and dark pair. `Color(light:dark:)` resolves from
/// the appearance of the view, so no screen branches on the colour scheme.
enum Theme {
    // Surfaces, from the back of the window to the front.
    static let bg = Color(light: 0xECECEC, dark: 0x1B1B1D)
    static let content = Color(light: 0xFFFFFF, dark: 0x1E1E21)
    static let raised = Color(light: 0xFBFBFA, dark: 0x27272B)
    static let sunken = Color(light: 0xF5F4F2, dark: 0x1A1A1C)
    static let field = Color(light: 0xFFFFFF, dark: 0x2C2C30)

    // Text, from the loudest to the quietest.
    ///
    /// Every tier clears 4.5 to 1 against the worst surface it ever lands on,
    /// which is `sunken` in light and `field` in dark, not the page. The old
    /// `text3` was 2.9 to 1 in light and 3.6 to 1 in dark, and it carried the
    /// placeholders, the counters, and every "Apple allows 35 pages" note, so
    /// the quietest tier was the one nobody could read. The other two moved
    /// with it, to keep three steps that are still three steps apart.
    static let text = Color(light: 0x1D1D1F, dark: 0xF1F1F3)
    static let text2 = Color(light: 0x5C5C63, dark: 0xAEAEB6)
    static let text3 = Color(light: 0x6E6E78, dark: 0x9696A0)

    static let sep = Color(light: .black.opacity(0.10), dark: .white.opacity(0.12))
    static let sep2 = Color(light: .black.opacity(0.055), dark: .white.opacity(0.07))

    /// The edge of something you can click or type into.
    ///
    /// WCAG 1.4.11 asks 3 to 1 of the boundary that tells you a control is a
    /// control. `sep` is 1.25 to 1 in light and 1.56 to 1 in dark: right for a
    /// card, invisible on a text field. It stays a hairline, because the rule
    /// is about contrast and not about thickness.
    static let controlEdge = Color(light: 0x86868C, dark: 0x7C7C82)

    static let accent = Color(light: 0x0A6FD8, dark: 0x4D9BF7)
    static let accentText = Color.white

    /// Fills that carry white text.
    ///
    /// The display tints above are tuned to be read AS colour against a dark
    /// surface, which makes them too light to put white on: `accent` in dark
    /// mode is about 2.5 to 1, well under the 4.5 to 1 that body text needs.
    /// These are the same hues, deep enough to sit under white in both modes.
    static let accentFill = Color(light: 0x0A6FD8, dark: 0x2C6ECF)
    static let purpleFill = Color(light: 0x6A35C9, dark: 0x6A44C4)

    /// Red says irreversible, and nothing else in the app may use it.
    static let red = Color(light: 0xC9302A, dark: 0xFF5C50)
    static let redFill = Color(light: 0xC9302A, dark: 0xC9362D)
    static let green = Color(light: 0x1C7F3C, dark: 0x42C463)
    static let yellow = Color(light: 0x9A6100, dark: 0xE2A336)

    /// Four more hues, so a tab of nine sections is nine pictures and not one
    /// blue wall. They carry no meaning of their own.
    static let purple = Color(light: 0x6A35C9, dark: 0xB294FF)
    static let teal = Color(light: 0x0C7681, dark: 0x4FCFDC)
    static let pink = Color(light: 0xBE1F66, dark: 0xFF7FB6)
    static let orange = Color(light: 0xB4531A, dark: 0xFF9A52)

    /// The store brands. A logo is a fixed colour and never follows the
    /// appearance, except the Apple mark, which is a silhouette.
    static let appleMark = Color(light: 0x000000, dark: 0xFFFFFF)
    static let playBlue = Color(hex: 0x4285F4)
    static let playGreen = Color(hex: 0x34A853)
    static let playYellow = Color(hex: 0xFBBC04)
    static let playRed = Color(hex: 0xEA4335)

    static let greenBg = Color(light: Color(hex: 0x1C7F3C).opacity(0.10),
                               dark: Color(hex: 0x42C463).opacity(0.14))
    static let yellowBg = Color(light: Color(hex: 0x9A6100).opacity(0.10),
                                dark: Color(hex: 0xE2A336).opacity(0.15))
    static let redBg = Color(light: Color(hex: 0xC9302A).opacity(0.09),
                             dark: Color(hex: 0xFF5C50).opacity(0.14))

    static let mono = Font.system(size: 11, design: .monospaced)
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // The window itself.
    static let windowRadius: CGFloat = 11
    static let sidebarWidth: CGFloat = 240
    static let headerHeight: CGFloat = 52
    static let hairline: CGFloat = 0.5

    /// The content is the window surface, and the sidebar is a panel floating
    /// on it. The gap is the separator, so no rule runs between the two.
    static let panelGap: CGFloat = 8
    static let panelRadius: CGFloat = 10
    static let panelEdge = Color(light: .black.opacity(0.16), dark: .white.opacity(0.20))
}

// MARK: - The colour helper

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// One colour that resolves from the appearance of the view.
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        })
    }

    init(light: UInt32, dark: UInt32) {
        self.init(light: Color(hex: light), dark: Color(hex: dark))
    }
}

// MARK: - Input limits

extension Binding where Value == String {
    /// Refuses input that would carry the text past `limit`.
    ///
    /// Growth is refused, never the text that is already there. A value that
    /// arrives over the limit from an import or a paste stays whole, and the
    /// field can always be edited back down, so the app still never shortens
    /// anything the developer wrote. Section 7 of context.md.
    func limited(to limit: Int?) -> Binding<String> {
        guard let limit else { return self }
        return Binding(
            get: { wrappedValue },
            set: { new in
                guard new.count <= limit || new.count < wrappedValue.count else { return }
                wrappedValue = new
            })
    }
}

extension Optional {
    /// True while a value is there, and clears it when set to false.
    ///
    /// `confirmationDialog(_:isPresented:presenting:)` wants a `Bool` binding
    /// beside the value it presents, so every panel that confirms an action
    /// wrote the same three-line `Binding(get:set:)`. `$item.isPresent` is
    /// that binding.
    var isPresent: Bool {
        get { self != nil }
        set { if !newValue { self = nil } }
    }
}

/// Runs a store call the way every Managing panel reports one: busy while it
/// runs, and the message on the line if it throws.
///
/// The panels are the only place this belongs. A failed read costs nothing and
/// is never a plan row, so it never reaches `AppState` or the run log.
@MainActor
func track(_ busy: Binding<Bool>, _ error: Binding<String?>,
           _ work: @escaping @MainActor () async throws -> Void) {
    busy.wrappedValue = true
    error.wrappedValue = nil
    Task {
        do { try await work() }
        catch let failure { error.wrappedValue = failure.localizedDescription }
        busy.wrappedValue = false
    }
}

// MARK: - The shared pieces

/// The line a panel shows when a store read failed.
///
/// Orange and not red. Red says irreversible, and a read that failed changed
/// nothing, so it is a warning and the developer presses the button again.
struct ErrorLine: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 11.5)).foregroundStyle(Theme.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension View {
    /// The panel that a card on a tab sits on.
    ///
    /// One definition on purpose. Five private copies of this chain grew
    /// across the tabs, and they disagreed about the corner radius, which is
    /// the exact drift the first copy was written to prevent. A panel that
    /// wants another radius is a different thing, not a card: a sheet, an
    /// onboarding illustration, and the entry cards all keep their own.
    func storePanel(padding: CGFloat = 13, horizontal: CGFloat? = nil,
                    background: Color = Theme.raised,
                    border: Color = Theme.sep,
                    borderWidth: CGFloat = Theme.hairline) -> some View {
        self.padding(.vertical, padding)
            .padding(.horizontal, horizontal ?? padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(border, lineWidth: borderWidth))
    }

    /// Turns a working area into a panel that floats on the window surface: a
    /// rounded fill, a hairline edge, and a shadow that lifts it off the back.
    func panelSurface() -> some View {
        self
            .background(Theme.raised)
            .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius))
            // A full point, not a hairline. The panel sits on a surface close
            // to its own tone, and half a point disappears into it.
            .overlay(RoundedRectangle(cornerRadius: Theme.panelRadius)
                .strokeBorder(Theme.panelEdge, lineWidth: 1))
            .shadow(color: .black.opacity(0.20), radius: 6, y: 1)
    }
}

/// A hairline rule. AppKit draws a 1 pixel line, and the mockup asks for half
/// a point, so this uses a filled shape and not `Divider`.
struct Hairline: View {
    var color: Color = Theme.sep
    var body: some View {
        Rectangle().fill(color).frame(height: Theme.hairline)
    }
}

/// The small state chip: `Done`, `Needed`, `Unknown`, `Not applicable`.
struct StatePill: View {
    let text: String
    let foreground: Color
    let background: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(background, in: RoundedRectangle(cornerRadius: 5))
    }
}

/// A line that reports an error, or something the developer has to act on.
///
/// It carries a colour and a tinted background because a warning set in the
/// same grey as the help beside it reads as one more sentence of help. Yellow
/// and not red: red says irreversible and nothing else in the app may use it.
struct WarningNote: View {
    let text: String
    var width: CGFloat?

    init(_ text: String, width: CGFloat? = nil) {
        self.text = text
        self.width = width
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 11.5))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.yellow)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(width: width, alignment: .leading)
        .background(Theme.yellowBg, in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Warning. \(text)")
    }
}

/// The plain push button used across the tabs.
struct QuietButton: View {
    let title: String
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 11)
                .padding(.vertical, 4)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Theme.controlEdge, lineWidth: Theme.hairline))
        }
        .buttonStyle(.plain)
    }
}

/// The switch on the Plan toolbar.
struct SmallToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.12)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                // The off track is the state, so it has to be visible against
                // the bar behind it. `sep` reads as nothing there.
                Capsule().fill(isOn ? Theme.accent : Theme.controlEdge)
                Circle()
                    .fill(.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
            }
            .frame(width: 34, height: 20)
            .padding(2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dry run")
        .accessibilityValue(isOn ? "On" : "Off")
    }
}
