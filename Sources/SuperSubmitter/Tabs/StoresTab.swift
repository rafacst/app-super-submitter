import SubmitKit
import SwiftUI

/// Tab 1. Choose the stores. Connect each one.
struct StoresTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                StoreChoiceCard(
                    name: "App Store",
                    line: "iOS and Mac App Store. Written through the App Store Connect API.")
                StoreChoiceCard(
                    name: "Google Play",
                    line: "Android. Written through the Android Publisher API.")
            }

            CredentialCard(
                title: "App Store credential",
                connection: "Connected · Fast Bill Split Lda.",
                keychainNote: "The key goes to the macOS Keychain. This app keeps no copy.",
                guideOpen: state.appleGuideOpen,
                toggleGuide: { state.appleGuideOpen.toggle() },
                guide: appleGuide
            ) {
                HStack(alignment: .top, spacing: 12) {
                    FileWell(name: "AuthKey_9F2KQ4X8L1.p8", prompt: "Drop the .p8 file, or")
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledField(label: "Key id", value: "9F2KQ4X8L1")
                        LabeledField(label: "Issuer id", value: "57246542-96fe-1a63-e053-0824d011072a")
                    }
                }
            }

            CredentialCard(
                title: "Google Play credential",
                connection: "Connected · fastbillsplit-ci@…iam.gserviceaccount.com",
                keychainNote: "The JSON goes to the macOS Keychain. This app keeps no copy.",
                guideOpen: state.googleGuideOpen,
                toggleGuide: { state.googleGuideOpen.toggle() },
                guide: googleGuide
            ) {
                FileWell(name: "play-service-account.json",
                         prompt: "Drop the service account JSON, or")
                    .frame(maxWidth: 420)
            }
        }
        .frame(maxWidth: 900, alignment: .leading)
    }

    private var appleGuide: GuideContent {
        GuideContent(
            steps: [
                "Open App Store Connect, then Users and Access, then Integrations, then App Store Connect API.",
                "Create a key with the App Manager role. Copy the key id and the issuer id.",
                "Download the .p8 file.",
            ],
            warning: "Apple shows the .p8 file once. Save it now. A lost key cannot be downloaded again — you create a new key.",
            buttons: ["Open Users and Access ↗"])
    }

    private var googleGuide: GuideContent {
        GuideContent(
            steps: [
                "In the Google Cloud console, create a service account and download its JSON key.",
                "Grant it the Android Publisher role.",
                "In the Play Console, open Users and permissions and invite the service account email.",
            ],
            warning: "Step 3 is mandatory and no API performs it. A skipped invitation returns a permission error later, with no clue about the cause.",
            buttons: ["Open Cloud console ↗", "Open Play Console ↗"])
    }
}

private struct StoreChoiceCard: View {
    let name: String
    let line: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name).font(.system(size: 13.5, weight: .semibold))
                Spacer()
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 16, height: 16)
                    .overlay(Text("✓").font(.system(size: 9, weight: .bold)).foregroundStyle(.white))
            }
            Text(line)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.accent, lineWidth: 1.5))
    }
}

struct GuideContent {
    let steps: [String]
    let warning: String
    let buttons: [String]
}

private struct CredentialCard<Content: View>: View {
    let title: String
    let connection: String
    let keychainNote: String
    let guideOpen: Bool
    let toggleGuide: () -> Void
    let guide: GuideContent
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    Text("●").font(.system(size: 8))
                    Text(connection).font(.system(size: 11.5))
                }
                .foregroundStyle(Theme.green)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            VStack(alignment: .leading, spacing: 12) {
                content

                Button(action: toggleGuide) {
                    HStack(spacing: 6) {
                        Text(guideOpen ? "▼" : "▶").font(.system(size: 8))
                        Text("Where do I get this?").font(.system(size: 12))
                    }
                    .foregroundStyle(Theme.accent)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityValue(guideOpen ? "Expanded" : "Collapsed")

                if guideOpen { GuideBox(guide: guide) }

                HStack(spacing: 12) {
                    QuietButton(title: "Test connection")
                    Text(keychainNote).font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }
}

private struct GuideBox: View {
    let guide: GuideContent

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 9) {
                    Text("\(index + 1)").foregroundStyle(Theme.text2)
                    Text(step).fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 12))
                .lineSpacing(3)
            }

            HStack(alignment: .top, spacing: 9) {
                Text("!").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.yellow)
                Text(guide.warning)
                    .font(.system(size: 12))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.yellowBg, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.yellow, lineWidth: 1))

            HStack(spacing: 8) {
                ForEach(guide.buttons, id: \.self) { QuietButton(title: $0) }
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }
}

/// The dashed drop target that holds a credential file.
struct FileWell: View {
    let name: String
    let prompt: String

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Theme.field)
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
                .frame(width: 30, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 12)).lineLimit(1)
                HStack(spacing: 3) {
                    Text(prompt).foregroundStyle(Theme.text2)
                    Text("choose a file…").foregroundStyle(Theme.accent)
                }
                .font(.system(size: 11))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Theme.sep, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
    }
}

struct LabeledField: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.text2)
            Text(value)
                .font(Theme.mono(12))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
        }
    }
}
