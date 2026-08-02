import SubmitKit
import SwiftUI
import UniformTypeIdentifiers

/// Tab 1. Store selection writes `apps` in the manifest. Credential files are
/// copied into the Keychain and never into the repository.
struct StoresTab: View {
    @Environment(AppState.self) private var state
    @State private var appleImporterOpen = false
    @State private var googleImporterOpen = false

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                StoreChoiceCard(
                    name: "App Store",
                    line: "iOS and Mac App Store. Written through the App Store Connect API.",
                    selected: state.stores.contains(.apple)) {
                        state.setStore(.apple, enabled: !state.stores.contains(.apple))
                    }
                StoreChoiceCard(
                    name: "Google Play",
                    line: "Android. Written through the Android Publisher API.",
                    selected: state.stores.contains(.google)) {
                        state.setStore(.google, enabled: !state.stores.contains(.google))
                    }
            }

            if state.stores.contains(.apple) {
                CredentialCard(
                    title: "App Store credential",
                    status: state.appleConnection,
                    keychainNote: "The key is stored in the macOS Keychain. The original file is not copied.",
                    guideOpen: state.appleGuideOpen,
                    toggleGuide: { state.appleGuideOpen.toggle() },
                    guide: appleGuide,
                    test: state.testAppleConnection
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .bottom, spacing: 12) {
                            EditableField(label: "App id", value: $state.appleAppID,
                                          prompt: "1234567890", width: 145)
                                .onChange(of: state.appleAppID) { state.updateAppleAppFields() }
                            EditableField(label: "Bundle id", value: $state.appleBundleID,
                                          prompt: "com.example.app", width: 240)
                                .onChange(of: state.appleBundleID) { state.updateAppleAppFields() }
                            if !state.remoteAppleApps.isEmpty {
                                Menu("Choose visible app") {
                                    ForEach(state.remoteAppleApps) { app in
                                        Button("\(app.name) · \(app.identifier)") {
                                            state.chooseRemoteAppleApp(app)
                                        }
                                    }
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                            }
                        }

                        HStack(alignment: .top, spacing: 12) {
                            FileWell(
                                name: state.appleCredentialFileName,
                                emptyName: "App Store Connect private key",
                                prompt: "Drop the .p8 file, or",
                                choose: { appleImporterOpen = true },
                                accept: { urls in
                                    guard let url = urls.first,
                                          url.pathExtension.lowercased() == "p8" else { return false }
                                    state.importAppleCredential(from: url)
                                    return true
                                })
                            VStack(alignment: .leading, spacing: 8) {
                                EditableField(label: "Key id", value: $state.appleKeyID,
                                              prompt: "9F2KQ4X8L1")
                                    .onChange(of: state.appleKeyID) { state.appleCredentialFieldsChanged() }
                                EditableField(label: "Issuer id", value: $state.appleIssuerID,
                                              prompt: "57246542-…")
                                    .onChange(of: state.appleIssuerID) { state.appleCredentialFieldsChanged() }
                            }
                        }
                    }
                }
                .fileImporter(isPresented: $appleImporterOpen,
                              allowedContentTypes: [UTType(filenameExtension: "p8") ?? .data]) { result in
                    if case .success(let url) = result { state.importAppleCredential(from: url) }
                    if case .failure(let error) = result { state.errorMessage = error.localizedDescription }
                }
            }

            if state.stores.contains(.google) {
                CredentialCard(
                    title: "Google Play credential",
                    status: state.googleConnection,
                    keychainNote: "The JSON is stored in the macOS Keychain. The original file is not copied.",
                    guideOpen: state.googleGuideOpen,
                    toggleGuide: { state.googleGuideOpen.toggle() },
                    guide: googleGuide,
                    test: state.testGoogleConnection
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        EditableField(label: "Package name", value: $state.googlePackageName,
                                      prompt: "com.example.app", width: 300)
                            .onChange(of: state.googlePackageName) { state.updateGoogleAppFields() }
                        FileWell(
                            name: state.googleCredentialFileName,
                            emptyName: "Google service-account key",
                            prompt: "Drop the service account JSON, or",
                            choose: { googleImporterOpen = true },
                            accept: { urls in
                                guard let url = urls.first,
                                      url.pathExtension.lowercased() == "json" else { return false }
                                state.importGoogleCredential(from: url)
                                return true
                            })
                            .frame(maxWidth: 520)
                        if !state.googleAccountEmail.isEmpty {
                            Text(state.googleAccountEmail)
                                .font(Theme.mono(11))
                                .foregroundStyle(Theme.text2)
                        }
                    }
                }
                .fileImporter(isPresented: $googleImporterOpen,
                              allowedContentTypes: [.json]) { result in
                    if case .success(let url) = result { state.importGoogleCredential(from: url) }
                    if case .failure(let error) = result { state.errorMessage = error.localizedDescription }
                }
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
            buttons: [GuideLink("Open Users and Access ↗",
                                "https://appstoreconnect.apple.com/access/integrations/api")])
    }

    private var googleGuide: GuideContent {
        GuideContent(
            steps: [
                "In the Google Cloud console, create a service account and download its JSON key.",
                "Grant it the Android Publisher role.",
                "In the Play Console, open Users and permissions and invite the service account email.",
            ],
            warning: "Step 3 is mandatory and no API performs it. A skipped invitation returns a permission error during the connection test.",
            buttons: [
                GuideLink("Open Cloud console ↗", "https://console.cloud.google.com/iam-admin/serviceaccounts"),
                GuideLink("Open Play Console ↗", "https://play.google.com/console"),
            ])
    }
}

