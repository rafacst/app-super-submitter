import AppKit
import SwiftUI

/// What the app is, who makes it, and how to reach a person.
///
/// It was a section inside Settings, beside the appearance picker and the poll
/// interval, which are things you change. Nothing here is a setting: it is the
/// label on the tin, and the one place a developer finds the support address
/// on the day something has gone wrong.
struct AboutPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    /// The address a person answers.
    ///
    /// One constant, because it belongs in the copy of two views and a mailto
    /// URL, and three literals of an email address drift the day it changes.
    static let supportEmail = "support@rafacst.me"

    /// Pre-filled with the answers to the first three questions any support
    /// reply has to ask: which build, which macOS, which Mac. The panel knows
    /// all three, and a person writing in because something broke should not
    /// have to go and find them.
    ///
    /// Nothing identifying goes in. No app names, no accounts, no paths, no
    /// keys: a version, an OS, and a model of Mac.
    static var supportURL: URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Self.supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject",
                         value: "Super Submitter \(Self.version) (\(Self.build))"),
            URLQueryItem(name: "body", value: Self.supportBody),
        ]
        return components.url ?? URL(string: "mailto:\(Self.supportEmail)")!
    }

    /// The blank the writer fills, then the three lines they would otherwise
    /// be asked for. The rule stops a reply quoting the report back as if it
    /// were the message.
    static var supportBody: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return """
        What were you doing?


        What happened instead?


        —
        Super Submitter \(version) (\(build))
        macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion) · \(hardware) · \(architecture)
        """
    }

    /// `hw.model`, which is the identifier and not the marketing name:
    /// "Mac15,3" rather than "MacBook Pro". The identifier is the one that
    /// says exactly which machine.
    private static var hardware: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "unknown Mac" }
        var value = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &value, &size, nil, 0)
        return String(cString: value)
    }

    /// The slice that is actually running, which is the useful half. A
    /// universal build on an Intel Mac and the same build on Apple silicon
    /// fail in different ways.
    private static var architecture: String {
        #if arch(arm64)
        "Apple silicon"
        #else
        "Intel"
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelTitleBar(title: "About") { dismiss() }
            Hairline()
            ScrollView {
                content
                    .padding(.horizontal, 26)
                    .padding(.top, 24)
                    // The last line sat against the bottom edge, because the
                    // content is taller than the frame and a scroll view gives
                    // its last row no room of its own. The panel is taller too,
                    // so the support address is in the frame rather than one
                    // scroll below it.
                    .padding(.bottom, 30)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Holds the whole panel with no scroll at all. It came down from
            // 660 as the copy shrank and the two sections went side by side.
            //
            // Read off a capture rather than guessed. A few points short and
            // AppKit draws a scrollbar down the side of a panel with nothing
            // to scroll, which is the tell that this number is wrong again.
            .frame(height: 505)
            .background(Theme.content)
        }
        .frame(width: 480)
        .background(Theme.bg)
        .foregroundStyle(Theme.text)
        .onExitCommand { dismiss() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            // The logo, centred and large. It is the one thing on this panel
            // that is not a sentence.
            HStack {
                Spacer(minLength: 0)
                VStack(spacing: 9) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 108, height: 108)
                        .accessibilityLabel("The Super Submitter icon")
                    Text(Self.appName)
                        .font(.system(size: 21, weight: .semibold))
                        .kerning(-0.25)
                    Text("Version \(Self.version) (build \(Self.build))")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text2)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
            }

            Text("Prepares an iOS, macOS, or Android app for the App Store and Google Play from one file. It shows you the exact diff, and sends nothing until you do.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text2)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            Hairline()

            // Two columns, not two rows. They are siblings: each is a heading,
            // a line, and one button, and stacked they read as a sequence you
            // work through rather than two things you might want.
            //
            // `.top` and not the default, so the two headings sit on one
            // baseline whichever column wraps to a second line.
            HStack(alignment: .top, spacing: 18) {
                column(title: "Support",
                       // Said plainly, because the mail is composed rather
                       // than sent: the writer sees the report before anybody
                       // else does. Saying nothing and attaching it anyway is
                       // the version of this that is not honest.
                       line: "Includes your version and Mac model.",
                       button: "Contact support") { openSupport() }

                Rectangle().fill(Theme.sep)
                    .frame(width: Theme.hairline)
                    .frame(maxHeight: .infinity)

                // The version is three lines above, so this is where a person
                // already is when they wonder whether it is the current one.
                column(title: "Updates",
                       line: "Signed. The app refuses one that is not.",
                       // The panel closes as this runs. Sparkle installs by
                       // quitting the app, and AppKit refuses to quit an app
                       // holding a sheet, which this panel is. See Updater.
                       button: "Check now") { Updater.check() }
            }
            .fixedSize(horizontal: false, vertical: true)

            Hairline()

            Text(Self.copyright)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text3)
        }
    }

    /// One of the two columns. Both are the same three things in the same
    /// order, so they are one function: a heading that shares its baseline
    /// with the other, a line of explanation, and the button underneath.
    private func column(title: String, line: String, button: String,
                        action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(line)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            // Pushes the button to the bottom, so the two sit level even when
            // one column's line wraps and the other's does not.
            Spacer(minLength: 0)
            QuietButton(title: button, action: action)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A button and not a `Link`, so the case with no mail client set has
    /// somewhere to go. `open` returns false there, and a link would simply do
    /// nothing and say nothing about it, on the one screen a person reaches
    /// because something is already wrong. The address goes to the clipboard
    /// instead, and the panel says so.
    private func openSupport() {
        guard !NSWorkspace.shared.open(Self.supportURL) else { return }
        state.copyToPasteboard(Self.supportEmail)
        state.errorMessage = """
        This Mac has no email app set up, so nothing opened. \
        The address is on your clipboard: \(Self.supportEmail)
        """
    }

    /// Read from the bundle, so the panel can never disagree with the build.
    private static func plist(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "unknown"
    }

    static var appName: String { plist("CFBundleDisplayName") }
    static var version: String { plist("CFBundleShortVersionString") }
    static var build: String { plist("CFBundleVersion") }
    static var copyright: String { plist("NSHumanReadableCopyright") }
}
