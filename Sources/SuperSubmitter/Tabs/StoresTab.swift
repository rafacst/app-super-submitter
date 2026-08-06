import SubmitKit
import SwiftUI
import UniformTypeIdentifiers

/// Tab 1. Store selection writes `apps` in the manifest. Credential files are
/// copied into the Keychain and never into the repository. Each credential
/// panel opens in the column under its own store card.
struct StoresTab: View {
    @Environment(AppState.self) private var state
    /// The store the developer just switched off, while the app asks whether
    /// the key goes with it.
    @State private var removing: Store?

    var body: some View {
        StoreSelectionGrid(selected: state.stores) { store in
            let turningOff = state.stores.contains(store)
            state.setStore(store, enabled: !turningOff)
            // Switching a store off is how a developer says "not this one".
            // The key is the other half of that, and it is the half no other
            // control reaches, so this is where it gets offered.
            if turningOff, state.hasCredential(for: store) { removing = store }
        } detail: { store in
            switch store {
            case .apple:
                if state.stores.contains(.apple) { AppleCredentialPanel() }
            case .google:
                if state.stores.contains(.google) { GoogleCredentialPanel() }
            }
        }
        .frame(maxWidth: 900, alignment: .leading)
        .confirmationDialog("Remove the stored credential?", isPresented: $removing.isPresent,
                            presenting: removing) { store in
            Button("Remove the credential", role: .destructive) {
                state.forgetCredential(for: store)
            }
            Button("Keep it", role: .cancel) {}
        } message: { store in
            Text(store == .apple
                 ? "\(store.storeName) is off for this app. The key covers every app on the account, so removing it removes it everywhere. App Store Connect offers a .p8 file once and never again, so keep your copy before you do this."
                 : "\(store.storeName) is off for this app. The service account covers every app on the account, so removing it removes it everywhere. You can download the JSON key again from the Google Cloud console.")
        }
    }

}

private extension AnyTransition {
    /// Grows out of the store card above it, rather than fading in place.
    static var credentialPanel: AnyTransition {
        .scale(scale: 0.96, anchor: .top).combined(with: .opacity)
    }
}

private struct AppleCredentialPanel: View {
    @Environment(AppState.self) private var state
    @State private var importerOpen = false

    var body: some View {
        @Bindable var state = state
        CredentialCard(
            store: .apple,
            status: state.appleConnection,
            keychainNote: "One key for the whole App Store Connect account. It is stored in the macOS Keychain, every app you open here uses it, and you never enter it a second time. The original file is not copied.",
            guideOpen: state.appleGuideOpen,
            toggleGuide: { state.appleGuideOpen.toggle() },
            guide: guide,
            test: state.testAppleConnection
        ) {
            VStack(alignment: .leading, spacing: 12) {
                FileWell(
                    name: state.appleCredentialFileName,
                    emptyName: "App Store Connect private key",
                    prompt: "Drop the .p8 file, or",
                    choose: { importerOpen = true },
                    accept: { urls in
                        guard let url = urls.first,
                              url.pathExtension.lowercased() == "p8" else { return false }
                        state.importAppleCredential(from: url)
                        return true
                    })

                EditableField(label: "Key id", value: $state.appleKeyID, prompt: "Key ID",
                              limit: AppleCredential.keyIDLength)
                    .onChange(of: state.appleKeyID) { state.appleCredentialFieldsChanged() }
                EditableField(label: "Issuer id", value: $state.appleIssuerID,
                              prompt: "Issuer UUID",
                              limit: AppleCredential.issuerIDLength)
                    .onChange(of: state.appleIssuerID) { state.appleCredentialFieldsChanged() }
            }
        }
        .fileImporter(isPresented: $importerOpen,
                      allowedContentTypes: [UTType(filenameExtension: "p8") ?? .data]) { result in
            if case .success(let url) = result { state.importAppleCredential(from: url) }
            if case .failure(let error) = result { state.errorMessage = error.localizedDescription }
        }
        .transition(.credentialPanel)
    }

    private var guide: GuideContent {
        GuideContent(
            steps: [
                "Open App Store Connect, then Users and Access, then Integrations, then App Store Connect API.",
                "Create a key with the App Manager role. Copy the key id and the issuer id.",
                "Download the .p8 file.",
            ],
            warning: "Apple shows the .p8 file once. Save it now. A lost key cannot be downloaded again. You create a new one.",
            buttons: [GuideLink("Open Users and Access ↗",
                                "https://appstoreconnect.apple.com/access/integrations/api")])
    }
}

private struct GoogleCredentialPanel: View {
    @Environment(AppState.self) private var state
    @State private var importerOpen = false

    var body: some View {
        @Bindable var state = state
        CredentialCard(
            store: .google,
            status: state.googleConnection,
            keychainNote: "One service account for the whole Google Play developer account. It is stored in the macOS Keychain, every app you open here uses it, and you never enter it a second time. The original file is not copied.",
            guideOpen: state.googleGuideOpen,
            toggleGuide: { state.googleGuideOpen.toggle() },
            guide: guide,
            test: state.testGoogleConnection
        ) {
            VStack(alignment: .leading, spacing: 12) {
                FileWell(
                    name: state.googleCredentialFileName,
                    emptyName: "Google service-account key",
                    prompt: "Drop the service account JSON, or",
                    choose: { importerOpen = true },
                    accept: { urls in
                        guard let url = urls.first,
                              url.pathExtension.lowercased() == "json" else { return false }
                        state.importGoogleCredential(from: url)
                        return true
                    })
                if !state.googleAccountEmail.isEmpty {
                    Text(state.googleAccountEmail)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.text2)
                }
            }
        }
        .fileImporter(isPresented: $importerOpen, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { state.importGoogleCredential(from: url) }
            if case .failure(let error) = result { state.errorMessage = error.localizedDescription }
        }
        .transition(.credentialPanel)
    }

    private var guide: GuideContent {
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
    let store: Store
    let status: ConnectionStatus
    let keychainNote: String
    let guideOpen: Bool
    let toggleGuide: () -> Void
    let guide: GuideContent
    let test: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                StoreMark(store: store, size: 18)
                Text("\(store.storeName) credential").font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 6)
                HStack(spacing: 5) {
                    Image(systemName: status.isConnected ? "checkmark.circle.fill"
                                    : status == .testing ? "clock.fill" : "circle.dashed")
                        .font(.system(size: 11))
                    Text(status.isConnected ? "Connected" : status == .testing ? "Testing" : "Not connected")
                        .font(.system(size: 11.5))
                        .fixedSize()
                }
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

                VStack(alignment: .leading, spacing: 7) {
                    QuietButton(title: status == .testing ? "Testing…" : "Test connection", action: test)
                        .disabled(status == .testing)
                    Text(keychainNote).font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    if case .failed(let message) = status {
                        WarningNote(message)
                    } else if case .connected(let message) = status {
                        Text(message).font(.system(size: 11.5)).foregroundStyle(Theme.green)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

            VStack(alignment: .leading, spacing: 6) {
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
    /// The length the store issues, where it issues a fixed one. Nil means the
    /// field takes whatever the developer has.
    var limit: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.text2)
            TextField(prompt, text: $value.limited(to: limit))
                .textFieldStyle(.plain)
                .font(Theme.mono(12))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
        }
    }
}
