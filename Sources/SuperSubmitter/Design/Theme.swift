import AppKit
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

    /// The edge of a card.
    ///
    /// Heavier in dark than the light value mirrors, and it has to be. A card
    /// is `raised` on `content`, which is 1.12 to 1 in dark — the two tones
    /// are four percent of luminance apart, so the fill carries none of the
    /// elevation and the whole boundary rests on this line. At 0.12 the line
    /// measured 1.63 to 1 against the page and the cards on the Build tab had
    /// no visible edges at all. Dark mode has no shadow to fall back on, which
    /// is why the HIG asks for the border there and not in light.
    static let sep = Color(light: .black.opacity(0.10), dark: .white.opacity(0.22))
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
    /// The third fill, for the second number on a card of numbers.
    ///
    /// `teal` in dark is 0x4FCFDC, which is a display tint and about 1.9 to 1
    /// under white. This is the same hue taken down until white clears it:
    /// 5.35 to 1 in light and 5.56 to 1 in dark.
    static let tealFill = Color(light: 0x0C7681, dark: 0x11737E)

    /// Red says irreversible, and nothing else in the app may use it.
    ///
    /// Green and yellow are darker than the hue a status word wants, and the
    /// reason is the pill. Every other use of these two lands on `content` or
    /// `raised`, where the old values cleared 4.5 to 1 easily. A status pill
    /// puts the word on `greenBg` or `yellowBg` instead, which is the same hue
    /// at a tenth, so it lifts the floor and takes the ratio down with it:
    /// "Done" measured 4.23 to 1 and "Needed" 4.38 to 1 on the Release tab.
    /// The pill is where these two are read most, so the pill sets the value.
    static let red = Color(light: 0xC42A24, dark: 0xFF7A6E)
    static let redFill = Color(light: 0xC9302A, dark: 0xC9362D)
    static let green = Color(light: 0x16702F, dark: 0x42C463)
    static let yellow = Color(light: 0x8A5800, dark: 0xE2A336)

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

    /// The same hue at a tenth. It follows the tint above, so a pill only ever
    /// mixes one green with one green.
    static let greenBg = Color(light: Color(hex: 0x16702F).opacity(0.10),
                               dark: Color(hex: 0x42C463).opacity(0.14))
    static let yellowBg = Color(light: Color(hex: 0x8A5800).opacity(0.10),
                                dark: Color(hex: 0xE2A336).opacity(0.15))
    static let redBg = Color(light: Color(hex: 0xC42A24).opacity(0.09),
                             dark: Color(hex: 0xFF7A6E).opacity(0.14))

    // MARK: - The type

    /// Every font in the app, at one size and in one face.
    ///
    /// It replaced about 670 hand-written system-font calls across thirty
    /// files. Each one stated a size in points, so the app had no scale it
    /// could change: making the text larger meant editing every call site, and
    /// the sizes drifted because nothing held them together.
    ///
    /// This is that one place. `fontScale` moves every size at once and keeps
    /// the tiers the design set, and the face is the body of this function.
    static func font(size: CGFloat, weight: Font.Weight = .regular,
                     design: Font.Design = .default) -> Font {
        .system(size: scaled(size), weight: weight, design: design)
    }

    /// How much larger than the design's own numbers the app draws.
    ///
    /// The design was set at 11 to 13 points, which is smaller than the macOS
    /// system font and small enough that the long explanatory sentences on
    /// every tab were hard work to read.
    static let fontScale: CGFloat = 1.15

    /// Rounded to a half point, and not to a whole one.
    ///
    /// The design has tiers half a point apart (10.5, 11, 11.5, 12, 12.5), and
    /// whole-point rounding would collapse neighbours into each other, so a
    /// caption and the body text beside it would come out the same size.
    static func scaled(_ size: CGFloat) -> CGFloat {
        (size * fontScale * 2).rounded() / 2
    }

    static let mono = font(size: 11, design: .monospaced)
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        font(size: size, weight: weight, design: .monospaced)
    }

    // MARK: - The type scale
    //
    // Sizes were magic numbers in about thirty view files: 11, 11.5, 12, 12.5,
    // 13, 13.5, 14, 17, 25. A change of tier meant a sweep, so the tiers never
    // changed. These are the tiers. Call sites move onto them as they are
    // touched, and a mechanical sweep of the rest would be a large diff that
    // nothing can test.

    /// The name of the screen, in the header band.
    static let screenTitle = Theme.font(size: 21, weight: .semibold)
    /// The question under the screen title.
    static let screenSubtitle = Theme.font(size: 12)
    /// The heading over a group of cards.
    static let sectionHeader = Theme.font(size: 12.5, weight: .semibold)
    /// The heading on a single card.
    static let cardTitle = Theme.font(size: 13, weight: .semibold)
    static let body = Theme.font(size: 12.5)
    static let caption = Theme.font(size: 11.5)

    // The window itself.
    static let windowRadius: CGFloat = 11
    /// Tall enough to carry a title at `screenTitle` with the question under
    /// it. It was 52, which held a 14 point title: smaller than the body text
    /// on the tab below it, so the screen named itself more quietly than it
    /// said anything else.
    static let headerHeight: CGFloat = 64
    /// One device pixel, on whatever display is drawing.
    ///
    /// This was the constant 0.5, which is exactly one pixel on a Retina
    /// screen and half of one on every other. Half a pixel has no pixel to
    /// land on, so the stroke antialiased into whichever neighbour the layout
    /// rounded toward: a card drew its border on the sides where the rounding
    /// went its way and drew nothing on the rest, and a rule disappeared
    /// outright. It looked like a bug in the cards. It was one number.
    ///
    /// Every border, rule and stroke in the app reads this, so the fix lands
    /// in all of them at once.
    ///
    /// It asks the window, and not `NSScreen.main`. That property is the
    /// screen holding the window with the keyboard focus, which stops being
    /// this app's screen the moment somebody clicks another app. On a Mac with
    /// a Retina display and a 1x display, this window sitting on the 1x one
    /// read 1 point while it was focused and 0.5 the instant it was not, so
    /// half the borders in the app thinned to nothing every time the developer
    /// switched to Xcode. The window does not move when the focus does.
    ///
    /// ponytail: one window, so the frontmost visible one answers for the app.
    /// A window dragged between displays of different scale corrects on the
    /// next redraw rather than the instant it crosses. Move to
    /// `@Environment(\.pixelLength)` at the call sites if that ever shows.
    static var hairline: CGFloat {
        MainActor.assumeIsolated {
            // Deterministic, and never "whichever window the array listed first".
            let window = NSApp?.keyWindow ?? NSApp?.mainWindow
                ?? NSApp?.windows.first { $0.isVisible && $0.canBecomeMain }
            return 1 / (window?.backingScaleFactor
                        ?? NSScreen.main?.backingScaleFactor ?? 2)
        }
    }

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

    /// Cuts the text to `limit`, coming and going.
    ///
    /// `limited(to:)` refuses growth and keeps whatever is already there,
    /// because shortening a description somebody wrote is destructive. A store
    /// id is the opposite case: an issuer id is a 36 character UUID and a 37th
    /// character is not the developer's writing, it is a paste that picked up
    /// something else. Nothing is lost by cutting it, and the field stops
    /// showing an id the store would refuse.
    ///
    /// The getter cuts too, so a value that reached the state from the
    /// Keychain or from an import is capped on sight and not only on the next
    /// keystroke.
    func capped(to limit: Int?) -> Binding<String> {
        guard let limit else { return self }
        return Binding(
            get: { String(wrappedValue.prefix(limit)) },
            set: { wrappedValue = String($0.prefix(limit)) })
    }

    /// Takes the line breaks out of whatever arrives.
    ///
    /// For a field that holds one line by definition: a key id, an issuer id,
    /// a package name. Return puts a break into a SwiftUI text field on macOS
    /// rather than ending the edit, and a value copied out of a web console
    /// carries one on the end. Either way the field editor then scrolls to a
    /// second, empty line and the value reads as cut in half, and the store
    /// receives an id with a break in it.
    ///
    /// It goes outside `limited(to:)`, so the break is gone before the length
    /// is counted. The other order refuses a 36 character id that arrives with
    /// a newline as 37 characters, which reads as a paste that did nothing.
    var oneLine: Binding<String> {
        Binding(get: { wrappedValue },
                set: { wrappedValue = $0.filter { !$0.isNewline } })
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
            .font(Theme.font(size: 11.5)).foregroundStyle(Theme.orange)
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

    /// The band that floats above scrolling content.
    ///
    /// It takes its own fill below macOS 26, because the band is the page at
    /// rest and only separates itself once there is something above the fold.
    /// `scrolled` is that state, and glass makes it moot: the material already
    /// says "there is content under me".
    func headerSurface(scrolled: Bool) -> some View {
        modifier(HeaderSurface(scrolled: scrolled))
    }

    /// One group of header controls, merged into a single lozenge on macOS 26.
    ///
    /// `morphOn` is the state that decides which controls the cluster holds.
    /// The container can only morph one shape into another if something tells
    /// it a change is coming, and a `ViewBuilder` closure carries no identity
    /// to watch, so the caller names the value.
    func glassCluster<V: Equatable>(spacing: CGFloat = 7,
                                    morphOn value: V) -> some View {
        modifier(GlassCluster(spacing: spacing, token: value))
    }

    /// Lets content dissolve under the band instead of sliding beneath a hard
    /// edge.
    ///
    /// The band is glass, so it already refracts what passes below it. Without
    /// the edge effect the first line of a scroll meets that glass at a hard
    /// boundary and reads as a line cut in half. This is the other half of the
    /// same material and belongs with it.
    func softScrollEdge() -> some View {
        modifier(SoftScrollEdge())
    }

    /// A floating surface that is not a form: a palette, a popover, a
    /// heads-up panel.
    ///
    /// Deliberately not applied to the sheets that hold dense fields. Glass
    /// under body copy is a legibility regression, which is the rule the panel
    /// and the band already follow. A command palette is the case the material
    /// was made for: a small thing over the top of the work, whose whole job
    /// is to feel like it is hovering there rather than replacing the screen.
    func floatingSurface(cornerRadius: CGFloat = 14) -> some View {
        modifier(FloatingSurface(cornerRadius: cornerRadius))
    }

    /// The file this window edits, for the title-bar proxy icon.
    ///
    /// `navigationDocument` takes a `URL` and not an optional, and the app has
    /// no manifest open until one is linked, so the branch lives here rather
    /// than at the call site.
    ///
    /// Nothing sets `isDocumentEdited`, and nothing should. Every field writes
    /// `store.yaml` as it is typed, so the app has no unsaved state to warn
    /// about, and a dot in the title bar would claim one. The report is firm
    /// on this: edited-document state must match what is safely stored.
    /// `SavedChip` in the header is what reports the write, at the moment it
    /// is news.
    @ViewBuilder
    func documentURL(_ url: URL?) -> some View {
        if let url {
            self.navigationDocument(url)
        } else {
            self
        }
    }

    /// The app's animation, and nothing at all under Reduce Motion.
    ///
    /// Every animation in the app goes through here, so the accessibility
    /// setting is honoured in one place rather than in fifty call sites that
    /// would drift apart. It reads `accessibilityReduceMotion`, which follows
    /// System Settings, Accessibility, Display, Reduce motion.
    ///
    /// `.animation(value:)` and never `withAnimation`. `withAnimation` opens a
    /// global transaction that animates every view SwiftUI updates in that
    /// pass, not the property in the braces, and this app has been bitten by
    /// that twice: see `HeaderSurface` and `SavedChip`.
    ///
    /// Reduce Motion means no movement, not no feedback. A view that moves
    /// under this modifier still changes state instantly, so nothing that the
    /// motion was reporting is lost.
    /// The animation is optional, because a caller may already have a reason
    /// of its own to stay still. `StoreSelectionGrid` passes nil until a card
    /// has been pressed, so the grid does not play its selection spring over
    /// the arrival of the whole tab on a first launch.
    func motion<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(Motion(animation: animation, value: value))
    }

    /// The same, for a transition on an insertion or a removal.
    ///
    /// A transition needs the animation to reach it through the transaction
    /// that inserts the view, so this pairs the two rather than leaving a
    /// caller to remember both halves.
    func motionTransition<V: Equatable>(_ transition: AnyTransition,
                                        _ animation: Animation,
                                        value: V) -> some View {
        modifier(MotionTransition(transition: transition,
                                  animation: animation, value: value))
    }
}

