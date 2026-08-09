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
        Section_("This app in the stores", icon: "number", tint: Theme.accent,
                 anchor: "build.identifiers") {
            VStack(alignment: .leading, spacing: 12) {
                Text("The store decides these, not you. An import fills them in, and the list below picks between the apps a credential can see. The credential that reaches them lives on the Stores tab and covers every app on the account.")
                    .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)

                if state.stores.contains(.apple) {
                    IdentifierValue(label: "App id", value: state.appleAppID,
                                    placeholder: "Numeric App Store ID")
                    IdentifierValue(label: "Bundle id", value: state.appleBundleID,
                                    placeholder: "Reverse-DNS bundle identifier")
                    // A universal app has a version train per platform, each
                    // with its own numbers, text, and screenshots. This says
                    // which one every read here means. It shows only when there
                    // is a choice to make.
                    if state.appleplatformChoices.count > 1 {
                        VStack(alignment: .leading, spacing: 4) {
                            Picker("Platform", selection: Binding(
                                get: { state.applePlatform },
                                set: { state.applePlatform = $0 })) {
                                ForEach(state.appleplatformChoices, id: \.self) {
                                    Text($0.shortName).tag($0)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 240)
                            Text("This app ships on more than one platform. The App Store keeps a separate version, listing, and set of screenshots for each one.")
                                .font(Theme.font(size: 11))
                                .foregroundStyle(Theme.text2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
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
                    IdentifierValue(label: "Package name", value: state.googlePackageName,
                                    placeholder: "Reverse-DNS package name")
                }
                if state.appleAppID.isEmpty, state.appleBundleID.isEmpty,
                   state.googlePackageName.isEmpty {
                    Text("Nothing has filled these in yet. Import an existing listing on the Stores tab, or open the YAML editor above to set them by hand.")
                        .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.storePanel()
        }
    }
}

/// One identifier, as a value and not as a box you may type in.
///
/// It was a `TextField`, under a paragraph that says the store decides these.
/// The two disagreed, and the box won the argument: an editable field is an
/// invitation, and the invitation was to invent an App id. The Build tab draws
/// the same three identifiers this way already.
private struct IdentifierValue: View {
    let label: String
    let value: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(Theme.font(size: 11)).foregroundStyle(Theme.text2)
            Text(value.isEmpty ? placeholder : value)
                .font(Theme.mono(12))
                .foregroundStyle(value.isEmpty ? Theme.text3 : Theme.text)
                .textSelection(.enabled)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
        }
    }
}
