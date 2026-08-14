import AppKit
import SubmitKit
import SwiftUI

/// Settings, as the Mac writes one: a grouped form.
///
/// It was four cards in a two-column grid, and inside them a label column, a
/// checkbox, and a note, all drawn by hand: `SettingRow` measured its own label
/// width so the words lined up, `Check` rebuilt a checkbox with a subtitle
/// because a `VStack` beside a box does not indent, and `Note` set the type for
/// every explanation. Three components, two fixed widths and about a hundred
/// lines of layout, to arrive at the screen `Form` draws.
///
/// The grid was the visible half of the problem. Two columns of unequal cards
/// left one panel ending halfway down the other, the buttons of the Files card
/// stacked into a wall — three of them saying "Reveal" — and the sentence about
/// where the store keys live floated under a rule at the bottom of a card about
/// something else. A grouped form has one column, one label column, one place
/// for a sentence that qualifies a section, and the system's own metrics at
/// every text size.
///
/// The provider choice sits here rather than on the Monetization tab. A
/// developer picks RevenueCat or Adapty once per machine, and then edits the
/// catalog on every app. The two jobs belong on two screens.
struct SettingsTab: View {
    @Environment(AppState.self) private var state
    @AppStorage(Appearance.defaultsKey) private var appearance: Appearance = .system
    @AppStorage("pollIntervalMinutes") private var pollMinutes = 5
    @AppStorage("dryRunByDefault") private var dryRun = true
    @AppStorage("showYAMLToggle") private var showYAMLToggle = false
    /// The drafts on disk, read when the screen appears and after each save.
    /// See `Draft`.
    @State private var drafts: [Draft] = []
    @State private var restoring = false
    @State private var deletingArchives = false

    private static let intervals = [1, 5, 10, 15, 30, 60]

    /// Wide enough for a sentence and no wider. A form row stretches to
    /// whatever it is given, and a checkbox 1200 points from its own label is
    /// the reason settings windows on the Mac are not full width.
    private static let width: CGFloat = 720

