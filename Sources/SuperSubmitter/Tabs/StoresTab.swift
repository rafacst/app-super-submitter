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
        VStack(alignment: .leading, spacing: 20) {
            StoreSelectionGrid(selected: state.stores) { store in
                let turningOff = state.stores.contains(store)
                state.setStore(store, enabled: !turningOff)
                // Switching a store off is how a developer says "not this
                // one". The key is the other half of that, and it is the half
                // no other control reaches, so this is where it gets offered.
                if turningOff, state.hasCredential(for: store) { removing = store }
            } detail: { store in
                switch store {
                case .apple:
                    if state.stores.contains(.apple) { AppleCredentialPanel() }
                case .google:
                    if state.stores.contains(.google) { GoogleCredentialPanel() }
                }
            }
            // Under both columns and not inside the Google one. A colleague
            // belongs to the developer account, the same way the service
            // account above does, so the panel is as wide as the tab rather
            // than half of it.
            if state.stores.contains(.apple) { AppleTeamPanel() }
            if state.stores.contains(.google) { GoogleTeamPanel() }
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
            keychainNote: "One key for the whole App Store Connect account. It is stored in the macOS Keychain, every app you open here uses it, and you never enter it a second time. The original file is not copied."
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
        CredentialCard(
            store: .google,
            status: state.googleConnection,
            summary: state.googleAccountEmail,
            open: state.credentialDetailsOpen(.google),
            toggle: { state.toggleCredentialDetails(.google) },
            guide: .google,
            guideOpen: state.googleGuideOpen,
            toggleGuide: { state.googleGuideOpen.toggle() },
            connect: state.connectGoogleStore,
            keychainNote: "One service account for the whole Google Play developer account. It is stored in the macOS Keychain, every app you open here uses it, and you never enter it a second time. The original file is not copied."
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
}