// MARK: - Reduce Motion

/// Reads the accessibility setting once, for `View.motion`.
private struct Motion<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation?
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

/// The same rule, for the imperative calls.
///
/// Most animation in the app is a state flag that a view watches, and
/// `View.motion` covers those. A few are commands with no flag behind them: a
/// scroll to an anchor, a step of the onboarding. Those still need
/// `withAnimation`, and this is how they ask for the setting.
///
/// Read it from `@Environment(\.accessibilityReduceMotion)` and pass it here,
/// rather than reading `NSWorkspace` at the call site: the environment value
/// updates the view when the setting changes, and a direct read would leave
/// the app on whatever the setting was when it launched.
@MainActor
func withMotion(_ reduceMotion: Bool, _ animation: Animation,
                _ body: () -> Void) {
    withAnimation(reduceMotion ? nil : animation, body)
}

/// A transition that becomes a plain fade under Reduce Motion.
///
/// A fade and not nothing. The report's rule is that large movement and
/// simulated depth become opacity, and that the feedback survives: a row that
/// appears with no mark at all is a row the reader never saw arrive.
private struct MotionTransition<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let transition: AnyTransition
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content
            .transition(reduceMotion ? .opacity : transition)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : animation, value: value)
    }
}

// MARK: - The floating materials
//
// Liquid Glass is macOS 26 and this app's floor is macOS 14, so every glass
// surface carries both paths. The branch lives here, once per concept, and
// never at a call site: a screen that has to know which OS it is on is a
// screen that will disagree with the next one.
//
// Glass goes on the layers that float over something else, and nowhere else.
// The form cards stay opaque, because glass under dense body copy is a
// legibility regression and this app is a form.