private struct StoreChoiceCard: View {
    let name: String
    let line: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(name).font(.system(size: 13.5, weight: .semibold))
                    Spacer()
                    Circle()
                        .fill(selected ? Theme.accent : .clear)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(Theme.sep, lineWidth: 1))
                        .overlay(Text(selected ? "✓" : "")
                            .font(.system(size: 9, weight: .bold)).foregroundStyle(.white))
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
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selected ? Theme.accent : Theme.sep,
                              lineWidth: selected ? 1.5 : Theme.hairline))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }
}

private struct GuideLink: Identifiable {
    let title: String
    let url: URL
    var id: String { title }

    init(_ title: String, _ url: String) {
        self.title = title
        self.url = URL(string: url)!
    }
}

private struct GuideContent {
    let steps: [String]
    let warning: String
    let buttons: [GuideLink]
}

private struct CredentialCard<Content: View>: View {
    let title: String
    let status: ConnectionStatus
    let keychainNote: String
    let guideOpen: Bool
    let toggleGuide: () -> Void
    let guide: GuideContent
    let test: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                Text(status.isConnected ? "● Connected" : status == .testing ? "● Testing" : "○ Not connected")
                    .font(.system(size: 11.5))
                    .foregroundStyle(status.isConnected ? Theme.green : status == .testing ? Theme.yellow : Theme.text2)
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

                HStack(alignment: .top, spacing: 12) {
                    QuietButton(title: status == .testing ? "Testing…" : "Test connection", action: test)
                        .disabled(status == .testing)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(keychainNote).font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                        if case .failed(let message) = status {
                            Text(message).font(.system(size: 11.5)).foregroundStyle(Theme.red)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if case .connected(let message) = status {
                            Text(message).font(.system(size: 11.5)).foregroundStyle(Theme.green)
                        }
                    }
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
                ForEach(guide.buttons) { item in
                    Link(destination: item.url) { QuietButtonLabel(title: item.title) }
                }
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

private struct QuietButtonLabel: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 12))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }
}

private struct FileWell: View {
    let name: String
    let emptyName: String
    let prompt: String
    let choose: () -> Void
    let accept: ([URL]) -> Bool
    @State private var targeted = false

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Theme.field)
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
                .frame(width: 30, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? emptyName : name).font(.system(size: 12)).lineLimit(1)
                HStack(spacing: 3) {
                    Text(prompt).foregroundStyle(Theme.text2)
                    Button("choose a file…", action: choose)
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                }
                .font(.system(size: 11))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(targeted ? Theme.field : Theme.sunken, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(targeted ? Theme.accent : Theme.sep,
                          style: StrokeStyle(lineWidth: targeted ? 1.5 : 1, dash: [3, 3])))
        .dropDestination(for: URL.self) { urls, _ in
            accept(urls)
        } isTargeted: { targeted = $0 }
    }
}

private struct EditableField: View {
    let label: String
    @Binding var value: String
    let prompt: String
    var width: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.text2)
            TextField(prompt, text: $value)
                .textFieldStyle(.plain)
                .font(Theme.mono(12))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(width: width)
                .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
        }
    }
}
