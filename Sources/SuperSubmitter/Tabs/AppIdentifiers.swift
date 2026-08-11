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
                Text("The store owns these, so the app reads them from the store. Connecting a credential on the Stores tab fills them in, and where that credential sees more than one app, the list beside the field picks between them. The box stays open for a value you are copying from the store yourself: an id that names no app fails the apply, and an id that names another app writes to it.")
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
                    VisibleAppsMenu(apps: state.remoteAppleApps,
                                    choose: state.chooseRemoteAppleApp)
                }

                if state.stores.contains(.google) {
                    IdentifierValue(label: "Package name",
                                    value: Binding(get: { state.googlePackageName },
                                                   set: { state.googlePackageName = $0 }),
                                    placeholder: "Reverse-DNS package name",
                                    commit: state.updateGoogleAppFields)
                    // The same menu Apple has had all along. Play's Publishing
                    // API is package-scoped and lists nothing, which is why
                    // this field had no way in but the keyboard, and the
                    // Reporting API answers it for the same credential.
                    VisibleAppsMenu(apps: state.remoteGoogleApps,
                                    choose: state.chooseRemoteGoogleApp)
                }

                RegistrationNote()
            }.storePanel()
        }
    }
}

/// The apps a connected credential can see, when seeing them is a choice.
///
/// One visible app is not a choice, and `adoptTheOnlyVisibleApp` has already
/// put it in the field by the time this draws. A menu with a single row asked
/// the developer to confirm a fact the app had read a second earlier.
private struct VisibleAppsMenu: View {
    let apps: [RemoteStoreApp]
    let choose: (RemoteStoreApp) -> Void

    var body: some View {
        if apps.count > 1 {
            Menu("Choose visible app") {
                ForEach(apps) { app in
                    Button("\(app.name) · \(app.identifier)") { choose(app) }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}

/// What no credential can fetch, and who has to be asked for it instead.
///
/// Every identifier on this panel is read from the store when the store holds
/// the app. A first submission is the case where it does not, and the fields
/// are still required: there is nothing to fetch, because neither store has
/// assigned anything yet. Saying "type them here" was true and useless, since
/// the developer has nothing to type until somebody registers the app.
///
/// So the note names the console that assigns each one. Both sentences are the
/// stores' own rules and not this app's: App Store Connect publishes no way to
/// create an app record, and the Play edits API refuses every call until one
/// build has been uploaded to the console by hand.
private struct RegistrationNote: View {
    @Environment(AppState.self) private var state

    var body: some View {
        // An app the stores already hold needs none of this, and an identifier
        // that is filled in is the proof they hold it.
        if state.showsNewAppFields, !missing.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text("This app is not on the stores yet, so there is nothing to fetch. These are assigned when you register it:")
                    .font(Theme.font(size: 11)).foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(missing, id: \.self) { line in
                    Text(line)
                        .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var missing: [String] {
        var lines: [String] = []
        if state.stores.contains(.apple), state.appleAppID.isEmpty {
            lines.append("App id: create the app in App Store Connect. Apple assigns the number there and publishes no way to create one from here. The bundle id goes in first, and the Stores tab can register it for you.")
        }
        if state.stores.contains(.google), state.googlePackageName.isEmpty {
            lines.append("Package name: you choose it in the build, then create the app in Play Console and upload one build there by hand. Play takes no change from this app until a first APK or AAB has landed.")
        }
        return lines
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
