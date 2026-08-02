import SubmitKit
import SwiftUI

/// The guard in front of one irreversible call.
///
/// It names one store, the version, the build, and the release type. It also
/// names the recovery **and the limit of that recovery**, because a developer
/// who believes a submission is reversible presses the button differently.
struct ReleaseSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let store: Store

    private var isApple: Bool { store == .apple }

    private var appName: String {
        let listing = state.manifest.listing
        return listing?.locales[listing?.defaultLocale ?? ""]?.name ?? "this app"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isApple
                 ? "Send \(appName) to App Store review?"
                 : "Send \(appName) to Google Play review?")
                .font(.system(size: 15, weight: .semibold))
                .kerning(-0.15)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                ForEach(rows, id: \.0) { key, value, mono in
                    HStack(spacing: 12) {
                        Text(key)
                            .foregroundStyle(Theme.text2)
                            .frame(width: 96, alignment: .leading)
                        Text(value).font(mono ? Theme.mono(12) : .system(size: 12))
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))

            Text(isApple
                 ? "This sends the App Store version to Apple. It takes a place in the review queue. Google Play stays a draft."
                 : "This commits the Google Play release to the \(track) track. The App Store is untouched.")
                .font(.system(size: 12))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            Text(recovery)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 9) {
                Spacer()
                Button { dismiss() } label: {
                    Text("Cancel")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Theme.field, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)

                Button {
                    let store = store
                    dismiss()
                    Task { await state.release(store) }
                } label: {
                    Text(isApple ? "Send to App Store" : "Send to Google Play")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Theme.redFill, in: RoundedRectangle(cornerRadius: 7))
                        // The halo says: this one does not come back.
                        .overlay(RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(Theme.redBg, lineWidth: 3)
                            .padding(-3))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 26)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .frame(width: 460)
        .background(Theme.content)
        .foregroundStyle(Theme.text)
        .onExitCommand { dismiss() }
    }

    private var track: String { state.manifest.googlePrimaryTrack }
    private var version: String { state.manifest.release?.versionName ?? "no version" }

    private var recovery: String {
        if isApple {
            return "You can cancel this submission only before the review starts. Once a reviewer opens it, you cannot."
        }
        let status = state.manifest.release?.google?.status ?? "completed"
        return status == "inProgress"
            ? "You can halt this staged rollout. A halt stops new installs; it does not remove the release."
            : "You can halt a staged rollout only. This release is a completed rollout, so it cannot be halted."
    }

    private var rows: [(String, String, Bool)] {
        if isApple {
            let type = ReleaseTab.appleRelease(
                state.manifest.release?.apple?.releaseType?.rawValue ?? "MANUAL")
            let phased = state.manifest.release?.apple?.phasedRelease == true
                ? ", phased over 7 days" : ""
            return [("Store", "App Store", false),
                    ("Version", version, true),
                    ("Build", state.packages[.ipa]?.buildNumber
                        ?? state.packages[.pkg]?.buildNumber ?? "the attached build", true),
                    ("Release", type + phased, false)]
        }
        let status = ReleaseTab.googleRelease(state.manifest.release?.google?.status ?? "completed")
        return [("Store", "Google Play", false),
                ("Version", version, true),
                ("Version code", state.packages[.aab]?.buildNumber
                    ?? "the committed bundle", true),
                ("Release", "\(track) track, \(status)", false)]
    }
}
