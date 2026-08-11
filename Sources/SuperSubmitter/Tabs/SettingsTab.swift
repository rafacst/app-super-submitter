import AppKit
import SubmitKit
import SwiftUI

/// Settings. A screen, and it was a sheet over the window.
///
/// The sheet carried a strip of four sections across the top: a second
/// navigation system, inside a panel, over the first one. Three of the four
/// sections were three rows each, so the strip hid two-thirds of a short screen
/// behind a click and the panel opened at a fixed 560 points whatever the
/// window was. The four are four blocks of one tab now, in the order a
/// developer meets them, and the sidebar says where you are.
///
/// The provider choice sits here rather than on the Monetization tab. A
/// developer picks RevenueCat or Adapty once per machine, and then edits the
/// catalog on every app. The two jobs belong on two screens.
///
/// Every control here is the AppKit one. A hand-drawn checkbox and a
/// hand-drawn segmented control land on different baselines and different
/// heights, and six of those in one column read as six different apps.
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

    private static let intervals = [1, 5, 10, 15, 30, 60]

    private var draftSummary: String {
        guard let newest = drafts.first else {
            return "No draft yet. One press copies every linked app."
        }
        return "\(drafts.count) \(drafts.count == 1 ? "draft" : "drafts") · newest "
            + "\(newest.savedAt.formatted(date: .abbreviated, time: .shortened)) · "
            + "\(newest.apps.count) \(newest.apps.count == 1 ? "app" : "apps")"
    }

    /// Four cards, in the order a developer meets them, and the last one is
    /// the one that erases everything.
    ///
    /// A grid and not a column. Every block here is short — four rows, three,
    /// one — and stacked they made one narrow ribbon down the left of a wide
    /// window with the erase button below the fold. Abreast, the whole of
    /// Settings is one screen, which is what it was as a panel and the one
    /// thing the panel had going for it.
    ///
    /// Two columns, always, and each one takes half of whatever there is.
    ///
    /// It was `adaptive`, with a minimum of a label column plus a 300-point
    /// control. That minimum is 479 points, so two of them need 973 and the
    /// window has to be about 1350 wide before a second column appears. A real
    /// window is 1200, the grid fell to one column, and Settings was the stack
    /// of boxes it was meant to stop being. An adaptive grid whose minimum no
    /// ordinary window can afford is a one-column grid with extra steps.
    ///
    /// So the count is fixed and the controls give way instead: every width
    /// below is a maximum now, and a card narrower than 479 shortens its
    /// pickers and wraps its notes rather than dropping its neighbour under it.
    var body: some View {
        @Bindable var state = state
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 14, alignment: .top),
                                   GridItem(.flexible(), spacing: 14, alignment: .top)],
                         spacing: 14) {
            card("Workspace", icon: "macwindow") { workspace }
            card("Files", icon: "folder") { files }
            // "Monetization tracker" and not "Provider", which is the word on
            // the row inside it. A box named after its own only control says
            // the same word twice and names neither of them: the box is the
            // subject, the row is the choice.
            card("Monetization tracker", icon: "creditcard") { provider }
            card("Nuclear", icon: "exclamationmark.octagon", tint: Theme.red) { nuclear }
        }
        .frame(maxWidth: Self.column, alignment: .leading)
        .onChange(of: state.revenueCatAPIKey) { _, _ in state.revenueCatKeyChanged() }
        .onChange(of: state.revenueCatProjectID) { _, _ in state.updateRevenueCatProject() }
    }

    /// One block, on the panel every card in this app sits on.
    private func card<Content: View>(_ title: String, icon: String,
                                     tint: Color = Theme.accent,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Section_(title, icon: icon, tint: tint, content: content)
        }
        // Both boxes of a row are one box tall, and the contents sit at the top
        // of it. Left to their own heights the two panels in a row ended at two
        // different places, which is the one thing a grid of boxes is for.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .storePanel(padding: 14, horizontal: 15)
    }

    /// The width a card is comfortable at: the label column, the gap, the
    /// control, and the panel's own inset either side. Not a minimum any more.
    /// The grid is two columns whatever the window is, and this is only what
    /// they stop growing at.
    static let card: CGFloat = labelWidth + 14 + controlWidth + 30

    /// One width for the page. Two cards abreast and no more. A third column
    /// would put a picker 1200 points from the sidebar, and no control here
    /// gains anything from the room.
    static let column: CGFloat = card * 2 + 14

    /// Start over. Everything the app holds, gone, and back to onboarding.
    ///
    /// Two confirmations and not one. The first is the ordinary destructive
    /// dialog, which people dismiss by reflex; the second names what goes and
    /// cannot be answered by reflex, because the buttons say different things.
    /// Nothing here reaches outside the app: the store listings, the developer
    /// accounts, and every `store.yaml` on disk are untouched, and the panel
    /// says so before the first click.
    private var nuclear: some View {
        @Bindable var state = state
        return VStack(alignment: .leading, spacing: 13) {
            SettingRow("Start over", symbol: "exclamationmark.octagon", alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Erase everything Super Submitter knows and return to the first-run screen.")
                        .font(Theme.font(size: 12))
                        .frame(maxWidth: Self.controlWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Note("This forgets every linked app, every key and password you entered, your account, and the archives, logs and settings Super Submitter wrote. It deletes no store.yaml anywhere, including the one a managed app keeps here. Your projects, your developer accounts, and everything already published are untouched.")
                    Button("Erase everything") { state.nuclearFirstConfirm = true }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.red)
                        .controlSize(.large)
                }
            }
        }
        // First gate: the ordinary destructive dialog.
        .confirmationDialog("Erase everything Super Submitter knows?",
                            isPresented: $state.nuclearFirstConfirm,
                            titleVisibility: .visible) {
            Button("Continue", role: .destructive) { state.nuclearSecondConfirm = true }
            Button("Cancel", role: .cancel) { state.nuclearFirstConfirm = false }
        } message: {
            Text("Every linked app, every key you entered, your account, and the data Super Submitter wrote. No store.yaml is deleted, and nothing on the stores changes.")
        }
        // Second gate. The destructive button says what it does rather than
        // "OK", so the reflex that cleared the first dialog does not clear
        // this one too.
        .confirmationDialog("This cannot be undone.",
                            isPresented: $state.nuclearSecondConfirm,
                            titleVisibility: .visible) {
            // No dismissal to make. `eraseEverything` sends the window to the
            // first-run screen, which is what closing the panel used to be for.
            Button("Erase everything and start over", role: .destructive) {
                state.eraseEverything()
            }
            Button("Keep my data", role: .cancel) { state.nuclearSecondConfirm = false }
        } message: {
            Text("Super Submitter restarts at the first-run screen with nothing in it.")
        }
    }

    private var workspace: some View {
        VStack(alignment: .leading, spacing: 13) {
            SettingRow("Appearance", symbol: "circle.lefthalf.filled") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: Self.controlWidth, alignment: .leading)
                .onChange(of: appearance) { appearance.apply() }
            }

            SettingRow("Poll interval", symbol: "timer") {
                Picker("Poll interval", selection: $pollMinutes) {
                    ForEach(Self.intervals, id: \.self) { Text("\($0) minutes").tag($0) }
                }
                .labelsHidden()
                .frame(maxWidth: Self.controlWidth, alignment: .leading)
                // The poller reads the value on the next tick, so a
                // restart makes the new interval take effect now.
                .onChange(of: pollMinutes) { state.startPolling() }
            }

            SettingRow("Raw YAML", symbol: "curlybraces", alignment: .top) {
                Check("Show the YAML toggle on every tab", isOn: $showYAMLToggle,
                      note: "The toggle opens the block of store.yaml behind the tab you are on.")
                    // A hidden toggle must not leave a tab stuck in YAML.
                    .onChange(of: showYAMLToggle) {
                        if !showYAMLToggle { state.showYAML = false }
                    }
            }

            SettingRow("Dry run", symbol: "testtube.2", alignment: .top) {
                Check("On by default for a new app", isOn: $dryRun,
                      note: "A dry run logs every request and sends none.")
            }
        }
    }

    private var files: some View {
        VStack(alignment: .leading, spacing: 13) {
            SettingRow("Manifest path", symbol: "doc.text", alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(state.manifestURL?.path ?? "No app is open.")
                        .font(Theme.mono(11))
                        .foregroundStyle(state.manifestURL == nil ? Theme.text3 : Theme.text)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .frame(maxWidth: Self.controlWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 7) {
                        QuietButton(title: "Show in Finder") { state.revealManifest() }
                        QuietButton(title: "Copy path") {
                            state.copyToPasteboard(state.manifestURL?.path ?? "")
                        }
                    }
                    .disabled(state.manifestURL == nil)
                }
            }

            SettingRow("Drafts", symbol: "clock.arrow.circlepath", alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(draftSummary)
                        .font(Theme.font(size: 12))
                        .frame(maxWidth: Self.controlWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Note("A draft copies the list of linked apps and the text of every store.yaml into Application Support, where an app update cannot reach them. Restoring puts back only what is missing: a store.yaml that is still on disk is never written over. A draft holds no key and no password. Those stay in the Keychain.")
                    HStack(spacing: 7) {
                        QuietButton(title: "Save a draft") { state.saveDraft() }
                        QuietButton(title: "Restore the newest") { restoring = true }
                            .disabled(drafts.isEmpty)
                        QuietButton(title: "Reveal") { state.revealDrafts() }
                    }
                }
            }
            .task(id: state.draftSavedAt) { drafts = DraftStore().list() }
            .confirmationDialog("Restore the draft of \(drafts.first.map { $0.savedAt.formatted(date: .abbreviated, time: .shortened) } ?? "")?",
                                isPresented: $restoring, titleVisibility: .visible) {
                Button("Restore") { if let draft = drafts.first { state.restore(draft) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every app in the draft that is no longer in the sidebar comes back, and every store.yaml that is no longer on disk is written again. A file that is still there is left exactly as it is.")
            }

            SettingRow("Build storage", symbol: "internaldrive", alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(state.buildStorageSummary)
                        .font(Theme.font(size: 12))
                        .frame(maxWidth: Self.controlWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Note("Archives and App Bundles are kept outside your repository. Deleting run data removes the logs and the temporary files. It never deletes a retained archive or a bundle, and it never touches your project.")
                    HStack(spacing: 7) {
                        QuietButton(title: "Reveal") { state.revealBuildStorage() }
                        QuietButton(title: "Delete old run data") {
                            state.pruneBuildStorage()
                        }
                    }
                }
            }
        }
    }

    private var provider: some View {
        VStack(alignment: .leading, spacing: 13) {
            SettingRow("Provider", symbol: "arrow.triangle.2.circlepath", alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Provider", selection: Binding(
                        get: { state.provider },
                        set: { value in state.setProvider(value) })) {
                        Text("None").tag(Manifest.Provider.none)
                        Text("RevenueCat").tag(Manifest.Provider.revenuecat)
                        Text("Adapty").tag(Manifest.Provider.adapty)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: Self.controlWidth, alignment: .leading)
                    Note("The provider mirrors the same purchases into one more catalog. The plan and the apply cover it beside the two stores.")
                    if state.provider == .revenuecat { revenueCat }
                    if state.provider == .adapty { adapty }
                }
            }

            Hairline()

            Text("The App Store and Google Play keys live on the Stores tab, next to the connection that needs them.")
                .font(Theme.font(size: 11.5))
                .foregroundStyle(Theme.text2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var revenueCat: some View {
        @Bindable var state = state
        return VStack(alignment: .leading, spacing: 8) {
            SecureField("Secret v2 API key", text: $state.revenueCatAPIKey)
            TextField("Project ID", text: $state.revenueCatProjectID)
            // The status sits under the button and not beside it. It carries
            // the full control width, which is also the width of this whole
            // column, so an HStack gave it every point and squeezed the button
            // to a bar: a tall empty rectangle with the words floating clear of
            // it. Adapty already stacked them, which is why only this one
            // looked broken.
            QuietButton(title: "Test connection") { state.testRevenueCatConnection() }
                .disabled(state.revenueCatAPIKey.isEmpty || state.revenueCatProjectID.isEmpty)
            connectionRow(state.revenueCatConnection)
            Note("The key is stored only in the macOS Keychain. It never reaches store.yaml.")
            Link("Create a RevenueCat account ↗",
                 destination: URL(string: "https://app.revenuecat.com/signup")!)
                .font(Theme.font(size: 11.5))
        }
        .frame(maxWidth: Self.controlWidth, alignment: .leading)
    }

    private var adapty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Note("Adapty authenticates through its own CLI. This app reads the status and never runs the login.")
            connectionRow(state.adaptyConnection)
            HStack(spacing: 7) {
                QuietButton(title: "Check CLI login") { state.checkAdapty() }
                QuietButton(title: "Copy login command") {
                    state.copyToPasteboard("adapty auth login")
                }
            }
            Link("Create an Adapty account ↗",
                 destination: URL(string: "https://app.adapty.io/registration")!)
                .font(Theme.font(size: 11.5))
        }
        .frame(maxWidth: Self.controlWidth, alignment: .leading)
    }

    /// Connected is green, refused is yellow, and everything else stays quiet.
    /// A refusal in the same grey as the help beside it is a refusal nobody
    /// reads.
    private func connectionRow(_ status: ConnectionStatus) -> some View {
        Group {
            if status.isFailed {
                // No width of its own. It is already inside the control
                // column, and a hard 300 in a card that came out narrower
                // reaches past the panel it is drawn on.
                WarningNote(status.label)
                    .frame(maxWidth: Self.controlWidth, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: 6) {
                    Circle().fill(status.isConnected ? Theme.green : Theme.text3)
                        .frame(width: 7, height: 7)
                        .padding(.top, 4)
                    Text(status.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(Theme.font(size: 11.5))
                .foregroundStyle(status.isConnected ? Theme.green : Theme.text2)
                .frame(maxWidth: Self.controlWidth, alignment: .leading)
            }
        }
    }

    /// One width for every control, so the second column has one left edge and
    /// one right edge down the whole page.
    ///
    /// The control width is not scaled and the label width is, and the two are
    /// different kinds of number. This one is a wrap width: a picker sits in it
    /// and a note wraps inside it, so a larger type sets more lines and nothing
    /// runs out of the card.
    static let controlWidth: CGFloat = 300

    /// The label column is a measure. "Manifest path" is the longest word here
    /// and it needs 114 points of the 118 at the shipped scale, so a fixed 118
    /// wrapped it onto two lines the moment the type grew at all.
    static let labelWidth = Theme.scaled(118)
}

/// One setting: a glyph, a word, and the control.
///
/// The glyph is C1 of the design refresh, and it comes from Vocalyn, which
/// puts one before every field label in its inspector. A settings panel is a
/// column of unrelated switches, and the glyph is what a reader finds a row by
/// on the second visit — the word is what they read on the first.
///
/// Not taken with it: the ⓘ Vocalyn puts *after* each label, which hides the
/// explanation behind a click. Several notes in this panel are the only
/// statement of a rule the developer has to know, and a note behind a glyph is
/// a note nobody opens.
private struct SettingRow<Content: View>: View {
    let label: String
    let symbol: String
    var alignment: VerticalAlignment = .center
    @ViewBuilder let content: Content

    init(_ label: String, symbol: String, alignment: VerticalAlignment = .center,
         @ViewBuilder content: () -> Content) {
        self.label = label
        self.symbol = symbol
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        HStack(alignment: alignment, spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(Theme.font(size: 12))
                    .foregroundStyle(Theme.text3)
                    // A fixed column, or a wide glyph pushes its own label out
                    // of line with the one above it.
                    .frame(width: 16)
                Text(label)
                    .font(Theme.font(size: 12.5))
                    .foregroundStyle(Theme.text2)
                Spacer(minLength: 0)
            }
            .frame(width: SettingsTab.labelWidth, alignment: .leading)
            // The label sits on the first line of a tall row, not in the
            // middle of it.
            .padding(.top, alignment == .top ? 1 : 0)
            // The glyph repeats the word beside it, so a reader hears the row
            // named once.
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            // The control takes the rest of the row, and each control caps
            // itself at `controlWidth` inside that.
            //
            // It was `content` followed by a `Spacer`. Two flexible views in
            // one `HStack` share the leftover width between them, so in a card
            // narrower than the old fixed layout the spacer took half of what
            // was left and the controls were squeezed to the other half. A
            // frame here leaves nothing for a spacer to claim.
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A checkbox and the one sentence under it.
///
/// The sentence is part of the checkbox's own label, and it used to be a second
/// row of a `VStack` beside it. A `VStack` aligns on its own leading edge,
/// which is the left of the *box*, so every note started about twenty points to
/// the left of the words it explains and no two lines in the card began at the
/// same place. Inside the label, AppKit indents it under the title for us and
/// the sentence is clickable, which is what a checkbox label is.
private struct Check: View {
    let title: String
    @Binding var isOn: Bool
    let note: String

    init(_ title: String, isOn: Binding<Bool>, note: String) {
        self.title = title
        self._isOn = isOn
        self.note = note
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(Theme.font(size: 12.5))
                Note(note)
            }
        }
        .toggleStyle(.checkbox)
        .frame(maxWidth: SettingsTab.controlWidth, alignment: .leading)
    }
}

private struct Note: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.font(size: 11))
            .foregroundStyle(Theme.text2)
            .lineSpacing(3)
            .frame(maxWidth: SettingsTab.controlWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