    var body: some View {
        Form {
            workspace
            files
            tracker
            startOver
        }
        .formStyle(.grouped)
        .frame(maxWidth: Self.width)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: state.revenueCatAPIKey) { _, _ in state.revenueCatKeyChanged() }
        .onChange(of: state.revenueCatProjectID) { _, _ in state.updateRevenueCatProject() }
        .task(id: state.draftSavedAt) { drafts = DraftStore().list() }
        .confirmationDialog(restoreTitle, isPresented: $restoring,
                            titleVisibility: .visible) {
            Button("Restore") { if let draft = drafts.first { state.restore(draft) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every app in the draft that is no longer in the sidebar comes back, and every store.yaml that is no longer on disk is written again. A file that is still there is left exactly as it is.")
        }
        .confirmationDialog("Delete every retained archive?",
                            isPresented: $deletingArchives, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { state.deleteRetainedArchives() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every archive Super Submitter built and kept is removed from this Mac. Your projects and their build output are untouched, and a build the store already holds stays where it is.")
        }
        .modifier(EraseDialogs())
    }

    // MARK: - Workspace

    private var workspace: some View {
        Section("Workspace") {
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: appearance) { appearance.apply() }

            Picker("Check the stores every", selection: $pollMinutes) {
                ForEach(Self.intervals, id: \.self) { Text("\($0) minutes").tag($0) }
            }
            // The poller reads the value on the next tick, so a restart makes
            // the new interval take effect now.
            .onChange(of: pollMinutes) { state.startPolling() }

            // The sentence under each switch is the switch's own second label,
            // which is what puts it under the words rather than under the box
            // and makes it part of the click target.
            Toggle(isOn: $showYAMLToggle) {
                Text("Show the YAML toggle on every tab")
                Text("The toggle opens the block of store.yaml behind the tab you are on.")
            }
            // A hidden toggle must not leave a tab stuck in YAML.
            .onChange(of: showYAMLToggle) {
                if !showYAMLToggle { state.showYAML = false }
            }

            Toggle(isOn: $dryRun) {
                Text("Start a new app with the dry run on")
                Text("A dry run logs every request and sends none.")
            }
        }
    }

    // MARK: - Files

    private var draftSummary: String {
        guard let newest = drafts.first else {
            return "No draft yet. One press copies every linked app."
        }
        return "\(drafts.count) \(drafts.count == 1 ? "draft" : "drafts") · newest "
            + "\(newest.savedAt.formatted(date: .abbreviated, time: .shortened)) · "
            + "\(newest.apps.count) \(newest.apps.count == 1 ? "app" : "apps")"
    }

    private var restoreTitle: String {
        "Restore the draft of "
            + (drafts.first.map { $0.savedAt.formatted(date: .abbreviated,
                                                       time: .shortened) } ?? "") + "?"
    }

    private var files: some View {
        Section("Files") {
            LabeledContent("Manifest") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(state.manifestURL?.path ?? "No app is open.")
                        .font(Theme.mono(11))
                        .foregroundStyle(state.manifestURL == nil ? Theme.text3 : Theme.text)
                        .textSelection(.enabled)
                        .lineLimit(2).truncationMode(.middle)
                    HStack(spacing: 8) {
                        Button("Show in Finder") { state.revealManifest() }
                        Button("Copy path") {
                            state.copyToPasteboard(state.manifestURL?.path ?? "")
                        }
                    }
                    .disabled(state.manifestURL == nil)
                }
            }

            LabeledContent("Drafts") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(draftSummary)
                    Text("Copies every store.yaml where an app update cannot reach it. Restoring writes back only what is missing. Keys stay in the Keychain.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button("Save progress") { state.saveDraft() }
                        Button("Restore newest") { restoring = true }
                            .disabled(drafts.isEmpty)
                        Button("Show in Finder") { state.revealDrafts() }
                    }
                }
            }

            LabeledContent("Build storage") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(state.buildStorageSummary)
                    Text("Kept outside your repository. Run data is logs and temporary files; the archives are the builds this app made. Your project is untouched.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button("Show in Finder") { state.revealBuildStorage() }
                        Button("Delete run data") { state.pruneBuildStorage() }
                        // Shut while a run is going. An upload reads the
                        // archive it is sending.
                        Button("Delete archives") { deletingArchives = true }
                            .disabled(state.buildFlow.isBusy)
                    }
                }
            }
        }
    }

    // MARK: - The tracker

    private var tracker: some View {
        Section {
            Picker("Provider", selection: Binding(get: { state.provider },
                                                  set: { state.setProvider($0) })) {
                Text("None").tag(Manifest.Provider.none)
                Text("RevenueCat").tag(Manifest.Provider.revenuecat)
                Text("Adapty").tag(Manifest.Provider.adapty)
            }
            .pickerStyle(.segmented)

            if state.provider == .revenuecat { revenueCat }
            if state.provider == .adapty { adapty }
        } header: {
            Text("Monetization tracker")
        } footer: {
            // The one place a sentence about the whole section belongs. It used
            // to sit under a rule at the foot of a card, which reads as a row
            // of that card with no label.
            Text("Mirrors the same purchases into one more catalog: the plan and the apply cover it beside the two stores. The store keys live on the Stores tab, beside the connection that needs them.")
        }
    }

    @ViewBuilder
    private var revenueCat: some View {
        @Bindable var state = state
        SecureField("Secret v2 API key", text: $state.revenueCatAPIKey)
        TextField("Project ID", text: $state.revenueCatProjectID)
        LabeledContent("Connection") {
            VStack(alignment: .leading, spacing: 6) {
                Button("Test connection") { state.testRevenueCatConnection() }
                    .disabled(state.revenueCatAPIKey.isEmpty
                              || state.revenueCatProjectID.isEmpty)
                connectionRow(state.revenueCatConnection)
                Text("The key is stored only in the macOS Keychain. It never reaches store.yaml.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link("Create a RevenueCat account ↗",
                     destination: URL(string: "https://app.revenuecat.com/signup")!)
            }
        }
    }

    @ViewBuilder
    private var adapty: some View {
        LabeledContent("Connection") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Adapty authenticates through its own CLI. This app reads the status and never runs the login.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                connectionRow(state.adaptyConnection)
                HStack(spacing: 8) {
                    Button("Check CLI login") { state.checkAdapty() }
                    Button("Copy login command") {
                        state.copyToPasteboard("adapty auth login")
                    }
                }
                Link("Create an Adapty account ↗",
                     destination: URL(string: "https://app.adapty.io/registration")!)
            }
        }
    }

    /// Connected is green, refused is yellow, and everything else stays quiet.
    /// A refusal in the same grey as the help beside it is a refusal nobody
    /// reads.
    @ViewBuilder
    private func connectionRow(_ status: ConnectionStatus) -> some View {
        if status.isFailed {
            WarningNote(status.label)
        } else {
            HStack(alignment: .top, spacing: 6) {
                Circle().fill(status.isConnected ? Theme.green : Theme.text3)
                    .frame(width: 7, height: 7)
                    .padding(.top, 5)
                Text(status.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(status.isConnected ? Theme.green : .secondary)
        }
    }

    // MARK: - Start over

    /// "Start over", and it was "Nuclear". The heading of a section says what
    /// the section is for, and the only person who reads "Nuclear" as a place
    /// to find the reset is the person who wrote it.
    private var startOver: some View {
        Section {
            Button("Erase everything…", role: .destructive) {
                state.nuclearFirstConfirm = true
            }
        } header: {
            Text("Start over")
        } footer: {
            Text("Forgets every linked app, key, password and archive, and returns to the first-run screen. No store.yaml is deleted, and nothing already published changes.")
        }
    }
}

/// The two gates in front of the erase.
///
/// Two confirmations and not one. The first is the ordinary destructive dialog,
/// which people dismiss by reflex; the second names what goes and cannot be
/// answered by reflex, because the buttons say different things. Nothing here
/// reaches outside the app: the store listings, the developer accounts, and
/// every `store.yaml` on disk are untouched, and the section says so before the
/// first click.
///
/// A modifier of its own, because two `confirmationDialog` calls that both read
/// `state` are two more expressions in a body the type checker already has to
/// infer four sections of.
private struct EraseDialogs: ViewModifier {
    @Environment(AppState.self) private var state

    func body(content: Content) -> some View {
        @Bindable var state = state
        return content
            .confirmationDialog("Erase everything Super Submitter knows?",
                                isPresented: $state.nuclearFirstConfirm,
                                titleVisibility: .visible) {
                Button("Continue", role: .destructive) { state.nuclearSecondConfirm = true }
                Button("Cancel", role: .cancel) { state.nuclearFirstConfirm = false }
            } message: {
                Text("Every linked app, every key you entered, your account, and the data Super Submitter wrote. No store.yaml is deleted, and nothing on the stores changes.")
            }
            // The destructive button says what it does rather than "OK", so the
            // reflex that cleared the first dialog does not clear this one too.
            .confirmationDialog("This cannot be undone.",
                                isPresented: $state.nuclearSecondConfirm,
                                titleVisibility: .visible) {
                // No dismissal to make. `eraseEverything` sends the window to
                // the first-run screen, which is what closing the panel used to
                // be for.
                Button("Erase everything and start over", role: .destructive) {
                    state.eraseEverything()
                }
                Button("Keep my data", role: .cancel) { state.nuclearSecondConfirm = false }
            } message: {
                Text("Super Submitter restarts at the first-run screen with nothing in it.")
            }
    }
}
