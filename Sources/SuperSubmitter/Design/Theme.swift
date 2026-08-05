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
    static let text = Color(light: 0x1D1D1F, dark: 0xF1F1F3)
    static let text2 = Color(light: 0x6B6B70, dark: 0x9A9AA1)
    static let text3 = Color(light: 0x96969B, dark: 0x75757C)

    static let sep = Color(light: .black.opacity(0.10), dark: .white.opacity(0.12))
    static let sep2 = Color(light: .black.opacity(0.055), dark: .white.opacity(0.07))

    static let accent = Color(light: 0x0A6FD8, dark: 0x4D9BF7)
    static let accentText = Color.white

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

// MARK: - The shared pieces

extension View {
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

/// A titled card on a tab. Every tab body is a stack of these.
struct Card<Content: View>: View {
    var title: String?
    var trailing: AnyView?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, trailing: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if title != nil || trailing != nil {
                HStack {
                    if let title {
                        Text(title).font(.system(size: 12.5, weight: .semibold))
                    }
                    Spacer(minLength: 8)
                    if let trailing { trailing }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                Hairline()
            }
            content
        }
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.sep, lineWidth: Theme.hairline))
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
                    .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
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
                Capsule().fill(isOn ? Theme.accent : Theme.sep)
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