// `PanelSurface` used to live here: a rounded fill, an edge and a shadow that
// made the sidebar float on the window. `NavigationSplitView` draws the
// sidebar's surface itself, in the system's own material, so there is nothing
// left to float.

private struct HeaderSurface: ViewModifier {
    let scrolled: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            // No hairline. The material separates the band from what passes
            // under it, which is the whole job the rule was doing.
            content.glassEffect(.regular, in: .rect(cornerRadius: 0))
        } else {
            content
                .background(scrolled ? Theme.raised : Theme.content)
                .overlay(alignment: .bottom) {
                    Hairline().opacity(scrolled ? 1 : 0)
                }
                // Here, and not at the `withAnimation` that used to set
                // `scrolled`. That one was a global transaction and swept the
                // whole first-run layout in with it. This animates the rule and
                // the fill, which is all the state was ever for.
                .motion(.easeOut(duration: 0.14), value: scrolled)
        }
    }
}

/// The container alone. The caller keeps its own `HStack`, so the fallback is
/// exactly the row this app already drew and nothing moves on macOS 14.
///
/// The container is what lets two neighbouring glass shapes merge into one
/// lozenge and, when one of them appears or leaves, morph rather than pop. The
/// header gains and loses controls constantly — a spinner while a re-check
/// runs, the send action once a release is pending, the read button whenever a
/// read has not failed — so this is where the material earns its keep.
private struct GlassCluster<Token: Equatable>: ViewModifier {
    let spacing: CGFloat
    let token: Token

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
                // The morph is the point. Without it the lozenge jumps to its
                // new width on the frame a control appears, which is the one
                // thing this material is meant not to do.
                .motion(.smooth(duration: 0.28), value: token)
        } else {
            content
        }
    }
}

