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
                Text("The store owns these. An import fills them in, and the list below picks between the apps a credential can see, which is the safest way to get them right. Type them only when you are copying a value the store already holds: an id that names no app fails the apply, and an id that names another app writes to it.")
                    .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)

                if state.stores.contains(.apple) {
                    IdentifierValue(label: "App id",
                                    value: Binding(get: { state.appleAppID },
                                                   set: { state.appleAppID = $0 }),
                                    placeholder: "Numeric App Store ID",
                                    commit: state.updateAppleAppFields)
                    IdentifierValue(label: "Bundle id",
                                    value: Binding(get: { state.appleBundleID },
                                                   set: { state.appleBundleID = $0 }),
                                    placeholder: "Reverse-DNS bundle identifier",
                                    commit: state.updateAppleAppFields)
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
                    IdentifierValue(label: "Package name",
                                    value: Binding(get: { state.googlePackageName },
                                                   set: { state.googlePackageName = $0 }),
                                    placeholder: "Reverse-DNS package name",
                                    commit: state.updateGoogleAppFields)
                }
                if state.appleAppID.isEmpty, state.appleBundleID.isEmpty,
                   state.googlePackageName.isEmpty {
                    Text("Nothing has filled these in yet. Import an existing listing on the Stores tab, or type them here.")
                        .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.storePanel()
        }
    }
}

/// One identifier, typed.
///
/// It was a `TextField` once, and was made a value on the grounds that the
/// paragraph above says the store decides these: an editable field is an
/// invitation, and the invitation was to invent an App id.
///
/// The reasoning was about what the field means and not about what it costs.
/// These three are required, and every way in went through somewhere else: an
/// import, or a picker that lists what a credential can see. A developer whose
/// credential cannot list the app, or who has not connected one, had the YAML
/// editor and nothing else, and this is the screen that exists so a wrong
/// bundle id is fixable without it.
///
/// So the box is back and the paragraph is what does the work. An invitation
/// is answered by saying what is true, not by taking the keyboard away.
private struct IdentifierValue: View {
    let label: String
    @Binding var value: String
    let placeholder: String
    let commit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(Theme.font(size: 11)).foregroundStyle(Theme.text2)
            TextField(placeholder, text: $value)
                .textFieldStyle(.plain)
                .font(Theme.mono(12))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
                .onChange(of: value) { commit() }
        }
    }
}
