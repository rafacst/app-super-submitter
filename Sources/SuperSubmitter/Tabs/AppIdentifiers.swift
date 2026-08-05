import SubmitKit
import SwiftUI

/// Which app this is, in each store.
///
/// These used to sit inside the credential card on the Stores tab, and they do
/// not belong there. A credential is one per account and covers every app you
/// open. An App id names one app. Mixing the two read as "enter your key
/// again" every time the developer opened a second app.
///
/// They live on Details because Details already describes this app rather than
/// this release, and because a wrong bundle id has to be fixable without the
/// YAML editor.
struct AppIdentifiers: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        Section_("This app in the stores", icon: "number", tint: Theme.accent) {
            VStack(alignment: .leading, spacing: 12) {
                Text("The store decides these, not you. An import fills them in. The credential that reaches them lives on the Stores tab and covers every app on the account.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)

                if state.stores.contains(.apple) {
                    IdentifierField(label: "App id", value: $state.appleAppID,
                                    prompt: "Numeric App Store ID")
                        .onChange(of: state.appleAppID) { state.updateAppleAppFields() }
                    IdentifierField(label: "Bundle id", value: $state.appleBundleID,
                                    prompt: "Reverse-DNS bundle identifier")
                        .onChange(of: state.appleBundleID) { state.updateAppleAppFields() }
                    // The apps the tested credential can see. It fills both
                    // fields above, so it belongs beside them and not beside
                    // the key that produced the list.
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

                if state.stores.contains(.google) {
                    IdentifierField(label: "Package name", value: $state.googlePackageName,
                                    prompt: "Reverse-DNS package name")
                        .onChange(of: state.googlePackageName) { state.updateGoogleAppFields() }
                }
            }.storePanel()
        }
    }
}

private struct IdentifierField: View {
    let label: String
    @Binding var value: String
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.text2)
            TextField(prompt, text: $value)
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
