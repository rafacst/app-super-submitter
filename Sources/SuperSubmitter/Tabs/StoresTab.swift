import SubmitKit
import SwiftUI
import UniformTypeIdentifiers

/// Tab 1. Store selection writes `apps` in the manifest. Credential files are
/// copied into the Keychain and never into the repository. Each credential
/// panel opens in the column under its own store card.
///
/// The card itself is `CredentialCard`, which the update sheet asks with too.
struct StoresTab: View {
    @Environment(AppState.self) private var state
    /// The store the developer just switched off, while the app asks whether
    /// the key goes with it.
    @State private var removing: Store?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StoreSelectionGrid(selected: state.stores) { store in
                let turningOff = state.stores.contains(store)
                state.setStore(store, enabled: !turningOff)
                // Switching a store off is how a developer says "not this
                // one". The key is the other half of that, and it is the half
                // no other control reaches, so this is where it gets offered.
                if turningOff, state.hasCredential(for: store) { removing = store }
            }
            HStack(alignment: .top, spacing: 16) {
                AppleCredentialPanel()
                    .frame(maxHeight: .infinity, alignment: .top)
                GoogleCredentialPanel()
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 16) {
                AppleTeamPanel()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                GoogleTeamPanel()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 1040, alignment: .leading)
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

/// The store-account state that stays visible while the tab scrolls.
struct StoresStatusBar: View {
    @Environment(AppState.self) private var state

    private var disconnected: [Store] {
        state.stores.filter { !state.connection(for: $0).isConnected }
            .sorted { $0.rawValue < $1.rawValue }
    }

    var body: some View {
        HStack(spacing: 14) {
            if !disconnected.isEmpty {
                // A red "N blockers ›" pill stood here and counted the stores
                // with no key. Two things were wrong with it. It wore a chevron
                // and opened nothing, and the header band above it now carries
                // that word for the release: one screen said "2 blockers" and
                // "4 blockers" at once, about two different things.
                //
                // The sentence beside it already names each store and what is
                // missing, which is the whole of what the pill counted.
                HStack(spacing: 6) {
                    Circle().fill(Theme.yellow).frame(width: 7, height: 7)
                    Text(disconnected.map { "\($0.storeName) is not connected" }
                        .joined(separator: " · "))
                }
                .font(Theme.font(size: 12.5))
                .foregroundStyle(Theme.text2)
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 8)
            Text("One key per account, for every app on this Mac")
                .font(Theme.font(size: 12))
                .foregroundStyle(Theme.text3)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised)
        .overlay(alignment: .bottom) { Hairline() }
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
            summary: state.appleKeyID,
            open: state.credentialDetailsOpen(.apple),
            toggle: { state.toggleCredentialDetails(.apple) },
            guide: .apple,
            guideOpen: state.appleGuideOpen,
            toggleGuide: { state.appleGuideOpen.toggle() },
            connect: state.connectAppleStore,
            keychainNote: "One key for the whole App Store Connect account. It is stored in the macOS Keychain, every app you open here uses it, and you never enter it a second time. The original file is not copied.",
            equalizedHeight: true
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

                // "Key ID" in both places. Apple spells it that way in App
                // Store Connect, and the label and its own placeholder
                // disagreeing reads as two different fields.
                EditableField(label: "Key ID", value: $state.appleKeyID, prompt: "Key ID",
                              limit: AppleCredential.keyIDLength)
                    .onChange(of: state.appleKeyID) { state.appleCredentialFieldsChanged() }
                    .fieldAnchor("stores.appleKeyID")
                EditableField(label: "Issuer id", value: $state.appleIssuerID,
                              prompt: "Issuer UUID",
                              limit: AppleCredential.issuerIDLength)
                    .onChange(of: state.appleIssuerID) { state.appleCredentialFieldsChanged() }
                    .fieldAnchor("stores.appleIssuerID")
            }
        }
        .fileImporter(isPresented: $importerOpen,
                      allowedContentTypes: [UTType(filenameExtension: "p8") ?? .data]) { result in
            if case .success(let url) = result { state.importAppleCredential(from: url) }
            if case .failure(let error) = result { state.errorMessage = error.localizedDescription }
        }
        .transition(.credentialPanel)
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
            summary: state.googleCredentialSummary,
            open: state.credentialDetailsOpen(.google),
            toggle: { state.toggleCredentialDetails(.google) },
            guide: state.googleCredentialChoice == .oauth ? .googleOAuth : .google,
            guideOpen: state.googleGuideOpen,
            toggleGuide: { state.googleGuideOpen.toggle() },
            connect: state.connectGoogleStore,
            keychainNote: state.googleCredentialChoice == .oauth
                ? "Google's refresh token is stored in the macOS Keychain and used by every app you open here."
                : "One service account for the whole Google Play developer account. It is stored in the macOS Keychain, every app you open here uses it, and the original file is not copied.",
            equalizedHeight: true
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Google credential", selection: $state.googleCredentialChoice) {
                    Text("Connect with Google").tag(GoogleCredentialChoice.oauth)
                    Text("Service account JSON").tag(GoogleCredentialChoice.serviceAccount)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Google credential type")

                if state.googleCredentialChoice == .oauth {
                    Text("Sign in in your browser. Super Submitter uses the Google Play access already granted to that account.")
                        .font(Theme.font(size: 11.5))
                        .foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    if GoogleOAuthConfiguration.clientID == nil,
                       state.googleOAuthCredential == nil {
                        WarningNote("This build still needs its Google OAuth desktop client ID. Service-account JSON works now.")
                    }
                } else {
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
        }
        .fileImporter(isPresented: $importerOpen, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { state.importGoogleCredential(from: url) }
            if case .failure(let error) = result { state.errorMessage = error.localizedDescription }
        }
        .transition(.credentialPanel)
    }
}
