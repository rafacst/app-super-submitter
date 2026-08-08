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

    /// Pre-filled with the version, because the first question any support
    /// reply asks is which build you are on, and the panel already knows.
    private var supportURL: URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Self.supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject",
                         value: "Super Submitter \(Self.version) (\(Self.build))"),
        ]
        return components.url ?? URL(string: "mailto:\(Self.supportEmail)")!
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
            // Raised with the Updates section, which pushed the copyright a
            // scroll below the fold and put the support address back against
            // the bottom edge. This holds the whole panel with no scroll at
            // all. The window is at least 720 tall, so 630 points and the 44
            // point bar still fit inside it.
            .frame(height: 660)
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

            Text("Super Submitter prepares an iOS, macOS, and Android app for the App Store and for Google Play from one file and one action. It reads both stores, shows you the exact diff, and writes every draft it can. It leaves the last irreversible step yours: nothing reaches review until you send it.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text2)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            Hairline()

            VStack(alignment: .leading, spacing: 9) {
                Text("Support")
                    .font(.system(size: 13, weight: .semibold))
                Text("Write to a person. Say what you were doing and what happened, and the reply comes from whoever wrote the part that broke.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.text2)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Link(destination: supportURL) {
                        HStack(spacing: 6) {
                            Image(systemName: "envelope").font(.system(size: 11))
                            Text(Self.supportEmail).font(.system(size: 12))
                        }
                    }
                    // Some Macs have no mail client set, and then the link
                    // opens nothing at all and says nothing about it.
                    QuietButton(title: "Copy address") {
                        state.copyToPasteboard(Self.supportEmail)
                    }
                    Spacer(minLength: 0)
                }
                Text("An email opens with the version already in the subject.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text3)
            }

            Hairline()

            // The version is three lines above, so this is where a person
            // already is when they wonder whether it is the current one.
            VStack(alignment: .leading, spacing: 9) {
                Text("Updates")
                    .font(.system(size: 13, weight: .semibold))
                Text("Super Submitter checks for a new version on its own and asks before it downloads anything. Every update is signed, and the app refuses one that carries the wrong signature.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.text2)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    // The panel closes as this runs. Sparkle installs by
                    // quitting the app, and AppKit refuses to quit an app
                    // holding a sheet, which this panel is. See Updater.
                    QuietButton(title: "Check now") { Updater.check() }
                    Spacer(minLength: 0)
                }
            }

            Hairline()

            Text(Self.copyright)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text3)
        }
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