private struct SoftScrollEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

private struct FloatingSurface: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .background {
                    // Clear, so the glass below is what shows through. A fill
                    // here would be a second surface under the material and
                    // the refraction would have nothing to refract.
                    Color.clear.glassEffect(.regular,
                                            in: .rect(cornerRadius: cornerRadius))
                }
        } else {
            content
                .background(Theme.content)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
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

/// The title bar of a panel that opens as a sheet.
///
/// A sheet has no title bar of its own, so this draws a title and one real close
/// control. Window traffic lights would promise minimise and zoom actions a
/// sheet cannot perform.
///
/// `// ponytail: one bar, two panels. A third sheet gets it for free.`
struct PanelTitleBar: View {
    let title: String
    let close: () -> Void

    static let height: CGFloat = 44

    var body: some View {
        ZStack {
            Text(title).font(Theme.font(size: 13, weight: .semibold))
            HStack {
                Spacer(minLength: 0)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(Theme.font(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.text2)
                        .frame(width: 24, height: 24)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close \(title)")
            }
            .padding(.trailing, 14)
        }
        .frame(height: Self.height)
        .background(Theme.raised)
    }
}

/// The small state chip: `Done`, `Needed`, `Unknown`, `Not applicable`.
struct StatePill: View {
    let text: String
    let foreground: Color
    let background: Color

    var body: some View {
        Text(text)
            .font(Theme.font(size: 10.5, weight: .medium))
            .foregroundStyle(foreground)
            // One word, on one line, in whatever column it is put in.
            //
            // "Warning" came out as "Warnin / g" on the Summary tab: the column
            // beside it reserves a width in points, the type scale grew, and the
            // pill wrapped inside a box that had stopped fitting it. A state
            // pill broken across two lines is worse than no pill, and it is one
            // word: it has no business wrapping anywhere.
            .lineLimit(1)
            .fixedSize()
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
                .font(Theme.font(size: 10))
                .padding(.top, 1)
            Text(text)
                .font(Theme.font(size: 11.5))
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
///
/// `glass` is opt-in, and off by default on purpose. It belongs to the buttons
/// that sit in the header clusters, where the material is what merges
/// neighbours into one lozenge. Every other quiet button stands on an opaque
/// form card, and glass there buys nothing and costs contrast.
struct QuietButton: View {
    let title: String
    var glass = false
    /// The one button of a cluster that is the reason the screen exists.
    ///
    /// A header cluster puts every control at one weight, which is right while
    /// they are all errands. It stops being right the moment one of them is
    /// the answer to the question in the tab's own subtitle: three buttons at
    /// one weight say the tab has three equal errands and no answer.
    var prominent = false
    /// An SF Symbol before the title, which bounces once each time the command
    /// runs.
    ///
    /// The header commands used to fire in silence. "Read the stores again"
    /// starts a pass over two APIs that takes seconds, and pressing it moved
    /// nothing on screen, so the developer pressed it twice. The symbol is the
    /// acknowledgement, and it is the whole of it: the work itself reports
    /// through the spinner and the counters, as it always did.
    ///
    /// `.bounce` and not `.rotate`. This app floors at macOS 14 and `.rotate`
    /// arrived in 15, so a rotating refresh glyph would need a branch on every
    /// call site for an effect that says the same thing.
    var symbol: String?
    /// Raised by the caller on each press. `.symbolEffect` fires on a change
    /// of value, so a `Bool` would only ever animate the first two presses.
    var tick = 0
    var action: () -> Void = {}

    var body: some View {
        if #available(macOS 26.0, *), glass {
            // The style draws the capsule, so the label carries no fill and
            // no border of its own. Two chromes on one button is a double edge.
            Button(action: action) {
                label.foregroundStyle(prominent ? Theme.accentText : Theme.text)
            }
                .buttonStyle(prominent ? AnyButtonStyle(.glassProminent)
                                       : AnyButtonStyle(.glass))
                // Only the prominent one takes a tint. Plain glass reads the tint
                // as a fill, so tinting both would paint the whole cluster accent
                // and lose the very distinction this flag exists to make.
                .tint(prominent ? Theme.accentFill : nil)
        } else {
            Button(action: action) { flatLabel }
                .buttonStyle(.plain)
        }
    }

    /// The title, with the symbol in front of it when there is one.
    ///
    /// One line, always. A button beside a paragraph competes with it for the
    /// width, and SwiftUI settled that by breaking the shorter string: the
    /// inspector on the Build tab read "Fetch / diagnostics", "Fetch the /
    /// workflows" and "Upload / and share", each one a command cut in half
    /// while the prose beside it had room to spare. `fixedSize` says the
    /// button keeps its own width and the paragraph wraps instead, which is
    /// the right way round: prose is written to wrap and a command is not.
    @ViewBuilder
    private var label: some View {
        let font = Theme.font(size: 12, weight: prominent ? .semibold : .regular)
        Group {
            if let symbol {
                HStack(spacing: 5) {
                    Image(systemName: symbol)
                        .symbolEffect(.bounce, value: tick)
                    Text(title)
                }
            } else {
                Text(title)
            }
        }
        .font(font)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var flatLabel: some View {
        label
            .foregroundStyle(prominent ? Theme.accentText : Theme.text)
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .background(prominent ? Theme.accent : Theme.field,
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(prominent ? Theme.accent : Theme.controlEdge,
                              lineWidth: Theme.hairline))
    }
}

/// Erases a button style, so one `Button` can take either of two.
///
/// `.buttonStyle(a ? x : y)` does not compile: the two styles are different
/// types, and the modifier is generic over one. Branching on the whole
/// `Button` instead would give the two branches different identities, and
/// SwiftUI would rebuild the button rather than restyle it.
struct AnyButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView

    init<S: PrimitiveButtonStyle>(_ style: S) {
        make = { AnyView(Button($0).buttonStyle(style)) }
    }

    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

/// The one prominent action on a screen: the apply on Summary.
///
/// Prominent glass on macOS 26, the filled accent rectangle this app shipped
/// below it. Deliberately not red. It writes a draft, a draft is reversible,
/// and red belongs to the Release tab alone.
struct ProminentButton: View {
    let title: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        if #available(macOS 26.0, *) {
            Button(action: action) {
                Text(title).font(Theme.font(size: 14, weight: .semibold))
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(Theme.accent)
        } else {
            Button(action: action) {
                Text(title)
                    .font(Theme.font(size: 14, weight: .semibold))
                    .foregroundStyle(enabled ? Theme.accentText : Theme.text3)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 11)
                    .background(enabled ? Theme.accent : Theme.sep2,
                                in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
        }
    }
}

/// The switch on the Summary toolbar.
struct SmallToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            // A bare assignment. The `.motion` on the stack below is what
            // animates the knob, and it honours Reduce Motion, which the
            // `withAnimation` that used to be here did not. That call was also
            // a global transaction: it animated every view SwiftUI updated in
            // the same pass, not the flag in its braces. See `SavedChip` and
            // `HeaderSurface` for the two bugs that came of exactly this.
            isOn.toggle()
        } label: {
            // An offset and a centred stack. See `AppearanceSwitch`: the
            // alignment this used to swap has nothing between its two values
            // to interpolate, so the knob jumped the full width of the track,
            // and it stopped hard against the end cap with its shadow outside
            // the capsule.
            ZStack {
                // The off track is the state, so it has to be visible against
                // the bar behind it. `sep` reads as nothing there.
                Capsule().fill(isOn ? Theme.accent : Theme.controlEdge)
                Circle()
                    .fill(.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                    .offset(x: isOn ? 7 : -7)
            }
            .frame(width: 34, height: 20)
            .padding(2)
            .contentShape(.rect)
            .motion(.easeOut(duration: 0.12), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dry run")
        .accessibilityValue(isOn ? "On" : "Off")
    }
}
