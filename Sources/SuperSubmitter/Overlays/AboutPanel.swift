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
                    .padding(.vertical, 22)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 400)
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

            VStack(alignment: .leading, spacing: 5) {
                Text(Self.copyright)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.text3)
                Text("This build carries no updater. It never checks for a new version, and it never downloads one.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
